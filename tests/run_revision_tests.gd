extends SceneTree
## Regresiones de la revisión: flujos brutos, empleo gradual, flota, mercado y pantalla adaptable.

const Config = preload("res://economy/economy_config.gd")
const Simulation = preload("res://economy/simulation.gd")
const Demand = preload("res://economy/demand_rules.gd")
var checks: int = 0
var failures: int = 0


func _init() -> void:
	## Difiere controles hasta disponer de un árbol y un viewport.
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	## Un fallo no impide diagnosticar los casos siguientes.
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _near(actual: float, expected: float, message: String) -> void:
	## Tolerancia monetaria limitada al redondeo binario.
	_check(absf(actual - expected) < 0.00001, "%s: %.8f frente a %.8f" % [message, actual, expected])


func _config():
	## Capital de prueba para aislar recursos; no altera los saldos del escenario jugable.
	var config = Config.new()
	config.companies[0].cash = 10000.0
	config.companies[1].cash = 10000.0
	config.logistics_auto_expand = false
	return config


func _run() -> void:
	## Ejecuta escenarios nuevos junto con las suites históricas, sin sustituirlas.
	_test_hiring()
	_test_market()
	_test_own_fleet()
	_test_reports()
	await _test_layout()
	print("Revisión económica: %d comprobaciones, %d fallos." % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_hiring() -> void:
	## Solicitar no incorpora ni paga salarios a candidatos; despedir cuesta un sueldo actual.
	var config = _config()
	var sim = Simulation.new(config)
	var company = sim.state.companies[0]
	var ops = company.operations
	_check(sim.manage_operations(0, "hire", 7).ok, "Abre siete vacantes")
	_check(ops.employees == 4 and ops.vacancies == 7 and ops.pending_count() == 0, "No contrata instantáneamente")
	var cash: float = company.cash
	var estimate: Array[int] = sim.estimate_next_sales()
	_check(ops.employees == 4 and ops.vacancies == 7, "Pronóstico no recluta realmente")
	sim.advance_cycle()
	_check(ops.employees == 4 and ops.vacancies == 5 and ops.pending_count() == 2, "Primera selección respeta velocidad")
	_near(ops.salary_expense, 16.0, "Solo paga personal incorporado")
	_check(company.sales == estimate[0], "Pronóstico incluye correctamente contratación y transporte")
	_check(company.cash != cash, "El ciclo ejecuta cobros y pagos")
	_check(sim.manage_operations(0, "cancel_vacancies", 3).ok, "Cancela vacantes abiertas")
	_check(not sim.manage_operations(0, "cancel_vacancies", 3).ok, "No cancela vacantes inexistentes")
	sim.advance_cycle()
	_check(ops.employees == 6 and ops.vacancies == 0 and ops.pending_count() == 2, "Llegada gradual mantiene candidatos futuros")
	_near(ops.salary_expense, 24.0, "Nómina de seis trabajadores reales")
	cash = company.cash
	_check(sim.manage_operations(0, "fire", 2).ok, "Despido válido")
	_near(company.cash, cash - 8.0, "Indemniza exactamente un sueldo por despedido")
	_check(not sim.manage_operations(0, "fire", 5).ok, "No despide más empleados de los existentes")
	_check(not sim.manage_operations(0, "hire", -1).ok, "No permite cantidades negativas")
	sim.advance_cycle()
	_check(ops.employees == 6, "Candidatos seleccionados se incorporan aunque se hayan despedido empleados")
	_near(company.finance.reports[-1].categories["Indemnizaciones"]["out"], 8.0, "Informe incluye indemnización inmediata")
	config.hiring_speed = 0
	_check(not config.validation_errors().is_empty(), "Rechaza velocidad inválida")


func _test_market() -> void:
	## Nueve escenarios comerciales, más límites de presupuesto y precio de reserva.
	var config = _config()
	config.extended_economy = false
	var sim = Simulation.new(config)
	var a = sim.state.companies[0]
	var b = sim.state.companies[1]
	for company in sim.state.companies:
		company.active_this_cycle = true
		company.inventory = 1000
		company.own_logistics_capacity = 1000
		company.price = 20.0
	_check(Demand.allocate(sim.state.companies, config) == [60, 60], "Precios iguales comparten compradores")
	a.price = 10.0
	var cheap: Array[int] = Demand.allocate(sim.state.companies, config)
	_check(cheap[0] > cheap[1], "Menor precio atrae más compradores")
	a.price = 10000.0
	_check(Demand.allocate(sim.state.companies, config)[0] == 0, "Precio extremo individual pierde ventas")
	b.price = 10000.0
	_check(Demand.aggregate(sim.state.companies, config) == 0 and Demand.allocate(sim.state.companies, config) == [0, 0], "Ambos extremos extinguen demanda")
	a.price = 40.0
	b.price = 40.0
	_check(Demand.aggregate(sim.state.companies, config) < 120, "Precios generales mayores reducen demanda agregada")
	a.price = 20.0
	b.price = 20.0
	a.inventory = 0
	_check(Demand.allocate(sim.state.companies, config) == [0, 120], "Sin producto no vende")
	a.inventory = 1000
	a.own_logistics_capacity = 0
	_check(Demand.allocate(sim.state.companies, config)[0] == 0, "Sin transporte no vende")
	a.own_logistics_capacity = 1000
	a.inventory = 3
	b.inventory = 4
	_check(Demand.allocate(sim.state.companies, config) == [3, 4], "Demanda mayor que oferta conserva límites físicos")
	a.inventory = 1000
	b.inventory = 1000
	_check(Demand.allocate(sim.state.companies, config) == [60, 60], "Sobreoferta no inventa compradores")
	config.consumer_budget = 100.0
	var limited: Array[int] = Demand.allocate(sim.state.companies, config)
	_check(limited[0] * a.price + limited[1] * b.price <= 100.0, "Presupuesto limita gasto conjunto")
	config = _config()
	config.companies[0].price = 79.0
	config.companies[0].variable_cost = 50.0
	sim = Simulation.new(config)
	sim.advance_cycle()
	_check(sim.state.companies[0].sales < sim.state.companies[1].sales and sim.state.companies[0].operating_profit < 0.0, "Costos y precio elevados no garantizan rentabilidad")


func _test_own_fleet() -> void:
	## Flota sembrada, costos ociosos, activos pagados, venta y restricciones de combustible.
	var config = _config()
	var sim = Simulation.new(config)
	var twin = Simulation.new(config)
	for index in range(2):
		var fleet = sim.state.companies[index].own_fleet
		_check(fleet.vehicles >= config.own_fleet_min and fleet.vehicles <= config.own_fleet_max, "Flota dentro del rango")
		_check(fleet.vehicles == twin.state.companies[index].own_fleet.vehicles, "Semilla reproduce cada flota")
	var company = sim.state.companies[0]
	var vehicles: int = company.own_fleet.vehicles
	var cash: float = company.cash
	var equity: float = company.equity()
	_check(sim.manage_operations(0, "buy_vehicle", 2).ok, "Compra vehículos con fondos")
	_near(company.cash, cash - 2 * config.own_vehicle_cost, "Compra descuenta caja")
	_near(company.equity(), equity, "Compra conserva patrimonio al costo")
	_check(company.own_logistics_capacity == (vehicles + 2) * config.own_vehicle_capacity, "Compra aporta capacidad nominal")
	cash = company.cash
	_check(sim.manage_operations(0, "sell_vehicle", 1).ok, "Reducción explícita de flota")
	_near(company.cash, cash + config.own_vehicle_cost * config.own_vehicle_resale, "Reventa transfiere importe documentado")
	_check(not sim.manage_operations(0, "sell_vehicle", 1000).ok, "No vende flota inexistente")
	config.market_demand = 0
	sim.advance_cycle()
	_check(company.own_fleet.fixed_expense > 0.0 and company.own_fleet.fuel_expense == 0.0, "Flota ociosa paga salarios y mantenimiento sin combustible")
	var poor_config = _config()
	poor_config.companies[0].cash = 0.0
	var poor = Simulation.new(poor_config)
	_check(not poor.manage_operations(0, "buy_vehicle", 1).ok, "No compra capacidad gratis")
	poor.advance_cycle()
	_check(poor.state.companies[0].own_fleet.effective_capacity == 0 and poor.state.companies[0].own_fleet.payable > 0.0, "Sin caja acumula obligación y no transporta")
	for day in range(8):
		sim.config.market_demand = 120
		sim.manage_operations(0, "inputs", 20)
		sim.advance_cycle()
		_check(company.sales <= company.distribution_limit and company.cash >= 0.0, "Entrega no supera capacidad financiada")


func _test_reports() -> void:
	## Reconciliación de tres entidades, flujos brutos compensados y pagos sin ingreso duplicado.
	var sim = Simulation.new(_config())
	var a = sim.state.companies[0]
	var operator = sim.state.logistics
	var cash: float = operator.cash
	sim.invest_in_logistics(0, 2)
	_near(operator.cash, cash, "Inversión entra y paga proveedor sin alterar neto de caja")
	sim.request_contract(1, 4, 2)
	sim.manage_operations(0, "inputs", 5)
	sim.manage_operations(0, "spares", 2)
	sim.manage_operations(0, "expand", 3)
	sim.advance_cycle()
	var report: Dictionary = operator.finance.reports[0]
	_near(report.categories["Financiación de expansión por cliente"]["in"], 24.0, "Cobro bruto de inversión registrado")
	_near(report.categories["Compra de flota logística"]["out"], 24.0, "Pago bruto de inversión registrado")
	_near(a.finance.reports[0].categories["Compra de insumos"]["out"], 10.0, "Informe conserva compras entre cierres")
	var frozen: Dictionary = a.finance.reports[0].duplicate(true)
	sim.advance_cycle()
	_check(a.finance.reports[0] == frozen, "Historial cerrado inmutable")
	for entity in [a, sim.state.companies[1], operator]:
		for closed in entity.finance.reports:
			_near(closed.closing, closed.opening + closed.incoming - closed.outgoing, "Caja conciliada por período y entidad")
			_near(closed.difference, 0.0, "Ninguna diferencia oculta")
		_near(entity.finance.reports[1].opening, entity.finance.reports[0].closing, "Cierres encadenados")
	var journal_size: int = sim.state.journal.size()
	sim.estimate_next_sales()
	_check(sim.state.journal.size() == journal_size and a.finance.reports.size() == 2, "Consultar no duplica asientos ni informes")
	var credit = Simulation.new(_config())
	credit.state.companies[0].cash = 0.0
	credit.request_contract(0, 2, 2, true)
	credit.advance_cycle()
	credit.state.companies[0].cash = 10.0
	var total_cash: float = credit.state.companies[0].cash + credit.state.logistics.cash
	credit.pay_note(0, 1, 5.0)
	_near(credit.state.companies[0].cash + credit.state.logistics.cash, total_cash, "Pago conserva dinero entre deudor y acreedor")
	credit.advance_cycle()
	var debt_report: Dictionary = credit.state.companies[0].finance.reports[1]
	_near(debt_report.categories["Intereses pagados"]["out"], 0.16, "Separa intereses pagados de principal")
	_near(debt_report.categories["Principal de deuda pagado"]["out"], 4.84, "Principal no se trata como gasto")


func _test_layout() -> void:
	## Monta controles reales en ambos tamaños; verifica navegación, borradores e informe visible.
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.simulation = Simulation.new(_config())
	root.add_child(scene)
	for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		root.content_scale_size = Vector2i.ZERO
		await process_frame
		await process_frame
		_check(scene.get_combined_minimum_size().x <= resolution.x, "Pantalla cabe horizontalmente")
		_check(scene.sections.get_global_rect().end.y <= resolution.y + 1, "Pestañas caben verticalmente")
		for panel in scene.company_panels:
			_check(panel.price_input.get_global_rect().end.x <= resolution.x, "Campo de precio no se corta")
			_check(panel.production_input.get_global_rect().end.y <= resolution.y, "Decisiones visibles sin desplazar toda la pantalla")
	_check(scene.company_panels[0].price_input.editable and scene.company_panels[1].price_input.editable, "Ambas columnas tienen decisiones independientes")
	scene.company_panels[1].price_input.get_line_edit().text = "30"
	scene.company_panels[1].apply_button.pressed.emit()
	_near(scene.simulation.state.companies[1].price, 30.0, "Aplica decisión al jugador seleccionado")
	scene.advance_button.pressed.emit()
	_check(scene.reports_view.text.contains("Ventas cobradas") and scene.reports_view.text.contains("diferencia 0.00000000"), "Informe visible procede del cierre real")
	scene.queue_free()
