extends SceneTree
## Casos económicos completos con recursos reales, crédito, inversiones y cuentas relacionadas.

const Config = preload("res://economy/economy_config.gd")
const Simulation = preload("res://economy/simulation.gd")
var checks: int = 0
var failures: int = 0


func _init() -> void:
	## Se difiere el montaje de controles hasta que exista el árbol de escenas.
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	## Informa todas las invariantes fallidas sin ocultar las pruebas posteriores.
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _near(actual: float, expected: float, description: String) -> void:
	## La tolerancia solo cubre representación binaria de importes decimales.
	_check(absf(actual - expected) < 0.00001, "%s: %.8f != %.8f" % [description, actual, expected])


func _config():
	## Escenario solvente para aislar recursos; otras pruebas reducen caja expresamente.
	var config = Config.new()
	config.companies[0].cash = 10000.0
	config.companies[1].cash = 10000.0
	config.logistics_auto_expand = false
	return config


func _run() -> void:
	## Ejecuta escenarios que corresponden a las reglas de la etapa 5, además de las regresiones.
	_test_cash_and_resources()
	_test_staff_and_maintenance()
	_test_storage_and_market()
	_test_fleet()
	_test_notes()
	_test_investments_and_ownership()
	_test_long_run()
	_test_integrated_conservation()
	_test_screen()
	print("Economía ampliada etapa 5: %d comprobaciones, %d fallos." % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_cash_and_resources() -> void:
	## Cobros y pagos afectan la caja real; comprar activos no se convierte en gasto íntegro.
	var config = _config()
	var sim = Simulation.new(config)
	var twin = Simulation.new(config)
	var client = sim.state.companies[0]
	var warehouse = client.operations.warehouse
	_check(warehouse.capacity >= config.warehouse_min_capacity and warehouse.capacity <= config.warehouse_max_capacity, "Bodega dentro del rango")
	_check(warehouse.capacity == twin.state.companies[0].operations.warehouse.capacity, "Semilla reproducible")
	var initial_equity: float = client.equity()
	_check(sim.manage_operations(0, "inputs", 10).ok, "Compra real de insumos")
	_near(client.cash, 9980.0, "Compra descuenta efectivo")
	_near(client.equity(), initial_equity, "Compra de inventario conserva patrimonio")
	_check(sim.manage_operations(0, "machine", 1).ok, "Compra de máquina")
	_near(client.equity(), initial_equity, "Máquina es activo, no gasto instantáneo")
	_check(sim.manage_operations(0, "expand", 10).ok, "Expansión pagada de bodega")
	_near(client.equity(), initial_equity, "Construcción es activo")
	var before: float = client.cash
	var predictions: Array[int] = sim.estimate_next_sales()
	sim.advance_cycle()
	_near(client.cash, before - client.fixed_cost_paid - client.operations.salary_expense - client.production_spending - client.advertising_spending + client.revenue, "Caja refleja costos pagados y ventas cobradas")
	_near(client.cash_flow, client.cash - 10000.0, "Flujo incluye compras entre cierres una sola vez")
	_near(client.equity(), initial_equity + client.net_profit, "Patrimonio cambia por beneficio neto, no por comprar activos")
	_check(client.sales == predictions[0], "Pronóstico no muta recursos y coincide con ventas")
	_check(client.cash > before, "Ventas cobradas aumentan dinero neto en escenario rentable")
	_check(sim.state.journal.size() > 0, "Movimientos auditables con saldo anterior y posterior")
	var poor = Simulation.new(_config())
	poor.state.companies[0].cash = 0.0
	_check(not poor.manage_operations(0, "machine", 1).ok, "Sin capital no compra maquinaria")
	poor.advance_cycle()
	_check(poor.state.companies[0].production == 0 and poor.state.companies[0].wages_payable > 0.0, "Salarios se deben aun si no hay caja")
	_near(poor.state.companies[0].cash, 0.0, "Sin saldo negativo ni dinero artificial")


func _test_staff_and_maintenance() -> void:
	## Falta de personal, reservas laborales, desgaste y recursos de mantenimiento son efectivos.
	var normal = Simulation.new(_config())
	var short = Simulation.new(_config())
	short.manage_operations(0, "fire", 3)
	normal.advance_cycle()
	short.advance_cycle()
	_check(short.state.companies[0].production < normal.state.companies[0].production, "Falta de empleados reduce producción")
	var excess = Simulation.new(_config())
	excess.manage_operations(0, "hire", 2)
	excess.advance_cycle()
	_check(excess.state.companies[0].production == normal.state.companies[0].production, "Reserva laboral no penaliza eficiencia por defecto")
	_near(excess.state.companies[0].operations.salary_expense, 24.0, "Se paga todo el exceso de empleados")
	var config = _config()
	config.excess_staff_penalty = 0.1
	var penalty = Simulation.new(config)
	penalty.manage_operations(0, "hire", 5)
	penalty.advance_cycle()
	_check(penalty.state.companies[0].production < normal.state.companies[0].production, "Penalización opcional por exceso configurable")
	var sim = Simulation.new(_config())
	var client = sim.state.companies[0]
	var machine = client.operations.machines[0]
	machine.wear = 1.0
	machine.operating_cycles = 10
	machine.preventive = false
	var warehouse = client.operations.warehouse
	warehouse.spares = 0
	warehouse.spares_value = 0.0
	var before: float = client.cash
	_check(not sim.manage_operations(0, "maintenance", machine.id).ok, "Sin repuestos no hay mantenimiento gratis")
	_near(client.cash, before, "Mantenimiento rechazado no consume caja")
	_check(machine.efficiency() == 0.0, "Desgaste deja máquina fuera de servicio")
	sim.manage_operations(0, "spares", 1)
	before = client.cash
	_check(sim.manage_operations(0, "maintenance", machine.id).ok, "Mantenimiento correctivo consume recursos")
	_near(client.cash, before - machine.maintenance_labor, "Se paga mano de obra real")
	_check(warehouse.spares == 0 and machine.wear == 0.0, "Consume repuesto y restaura máquina")
	sim.manage_operations(0, "spares", 2)
	sim.manage_operations(0, "preventive_on", machine.id)
	machine.operating_cycles = machine.maintenance_interval
	sim.advance_cycle()
	_check(machine.operating_cycles == 1, "Preventivo se ejecuta antes de operar")
	_check(client.operations.maintenance_expense > 0.0, "Costo de mantenimiento reconocido")
	var retiring = Simulation.new(_config())
	retiring.manage_operations(0, "machine", 1)
	var equity: float = retiring.state.companies[0].equity()
	retiring.manage_operations(0, "retire", 3)
	_near(retiring.state.companies[0].equity(), equity - 250.0, "Retirar da de baja el activo sin reventa ficticia")


func _test_storage_and_market() -> void:
	## Nunca desaparece el excedente; se conserva o se limita la nueva producción.
	var config = _config()
	config.market_demand = 0
	var sim = Simulation.new(config)
	var client = sim.state.companies[0]
	var warehouse = client.operations.warehouse
	sim.manage_operations(0, "spares", 10000)
	_check(warehouse.occupied(client.inventory) == warehouse.capacity, "Compra parcial llena bodega sin excederla")
	_check(not sim.manage_operations(0, "inputs", 1).ok, "Bodega llena rechaza compra")
	sim.advance_cycle()
	_check(client.sales == 0 and client.inventory == client.production, "Demanda cero conserva productos")
	_check(warehouse.occupied(client.inventory) <= warehouse.capacity, "Consumir insumos libera espacio antes de producir")
	for machine in client.operations.machines:
		machine.inputs_per_unit = 0
	sim.advance_cycle()
	_check(client.production == 0, "Producción sin liberar insumos se detiene ante bodega llena")
	var no_inputs = Simulation.new(_config())
	no_inputs.state.companies[0].operations.warehouse.inputs = 0
	no_inputs.state.companies[0].operations.warehouse.inputs_value = 0.0
	no_inputs.advance_cycle()
	_check(no_inputs.state.companies[0].production == 0, "Falta total de insumos detiene producción")
	var limited = Simulation.new(_config())
	limited.state.companies[0].own_logistics_capacity = 2
	limited.advance_cycle()
	_check(limited.state.companies[0].sales == 2 and limited.state.companies[0].inventory > 0, "Exceso sobre transporte queda almacenado")
	var low_demand = _config()
	low_demand.market_demand = 2
	var slow = Simulation.new(low_demand)
	slow.advance_cycle()
	_check(slow.state.total_sales <= 2 and slow.state.companies[0].inventory > 0, "No obliga a vender toda la oferta")


func _test_fleet() -> void:
	## Tarifas suben con presión y bajan en ocio; expandir consume caja y respeta reservas.
	var config = _config()
	config.logistics_auto_expand = true
	var sim = Simulation.new(config)
	var operator = sim.state.logistics
	sim.request_contract(0, 60, 2)
	var cash: float = operator.cash
	var rate: float = operator.unit_rate
	sim.advance_cycle()
	_check(operator.total_capacity == 90, "Expansión automática crea capacidad pagada")
	_near(operator.cash, cash - operator.operating_costs - 120.0, "Expansión descuenta costo real una vez")
	_check(operator.available_cash() >= config.logistics_cash_reserve, "Expansión respeta reserva de liquidez")
	_check(operator.unit_rate > rate and operator.unit_rate <= config.transport_max_price, "Presión aumenta tarifa gradualmente")
	var idle = Simulation.new(_config())
	idle.advance_cycle()
	_check(idle.state.logistics.unit_rate < rate, "Ocio reduce tarifa")
	_near(idle.state.logistics.fuel_expense, 0.0, "Sin entregas no consume combustible")
	var active = Simulation.new(_config())
	active.state.companies[0].own_logistics_capacity = 0
	active.request_contract(0, 20, 2)
	active.advance_cycle()
	_near(active.state.logistics.fuel_expense, active.state.logistics.distributed_units * config.fuel_cost_per_delivery, "Combustible por actividad real")
	_near(active.state.logistics.staff_expense, active.state.logistics.distributed_units * config.logistics_wage_per_delivery, "Personal logístico por entregas")
	_check(active.state.logistics.distributed_units <= 20, "No sobreusa reserva")
	var poor_config = _config()
	poor_config.logistics_auto_expand = true
	poor_config.logistics_cash_reserve = 100000.0
	var poor = Simulation.new(poor_config)
	poor.request_contract(0, 60, 2)
	poor.advance_cycle()
	_check(poor.state.logistics.total_capacity == 80, "No expande sin reserva financiera")


func _test_notes() -> void:
	## Anticipo financiado es activo contra deuda, no cobro; intereses y pagos se registran una vez.
	var config = _config()
	config.note_maturity_days = 2
	var sim = Simulation.new(config)
	var client = sim.state.companies[0]
	var operator = sim.state.logistics
	client.cash = 0.0
	_check(not sim.request_contract(0, 10, 2).ok, "Crédito requiere autorización expresa")
	_check(sim.request_contract(0, 10, 2, true).ok, "Pagaré permite contrato sin caja")
	_near(client.prepaid_logistics, 24.0, "Servicio anticipado financiado")
	_near(client.note_debt, 24.0, "Principal de deuda exacto")
	_near(operator.cash, 1000.0, "Firma financiada no crea efectivo")
	_near(operator.revenue, 0.0, "Firma no duplica ingresos devengados")
	var note = operator.notes[0]
	sim.advance_cycle()
	_near(note.interest_due, 0.48, "Interés simple primer período")
	_near(operator.revenue, 12.0, "Solo reconoce un día de servicio")
	sim.advance_cycle()
	_near(note.interest_due, 0.96, "Sin interés sobre interés")
	_check(note.status == "vencido", "Vencimiento sin pago registra incumplimiento")
	_check(not sim.request_contract(0, 1, 1, true).ok, "Atraso bloquea nuevo crédito")
	client.cash = 10.0
	var cash: float = operator.cash
	var income: float = operator.revenue
	_check(sim.pay_note(0, note.id, 10.0).ok, "Pago parcial permitido")
	_near(note.principal, 14.96, "Pago cubre interés primero y reduce principal")
	_near(operator.cash, cash + 10.0, "Acreedor cobra transferencia")
	_near(operator.revenue, income, "Cobrar no repite ingreso")
	client.cash = 100.0
	sim.pay_note(0, note.id, 100.0)
	_check(note.status == "pagado" and note.payments.size() == 2, "Pago final conserva calendario de abonos")
	_near(client.note_debt, 0.0, "Deuda extinguida")
	_near(operator.receivables, 0.0, "Derecho de cobro extinguido")
	var cancel = Simulation.new(_config())
	cancel.state.companies[0].cash = 0.0
	cancel.request_contract(0, 10, 2, true)
	cancel.state.companies[0].cash = 5.0
	cancel.pay_note(0, 1, 5.0)
	cancel.cancel_contract(1)
	_near(cancel.state.companies[0].cash, 5.0, "Cancelar devuelve solo lo efectivamente pagado")
	_near(cancel.state.logistics.cash, 1000.0, "Cancelación de crédito no regala efectivo")
	_near(cancel.state.companies[0].note_debt, 0.0, "Cancelación anula deuda restante")
	var upfront = Simulation.new(_config())
	upfront.request_contract(0, 10, 2, true)
	_check(upfront.state.logistics.notes.is_empty(), "Si hay caja cobra antes de emitir pagaré")
	_near(upfront.state.logistics.cash, 1024.0, "Anticipo pagado llega al operador")


func _test_investments_and_ownership() -> void:
	## Invertir en descuento financia un activo físico sin comprar la empresa.
	var config = _config()
	config.investment_discount_days = 2
	var sim = Simulation.new(config)
	var client = sim.state.companies[0]
	var operator = sim.state.logistics
	var equity: float = client.equity()
	_check(sim.invest_in_logistics(0, 10).ok, "Inversión financiada")
	_near(client.cash, 9880.0, "Inversión descuenta capital real")
	_near(operator.cash, 1000.0, "Financiación directa paga proveedor, sin caja creada")
	_check(operator.total_capacity == 90 and operator.owner_company_index == -1, "Capacidad nueva no transfiere propiedad")
	_near(client.equity(), equity, "Derecho temporal registrado como activo")
	_check(not sim.invest_in_logistics(0, 10).ok, "No acumula descuentos ilimitados")
	_check(not sim.request_contract(0, 10, 3).ok, "No extiende descuento fuera del plazo")
	_check(sim.request_contract(0, 10, 2).ok, "Contrato dentro de vigencia")
	_near(operator.contracts[0].unit_rate, 0.85, "Tarifa descontada no negativa")
	var contract_rate: float = operator.contracts[0].unit_rate
	sim.advance_cycle()
	_near(client.discount_expense, 60.0, "Derecho se consume por período")
	_check(sim.acquire_logistics(0, operator.acquisition_price()).ok, "Compra sigue funcionando con inversión vigente")
	_near(operator.contracts[0].unit_rate, contract_rate, "Compra preserva descuento firmado")
	sim.advance_cycle()
	_near(client.discount_asset, 0.0, "Descuento expira exactamente al cumplir plazo")
	var group: Dictionary = sim.consolidated_result()
	_near(group.profit, client.operating_profit + operator.operating_profit, "No duplica operaciones internas")
	_near(group.net_profit, client.net_profit + operator.net_profit, "Consolidado neto elimina interés interno")
	sim.request_contract(0, 1, 1)
	_near(operator.contracts[-1].unit_rate, operator.unit_rate, "Tras expirar aplica tarifa normal")
	var debt_sim = Simulation.new(_config())
	debt_sim.state.companies[1].cash = 0.0
	debt_sim.request_contract(1, 5, 2, true)
	var note = debt_sim.state.logistics.notes[0]
	debt_sim.acquire_logistics(0, debt_sim.state.logistics.acquisition_price())
	_near(note.principal, 14.0, "Compra conserva principal de pagaré rival")
	_near(note.interest_rate, config.note_interest_rate, "Compra conserva interés pactado")
	_check(note.due_cycle == config.note_maturity_days, "Compra conserva vencimiento")


func _test_long_run() -> void:
	## Recursos y caja permanecen válidos durante compras, salarios, mantenimiento y ventas repetidas.
	var sim = Simulation.new(_config())
	for day in range(40):
		for index in range(2):
			sim.manage_operations(index, "inputs", 30)
			if day % 3 == 0:
				sim.manage_operations(index, "spares", 2)
		var predicted: Array[int] = sim.estimate_next_sales()
		sim.advance_cycle()
		for index in range(2):
			var client = sim.state.companies[index]
			var warehouse = client.operations.warehouse
			_check(client.cash >= 0.0 and is_finite(client.cash), "Caja finita no negativa")
			_check(warehouse.inputs >= 0 and warehouse.spares >= 0 and client.inventory >= 0, "Existencias no negativas")
			_check(warehouse.occupied(client.inventory) <= warehouse.capacity, "Bodega nunca excede capacidad")
			_check(client.sales <= client.distribution_limit and client.sales == predicted[index], "Distribución y pronóstico coherentes")
			_near(client.net_profit, client.operating_profit - client.interest_expense, "Resultado neto consistente")


func _test_screen() -> void:
	## Señales de controles de recursos y crédito muestran saldos e inventarios reales.
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.simulation = Simulation.new(_config())
	root.add_child(scene)
	var panel = scene.company_panels[0].operations_panel
	panel.amount_input.get_line_edit().text = "10"
	panel.apply_button.pressed.emit()
	_near(scene.simulation.state.companies[0].cash, 9980.0, "Botón de insumos cambia caja real")
	_check(panel.summary.text.contains("Insumos 170"), "Inventario comprado visible")
	scene.advance_button.pressed.emit()
	_check(panel.summary.text.contains("Beneficio neto"), "Desglose financiero visible")
	var logistics = scene.logistics_panel
	logistics.capacity_input.get_line_edit().text = "2"
	logistics.investment_button.pressed.emit()
	_check(scene.simulation.state.logistics.total_capacity == 82, "Botón inversión aumenta capacidad pagada")
	_check(logistics.finance_view.text.contains("Inversión Empresa A"), "Acuerdo de descuento visible")
	scene.queue_free()


func _test_integrated_conservation() -> void:
	## Comprueba patrimonio antes de decisiones y después del cierre, incluidos créditos y activos.
	var config = _config()
	config.logistics_auto_expand = true
	var sim = Simulation.new(config)
	for day in range(12):
		var equities: Array[float] = [sim.state.companies[0].equity(), sim.state.companies[1].equity()]
		var operator = sim.state.logistics
		var operator_equity: float = operator.book_equity()
		for index in range(2):
			sim.manage_operations(index, "inputs", 20)
			if day % 3 == 0:
				sim.manage_operations(index, "spares", 2)
		if day == 0:
			sim.manage_operations(0, "hire", 1)
			sim.manage_operations(0, "machine", 1)
			sim.invest_in_logistics(1, 2)
		if day % 3 == 0:
			sim.request_contract(0, 30, 2)
		if day == 4:
			sim.acquire_logistics(0, operator.acquisition_price())
		sim.advance_cycle()
		for index in range(2):
			_near(sim.state.companies[index].equity(), equities[index] + sim.state.companies[index].net_profit, "Patrimonio conserva todo el período con compras, salarios y contratos")
		_near(operator.book_equity(), operator_equity + operator.net_profit, "Logística conserva patrimonio con expansión e inversión")
	var internal_config = _config()
	internal_config.companies[0].cash = 25.0
	internal_config.logistics_purchase_multiplier = 0.01
	var internal = Simulation.new(internal_config)
	internal.request_contract(0, 20, 2, true)
	_check(internal.acquire_logistics(0, internal.state.logistics.acquisition_price()).ok, "Compra con pagaré del futuro dueño")
	internal.advance_cycle()
	var group: Dictionary = internal.consolidated_result()
	_near(group.internal_interest, 0.88, "Identifica interés intragrupo real")
	_near(group.net_profit, group.profit, "Interés interno no genera beneficio consolidado")
	var idle = Simulation.new(_config())
	idle.state.companies[0].cash = 0.0
	idle.request_contract(0, 10, 5, true)
	idle.request_contract(1, 10, 5)
	var free_before: float = idle.state.logistics.available_cash()
	idle.state.logistics.notes[0].interest_due = 100.0
	idle.state.logistics.receivables += 100.0
	_near(idle.state.logistics.available_cash(), free_before, "Interés por cobrar nunca desbloquea anticipos ajenos")
