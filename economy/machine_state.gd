extends RefCounted
## Máquina individual con condiciones configurables, desgaste y mantenimiento pendiente.

var id: int
var capacity: int
var inputs_per_unit: int
var staff_required: int
var maintenance_interval: int
var maintenance_spares: int
var maintenance_labor: float
var wear: float = 0.0
var base_efficiency: float
var wear_per_cycle: float
var failure_wear: float
var overdue_efficiency: float
var operating_cycles: int = 0
var preventive: bool = true
var book_value: float = 0.0


func _init(config, identifier: int, units: int, cost: float = 0.0) -> void:
	## Las condiciones se copian al adquirir para que cada equipo conserve sus parámetros.
	id = identifier
	capacity = units
	book_value = cost
	base_efficiency = config.machine_base_efficiency
	inputs_per_unit = config.machine_inputs_per_unit
	staff_required = config.machine_staff_required
	maintenance_interval = config.machine_maintenance_interval
	maintenance_spares = config.machine_maintenance_spares
	maintenance_labor = config.machine_maintenance_labor
	wear_per_cycle = config.machine_wear_per_cycle
	failure_wear = config.machine_failure_wear
	overdue_efficiency = config.overdue_efficiency


func efficiency() -> float:
	## El desgaste reduce rendimiento y el atraso añade una penalización; puede detenerse.
	if wear >= failure_wear:
		return 0.0
	return base_efficiency * (1.0 - wear) * (overdue_efficiency if operating_cycles >= maintenance_interval else 1.0)
