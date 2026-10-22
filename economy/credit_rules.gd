extends RefCounted
## Intereses, pagos y vencimientos: cada transferencia cambia caja de ambas partes una sola vez.

const Note = preload("res://economy/promissory_note.gd")


static func can_finance(state, config, client_index: int, amount: float) -> bool:
	## El límite de deuda y los atrasos impiden nuevos créditos; el operador debe poder prestar servicio.
	if not config.credit_enabled or state.companies[client_index].note_debt + amount > config.credit_limit_per_client:
		return false
	for note in state.logistics.notes:
		if note.client_index == client_index and note.status == "vencido" and note.blocks_credit_when_overdue:
			return false
	return state.logistics.available_cash() - state.logistics.receivables >= amount


static func issue(state, config, contract, amount: float) -> void:
	## Financia todo el anticipo sin fingir una transferencia de efectivo.
	var note = Note.new()
	note.id = state.logistics.notes.size() + 1
	note.client_index = contract.client_index
	note.contract_id = contract.id
	note.original_principal = amount
	note.principal = amount
	note.interest_rate = config.note_interest_rate
	note.issued_cycle = state.cycle
	note.due_cycle = state.cycle + config.note_maturity_days
	note.blocks_credit_when_overdue = config.credit_block_overdue
	state.logistics.notes.append(note)
	state.logistics.receivables += amount
	state.companies[note.client_index].note_debt += amount
	contract.note_id = note.id
	contract.payment_terms = "pagaré"
	state.record_event("Pagaré #%d: principal %.2f, interés simple %.4f por día, vencimiento día %d." % [note.id, amount, note.interest_rate, note.due_cycle])


static func accrue(state) -> void:
	## Un período genera interés una sola vez; no aplica interés sobre intereses impagados.
	state.logistics.interest_income = 0.0
	for note in state.logistics.notes:
		if note.status == "pagado" or note.status == "cancelado":
			continue
		var interest: float = note.principal * note.interest_rate
		note.interest_due += interest
		state.companies[note.client_index].interest_expense += interest
		state.companies[note.client_index].note_debt += interest
		state.logistics.interest_income += interest
		state.logistics.receivables += interest
		state.record_event("Interés pagaré #%d: %.2f; deuda %.2f (sin movimiento de caja)." % [note.id, interest, note.balance()])


static func pay(state, client_index: int, note_id: int, amount: float) -> Dictionary:
	## Abona primero interés y luego principal; el importe no puede superar caja ni saldo.
	if client_index < 0 or client_index >= state.companies.size() or not is_finite(amount) or amount <= 0.0:
		return {"ok": false, "message": "Pago inválido."}
	for note in state.logistics.notes:
		if note.id != note_id or note.client_index != client_index or note.balance() <= 0.0:
			continue
		var client = state.companies[client_index]
		var paid: float = minf(amount, minf(client.cash, note.balance()))
		if paid <= 0.0:
			return {"ok": false, "message": "Sin caja para pagar el pagaré."}
		var interest_paid: float = minf(paid, note.interest_due)
		note.interest_due -= interest_paid
		note.principal = maxf(0.0, note.principal - (paid - interest_paid))
		client.finance.category = "Intereses pagados"
		state.logistics.finance.category = "Intereses cobrados"
		client.cash -= interest_paid
		state.logistics.cash += interest_paid
		client.finance.category = "Principal de deuda pagado"
		state.logistics.finance.category = "Principal de deuda cobrado"
		client.cash -= paid - interest_paid
		client.note_debt = maxf(0.0, client.note_debt - paid)
		state.logistics.cash += paid - interest_paid
		state.logistics.receivables = maxf(0.0, state.logistics.receivables - paid)
		note.payments.append({"cycle": state.cycle, "amount": paid, "interest": interest_paid})
		if note.balance() < 0.0000001:
			note.principal = 0.0
			note.interest_due = 0.0
			note.status = "pagado"
		state.record_event("Pago pagaré #%d: %.2f, saldo %.2f." % [note.id, paid, note.balance()])
		return {"ok": true, "message": "Pagaré #%d: pago %.2f." % [note.id, paid]}
	return {"ok": false, "message": "No existe un pagaré pendiente de ese cliente."}


static func collect_due(state) -> void:
	## Al vencimiento intenta cobrar después de las ventas; el saldo vencido bloquea nuevo crédito.
	for note in state.logistics.notes:
		if state.cycle >= note.due_cycle and note.balance() > 0.0:
			pay(state, note.client_index, note.id, note.balance())
			if note.balance() > 0.0000001:
				note.status = "vencido"
				state.record_event("Incumplimiento pagaré #%d: saldo %.2f; bloqueo de crédito %s, interés simple continúa." % [note.id, note.balance(), str(note.blocks_credit_when_overdue)])
