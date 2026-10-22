extends RefCounted
## Orquesta un ciclo completo; no depende del árbol de escenas ni de los FPS.

const SimulationState = preload("res://economy/simulation_state.gd")
const ProductionRules = preload("res://economy/production_rules.gd")
const DemandRules = preload("res://economy/demand_rules.gd")
const AccountingRules = preload("res://economy/accounting_rules.gd")
const AdvertisingRules = preload("res://economy/advertising_rules.gd")
const LogisticsRules = preload("res://economy/logistics_rules.gd")
const AcquisitionRules = preload("res://economy/acquisition_rules.gd")
const OperationsRules = preload("res://economy/operations_rules.gd")
const CreditRules = preload("res://economy/credit_rules.gd")
const FleetRules = preload("res://economy/fleet_rules.gd")
const Journal = preload("res://economy/financial_journal.gd")

var config
var state
var errors: PackedStringArray


func _init(parameters) -> void:
	## Valida los parámetros y expone errores sin crear una partida inválida.
	config = parameters
	errors = config.validation_errors()
	if errors.is_empty():
		state = SimulationState.new(config)


func set_decision(company_index: int, new_price: float, target: int, advertising: float = 0.0) -> bool:
	## Entrada para ambos jugadores locales: decisiones persistentes hasta cambiarlas.
	if state == null or company_index < 0 or company_index >= state.companies.size():
		return false
	if not is_finite(new_price) or new_price < config.minimum_price or new_price > config.maximum_price or target < 0:
		return false
	var company = state.companies[company_index]
	if not is_finite(advertising) or advertising < 0.0 or advertising > config.maximum_advertising:
		return false
	if company.price != new_price:
		state.record_event("%s: precio %.2f → %.2f." % [company.company_name, company.price, new_price])
	company.price = new_price
	company.production_target = mini(target, company.capacity)
	company.advertising_budget = advertising
	state.record_event("%s: decisiones aplicadas; producción %d, publicidad %.2f por día." % [company.company_name, company.production_target, advertising])
	return true


func advance_cycle() -> bool:
	## Primero producen ambas empresas, luego compiten y finalmente cierran sus cuentas.
	if state == null:
		return false
	var opening_cash: Array[float] = []
	var before: Array[float] = Journal.balances(state)
	var reserved_today: int = state.logistics.contracted_capacity
	if config.extended_economy:
		var service: Array[int] = FleetRules.service_capacities(state, config)
		for index in range(state.companies.size()):
			if service[index] < state.companies[index].contracted_capacity:
				state.record_event("Logística sin liquidez: capacidad efectiva reducida; la reserva y deuda no desaparecen.")
			state.companies[index].contracted_capacity = service[index]
	for company in state.companies:
		opening_cash.append(company.cash_at_period_start if config.extended_economy else company.cash)
		company.reset_cycle_results()
	state.cycle += 1
	if config.extended_economy:
		CreditRules.accrue(state)
		FleetRules.recognize_discounts(state)
	for company in state.companies:
		ProductionRules.prepare(company, config, false)
		AdvertisingRules.apply(company, config)
	var sales: Array[int] = DemandRules.allocate(state.companies, config)
	LogisticsRules.settle_day(state)
	state.total_sales = 0
	state.unserved_demand = config.market_demand
	for index in range(state.companies.size()):
		AccountingRules.settle(state.companies[index], sales[index], opening_cash[index])
		state.unserved_demand -= sales[index]
		state.total_sales += sales[index]
	for company in state.companies:
		company.market_share = float(company.sales) / state.total_sales if state.total_sales > 0 else 0.0
		state.record_event("%s: vendió %d; ingresos %.2f; beneficio %.2f." % [company.company_name, company.sales, company.revenue, company.operating_profit])
		if not company.active_this_cycle:
			state.record_event("%s: actividad suspendida, caja insuficiente para el costo fijo." % company.company_name)
		elif company.production < company.production_target and not config.extended_economy:
			state.record_event("%s: producción limitada por falta de caja." % company.company_name)
		if company.advertising_spending < company.advertising_budget:
			state.record_event("%s: presupuesto publicitario no cubierto; gasto real %.2f." % [company.company_name, company.advertising_spending])
		if company.operating_profit < 0.0:
			state.record_event("%s: pérdida operativa %.2f." % [company.company_name, company.operating_profit])
	LogisticsRules.finish_day(state)
	if config.extended_economy:
		CreditRules.collect_due(state)
		FleetRules.finish(state, config, reserved_today)
		for index in range(state.companies.size()):
			var company = state.companies[index]
			company.cash_flow = company.cash - opening_cash[index]
			company.cash_at_period_start = company.cash
			state.record_event("%s: venta cobrada %.2f, pagos de conversión %.2f, salarios devengados %.2f, mantenimiento %.2f, interés %.2f." % [company.company_name, company.revenue, company.production_spending, company.operations.salary_expense, company.operations.maintenance_expense, company.interest_expense])
			for reason in company.operations.penalties:
				state.record_event(company.company_name + ": " + reason)
		state.logistics.cash_flow = state.logistics.cash - state.logistics.cash_at_period_start
		state.logistics.cash_at_period_start = state.logistics.cash
		Journal.record(state, before, "Cierre de ciclo")
	state.logistics.valuation_age = state.cycle
	return true


