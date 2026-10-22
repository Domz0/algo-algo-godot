extends RefCounted
## Compra indivisible en el ejecutor local y presentación consolidada sin duplicar operaciones.


static func acquire(state, buyer_index: int, quoted_price: float) -> Dictionary:
	## Sin await ni señales entre validación y escritura: la primera solicitud válida gana.
	var operator = state.logistics
	var reason: String = ""
	var price: float = operator.acquisition_price()
	if buyer_index < 0 or buyer_index >= state.companies.size():
		reason = "Comprador inexistente."
	elif operator.owner_company_index != -1:
		reason = "La logística ya fue adquirida; no se permite recompra ni reventa."
	elif not is_finite(price) or price < 0.0 or not is_finite(quoted_price) or quoted_price != price:
		reason = "Cotización inválida o desactualizada; revisa el precio actual."
	elif not is_finite(state.companies[buyer_index].cash) or state.companies[buyer_index].cash < price:
		reason = "Fondos insuficientes en la caja de la productora."
	if not reason.is_empty():
		state.record_event("Compra rechazada: " + reason)
		return {"ok": false, "message": reason}
	var buyer = state.companies[buyer_index]
	var previous_owner: String = operator.owner
	# El pago va al vendedor externo, no a la caja de la empresa comprada.
	buyer.finance.category = "Adquisición de logística"
	buyer.cash -= price
	buyer.logistics_investment += price
	operator.owner_company_index = buyer_index
	operator.owner = buyer.company_name
	operator.acquired_cycle = state.cycle
	operator.acquisition_paid = price
	operator.external_seller_proceeds += price
	state.record_event("Compra completada: %s pagó %.2f a %s. Propietario: %s → %s." % [buyer.company_name, price, previous_owner, previous_owner, operator.owner])
	for contract in operator.contracts:
		if contract.reserves_capacity():
			state.record_event("Contrato #%d de %s conservado tras compra: tarifa %.2f, fijo %.2f, capacidad %d, fin día %d. %s" % [contract.id, contract.client_name, contract.unit_rate, contract.fixed_fee, contract.capacity, contract.end_cycle, "Operación relacionada desde el próximo ciclo." if contract.client_index == buyer_index else "Cliente externo al grupo."])
	return {"ok": true, "message": "Compra completada por %s: %.2f créditos." % [buyer.company_name, price], "price": price}


static func consolidated_result(state) -> Dictionary:
	## Solo consolida ciclos completos posteriores a la compra, sin atribuir beneficios anteriores.
	var operator = state.logistics
	if operator.owner_company_index < 0 or state.cycle <= operator.acquired_cycle:
		return {"available": false}
	var buyer = state.companies[operator.owner_company_index]
	# El mismo servicio aparece como gasto del comprador e ingreso de su filial.
	# Se elimina de ambas columnas; el costo real de operar la flota permanece.
	var internal_fee: float = buyer.logistics_expense + buyer.discount_expense
	var revenue: float = buyer.revenue + operator.revenue - internal_fee
	var costs: float = buyer.operating_costs + operator.operating_costs - internal_fee
	# Interés del dueño se elimina de ambos lados; solo queda ingreso financiero del rival.
	var external_interest: float = operator.interest_income - buyer.interest_expense
	return {"available": true, "revenue": revenue, "costs": costs, "profit": revenue - costs, "net_profit": revenue - costs + external_interest, "eliminated": internal_fee, "internal_interest": buyer.interest_expense}
