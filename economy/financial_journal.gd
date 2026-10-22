extends RefCounted
## Auditoría de efectivo por operación atómica; el registro no modifica ni genera dinero.


static func balances(state) -> Array[float]:
	## Captura saldos antes de una acción o un ciclo para comprobar sus cambios reales.
	return [state.companies[0].cash, state.companies[1].cash, state.logistics.cash]


static func record(state, before: Array[float], reason: String) -> void:
	## Registra una sola vez el cambio neto de cada entidad; los detalles son eventos explicativos.
	var after: Array[float] = balances(state)
	var names: Array = [state.companies[0].company_name, state.companies[1].company_name, state.logistics.company_name]
	for index in range(3):
		if after[index] == before[index]:
			continue
		state.journal.append({"cycle": state.cycle, "entity": index, "reason": reason, "before": before[index], "change": after[index] - before[index], "after": after[index]})
		state.record_event("%s — %s: caja %.2f → %.2f (movimiento %+.2f)." % [names[index], reason, before[index], after[index], after[index] - before[index]])
	while state.journal.size() > 300:
		state.journal.pop_front()
