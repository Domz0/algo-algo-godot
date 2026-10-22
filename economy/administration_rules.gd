extends RefCounted
## Políticas administrativas persistentes; la interfaz solo propone objetivos y presupuestos.

const Operations = preload("res://economy/operations_rules.gd")


static func set_staff_target(company, config, target: int) -> Dictionary:
	## El objetivo no incorpora personas: reserva vacantes que cubrirá el proceso gradual existente.
	var ops = company.operations
	if target < ops.employees or target > config.maximum_staff_target:
		return {"ok": false, "message": "El objetivo debe estar entre la plantilla actual y el límite. Para reducirla usa Despedir."}
	var committed: int = ops.employees + ops.vacancies + ops.pending_count()
	var additional: int = maxi(0, target - committed)
	var cost: float = additional * config.hiring_cost
	if not is_finite(cost) or cost > company.cash:
		return {"ok": false, "message": "Caja insuficiente para abrir las nuevas vacantes; objetivo sin cambios."}
	if additional > 0:
		Operations.decide(company, config, "hire", additional)
	# Reducir un objetivo cancela primero vacantes y después candidatos aún no incorporados.
	# La selección pagada no se devuelve y nunca se despide a alguien al mover este objetivo.
	var excess: int = maxi(0, committed - target)
	var cancelled: int = mini(excess, ops.vacancies)
	ops.vacancies -= cancelled
	excess -= cancelled
	for batch in ops.pending_hires.duplicate():
		var count: int = mini(excess, batch.count)
		batch.count -= count
		excess -= count
		if batch.count == 0:
			ops.pending_hires.erase(batch)
	ops.staff_target = target
	return {"ok": true, "message": "Objetivo: %d empleados; incorporación gradual, selección pagada %.2f." % [target, cost]}


static func set_purchasing(company, config, enabled: bool, target: int, budget: float) -> Dictionary:
	## Guarda una reposición hasta objetivo; el presupuesto es un máximo por período, no un gasto fijo.
	if target < 0 or target > config.maximum_input_target or not is_finite(budget) or budget < 0.0 or budget > config.maximum_auto_purchase_budget:
		return {"ok": false, "message": "Objetivo de insumos o presupuesto fuera de límites."}
	company.operations.auto_inputs = enabled
	company.operations.input_target = target
	company.operations.input_budget = budget
	return {"ok": true, "message": "Reposición automática configurada." if enabled else "Compras manuales: reposición automática desactivada."}


static func purchase(company, config) -> void:
	## Repone antes de producir, respetando espacio y caja después de reservar apertura y nóminas.
	var ops = company.operations
	ops.auto_bought = 0
	ops.auto_spent = 0.0
	if not ops.auto_inputs:
		return
	var reserve: float = config.auto_purchase_cash_reserve + company.fixed_cost + company.wages_payable + ops.employees * config.wage_per_employee
	if company.own_fleet != null:
		reserve += company.own_fleet.payable + company.own_fleet.vehicles * (config.own_drivers_per_vehicle * config.own_driver_wage + config.own_vehicle_maintenance)
	var budget: float = minf(ops.input_budget, maxf(0.0, company.cash - reserve))
	var units: int = mini(maxi(0, ops.input_target - ops.warehouse.inputs), ops.warehouse.available(company.inventory))
	if config.input_price > 0.0:
		units = mini(units, int(floor(budget / config.input_price)))
	if units > 0:
		var before: float = company.cash
		var result: Dictionary = Operations.decide(company, config, "inputs", units)
		if result.ok:
			ops.auto_bought = units
			ops.auto_spent = before - company.cash
