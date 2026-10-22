extends RefCounted
## Reparte un único mercado entre empresas y la alternativa de no comprar.


static func allocate(companies: Array, config) -> Array[int]:
	## Peso = disponibilidad * (1 + fuerza_marca * marca) * (precio_ref / precio)^elasticidad.
	## Disponibilidad exige stock y distribución; ventas limitadas por ambos recursos.
	## Cuota = demanda * peso / (suma_pesos + peso_no_compra).
	var weights: Array[float] = []
	var total_weight: float = config.outside_option_weight
	for company in companies:
		var weight: float = 0.0
		if company.active_this_cycle and company.inventory > 0 and company.logistics_capacity() > 0:
			weight = (1.0 + config.brand_strength * company.brand) * pow(config.reference_price / company.price, config.price_elasticity)
		weights.append(weight)
		total_weight += weight
	weights.append(config.outside_option_weight)
	var quotas: Array[int] = []
	var remainders: Array[float] = []
	var assigned: int = 0
	for weight in weights:
		var exact: float = config.market_demand * weight / total_weight
		var whole: int = int(floor(exact))
		quotas.append(whole)
		remainders.append(exact - whole)
		assigned += whole
	# Restos mayores: redondea unidades sin crear compradores adicionales.
	# Empates se resuelven por orden A, B, no compra, de forma reproducible.
	for unused in range(config.market_demand - assigned):
		var best: int = 0
		for index in range(1, remainders.size()):
			if remainders[index] > remainders[best]:
				best = index
		quotas[best] += 1
		remainders[best] = -1.0
	var sales: Array[int] = []
	for index in range(companies.size()):
		# El cliente no vuelve a elegir si su empresa agota stock en este ciclo.
		sales.append(mini(quotas[index], mini(companies[index].inventory, companies[index].logistics_capacity())))
	return sales
