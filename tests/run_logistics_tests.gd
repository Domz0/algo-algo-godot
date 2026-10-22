extends SceneTree
## Pruebas locales de contratos, contabilidad, límites físicos e integración de pantalla.

const Config = preload("res://economy/economy_config.gd")
const Simulation = preload("res://economy/simulation.gd")
var checks: int = 0
var failures: int = 0


func _init() -> void:
	## Se difiere la ejecución para poder montar la escena en el caso de interfaz.
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	## Acumula fallos, en lugar de abortar antes de revisar las demás invariantes.
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _near(actual: float, expected: float, description: String) -> void:
	## Tolerancia monetaria para errores de representación, no para errores económicos.
	_check(absf(actual - expected) < 0.00001, "%s: %.8f != %.8f" % [description, actual, expected])


func _config():
	## Caso manual: A puede distribuir 5 unidades propias y produce 20 a costo 5.
	var config = _legacy_config()
	# El ejemplo contable aísla el valor base de la revalorización de la etapa 4.
	config.logistics_value_growth_rate = 0.0
	config.companies[0].merge({"cash": 1000.0, "production_target": 20, "variable_cost": 5.0, "fixed_cost": 10.0, "own_logistics_capacity": 5}, true)
	return config


func _run() -> void:
	## Ejecuta pruebas del modelo y de las señales reales usadas por la interfaz.
	_test_validation_and_cancellation()
	_test_costs_and_expiry()
	_test_distribution_and_idle_contracts()
	_test_many_cycles()
	_test_fractional_rates()
	_test_screen()
	print("Logística etapa 3: %d comprobaciones, %d fallos." % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_validation_and_cancellation() -> void:
	## Una solicitud rechazada no cambia caja, anticipos, identificadores ni reservas.
	var sim = Simulation.new(_config())
	var client = sim.state.companies[0]
	var operator = sim.state.logistics
	for request in [[-1, 10, 2], [2, 10, 2], [0, 0, 2], [0, -1, 2], [0, 10, 0], [0, 10, 31], [0, 81, 1], [0, 80, 30]]:
		_check(not sim.request_contract(request[0], request[1], request[2]).ok, "Rechaza solicitud inválida o sin capacidad/caja")
	_near(client.cash, 1000.0, "Rechazos no gastan")
	_check(operator.contracts.is_empty() and operator.next_contract_id == 1, "Rechazos no crean contratos")
	var first: Dictionary = sim.request_contract(0, 50, 2)
	_check(first.ok, "Acepta contrato válido")
	_check(operator.contracted_capacity == 50 and operator.available_capacity() == 30, "Reserva exacta")
	_near(client.cash, 896.0, "Anticipo = (50*1+2)*2")
	_near(client.prepaid_logistics, 104.0, "Anticipo activo de productora")
	_near(operator.deferred_revenue, 104.0, "Anticipo obligación del operador")
	_near(operator.revenue, 0.0, "Cobrar anticipo no es ingreso")
	_check(not sim.request_contract(1, 31, 1).ok, "Segundo cliente no sobrecontrata")
	_check(sim.request_contract(1, 30, 1).ok, "Segundo cliente usa capacidad restante exacta")
	_check(operator.available_capacity() == 0, "No queda capacidad")
	_check(sim.cancel_contract(first.id).ok, "Desistimiento permitido antes de iniciar")
	_near(client.cash, 1000.0, "Reembolso íntegro")
	_near(client.prepaid_logistics, 0.0, "Reembolso extingue activo")
	_check(operator.available_capacity() == 50 and client.contracted_capacity == 0, "Cancelar libera reservas")
	_check(not sim.cancel_contract(first.id).ok, "No hay doble reembolso")
	_check(not sim.cancel_contract(999).ok, "Contrato inexistente rechazado")
	var config = _config()
	config.logistics_unit_rate = 0.1
	_check(not config.validation_errors().is_empty(), "Tarifa no puede comprometer servicio sin financiar costos")
	config = _config()
	config.companies[0].own_logistics_capacity = -1
	_check(not config.validation_errors().is_empty(), "Capacidad propia no negativa")


func _test_costs_and_expiry() -> void:
	## Comprueba cifras exactas y que un plazo de tres días dé tres servicios, nunca dos o cuatro.
	var sim = Simulation.new(_config())
	var result: Dictionary = sim.request_contract(0, 10, 3)
	var client = sim.state.companies[0]
	var operator = sim.state.logistics
	var contract = operator.contracts[0]
	_near(client.equity(), 1000.0, "Firmar no cambia patrimonio")
	_near(operator.available_cash(), 1000.0, "Anticipo no infla caja libre")
	var expected: Array[int] = sim.estimate_next_sales()
	_near(contract.prepaid_balance, 36.0, "Estimar no consume anticipo")
	_check(contract.served_days == 0, "Estimar no consume duración")
	sim.advance_cycle()
	_check(client.sales == 15 and client.sales == expected[0], "Ventas limitadas a propia más contrato")
	_check(client.distributed_units == 15 and operator.distributed_units == 10, "Se usa primero capacidad propia")
	_near(client.cash, 1154.0, "Caja no vuelve a pagar servicio prepagado")
	_near(client.logistics_expense, 12.0, "Gasto diario contractual")
	_near(client.operating_profit, 203.0, "Beneficio con costo de ventas 75, fijo 10 y logística 12")
	_near(client.equity(), 1203.0, "Patrimonio incluye anticipo restante")
	_near(client.prepaid_logistics, 24.0, "Consume solo un día de anticipo")
	_near(operator.revenue, 12.0, "Ingreso diario devengado")
	_near(operator.operating_costs, 5.0, "Costo = 10*0.4+1")
	_near(operator.operating_profit, 7.0, "Beneficio del operador")
	_near(operator.cash, 1031.0, "Caja del operador tras costos")
	_near(operator.cash_flow, -5.0, "Flujo diario distingue cobro anticipado")
	_near(operator.estimated_value(), 1877.0, "Valor estimado según parámetros")
	_check(contract.status == "activo" and contract.start_cycle == 1 and contract.end_cycle == 3, "Fechas y estado activo")
	_check(not sim.cancel_contract(result.id).ok, "No se permite cancelar durante plazo")
	_near(client.prepaid_logistics, 24.0, "Cancelación rechazada no devuelve dinero")
	sim.advance_cycle()
	_check(contract.status == "activo" and client.contracted_capacity == 10, "Segundo día conserva reserva")
	sim.advance_cycle()
	_check(client.sales == 15 and client.distribution_limit == 15, "Último día aún tiene servicio")
	_check(contract.status == "vencido" and contract.served_days == 3, "Vence tras exactamente tres servicios")
	_check(client.contracted_capacity == 0 and operator.available_capacity() == 80, "Vencimiento libera reservas para siguiente día")
	_near(client.prepaid_logistics, 0.0, "Anticipo consumido")
	_near(operator.deferred_revenue, 0.0, "Obligación consumida")
	sim.advance_cycle()
	_check(client.sales == 5, "Tras vencer solo distribuye capacidad propia")
	_near(operator.revenue, 0.0, "No cobra días adicionales")
	_near(operator.operating_costs, 0.0, "Sin reservas no incurre costos contractuales")
	_check(sim.request_contract(0, 10, 1).ok, "Puede contratar de nuevo tras vencer")


func _test_distribution_and_idle_contracts() -> void:
	## Sin distribución no hay ventas; el stock no desaparece y las reservas se pagan aunque no se usen.
	var config = _config()
	config.companies[0].own_logistics_capacity = 0
	var sim = Simulation.new(config)
	sim.advance_cycle()
	_check(sim.state.companies[0].sales == 0 and sim.state.companies[0].inventory == 20, "Cero distribución conserva todo el inventario")
	_check(sim.request_contract(0, 7, 1).ok, "Capacidad externa habilita acceso al mercado")
	sim.advance_cycle()
	_check(sim.state.companies[0].sales == 7, "Distribución limitada aun con stock acumulado")
	config = _config()
	config.market_demand = 0
	sim = Simulation.new(config)
	sim.request_contract(0, 10, 1)
	sim.advance_cycle()
	_near(sim.state.logistics.revenue, 12.0, "Reserva se paga con demanda cero")
	_check(sim.state.logistics.distributed_units == 0, "No inventa entregas sin ventas")
	config = _config()
	config.companies[0].cash = 12.0
	sim = Simulation.new(config)
	sim.request_contract(0, 10, 1)
	sim.advance_cycle()
	_check(not sim.state.companies[0].active_this_cycle, "Anticipo puede dejar sin caja para abrir")
	_near(sim.state.companies[0].logistics_expense, 12.0, "Suspensión no elimina compromiso reservado")
	_near(sim.state.companies[0].cash, 0.0, "Sin deuda implícita tras suspensión")


func _test_many_cycles() -> void:
	## Contratos solapados de ambos clientes conservan caja, patrimonio y capacidad.
	var sim = Simulation.new(_config())
	for day in range(120):
		var operator = sim.state.logistics
		var cash_before: float = operator.cash
		for client in sim.state.companies:
			cash_before += client.cash
		if day % 2 == 0:
			sim.request_contract(day % 4 / 2, 3 + day % 7, 1 + day % 5)
		var opening_equity: Array[float] = []
		for client in sim.state.companies:
			opening_equity.append(client.equity())
		var prior_operator_equity: float = operator.available_cash()
		sim.advance_cycle()
		var cash_after: float = operator.cash
		var cash_from_market: float = 0.0
		var external_spending: float = operator.operating_costs
		var reserved_sum: int = 0
		var prepaid_sum: float = 0.0
		for index in range(2):
			var client = sim.state.companies[index]
			cash_after += client.cash
			cash_from_market += client.revenue
			external_spending += client.production_spending + client.fixed_cost_paid
			reserved_sum += client.contracted_capacity
			prepaid_sum += client.prepaid_logistics
			_check(client.sales <= client.distribution_limit and client.inventory >= 0 and client.cash >= 0.0, "Límites físicos y caja no negativa")
			_near(client.equity(), opening_equity[index] + client.operating_profit, "Conservación patrimonial productora")
		_near(cash_after, cash_before + cash_from_market - external_spending, "Contratos transfieren dinero, no lo crean")
		_near(operator.available_cash(), prior_operator_equity + operator.operating_profit, "Conservación patrimonial operador")
		_near(prepaid_sum, operator.deferred_revenue, "Anticipos de clientes coinciden con obligación")
		_check(reserved_sum == operator.contracted_capacity and operator.available_capacity() >= 0, "Reservas nunca exceden capacidad")
		_check(operator.distributed_units <= operator.total_capacity and operator.cash >= 0.0, "Operador respeta capacidad y caja")


func _test_screen() -> void:
	## Campos y botones reales actualizan reservas, estimaciones, contratos y eventos visibles.
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.simulation = Simulation.new(_config())
	root.add_child(scene)
	var panel = scene.logistics_panel
	panel.capacity_input.get_line_edit().text = "10"
	panel.days_input.get_line_edit().text = "2"
	panel.request_button.pressed.emit()
	_check(scene.simulation.state.logistics.contracted_capacity == 10, "Botón solicita contrato al modelo")
	_check(panel.contracts_view.text.contains("pendiente") and panel.contracts_view.text.contains("12.00/día"), "Contrato y costo visibles")
	_check(scene.company_panels[0].logistics_label.text.contains("contratada 10"), "Capacidad contratada visible")
	_check(scene.company_panels[0].metrics.estimate.text == "15", "Estimación incorpora distribución")
	panel.cancel_button.pressed.emit()
	_check(scene.simulation.state.logistics.contracted_capacity == 0, "Botón cancela antes de iniciar")
	panel.request_button.pressed.emit()
	scene.advance_button.pressed.emit()
	panel.cancel_button.pressed.emit()
	_check(scene.status_label.text.contains("no admite cancelación"), "Rechazo por duración visible")
	_check(scene.company_panels[0].metrics.sales.text == "15", "Efecto en ventas visible")
	_check(scene.events_view.text.contains("aceptado") and scene.events_view.text.contains("rechazada"), "Eventos de solicitudes visibles")
	scene.advance_button.pressed.emit()
	_check(panel.contracts_view.text.contains("vencido") and panel.cancel_button.disabled, "Vencimiento visible sin cancelaciones pendientes")
	scene.queue_free()


func _test_fractional_rates() -> void:
	## Un operador sin capital inicial puede cumplir reservas al costo sin caja negativa por redondeo.
	var config = _config()
	config.logistics_initial_cash = 0.0
	config.logistics_unit_rate = 0.1
	config.logistics_unit_cost = 0.1
	config.logistics_contract_fee = 0.0
	config.logistics_contract_cost = 0.0
	var sim = Simulation.new(config)
	_check(sim.request_contract(0, 1, 30).ok, "Acepta tarifas decimales al costo")
	for day in range(30):
		sim.advance_cycle()
		_check(sim.state.logistics.cash >= 0.0 and sim.state.logistics.available_cash() >= 0.0, "Importes decimales no generan caja negativa")
	_near(sim.state.logistics.cash, 0.0, "Se consume anticipo al costo")
	_near(sim.state.logistics.contracts[0].prepaid_balance, 0.0, "Contrato sin anticipo residual")


func _legacy_config():
	## Aísla regresiones de etapas 1–4 sin recursos adicionales; la etapa 5 tiene su propia suite.
	var config = Config.new()
	config.extended_economy = false
	return config
