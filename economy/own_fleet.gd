extends RefCounted
## Flota propia con conductores dedicados contratados por período; no usa operarios de fábrica.

var vehicles: int = 0
var book_values: Array[float] = []
var effective_capacity: int = 0
var employees: int = 0
var expense: float = 0.0
var payable: float = 0.0
var fuel_expense: float = 0.0
var fixed_expense: float = 0.0
var salary_payable: float = 0.0
var maintenance_payable: float = 0.0


func initialize(config, seed_value: int) -> void:
	## Un generador por empresa hace reproducible la flota sin depender del sorteo de bodegas.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	vehicles = rng.randi_range(config.own_fleet_min, config.own_fleet_max)
	for index in range(vehicles):
		book_values.append(config.own_vehicle_cost)
	effective_capacity = vehicles * config.own_vehicle_capacity
	employees = vehicles * config.own_drivers_per_vehicle


func book_value() -> float:
	## Conserva activos al costo; la venta reconoce solo la diferencia con el precio recibido.
	var total: float = 0.0
	for value in book_values:
		total += value
	return total


func prepare(company, config) -> void:
	## Conductores y mantenimiento fijo se devengan aun con vehículos ociosos.
	employees = vehicles * config.own_drivers_per_vehicle
	fixed_expense = employees * config.own_driver_wage + vehicles * config.own_vehicle_maintenance
	expense = fixed_expense
	fuel_expense = 0.0
	salary_payable += employees * config.own_driver_wage
	maintenance_payable += vehicles * config.own_vehicle_maintenance
	var payment: float = minf(company.cash, salary_payable)
	company.finance.category = "Salarios de conductores propios"
	company.cash -= payment
	salary_payable -= payment
	payment = minf(company.cash, maintenance_payable)
	company.finance.category = "Mantenimiento fijo de vehículos propios"
	company.cash -= payment
	maintenance_payable -= payment
	payable = salary_payable + maintenance_payable
	effective_capacity = 0


func fund_capacity(company, config) -> void:
	## Después de producir, solo se ofrece la capacidad cuyo combustible se puede financiar.
	effective_capacity = 0 if payable > 0.000001 else vehicles * config.own_vehicle_capacity
	if config.own_fuel_per_unit > 0.0:
		effective_capacity = mini(effective_capacity, int(floor(company.cash / config.own_fuel_per_unit)))


func deliver(company, config, sales: int) -> void:
	## Prioriza vehículos propios; el combustible se paga antes de cobrar las ventas.
	fuel_expense = mini(sales, effective_capacity) * config.own_fuel_per_unit
	expense += fuel_expense
	company.finance.category = "Combustible propio"
	company.cash -= fuel_expense


func decide(company, config, action: String, amount: int) -> Dictionary:
	## Comprar exige caja; vender devuelve una fracción configurable del costo histórico.
	if amount <= 0:
		return {"ok": false, "message": "Cantidad de vehículos inválida."}
	if action == "buy_vehicle":
		var cost: float = amount * config.own_vehicle_cost
		if not is_finite(cost) or cost > company.cash:
			return {"ok": false, "message": "Caja insuficiente para vehículos."}
		company.finance.category = "Compra de vehículos"
		company.cash -= cost
		for index in range(amount):
			book_values.append(config.own_vehicle_cost)
		vehicles += amount
	else:
		if amount > vehicles:
			return {"ok": false, "message": "No hay tantos vehículos."}
		var removed: float = 0.0
		for index in range(amount):
			removed += book_values.pop_back()
		var proceeds: float = removed * config.own_vehicle_resale
		company.finance.category = "Venta de vehículos"
		company.cash += proceeds
		company.operations.pending_expenses += removed - proceeds
		vehicles -= amount
	employees = vehicles * config.own_drivers_per_vehicle
	fund_capacity(company, config)
	return {"ok": true, "message": "Flota actualizada: %d vehículos; capacidad nominal %d." % [vehicles, vehicles * config.own_vehicle_capacity]}


func copy_to(target) -> void:
	## Los pronósticos no comparten los activos ni las obligaciones de la partida.
	for field in ["vehicles", "effective_capacity", "employees", "payable", "salary_payable", "maintenance_payable"]:
		target.set(field, get(field))
	target.book_values.assign(book_values)
