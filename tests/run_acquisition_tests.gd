extends SceneTree
## Valida adquisición atómica, conservación contractual y eliminación de servicios internos.

const Config = preload("res://economy/economy_config.gd")
const Simulation = preload("res://economy/simulation.gd")
var checks: int = 0
var failures: int = 0


func _init() -> void:
	## Difiere el caso de interfaz hasta que exista un árbol capaz de recibir controles.
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	## Acumula fallos para revisar todas las condiciones de una misma ejecución.
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _near(actual: float, expected: float, description: String) -> void:
	## La tolerancia solo cubre el redondeo de números de coma flotante.
	_check(absf(actual - expected) < 0.00001, description)


func _config():
	## Ambas productoras pueden pagar; esto permite probar competencia por la misma venta.
	var config = _legacy_config()
	config.companies[0].cash = 10000.0
	config.companies[1].cash = 10000.0
	return config


func _run() -> void:
	## Cada caso usa una partida independiente para no ocultar dependencias entre pruebas.
	_test_atomic_purchase()
	_test_growth()
	_test_contracts_and_finance()
	_test_screen()
	print("Adquisición etapa 4: %d comprobaciones, %d fallos." % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_atomic_purchase() -> void:
	## Solicitudes del mismo instante se serializan: solo la primera válida puede comprar.
	for first_buyer in [0, 1]:
		var sim = Simulation.new(_config())
		var operator = sim.state.logistics
		var price: float = operator.acquisition_price()
		_check(not sim.acquire_logistics(-1, price).ok, "Rechaza comprador inválido")
		_check(not sim.acquire_logistics(0, NAN).ok, "Rechaza cotización NaN")
		_check(not sim.acquire_logistics(0, price - 1.0).ok, "Rechaza precio incompatible")
		_near(sim.state.companies[0].cash, 10000.0, "Rechazos no descuentan")
		_check(operator.owner_company_index == -1, "Rechazos no transfieren propiedad")
		_check(sim.acquire_logistics(first_buyer, price).ok, "Compra exitosa para cualquiera de los jugadores")
		_near(sim.state.companies[first_buyer].cash, 10000.0 - price, "Descuento exacto")
		_near(sim.state.companies[first_buyer].equity(), 10000.0, "Inversión registrada al costo, sin pérdida operativa")
		_near(operator.cash, 1000.0, "Pago no entra en la filial")
		_near(operator.external_seller_proceeds, price, "Pago recibido por vendedor externo")
		_check(operator.owner_company_index == first_buyer, "Propietario correcto")
		_check(not sim.acquire_logistics(1 - first_buyer, price).ok, "Segundo intento del mismo instante rechazado")
		_check(not sim.acquire_logistics(first_buyer, price).ok, "Doble clic no cobra dos veces")
		_near(sim.state.companies[1 - first_buyer].cash, 10000.0, "Perdedor conserva dinero")
		_near(sim.state.companies[first_buyer].cash, 10000.0 - price, "No hay segundo descuento")
		_check(not sim.consolidated_result().available, "No atribuye beneficios anteriores al nuevo grupo")
	var poor = Simulation.new(_legacy_config())
	var initial_cash: float = poor.state.companies[0].cash
	_check(not poor.acquire_logistics(0, poor.state.logistics.acquisition_price()).ok, "Fondos insuficientes")
	_near(poor.state.companies[0].cash, initial_cash, "Insuficiencia no descuenta dinero")
	_check(poor.state.logistics.owner_company_index == -1, "Insuficiencia conserva vendedor")
	var exact = Simulation.new(_config())
	exact.state.companies[0].cash = exact.state.logistics.acquisition_price()
	_check(exact.acquire_logistics(0, exact.state.logistics.acquisition_price()).ok, "Admite fondos exactamente iguales")
	_near(exact.state.companies[0].cash, 0.0, "Compra exacta no deja caja negativa")


func _test_growth() -> void:
	## Aísla el paso del tiempo: operador sin contratos no tiene beneficios ni movimientos de caja.
	var config = _config()
	config.logistics_value_growth_rate = 0.1
	config.logistics_purchase_multiplier = 1.2
	var sim = Simulation.new(config)
	var operator = sim.state.logistics
	var original_quote: float = operator.acquisition_price()
	sim.advance_cycle()
	_near(operator.estimated_value(), 1980.0, "Valor base 1800 crece 10% en un día")
	_near(operator.acquisition_price(), 2376.0, "Precio configurable sobre estimación")
	_near(operator.cash, 1000.0, "Crecimiento no crea caja")
	_near(operator.operating_profit, 0.0, "Crecimiento no crea beneficio")
	_check(not sim.acquire_logistics(0, original_quote).ok, "Cotización antigua no compra al precio anterior")
	var cash: float = sim.state.companies[0].cash
	_check(sim.acquire_logistics(0, operator.acquisition_price()).ok, "Cotización renovada permite compra")
	_near(sim.state.companies[0].cash, cash - 2376.0, "Descuento del precio renovado")
	var investment: float = sim.state.companies[0].logistics_investment
	sim.advance_cycle()
	_near(sim.state.companies[0].logistics_investment, investment, "Revalorización no altera inversión histórica")
	config.logistics_value_growth_rate = -0.1
	_check(not config.validation_errors().is_empty(), "Rechaza tasa negativa")
	config.logistics_value_growth_rate = 0.0
	config.logistics_purchase_multiplier = INF
	_check(not config.validation_errors().is_empty(), "Rechaza multiplicador infinito")


func _test_contracts_and_finance() -> void:
	## Mantiene condiciones firmadas y elimina ingresos y gastos internos en igual importe.
	var sim = Simulation.new(_config())
	sim.request_contract(0, 10, 3)
	sim.request_contract(1, 20, 3)
	sim.advance_cycle()
	var operator = sim.state.logistics
	var contract = operator.contracts[0]
	var prepaid: float = contract.prepaid_balance
	var operator_cash: float = operator.cash
	var deferred: float = operator.deferred_revenue
	var price: float = operator.acquisition_price()
	_check(sim.acquire_logistics(0, price).ok, "Compra con contratos activos")
	_check(contract.status == "activo" and contract.served_days == 1 and contract.end_cycle == 3, "Conserva estado, duración y fecha")
	_near(contract.prepaid_balance, prepaid, "Compra no consume anticipo")
	_near(contract.unit_rate, 1.0, "No modifica tarifa vigente")
	_near(contract.fixed_fee, 2.0, "No modifica fijo vigente")
	_near(operator.cash, operator_cash, "Conserva caja de filial")
	_near(operator.deferred_revenue, deferred, "Conserva obligaciones")
	_check(operator.available_capacity() == 50, "Conserva reservas de ambos clientes")
	_check(not sim.request_contract(0, 51, 1).ok, "Ser dueño no permite quitar capacidad al rival")
	_check(sim.request_contract(0, 30, 1).ok, "Dueño puede contratar capacidad sobrante")
	_check(sim.request_contract(1, 20, 1).ok, "Rival puede contratar el resto")
	_check(not sim.request_contract(1, 1, 1).ok, "No sobreasigna capacidad tras compra")
	var buyer_equity: float = sim.state.companies[0].equity()
	sim.advance_cycle()
	var buyer = sim.state.companies[0]
	var group: Dictionary = sim.consolidated_result()
	_check(group.available, "Consolidado disponible para día posterior")
	_near(group.eliminated, 44.0, "Elimina contratos internos de 12 y 32")
	_near(group.revenue, buyer.revenue + 44.0, "Consolidado conserva ingresos del rival de 22 y 22")
	_near(group.costs, buyer.operating_costs + operator.operating_costs - 44.0, "Elimina gasto interno, conserva costos reales")
	_near(group.profit, buyer.operating_profit + operator.operating_profit, "No suma nuevamente ingresos internos al beneficio")
	_near(buyer.equity(), buyer_equity + buyer.operating_profit, "Cuenta individual conserva patrimonio al costo")
	_check(not sim.cancel_contract(contract.id).ok, "Dueño respeta plazo original")
	sim.advance_cycle()
	_check(contract.status == "vencido" and operator.available_capacity() == 80, "Compra no renueva ni prolonga contratos")
	_check("\n".join(sim.state.events).contains("conservado tras compra"), "Historial identifica contratos afectados")


func _test_screen() -> void:
	## El botón transmite la cotización mostrada; la respuesta permanece visible.
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.simulation = Simulation.new(_config())
	root.add_child(scene)
	var panel = scene.rental_panels[1]
	_check(panel.purchase_label.text.contains("1800.00"), "Precio real visible")
	panel.purchase_button.pressed.emit()
	_check(scene.simulation.state.logistics.owner_company_index == 1, "Botón compra para jugador seleccionado")
	_check(panel.purchase_result.text.contains("Compra completada") and panel.purchase_button.disabled, "Resultado y estado adquirido visibles")
	_check(panel.summary.text.contains("Propietario: Empresa B"), "Propietario actualizado")
	scene.advance_button.pressed.emit()
	_check(panel.purchase_label.text.contains("Servicios internos eliminados"), "Resultado consolidado visible")
	scene.queue_free()


func _legacy_config():
	## Aísla regresiones de etapas 1–4 sin recursos adicionales; la etapa 5 tiene su propia suite.
	var config = Config.new()
	config.extended_economy = false
	return config
