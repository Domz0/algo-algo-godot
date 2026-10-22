extends RefCounted
## Parámetros del escenario ficticio. Una instancia permite ensayar otras economías.

var locality_name: String = "Valle de Nimbra"
var product_name: String = "Luminita"
# Cada ciclo representa un día económico, independientemente del tiempo de pantalla.
var seconds_per_cycle: float = 2.0
var market_demand: int = 120
var reference_price: float = 20.0
var price_elasticity: float = 1.5
var brand_strength: float = 1.0
# Peso de no comprar: evita que toda la demanda compre incluso a precios enormes.
var outside_option_weight: float = 1.0
# Límites de decisiones: evitan divisiones por cero y entradas fuera del modelo.
var minimum_price: float = 0.01
var maximum_price: float = 10000.0
# Publicidad por día: primero se financian apertura y producción; luego la campaña.
var maximum_advertising: float = 1000.0
var advertising_brand_gain: float = 0.002
# Operador independiente: cobra por capacidad reservada, aunque no se utilice.
var logistics_name: String = "Rutas de Nimbra"
var logistics_owner: String = "Cooperativa ficticia Ardel"
var logistics_capacity: int = 80
var logistics_initial_cash: float = 1000.0
var logistics_unit_rate: float = 1.0
var logistics_contract_fee: float = 2.0
var logistics_unit_cost: float = 0.4
var logistics_contract_cost: float = 1.0
var logistics_asset_value_per_unit: float = 10.0
var logistics_profit_multiple: float = 10.0
var maximum_contract_days: int = 30
# Revalorización lineal por día; no genera efectivo ni ingresos contables.
var logistics_value_growth_rate: float = 0.002
var logistics_purchase_multiplier: float = 1.0
# Las pruebas históricas desactivan esta ampliación para aislar las fórmulas anteriores.
var extended_economy: bool = true
var random_seed: int = 20261022
var warehouse_min_capacity: int = 220
var warehouse_max_capacity: int = 300
var warehouse_expansion_unit_cost: float = 3.0
var initial_inputs: int = 160
var initial_spares: int = 6
var input_price: float = 2.0
var spare_price: float = 4.0
var initial_machine_count: int = 2
var machine_purchase_cost: float = 250.0
var machine_purchase_capacity: int = 40
var machine_base_efficiency: float = 1.0
var machine_inputs_per_unit: int = 1
var machine_staff_required: int = 2
var machine_maintenance_interval: int = 3
var machine_maintenance_spares: int = 1
var machine_maintenance_labor: float = 8.0
var machine_wear_per_cycle: float = 0.12
var machine_failure_wear: float = 0.9
var overdue_efficiency: float = 0.6
var initial_employees: int = 4
var wage_per_employee: float = 4.0
var employee_work_capacity: int = 30
var hiring_cost: float = 2.0
var severance_cost: float = 3.0
var understaff_exponent: float = 1.0
var excess_staff_penalty: float = 0.0
var input_shortage_efficiency: float = 0.9
var fuel_cost_per_delivery: float = 0.12
var logistics_wage_per_delivery: float = 0.08
var fleet_maintenance_per_reserved_unit: float = 0.05
var logistics_fixed_overhead: float = 1.0
var logistics_auto_expand: bool = true
var logistics_expansion_units: int = 10
var logistics_expansion_unit_cost: float = 12.0
var logistics_max_capacity: int = 200
var logistics_cash_reserve: float = 200.0
var logistics_expansion_utilization: float = 0.7
var transport_min_price: float = 0.75
var transport_max_price: float = 3.0
var transport_target_utilization: float = 0.6
var transport_price_adjustment: float = 0.1
var credit_enabled: bool = true
var credit_limit_per_client: float = 300.0
var note_interest_rate: float = 0.02
var note_maturity_days: int = 5
var credit_block_overdue: bool = true
var investment_discount: float = 0.15
var investment_discount_days: int = 5
var companies: Array[Dictionary] = [
	{"name": "Empresa A", "cash": 800.0, "price": 20.0,
	 "capacity": 100, "production_target": 80, "variable_cost": 6.0,
	 "fixed_cost": 60.0, "brand": 0.25, "own_logistics_capacity": 45},
	{"name": "Empresa B", "cash": 1600.0, "price": 22.0,
	 "capacity": 60, "production_target": 50, "variable_cost": 9.0,
	 "fixed_cost": 60.0, "brand": 0.8, "own_logistics_capacity": 50}
]


