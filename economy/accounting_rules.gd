extends RefCounted
## Liquida ventas sin confundir el gasto contable con el desembolso de producción.


static func settle(company, units_sold: int, opening_cash: float) -> void:
	## Promedio ponderado: el stock antiguo y nuevo comparten un costo medio.
	company.sales = clampi(units_sold, 0, company.inventory)
	var average_cost: float = 0.0
	if company.inventory > 0:
		average_cost = company.inventory_value / company.inventory
	company.cost_of_goods_sold = company.sales * average_cost
	company.inventory -= company.sales
	company.inventory_value = maxf(0.0, company.inventory_value - company.cost_of_goods_sold)
	if company.inventory == 0:
		company.inventory_value = 0.0
	company.revenue = company.sales * company.price
	company.operating_costs = company.cost_of_goods_sold + company.fixed_cost_paid + company.logistics_expense
	if company.operations != null:
		var ops = company.operations
		company.operating_costs += ops.salary_expense + ops.maintenance_expense + ops.other_expense + company.discount_expense
	if company.own_fleet != null:
		company.operating_costs += company.own_fleet.expense
	company.operating_profit = company.revenue - company.operating_costs
	company.net_profit = company.operating_profit - company.interest_expense
	company.finance.category = "Ventas cobradas"
	company.cash += company.revenue
	# Flujo = ingresos - producción pagada - fijo; difiere del beneficio.
	company.cash_flow = company.cash - opening_cash
