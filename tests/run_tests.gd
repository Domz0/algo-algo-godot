extends SceneTree
## Pruebas sin interfaz ni dependencias externas; el código de salida sirve para automatización.

const EconomyConfig = preload("res://economy/economy_config.gd")
const Simulation = preload("res://economy/simulation.gd")
const DemandRules = preload("res://economy/demand_rules.gd")

var checks: int = 0
var failures: int = 0


func _init() -> void:
	## Ejecuta casos contables, decisiones y límites; termina con error si algo falla.
	_test_accounting()
	_test_weighted_inventory()
	_test_demand()
	_test_limits()
	_test_long_run()
	print("Pruebas: %d comprobaciones, %d fallos." % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	## Continúa después de un fallo para mostrar todos los problemas en una ejecución.
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _near(actual: float, expected: float, description: String) -> void:
	## La tolerancia cubre únicamente el redondeo binario de los importes decimales.
	_check(absf(actual - expected) < 0.00001, "%s: recibido %.8f, esperado %.8f" % [description, actual, expected])


func _accounting_config():
	## Escenario calculable a mano: 20 compradores, una oferta y opción externa iguales.
	var config = _legacy_config()
	config.market_demand = 20
	config.brand_strength = 0.0
	config.companies[0].merge({"cash": 1000.0, "price": 20.0, "production_target": 20, "variable_cost": 5.0, "fixed_cost": 10.0}, true)
	config.companies[1].production_target = 0
	return config


func _test_accounting() -> void:
	## Diez unidades sin vender explican la diferencia de 50 entre beneficio y caja.
	var sim = Simulation.new(_accounting_config())
	_check(sim.advance_cycle(), "Se ejecuta el ciclo válido")
	var company = sim.state.companies[0]
	_check(company.production == 20 and company.sales == 10 and company.inventory == 10, "Balance físico 20 - 10 = 10")
	_near(company.revenue, 200.0, "Ingresos")
	_near(company.production_spending, 100.0, "Desembolso de producción")
	_near(company.cost_of_goods_sold, 50.0, "Costo de ventas")
	_near(company.operating_costs, 60.0, "Costos operativos")
	_near(company.operating_profit, 140.0, "Beneficio operativo")
	_near(company.cash_flow, 90.0, "Flujo de caja")
	_near(company.cash, 1090.0, "Caja final")
	_near(company.inventory_value, 50.0, "Valor del stock")
	_near(company.equity(), 1140.0, "Patrimonio final")
	var no_demand = _accounting_config()
	no_demand.market_demand = 0
	var idle_market = Simulation.new(no_demand)
	idle_market.advance_cycle()
	_near(idle_market.state.companies[0].operating_profit, -10.0, "Sin ventas el beneficio reconoce solo el fijo")
	_near(idle_market.state.companies[0].cash_flow, -110.0, "El flujo negativo incluye la producción sin vender")


func _test_weighted_inventory() -> void:
	## Conserva el costo anterior cuando cambia el costo de producir en otro día.
	var sim = Simulation.new(_accounting_config())
	sim.advance_cycle()
	var company = sim.state.companies[0]
	company.variable_unit_cost = 10.0
	sim.set_decision(0, 20.0, 10)
	sim.advance_cycle()
	_near(company.cost_of_goods_sold, 75.0, "Costo promedio: (50 + 100) / 20 * 10")
	_near(company.inventory_value, 75.0, "Stock al costo promedio")
	sim.set_decision(0, 20.0, 0)
	sim.advance_cycle()
	_check(company.inventory == 0, "Es posible vender stock sin producir")
	_near(company.inventory_value, 0.0, "Agotar stock elimina su valor")
	_near(company.production_spending, 0.0, "Sin producción no hay desembolso variable")


func _test_demand() -> void:
	## Aísla preferencias de las restricciones de financiación y producción.
	var config = _legacy_config()
	var sim = Simulation.new(config)
	for company in sim.state.companies:
		company.active_this_cycle = true
		company.inventory = 1000
		# Esta prueba aísla preferencias; la capacidad limitada se prueba en logística.
		company.own_logistics_capacity = 1000
		company.price = 20.0
		company.brand = 0.0
	var equal: Array[int] = DemandRules.allocate(sim.state.companies, config)
	_check(equal == [40, 40], "Mercado compartido con 40 compradores que no compran")
	sim.state.companies[0].price = 40.0
	var expensive: Array[int] = DemandRules.allocate(sim.state.companies, config)
	_check(expensive[0] < equal[0], "Subir el precio reduce ventas propias")
	_check(expensive[0] + expensive[1] < 80, "El precio también reduce ventas totales")
	sim.state.companies[0].price = 20.0
	sim.state.companies[0].brand = 1.0
	var branded: Array[int] = DemandRules.allocate(sim.state.companies, config)
	_check(branded[0] > equal[0], "La marca aumenta demanda propia")
	sim.state.companies[0].inventory = 0
	var unavailable: Array[int] = DemandRules.allocate(sim.state.companies, config)
	_check(unavailable[0] == 0 and unavailable[1] == 60, "Sin stock no participa; el rival recibe más demanda")
	sim.state.companies[0].inventory = 1
	var scarce: Array[int] = DemandRules.allocate(sim.state.companies, config)
	_check(scarce[0] == 1, "No se vende más que el stock disponible")
	config.market_demand = 0
	_check(DemandRules.allocate(sim.state.companies, config) == [0, 0], "Demanda cero no crea ventas")
	config.market_demand = 1
	sim.state.companies[0].brand = 0.0
	_check(DemandRules.allocate(sim.state.companies, config) == [1, 0], "Empate de redondeo determinista sin duplicar compradores")


func _test_limits() -> void:
	## Cubre suspensión, producción financiable, decisiones inválidas y costos nulos.
	var config = _legacy_config()
	config.companies[0].cash = 59.0
	config.companies[1].cash = 80.0
	var sim = Simulation.new(config)
	_check(not sim.set_decision(0, -1.0, 10), "Rechaza precio negativo")
	_check(not sim.set_decision(0, NAN, 10), "Rechaza NaN")
	_check(not sim.set_decision(0, INF, 10), "Rechaza infinito")
	_check(not sim.set_decision(0, 20.0, -1), "Rechaza producción negativa")
	_check(not sim.set_decision(2, 20.0, 1), "Rechaza empresa inexistente")
	_check(sim.set_decision(1, 20.0, 1000), "Acepta y limita objetivo a capacidad")
	_check(sim.state.companies[1].production_target == 60, "Objetivo limitado")
	sim.advance_cycle()
	_check(not sim.state.companies[0].active_this_cycle, "Suspensión por falta de costo fijo")
	_near(sim.state.companies[0].cash, 59.0, "No se crea deuda implícita")
	_check(sim.state.companies[1].production == 2, "Reserva fijo y solo financia dos unidades")
	config = _legacy_config()
	config.market_demand = 0
	config.companies[0].cash = 0.0
	config.companies[0].fixed_cost = 0.0
	config.companies[0].variable_cost = 0.0
	sim = Simulation.new(config)
	sim.advance_cycle()
	_check(sim.state.companies[0].production == 80, "Costo cero no divide por cero")
	_near(sim.state.companies[0].cash, 0.0, "Caja cero sigue siendo válida")
	config.market_demand = -1
	sim = Simulation.new(config)
	_check(not sim.errors.is_empty() and not sim.advance_cycle(), "Configuración inválida no avanza")
	config = _legacy_config()
	config.price_elasticity = 10000.0
	_check(not config.validation_errors().is_empty(), "Rechaza parámetros que desbordan la fórmula")


func _test_long_run() -> void:
	## Verifica conservación durante 500 ciclos deterministas con decisiones variables.
	var sim = Simulation.new(_legacy_config())
	var twin = Simulation.new(_legacy_config())
	for day in range(500):
		var prior_cash: Array[float] = []
		var prior_equity: Array[float] = []
		var prior_stock: Array[int] = []
		for index in range(2):
			var company = sim.state.companies[index]
			prior_cash.append(company.cash)
			prior_equity.append(company.equity())
			prior_stock.append(company.inventory)
			var price: float = 10.0 + (day + index * 7) % 30
			var target: int = (day * 13 + index * 17) % 110
			sim.set_decision(index, price, target)
			twin.set_decision(index, price, target)
		sim.advance_cycle()
		twin.advance_cycle()
		var total_sales: int = 0
		for index in range(2):
			var company = sim.state.companies[index]
			total_sales += company.sales
			_check(company.cash >= 0.0 and is_finite(company.cash) and company.inventory >= 0 and company.inventory_value >= 0.0, "Caja y existencias válidas")
			_check(company.production >= 0 and company.production <= company.capacity and company.sales >= 0, "Producción y ventas válidas")
			_check(company.inventory == prior_stock[index] + company.production - company.sales, "Conservación de unidades")
			_near(company.cash, prior_cash[index] + company.revenue - company.production_spending - company.fixed_cost_paid, "Conservación de caja")
			_near(company.equity(), prior_equity[index] + company.operating_profit, "Conservación patrimonial")
			_near(company.cash, twin.state.companies[index].cash, "Reproducibilidad sin reloj gráfico")
		_check(total_sales <= sim.config.market_demand and sim.state.unserved_demand == sim.config.market_demand - total_sales, "Conservación del mercado compartido")


func _legacy_config():
	## Aísla regresiones de etapas 1–4 sin recursos adicionales; la etapa 5 tiene su propia suite.
	var config = EconomyConfig.new()
	config.extended_economy = false
	return config
