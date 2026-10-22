extends RefCounted
## Aplica restricciones físicas y de caja antes de ofrecer producto al mercado.
const OperationsRules = preload("res://economy/operations_rules.gd")


static func prepare(company, config = null, reset: bool = true) -> void:
	## Sin crédito: una empresa que no cubre el costo fijo suspende toda actividad.
	if reset:
		company.reset_cycle_results()
	if company.operations != null:
		OperationsRules.prepare(company, config)
		return
	if company.cash < company.fixed_cost:
		return
	company.active_this_cycle = true
	company.fixed_cost_paid = company.fixed_cost
	company.cash -= company.fixed_cost_paid
	var units: int = mini(company.capacity, maxi(0, company.production_target))
	if company.variable_unit_cost > 0.0:
		units = mini(units, int(floor(company.cash / company.variable_unit_cost)))
	company.production = units
	company.production_spending = units * company.variable_unit_cost
	company.cash = maxf(0.0, company.cash - company.production_spending)
	company.inventory += units
	company.inventory_value += company.production_spending
