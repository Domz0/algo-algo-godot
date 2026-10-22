extends RefCounted
## Recursos reales de producción y desgloses contables del período.

const Warehouse = preload("res://economy/warehouse_state.gd")
const Machine = preload("res://economy/machine_state.gd")
var warehouse
var machines: Array = []
var next_machine_id: int = 1
var employees: int
# -1 conserva la contratación manual anterior; los objetivos explícitos usan el mismo proceso laboral.
var staff_target: int = -1
var auto_inputs: bool = false
var input_target: int = 80
var input_budget: float = 100.0
var auto_bought: int = 0
var auto_spent: float = 0.0
# Tarifa por empleado vigente en el último cálculo; se expone para interpretar la nómina.
var wage: float
var vacancies: int = 0
var pending_hires: Array[Dictionary] = []
var salary_expense: float = 0.0
var maintenance_expense: float = 0.0
var materials_consumed: float = 0.0
var other_expense: float = 0.0
# Las decisiones entre días acumulan gastos que se reconocen en el próximo cierre.
var pending_expenses: float = 0.0
var pending_maintenance: float = 0.0
var penalties: PackedStringArray = []


func _init(config, rng: RandomNumberGenerator, nominal_capacity: int) -> void:
	## La semilla de la partida determina una capacidad de bodega dentro del rango indicado.
	warehouse = Warehouse.new()
	warehouse.capacity = rng.randi_range(config.warehouse_min_capacity, config.warehouse_max_capacity)
	warehouse.inputs = config.initial_inputs
	warehouse.spares = config.initial_spares
	warehouse.inputs_value = warehouse.inputs * config.input_price
	warehouse.spares_value = warehouse.spares * config.spare_price
	employees = config.initial_employees
	wage = config.wage_per_employee
	for index in range(config.initial_machine_count):
		# Distribuye la capacidad inicial anterior sin inventar capacidad por redondeo.
		var units: int = nominal_capacity / config.initial_machine_count
		if index < nominal_capacity % config.initial_machine_count:
			units += 1
		machines.append(Machine.new(config, next_machine_id, units))
		next_machine_id += 1


func asset_value() -> float:
	## No hay depreciación previa: los bienes comprados permanecen al costo hasta retirarlos.
	var total: float = warehouse.inputs_value + warehouse.spares_value + warehouse.construction_value
	for machine in machines:
		total += machine.book_value
	return total


func copy_to(target, config) -> void:
	## Copia profunda para pronósticos: ninguna máquina ni inventario queda compartido.
	for field in ["employees", "vacancies", "next_machine_id", "pending_expenses", "pending_maintenance", "staff_target", "auto_inputs", "input_target", "input_budget"]:
		target.set(field, get(field))
	for field in ["capacity", "inputs", "spares", "inputs_value", "spares_value", "construction_value"]:
		target.warehouse.set(field, warehouse.get(field))
	target.pending_hires.assign(pending_hires.duplicate(true))
	target.machines.clear()
	for machine in machines:
		var copy = Machine.new(config, machine.id, machine.capacity, machine.book_value)
		for field in ["base_efficiency", "inputs_per_unit", "staff_required", "maintenance_interval", "maintenance_spares", "maintenance_labor", "wear", "wear_per_cycle", "failure_wear", "overdue_efficiency", "operating_cycles", "preventive"]:
			copy.set(field, machine.get(field))
		target.machines.append(copy)


func pending_count() -> int:
	## Los candidatos no generan salarios hasta incorporarse.
	var count: int = 0
	for batch in pending_hires:
		count += batch.count
	return count


func required_employees() -> int:
	## Necesidad nominal de operarios de todas las máquinas instaladas.
	var count: int = 0
	for machine in machines:
		count += machine.staff_required
	return count
