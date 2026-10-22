extends RefCounted
## Publica movimientos brutos del libro, incluso operaciones cuyo saldo neto es cero.


static func balances(state) -> Array[float]:
	## Consulta de saldos conservada para las operaciones existentes.
	return [state.companies[0].cash, state.companies[1].cash, state.logistics.cash]


static func record(state, _before: Array[float], _reason: String) -> void:
	## Vacía la cola una sola vez: refrescar no duplica movimientos ni genera dinero.
	var entities: Array = state.companies.duplicate()
	entities.append(state.logistics)
	for index in range(entities.size()):
		var entity = entities[index]
		for entry in entity.finance.pending_events:
			var recorded: Dictionary = entry.duplicate()
			recorded.merge({"cycle": state.cycle, "entity": index})
			state.journal.append(recorded)
			state.record_event("%s — %s: %+.2f; caja %.2f → %.2f." % [entity.company_name, entry.reason, entry.change, entry.before, entry.after])
		entity.finance.pending_events.clear()
	while state.journal.size() > 300:
		state.journal.pop_front()
