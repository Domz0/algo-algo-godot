extends VBoxContainer
## Controles locales del operador y contratos; delega todas las decisiones en Simulation.

signal contract_requested(client_index: int, capacity: int, days: int, allow_credit: bool)
signal note_payment_requested(client_index: int, note_id: int, amount: float)
signal investment_requested(client_index: int, units: int)
signal cancellation_requested(contract_id: int)
signal acquisition_requested(buyer_index: int, quoted_price: float)

var client_index: int = 0
var simulation
var quote_label: Label
var summary: Label
var capacity_input: SpinBox
var days_input: SpinBox
var request_button: Button
var contract_input: OptionButton
var cancel_button: Button
var contracts_view: TextEdit
var purchase_button: Button
var purchase_label: Label
var purchase_result: Label
var quoted_price: float = 0.0
var credit_input: CheckBox
var finance_view: TextEdit
var note_input: SpinBox
var payment_input: SpinBox
var payment_button: Button
var investment_button: Button


func setup(state, config, index: int = 0) -> void:
	## Monta campos mínimos y conecta botones a señales que recibe la pantalla principal.
	client_index = index
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary = Label.new()
	add_child(summary)
	var purchase_row := HBoxContainer.new()
	add_child(purchase_row)
	purchase_button = Button.new()
	purchase_button.text = "Comprar empresa logística"
	purchase_button.pressed.connect(_purchase)
	purchase_row.add_child(purchase_button)
	purchase_label = Label.new()
	add_child(purchase_label)
	purchase_result = Label.new()
	purchase_result.text = "Sin intento de compra."
	add_child(purchase_result)
	var details := TabContainer.new()
	add_child(details)
	var contract_content := VBoxContainer.new()
	contract_content.name = "Arrendar"
	details.add_child(contract_content)
	var row := GridContainer.new()
	row.columns = 2
	contract_content.add_child(row)
	capacity_input = _number(row, "Capacidad diaria", 1, maxi(1, state.logistics.total_capacity))
	days_input = _number(row, "Días", 1, config.maximum_contract_days)
	quote_label = Label.new()
	quote_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contract_content.add_child(quote_label)
	capacity_input.value_changed.connect(_refresh_quote)
	days_input.value_changed.connect(_refresh_quote)
	request_button = Button.new()
	request_button.text = "Solicitar contrato (anticipo)"
	request_button.pressed.connect(_request)
	contract_content.add_child(request_button)
	credit_input = CheckBox.new()
	credit_input.text = "Permitir pagaré si no alcanza la caja (interés simple)"
	credit_input.visible = config.extended_economy
	contract_content.add_child(credit_input)
	var terms := Label.new()
	terms.text = "Pago anticipado de todo el plazo. Cancelación con reembolso solo antes del primer día de servicio."
	if config.extended_economy:
		terms.text = "Anticipo o pagaré autorizado: interés %.2f%%/día, vence en %d días; atraso bloquea nuevo crédito.\nCancelar antes del servicio devuelve pagos y extingue deuda no cobrada. Descuento: plazo dentro de su vigencia." % [config.note_interest_rate * 100.0, config.note_maturity_days]
	contract_content.add_child(terms)
	for label in [summary, purchase_label, purchase_result, terms]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contracts_view = TextEdit.new()
	contracts_view.editable = false
	contracts_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	contracts_view.custom_minimum_size.y = 130
	contract_content.add_child(contracts_view)
	var cancel_row := HBoxContainer.new()
	contract_content.add_child(cancel_row)
	contract_input = OptionButton.new()
	contract_input.fit_to_longest_item = false
	contract_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_row.add_child(contract_input)
	cancel_button = Button.new()
	cancel_button.text = "Solicitar cancelación"
	cancel_button.pressed.connect(_cancel)
	cancel_row.add_child(cancel_button)
	if config.extended_economy:
		var finance_content := VBoxContainer.new()
		finance_content.name = "Deudas e inversión"
		details.add_child(finance_content)
		var finance_row := GridContainer.new()
		finance_row.columns = 2
		finance_content.add_child(finance_row)
		note_input = _number(finance_row, "Pagaré ID", 1, 100000)
		payment_input = _number(finance_row, "Importe", 1, 1000000)
		payment_input.step = 0.01
		payment_button = Button.new()
		payment_button.text = "Pagar deuda de mi empresa"
		payment_button.pressed.connect(_pay_note)
		finance_content.add_child(payment_button)
		investment_button = Button.new()
		investment_button.text = "Invertir · descuento %.0f%% durante %d días" % [config.investment_discount * 100, config.investment_discount_days]
		investment_button.pressed.connect(_invest)
		finance_content.add_child(investment_button)
		finance_view = TextEdit.new()
		finance_view.editable = false
		finance_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		finance_view.custom_minimum_size.y = 200
		finance_content.add_child(finance_view)


func _number(row: Container, caption: String, minimum: int, maximum: int) -> SpinBox:
	## Los límites visibles ayudan a editar, pero el modelo vuelve a validar las solicitudes.
	var label := Label.new()
	label.text = caption
	row.add_child(label)
	var input := SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.step = 1
	input.value = minimum
	row.add_child(input)
	return input


