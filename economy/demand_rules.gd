extends RefCounted
## Mercado finito con comparación de precios y presupuesto común limitado.


static func weight(company, config) -> float:
	## Precio de reserva: ninguna oferta extrema recibe compras garantizadas.
	if not company.active_this_cycle or company.inventory <= 0 or company.logistics_capacity() <= 0 or company.price >= config.reference_price * config.choke_price_multiplier:
		return 0.0
	return pow(config.reference_price / company.price, config.price_elasticity)


static func aggregate(companies: Array, config) -> int:
	## D = base * clamp((reserva - precio_general)/(reserva - referencia),0,1)^sensibilidad.
	## Precio general ponderado por atractivo; una oferta excluida no elimina compradores del rival.
	var weighted_price: float = 0.0
	var total: float = 0.0
	for company in companies:
		var attraction: float = weight(company, config)
		total += attraction
		weighted_price += company.price * attraction
	if total <= 0.0 or config.consumer_budget <= 0.0:
		return 0
	var average: float = weighted_price / total
	var reserve: float = config.reference_price * config.choke_price_multiplier
	var factor: float = pow(clampf((reserve - average) / (reserve - config.reference_price), 0.0, 1.0), config.aggregate_sensitivity)
	return int(floor(config.market_demand * factor))


static func allocate(companies: Array, config) -> Array[int]:
	## Reparte compradores por pesos y restos mayores; cada grupo recibe la misma proporción
	## del presupuesto. No reasigna clientes frustrados: stock, transporte y dinero limitan ventas.
	var demand: int = aggregate(companies, config)
	var weights: Array[float] = []
	var total: float = 0.0
	for company in companies:
		weights.append(weight(company, config))
		total += weights.back()
	var quotas: Array[int] = []
	var remainders: Array[float] = []
	var assigned: int = 0
	for attraction in weights:
		var exact: float = demand * attraction / total if total > 0.0 else 0.0
		quotas.append(int(floor(exact)))
		remainders.append(exact - floor(exact))
		assigned += quotas.back()
	for unused in range(demand - assigned):
		var best: int = 0
		for index in range(1, remainders.size()):
			if remainders[index] > remainders[best]:
				best = index
		quotas[best] += 1
		remainders[best] = -1.0
	var sales: Array[int] = []
	for index in range(companies.size()):
		var company = companies[index]
		var budget: float = config.consumer_budget * weights[index] / total if total > 0.0 else 0.0
		var affordable: int = int(floor(budget / company.price))
		sales.append(mini(affordable, mini(quotas[index], mini(company.inventory, company.logistics_capacity()))))
	return sales
