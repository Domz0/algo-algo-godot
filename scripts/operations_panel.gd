extends VBoxContainer
## Administración mínima de recursos: consulta el estado y emite decisiones sin fórmulas económicas.

signal operation_requested(action: String, amount: int)
var summary: Label
var machine_view: TextEdit
var action_input: OptionButton
var amount_input: SpinBox
var apply_button: Button
var action_codes: Array[String] = ["inputs", "spares", "expand", "hire", "fire", "machine", "retire", "maintenance", "preventive_on", "preventive_off"]


func _ready() -> void:
	## Un selector evita llenar la pantalla de botones; cantidad significa ID al actuar sobre una máquina.
	summary = Label.new()
	add_child(summary)
	machine_view = TextEdit.new()
	machine_view.editable = false
	machine_view.custom_minimum_size.y = 100
	add_child(machine_view)
	action_input = OptionButton.new()
	for label in ["Comprar insumos", "Comprar repuestos", "Ampliar bodega", "Contratar empleados", "Despedir empleados", "Comprar máquinas", "Retirar máquina (ID)", "Mantenimiento correctivo (ID)", "Programar preventivo (ID)", "Desactivar preventivo (ID)"]:
		action_input.add_item(label)
	add_child(action_input)
	var row := HBoxContainer.new()
	add_child(row)
	var label := Label.new()
	label.text = "Cantidad / ID"
	row.add_child(label)
	amount_input = SpinBox.new()
	amount_input.min_value = 1
	amount_input.max_value = 10000
	amount_input.value = 1
	row.add_child(amount_input)
	apply_button = Button.new()
	apply_button.text = "Ejecutar operación"
	apply_button.pressed.connect(_submit)
	row.add_child(apply_button)


func _submit() -> void:
	## Confirma el texto y delega validaciones, pagos y mutaciones en el modelo.
	amount_input.apply()
	operation_requested.emit(action_codes[action_input.selected], int(amount_input.value))


func refresh(company) -> void:
	## Separa saldos actuales, resultados del cierre anterior y movimientos aún sin cerrar.
	var ops = company.operations
	var warehouse = ops.warehouse
	summary.text = "Bodega: total %d | ocupada %d | libre %d\nInsumos %d | Repuestos %d | Terminados %d\nEmpleados %d | Salarios %.2f | Salarios pendientes %.2f\nInsumos consumidos al costo %.2f | Mantenimiento %.2f\nIntereses %.2f | Deuda pagarés %.2f | Beneficio neto %.2f\nPatrimonio al costo %.2f | Caja entre cierres %+.2f\nLimitaciones: %s" % [warehouse.capacity, warehouse.occupied(company.inventory), warehouse.available(company.inventory), warehouse.inputs, warehouse.spares, company.inventory, ops.employees, ops.salary_expense, company.wages_payable, ops.materials_consumed, ops.maintenance_expense, company.interest_expense, company.note_debt, company.net_profit, company.equity(), company.cash - company.cash_at_period_start, "; ".join(ops.penalties)]
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.text += "\nValor estimado (no caja): %.2f" % company.estimated_value()
	summary.custom_minimum_size.x = 410
	var lines := PackedStringArray()
	for machine in ops.machines:
		lines.append("#%d: capacidad %d, eficiencia %.2f, desgaste %.2f\n  Personal %d, insumos/u %d; preventivo %s, ciclos %d/%d\n  Mantenimiento: %d repuestos + %.2f; valor contable %.2f" % [machine.id, machine.capacity, machine.efficiency(), machine.wear, machine.staff_required, machine.inputs_per_unit, "sí" if machine.preventive else "no", machine.operating_cycles, machine.maintenance_interval, machine.maintenance_spares, machine.maintenance_labor, machine.book_value])
	machine_view.text = "Sin maquinaria." if lines.is_empty() else "\n".join(lines)
