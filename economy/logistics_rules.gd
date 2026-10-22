extends RefCounted
## Valida reservas, anticipos, cumplimiento de plazos y liquidación del operador.

const Contract = preload("res://economy/logistics_contract.gd")
const CreditRules = preload("res://economy/credit_rules.gd")
const FleetRules = preload("res://economy/fleet_rules.gd")


static func request(state, config, client_index: int, capacity: int, days: int, allow_credit: bool = false) -> Dictionary:
	## Valida todo antes de mover dinero o capacidad; no hay reservas parcialmente aceptadas.
	state.record_event("Solicitud logística: cliente %d, capacidad %d, duración %d días." % [client_index, capacity, days])
	if client_index < 0 or client_index >= state.companies.size():
		return _reject(state, "Cliente inexistente.")
	if capacity <= 0 or days < 1 or days > config.maximum_contract_days:
		return _reject(state, "Capacidad o duración inválida.")
	var operator = state.logistics
	if config.extended_economy:
		operator.requested_capacity += capacity
	if capacity > operator.available_capacity():
		return _reject(state, "Capacidad logística insuficiente.")
	var rate: float = operator.unit_rate
	if config.extended_economy:
		var discount: float = FleetRules.discount_for(state, client_index)
		for agreement in operator.investments:
			if agreement.client_index == client_index and state.cycle < agreement.end_cycle and days > agreement.end_cycle - state.cycle:
				return _reject(state, "El plazo supera la vigencia del descuento; solicita un contrato más corto.")
		rate *= 1.0 - discount
	var payment: float = (capacity * rate + operator.fixed_fee) * days
	var client = state.companies[client_index]
	var financed: bool = payment > client.cash
	if not is_finite(payment) or (financed and (not config.extended_economy or not allow_credit or not CreditRules.can_finance(state, config, client_index, payment))):
		return _reject(state, "Caja insuficiente para el anticipo completo.")
	var contract = Contract.new()
	contract.id = operator.next_contract_id
	contract.client_index = client_index
	contract.client_name = client.company_name
	contract.capacity = capacity
	contract.unit_rate = rate
	contract.fixed_fee = operator.fixed_fee
	contract.unit_operating_cost = config.logistics_unit_cost
	contract.fixed_operating_cost = config.logistics_contract_cost
	contract.duration = days
	contract.start_cycle = state.cycle + 1
	contract.end_cycle = state.cycle + days
	contract.prepaid_balance = payment
	if financed:
		CreditRules.issue(state, config, contract, payment)
	else:
		client.cash -= payment
		operator.cash += payment
	client.prepaid_logistics += payment
	operator.deferred_revenue += payment
	operator.next_contract_id += 1
	operator.contracts.append(contract)
	sync_capacity(state)
	state.record_event("Contrato #%d aceptado para %s; importe %.2f por %s, días %d–%d." % [contract.id, client.company_name, payment, contract.payment_terms, contract.start_cycle, contract.end_cycle])
	return {"ok": true, "message": "Contrato #%d aceptado. Importe %.2f (%s)." % [contract.id, payment, contract.payment_terms], "id": contract.id}


static func _reject(state, reason: String) -> Dictionary:
	## El rechazo queda visible sin cambiar activos ni compromisos.
	state.record_event("Solicitud rechazada: " + reason)
	return {"ok": false, "message": reason, "id": -1}


