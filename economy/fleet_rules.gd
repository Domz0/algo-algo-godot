extends RefCounted
## Actividad logística, precios graduales y expansión financiada con efectivo real.


static func service_capacities(state, config) -> Array[int]:
	## Reserva efectivo para obligaciones; solo ofrece transporte con combustible y nómina financiables.
	var operator = state.logistics
	var committed: float = operator.operating_payable + config.logistics_fixed_overhead + operator.contracted_capacity * config.fleet_maintenance_per_reserved_unit
	for contract in operator.contracts:
		if contract.reserves_capacity():
			committed += contract.daily_cost()
	var funds: float = maxf(0.0, operator.cash - committed)
	var per_delivery: float = config.fuel_cost_per_delivery + config.logistics_wage_per_delivery
	var capacity: int = operator.contracted_capacity
	if per_delivery > 0.0:
		capacity = mini(capacity, int(floor(funds / per_delivery)))
	if operator.cash < committed:
		capacity = 0
	var result: Array[int] = []
	# Prioridad estable A/B solo en insolvencia del operador; no libera reservas vendidas.
	for client in state.companies:
		var units: int = mini(client.contracted_capacity, capacity)
		result.append(units)
		capacity -= units
	return result


static func discount_for(state, client_index: int) -> float:
	## Un solo acuerdo vigente por cliente evita acumulación ilimitada de descuentos.
	for agreement in state.logistics.investments:
		if agreement.client_index == client_index and state.cycle < agreement.end_cycle:
			return agreement.discount
	return 0.0


static func invest(state, config, client_index: int, units: int) -> Dictionary:
	## El cliente financia flota directamente: transferencia y compra al proveedor forman una operación.
	var operator = state.logistics
	if client_index < 0 or client_index >= state.companies.size() or units <= 0 or units > config.logistics_max_capacity - operator.total_capacity:
		return {"ok": false, "message": "Inversión fuera de límites de capacidad."}
	for agreement in operator.investments:
		if agreement.client_index == client_index and state.cycle < agreement.end_cycle:
			return {"ok": false, "message": "Ya existe un descuento vigente; no se acumulan acuerdos."}
	var amount: float = units * config.logistics_expansion_unit_cost
	var client = state.companies[client_index]
	if not is_finite(amount) or client.cash < amount:
		return {"ok": false, "message": "Capital insuficiente para invertir."}
	client.finance.category = "Inversión por descuento logístico"
	client.cash -= amount
	operator.finance.category = "Financiación de expansión por cliente"
	operator.cash += amount
	operator.finance.category = "Compra de flota logística"
	operator.cash -= amount
	client.discount_asset += amount
	# La caja del operador recibe y paga exactamente el mismo importe al proveedor de flota.
	operator.total_capacity += units
	operator.expanded_units += units
	operator.expansion_book_value += amount
	operator.discount_deferred += amount
	operator.investments.append({"client_index": client_index, "amount": amount, "units": units, "discount": config.investment_discount, "duration": config.investment_discount_days, "start_cycle": state.cycle + 1, "end_cycle": state.cycle + config.investment_discount_days, "remaining": amount})
	state.record_event("Inversión %s: pago %.2f a proveedor de flota por cuenta de logística; +%d capacidad; descuento %.0f%% hasta día %d. No cambia propietario." % [client.company_name, amount, units, config.investment_discount * 100, state.cycle + config.investment_discount_days])
	return {"ok": true, "message": "Expansión financiada y descuento registrados."}


static func recognize_discounts(state) -> void:
	## El derecho al descuento se consume por tiempo, aunque el cliente no contrate transporte.
	var operator = state.logistics
	operator.discount_income = 0.0
	for agreement in operator.investments:
		if agreement.remaining <= 0.0:
			continue
		var amount: float = minf(agreement.remaining, agreement.amount / agreement.duration)
		if state.cycle >= agreement.end_cycle:
			amount = agreement.remaining
		agreement.remaining = maxf(0.0, agreement.remaining - amount)
		var client = state.companies[agreement.client_index]
		client.discount_asset = maxf(0.0, client.discount_asset - amount)
		client.discount_expense += amount
		operator.discount_deferred = maxf(0.0, operator.discount_deferred - amount)
		operator.discount_income += amount


static func finish(state, config, reserved_today: int) -> void:
	## Combustible y personal se pagan por entregas reales; mantenimiento por capacidad comprometida.
	var operator = state.logistics
	operator.fuel_expense = operator.distributed_units * config.fuel_cost_per_delivery
	operator.staff_expense = operator.distributed_units * config.logistics_wage_per_delivery
	operator.maintenance_expense = reserved_today * config.fleet_maintenance_per_reserved_unit
	operator.fixed_expense = config.logistics_fixed_overhead
	# Cuadrillas por entrega: personal eventual facturado por unidad, sin plantilla permanente.
	operator.employees = int(ceil(float(operator.distributed_units) / config.logistics_units_per_worker))
	var current_costs: Dictionary = {"Operación de contratos": operator.operating_costs, "Combustible logístico": operator.fuel_expense, "Personal logístico eventual": operator.staff_expense, "Mantenimiento logístico": operator.maintenance_expense, "Gastos fijos logísticos": operator.fixed_expense}
	operator.operating_costs += operator.fuel_expense + operator.staff_expense + operator.maintenance_expense + operator.fixed_expense
	var payment: float = 0.0
	operator.operating_payable = 0.0
	for category in current_costs:
		var obligation: float = operator.payable_categories.get(category, 0.0) + current_costs[category]
		var paid: float = minf(operator.cash, obligation)
		operator.finance.category = category
		operator.cash -= paid
		payment += paid
		operator.payable_categories[category] = obligation - paid
		operator.operating_payable += obligation - paid
	operator.revenue += operator.discount_income
	operator.operating_profit = operator.revenue - operator.operating_costs
	operator.net_profit = operator.operating_profit + operator.interest_income
	state.record_event("Logística: cobros por contratos se reconocen %.2f; combustible %.2f, personal %.2f, mantenimiento %.2f; pago operativo %.2f, pendiente %.2f." % [operator.revenue, operator.fuel_expense, operator.staff_expense, operator.maintenance_expense, payment, operator.operating_payable])
	var utilization: float = float(maxi(reserved_today, operator.requested_capacity)) / maxi(1, operator.total_capacity)
	var old_rate: float = operator.unit_rate
	operator.unit_rate = clampf(old_rate * (1.0 + config.transport_price_adjustment * clampf(utilization - config.transport_target_utilization, -1.0, 1.0)), config.transport_min_price, config.transport_max_price)
	if old_rate != operator.unit_rate:
		state.record_event("Tarifa nuevos contratos: %.3f → %.3f por presión de demanda %.2f." % [old_rate, operator.unit_rate, utilization])
	if config.logistics_auto_expand and utilization >= config.logistics_expansion_utilization:
		var units: int = mini(config.logistics_expansion_units, config.logistics_max_capacity - operator.total_capacity)
		var cost: float = units * config.logistics_expansion_unit_cost
		if units > 0 and operator.operating_payable == 0.0 and operator.available_cash() - cost >= config.logistics_cash_reserve:
			operator.finance.category = "Compra de flota logística"
			operator.cash -= cost
			operator.total_capacity += units
			operator.expanded_units += units
			operator.expansion_book_value += cost
			state.record_event("Expansión automática: +%d capacidad; pago real %.2f, caja libre restante %.2f." % [units, cost, operator.available_cash()])
	operator.requested_capacity = 0