func validation_errors() -> PackedStringArray:
	## Rechaza escenarios inválidos antes de crear estados parcialmente utilizables.
	var errors := PackedStringArray()
	if extended_economy:
		if warehouse_min_capacity < initial_inputs + initial_spares or warehouse_max_capacity < warehouse_min_capacity:
			errors.append("Las bodegas deben contener la dotación inicial y tener un rango válido.")
		for value in [initial_inputs, initial_spares, initial_employees, initial_machine_count, machine_inputs_per_unit, machine_maintenance_spares]:
			if value < 0:
				errors.append("Las cantidades iniciales y consumos no pueden ser negativos.")
		for value in [machine_purchase_capacity, machine_staff_required, machine_maintenance_interval, employee_work_capacity, logistics_expansion_units, note_maturity_days, investment_discount_days]:
			if value <= 0:
				errors.append("Capacidades e intervalos deben ser positivos.")
		for value in [warehouse_expansion_unit_cost, input_price, spare_price, machine_purchase_cost, machine_maintenance_labor, machine_wear_per_cycle, wage_per_employee, hiring_cost, severance_cost, understaff_exponent, excess_staff_penalty, fuel_cost_per_delivery, logistics_wage_per_delivery, fleet_maintenance_per_reserved_unit, logistics_fixed_overhead, logistics_cash_reserve, credit_limit_per_client, note_interest_rate]:
			if not is_finite(value) or value < 0.0:
				errors.append("Costos y tasas ampliadas deben ser finitos y no negativos.")
		for value in [machine_base_efficiency, overdue_efficiency, input_shortage_efficiency, logistics_expansion_utilization, transport_target_utilization, transport_price_adjustment, investment_discount]:
			if not is_finite(value) or value < 0.0 or value > 1.0:
				errors.append("Eficiencias, proporciones y descuentos deben estar en [0,1].")
		if investment_discount >= 1.0 or not is_finite(machine_failure_wear) or machine_failure_wear <= 0.0 or machine_failure_wear > 1.0:
			errors.append("Descuento inferior a 1 y umbral de desgaste en (0,1].")
		if logistics_max_capacity < logistics_capacity or logistics_expansion_unit_cost <= 0.0 or not is_finite(logistics_expansion_unit_cost):
			errors.append("Límite de flota o costo de expansión inválido.")
		if not is_finite(transport_min_price) or transport_min_price <= 0.0 or transport_max_price < transport_min_price or not is_finite(transport_max_price):
			errors.append("Rango de tarifas inválido.")
	if not is_finite(logistics_value_growth_rate) or logistics_value_growth_rate < 0.0 or not is_finite(logistics_purchase_multiplier) or logistics_purchase_multiplier <= 0.0:
		errors.append("Crecimiento de valor no negativo y multiplicador de compra positivo deben ser finitos.")
	if logistics_capacity < 0 or maximum_contract_days < 1:
		errors.append("Capacidad logística o duración máxima inválida.")
	for value in [logistics_initial_cash, logistics_unit_rate, logistics_contract_fee, logistics_unit_cost, logistics_contract_cost, logistics_asset_value_per_unit, logistics_profit_multiple]:
		if not is_finite(value) or value < 0.0:
			errors.append("Los parámetros logísticos deben ser finitos y no negativos.")
	# Evita prometer servicios deficitarios sin un modelo de crédito o insolvencia.
	if logistics_unit_rate < logistics_unit_cost or logistics_contract_fee < logistics_contract_cost:
		errors.append("La tarifa logística debe cubrir sus costos de capacidad y contrato.")
	if not is_finite((logistics_unit_rate * logistics_capacity + logistics_contract_fee) * maximum_contract_days):
		errors.append("El importe contractual excede el rango numérico.")
	if not is_finite(seconds_per_cycle) or seconds_per_cycle <= 0.0:
		errors.append("La duración del ciclo debe ser positiva y finita.")
	if market_demand < 0:
		errors.append("La demanda no puede ser negativa.")
	for value in [reference_price, minimum_price, maximum_price, outside_option_weight]:
		if not is_finite(value) or value <= 0.0:
			errors.append("Los precios de referencia, límites y opción externa deben ser positivos.")
	if minimum_price > maximum_price:
		errors.append("El precio mínimo supera al máximo.")
	for value in [price_elasticity, brand_strength, maximum_advertising, advertising_brand_gain]:
		if not is_finite(value) or value < 0.0:
			errors.append("Elasticidad y fuerza de marca deben ser finitas y no negativas.")
	if errors.is_empty():
		# Valida el extremo de mayor atractivo para que ninguna decisión desborde cuotas.
		var maximum_weight: float = (1.0 + brand_strength) * pow(reference_price / minimum_price, price_elasticity)
		if not is_finite((2.0 * maximum_weight + outside_option_weight) * maxf(1.0, float(market_demand))):
			errors.append("Los parámetros de demanda exceden el rango numérico del modelo.")
	if companies.size() != 2:
		errors.append("Esta etapa requiere exactamente dos empresas humanas.")
	for company in companies:
		for key in ["name", "cash", "price", "capacity", "production_target", "variable_cost", "fixed_cost", "brand", "own_logistics_capacity"]:
			if not company.has(key):
				errors.append("Falta el parámetro empresarial: " + key)
		if errors.size() > 0:
			continue
		for key in ["cash", "price", "variable_cost", "fixed_cost", "brand"]:
			if not (company[key] is float or company[key] is int) or not is_finite(float(company[key])) or float(company[key]) < 0.0:
				errors.append("Valor empresarial inválido: " + key)
		for key in ["capacity", "production_target", "own_logistics_capacity"]:
			if not company[key] is int or company[key] < 0:
				errors.append("Se requieren unidades enteras no negativas: " + key)
		if errors.size() == 0:
			if company.price < minimum_price or company.price > maximum_price or company.brand > 1.0:
				errors.append("Precio fuera de límites o marca fuera de [0, 1].")
	return errors