static func cancel(state, contract_id: int) -> Dictionary:
	## Solo se admite desistir antes del primer día; no se acorta un plazo en curso.
	for contract in state.logistics.contracts:
		if contract.id != contract_id:
			continue
		if contract.status != "pendiente" or state.cycle >= contract.start_cycle:
			return _reject(state, "El contrato no admite cancelación: debe cumplir su duración o ya terminó.")
		var refund: float = contract.prepaid_balance
		var client = state.companies[contract.client_index]
		if contract.note_id >= 0:
			var note = state.logistics.notes[contract.note_id - 1]
			# Si ya hubo abonos antes de iniciar, solo esa parte se devuelve en efectivo.
			var paid_refund: float = maxf(0.0, refund - note.principal)
			client.cash += paid_refund
			state.logistics.cash -= paid_refund
			client.note_debt = maxf(0.0, client.note_debt - note.balance())
			state.logistics.receivables = maxf(0.0, state.logistics.receivables - note.balance())
			note.principal = 0.0
			note.interest_due = 0.0
			note.status = "cancelado"
		else:
			client.cash += refund
			state.logistics.cash -= refund
		client.prepaid_logistics = maxf(0.0, client.prepaid_logistics - refund)
		state.logistics.deferred_revenue = maxf(0.0, state.logistics.deferred_revenue - refund)
		contract.prepaid_balance = 0.0
		contract.status = "cancelado"
		sync_capacity(state)
		state.record_event("Contrato #%d cancelado antes del inicio; anticipo %.2f revertido: devolución de efectivo cobrado y anulación de principal no pagado." % [contract.id, refund])
		return {"ok": true, "message": "Contrato cancelado; pagos devueltos y deuda pendiente anulada."}
	return _reject(state, "Contrato inexistente.")


static func sync_capacity(state) -> void:
	## Recalcula reservas desde los contratos para evitar contadores divergentes.
	var previous: int = state.logistics.contracted_capacity
	state.logistics.contracted_capacity = 0
	for client in state.companies:
		client.contracted_capacity = 0
	for contract in state.logistics.contracts:
		if contract.reserves_capacity():
			state.logistics.contracted_capacity += contract.capacity
			state.companies[contract.client_index].contracted_capacity += contract.capacity
	if previous != state.logistics.contracted_capacity:
		state.record_event("Capacidad logística: reservada %d, disponible %d." % [state.logistics.contracted_capacity, state.logistics.available_capacity()])


static func settle_day(state) -> void:
	## Reconoce un día de servicio: reduce anticipos, sin volver a cobrar al cliente.
	var operator = state.logistics
	operator.revenue = 0.0
	operator.operating_costs = 0.0
	operator.distributed_units = 0
	for contract in operator.contracts:
		if not contract.reserves_capacity():
			continue
		contract.status = "activo"
		var fee: float = contract.daily_fee()
		# El último día absorbe el residuo binario del anticipo, sin dejar saldos fantasma.
		if contract.served_days + 1 == contract.duration:
			fee = contract.prepaid_balance
		var client = state.companies[contract.client_index]
		client.logistics_expense += fee
		client.prepaid_logistics = maxf(0.0, client.prepaid_logistics - fee)
		contract.prepaid_balance = maxf(0.0, contract.prepaid_balance - fee)
		operator.deferred_revenue = maxf(0.0, operator.deferred_revenue - fee)
		operator.revenue += fee
		operator.operating_costs += contract.daily_cost()
		contract.served_days += 1
	# Las tarifas cubren costos por validación; maxf solo elimina residuos de coma flotante.
	if not operator.extended:
		operator.cash = maxf(0.0, operator.cash - operator.operating_costs)
	operator.cash_flow = -operator.operating_costs
	operator.operating_profit = operator.revenue - operator.operating_costs


static func finish_day(state) -> void:
	## Usa primero capacidad propia y libera reservas solo después del último servicio.
	for client in state.companies:
		client.distributed_units = client.sales
		state.logistics.distributed_units += maxi(0, client.sales - client.own_logistics_capacity)
		if client.active_this_cycle and client.inventory > 0 and client.sales >= client.distribution_limit:
			state.record_event("%s: límite de distribución alcanzado (%d); queda inventario sin vender." % [client.company_name, client.distribution_limit])
	for contract in state.logistics.contracts:
		if contract.status == "activo" and contract.served_days >= contract.duration:
			contract.status = "vencido"
			state.record_event("Contrato #%d vencido: plazo cumplido." % contract.id)
	sync_capacity(state)