func _request() -> void:
	## Confirma el texto pendiente y transmite una solicitud, sin reservar capacidad aquí.
	capacity_input.apply()
	days_input.apply()
	contract_requested.emit(client_index, int(capacity_input.value), int(days_input.value), credit_input.button_pressed)


func _cancel() -> void:
	## El identificador es estable aunque cambie el orden de los elementos visibles.
	if contract_input.selected >= 0:
		cancellation_requested.emit(contract_input.get_selected_id())


func _purchase() -> void:
	## Envía el precio mostrado; el modelo rechaza una cotización que haya cambiado.
	acquisition_requested.emit(client_index, quoted_price)


func refresh(state) -> void:
	## Presenta capacidades actuales y resultados del último día sin simular servicios.
	var operator = state.logistics
	_refresh_quote()
	quoted_price = operator.acquisition_price()
	purchase_button.disabled = operator.owner_company_index >= 0
	purchase_label.text = "Precio de empresa %.2f | Mi caja %.2f" % [quoted_price, state.companies[client_index].cash]
	summary.text = "%s
Propietario: %s
Disponibles %d / %d · arrendadas %d
Transporte: %.2f por unidad + %.2f fijo / día" % [operator.company_name, operator.owner, operator.available_capacity(), operator.total_capacity, operator.contracted_capacity, operator.unit_rate, operator.fixed_fee]
	var selected_id: int = contract_input.get_selected_id()
	contract_input.clear()
	var lines := PackedStringArray()
	for contract in operator.contracts:
		if contract.client_index != client_index:
			continue
		lines.append("#%d %s | %s | %d unidades/día | tarifa %.2f + fijo %.2f = %.2f/día\n    Duración %d días (%d–%d), cumplidos %d | Anticipo pendiente %.2f" % [contract.id, contract.client_name, contract.status, contract.capacity, contract.unit_rate, contract.fixed_fee, contract.daily_fee(), contract.duration, contract.start_cycle, contract.end_cycle, contract.served_days, contract.prepaid_balance])
		if contract.reserves_capacity():
			lines.append("    Pago: %s | Pagaré ID %d" % [contract.payment_terms, contract.note_id])
			contract_input.add_item("#%d %s (%s)" % [contract.id, contract.client_name, contract.status], contract.id)
			if contract.id == selected_id:
				contract_input.select(contract_input.item_count - 1)
	contracts_view.text = "Sin contratos." if lines.is_empty() else "\n".join(lines)
	cancel_button.disabled = contract_input.item_count == 0
	if finance_view != null:
		capacity_input.max_value = maxi(1, operator.total_capacity)
		var finance_lines: PackedStringArray = ["Combustible %.2f | Personal %.2f | Mantenimiento %.2f | Fijo %.2f\nObligaciones operativas %.2f | Cuentas por cobrar %.2f | Interés ganado %.2f\nBeneficio neto %.2f | Caja entre cierres %+.2f\nFlota adquirida al costo %.2f | Derechos de descuento pendientes %.2f" % [operator.fuel_expense, operator.staff_expense, operator.maintenance_expense, operator.fixed_expense, operator.operating_payable, operator.receivables, operator.interest_income, operator.net_profit, operator.cash - operator.cash_at_period_start, operator.expansion_book_value, operator.discount_deferred]]
		for note in operator.notes:
			if note.client_index != client_index:
				continue
			finance_lines.append("Pagaré #%d cliente %s: %s | principal %.2f + intereses %.2f = %.2f\n  Tasa %.4f/día; vence día %d; abonos %s" % [note.id, state.companies[note.client_index].company_name, note.status, note.principal, note.interest_due, note.balance(), note.interest_rate, note.due_cycle, str(note.payments)])
		for agreement in operator.investments:
			if agreement.client_index != client_index:
				continue
			finance_lines.append("Inversión %s: %.2f por %d capacidad; descuento %.0f%% días %d–%d; derecho pendiente %.2f" % [state.companies[agreement.client_index].company_name, agreement.amount, agreement.units, agreement.discount * 100, agreement.start_cycle, agreement.end_cycle, agreement.remaining])
		finance_view.text = "\n".join(finance_lines)
		finance_view.text += "\nPatrimonio logístico al costo: %.2f" % operator.book_equity()
		finance_view.text += "\nPersonal eventual utilizado: %d trabajadores (remuneración por entrega)." % operator.employees


func _refresh_quote(_value: float = 0.0) -> void:
	## Muestra el presupuesto del modelo; cambiar los campos no reserva capacidad ni cobra.
	if simulation == null:
		return
	var offer: Dictionary = simulation.contract_quote(client_index, int(capacity_input.value), int(days_input.value))
	quote_label.text = "Costo diario %.2f · anticipo total %.2f\nLa firma vuelve a comprobar fondos, capacidad y condiciones." % [offer.daily, offer.total]


func _pay_note() -> void:
	## No calcula interés ni saldo: el modelo acota el pago y registra las dos cajas.
	note_input.apply()
	payment_input.apply()
	note_payment_requested.emit(client_index, int(note_input.value), payment_input.value)


func _invest() -> void:
	## Financia unidades nuevas usando el cliente y cantidad elegidos, sin comprar propiedad.
	capacity_input.apply()
	investment_requested.emit(client_index, int(capacity_input.value))