func estimate_next_sales() -> Array[int]:
	## Proyecta un ciclo sobre copias: observar no gasta caja, no cambia marca ni eventos.
	if state == null:
		return []
	var preview = SimulationState.new(config)
	var service: Array[int] = []
	if config.extended_economy:
		service = FleetRules.service_capacities(state, config)
	for index in range(state.companies.size()):
		var source = state.companies[index]
		var copy = preview.companies[index]
		for field in ["cash", "price", "capacity", "production_target", "variable_unit_cost", "fixed_cost", "brand", "inventory", "inventory_value", "advertising_budget", "own_logistics_capacity", "contracted_capacity", "wages_payable"]:
			copy.set(field, source.get(field))
		if config.extended_economy:
			source.operations.copy_to(copy.operations, config)
			copy.contracted_capacity = service[index]
		ProductionRules.prepare(copy, config)
		AdvertisingRules.apply(copy, config)
	return DemandRules.allocate(preview.companies, config)


func request_contract(client_index: int, capacity: int, days: int, allow_credit: bool = false) -> Dictionary:
	## La interfaz solicita; las reglas validan capacidad, plazo y anticipo.
	if state == null:
		return {"ok": false, "message": "Simulación inválida."}
	var before: Array[float] = Journal.balances(state)
	var result: Dictionary = LogisticsRules.request(state, config, client_index, capacity, days, allow_credit)
	Journal.record(state, before, "Contrato de transporte")
	return result


func cancel_contract(contract_id: int) -> Dictionary:
	## Aplica las condiciones originales sin permitir que la vista altere estados.
	if state == null:
		return {"ok": false, "message": "Simulación inválida."}
	var before: Array[float] = Journal.balances(state)
	var result: Dictionary = LogisticsRules.cancel(state, contract_id)
	Journal.record(state, before, "Cancelación de contrato")
	return result


func acquire_logistics(buyer_index: int, quoted_price: float) -> Dictionary:
	## Revalida precio, fondos y propiedad en el momento de comprar, no en la vista.
	if state == null:
		return {"ok": false, "message": "Simulación inválida."}
	var before: Array[float] = Journal.balances(state)
	var result: Dictionary = AcquisitionRules.acquire(state, buyer_index, quoted_price)
	Journal.record(state, before, "Compra de empresa logística")
	return result


func consolidated_result() -> Dictionary:
	## Informe operativo del grupo; no incorpora revalorizaciones ni el precio de inversión.
	if state == null:
		return {"available": false}
	return AcquisitionRules.consolidated_result(state)


func manage_operations(client_index: int, action: String, amount: int) -> Dictionary:
	## Única entrada de decisiones físicas; registra la causa del cambio de caja.
	if state == null or not config.extended_economy or client_index < 0 or client_index >= state.companies.size():
		return {"ok": false, "message": "Cliente o modo de recursos inválido."}
	var before: Array[float] = Journal.balances(state)
	var company = state.companies[client_index]
	var result: Dictionary = OperationsRules.decide(company, config, action, amount)
	company.capacity = 0
	for machine in company.operations.machines:
		company.capacity += machine.capacity
	company.production_target = mini(company.production_target, company.capacity)
	state.record_event(company.company_name + ": " + result.message)
	Journal.record(state, before, result.message)
	return result


func pay_note(client_index: int, note_id: int, amount: float) -> Dictionary:
	## Un pago reduce deuda y aumenta caja del acreedor, sin reconocer otra vez el ingreso.
	if state == null or not config.extended_economy:
		return {"ok": false, "message": "Crédito no disponible."}
	var before: Array[float] = Journal.balances(state)
	var result: Dictionary = CreditRules.pay(state, client_index, note_id, amount)
	Journal.record(state, before, "Pago de pagaré")
	return result


func invest_in_logistics(client_index: int, units: int) -> Dictionary:
	## Financiar expansión compra un descuento temporal, nunca transfiere la propiedad.
	if state == null or not config.extended_economy:
		return {"ok": false, "message": "Inversión no disponible."}
	var before: Array[float] = Journal.balances(state)
	var result: Dictionary = FleetRules.invest(state, config, client_index, units)
	state.record_event(result.message)
	Journal.record(state, before, "Inversión en expansión logística")
	return result
