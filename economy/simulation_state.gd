extends RefCounted
## Estado persistente del mundo ficticio, separado del reloj y de las fórmulas.

const CompanyState = preload("res://economy/company_state.gd")
const LogisticsState = preload("res://economy/logistics_state.gd")
const OperationsState = preload("res://economy/operations_state.gd")

var locality_name: String
var product_name: String
var cycle: int = 0
var companies: Array = []
var unserved_demand: int = 0
var total_sales: int = 0
var estimated_demand: int = 0
var logistics
var journal: Array[Dictionary] = []
# El registro acotado evita crecimiento ilimitado durante sesiones automáticas.
var events: PackedStringArray = []


func record_event(message: String) -> void:
	## Conserva los últimos 100 eventos con el día al que pertenecen.
	events.append("Día %d — %s" % [cycle, message])
	if events.size() > 100:
		events.remove_at(0)


func _init(config) -> void:
	## Cada simulación recibe empresas nuevas; dos partidas no comparten inventario.
	locality_name = config.locality_name
	product_name = config.product_name
	logistics = LogisticsState.new(config)
	var rng := RandomNumberGenerator.new()
	rng.seed = config.random_seed
	for parameters in config.companies:
		var company = CompanyState.new(parameters)
		if config.extended_economy:
			company.operations = OperationsState.new(config, rng, company.capacity)
			company.own_fleet = preload("res://economy/own_fleet.gd").new()
			company.own_fleet.initialize(config, config.random_seed + 1009 * (companies.size() + 1))
			company.own_logistics_capacity = company.own_fleet.vehicles * config.own_vehicle_capacity
			company.capacity = 0
			for machine in company.operations.machines:
				company.capacity += machine.capacity
			company.production_target = mini(company.production_target, company.capacity)
		companies.append(company)
