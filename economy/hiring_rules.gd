extends RefCounted
## Separa vacantes, candidatos seleccionados e incorporaciones para evitar empleo instantáneo.


static func advance(ops, config) -> void:
	## Primero llegan candidatos anteriores; los seleccionados hoy esperan al menos otro ciclo.
	for batch in ops.pending_hires.duplicate():
		batch.remaining -= 1
		if batch.remaining <= 0:
			ops.employees += batch.count
			ops.pending_hires.erase(batch)
	var selected: int = mini(ops.vacancies, config.hiring_speed)
	if selected > 0:
		ops.vacancies -= selected
		ops.pending_hires.append({"count": selected, "remaining": config.hiring_delay})
