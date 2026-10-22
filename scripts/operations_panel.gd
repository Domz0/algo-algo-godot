extends VBoxContainer
## Administración mínima de recursos: consulta el estado y emite decisiones sin fórmulas económicas.

signal operation_requested(action: String, amount: int)
var summary: Label
var machine_view: TextEdit
var action_input: OptionButton
var amount_input: SpinBox
var apply_button: Button
var action_codes: Array[String] = ["spares", "expand", "machine", "retire", "maintenance", "preventive_on", "preventive_off", "buy_vehicle", "sell_vehicle"]


func _ready() -> void:
	## Un selector evita llenar la pantalla de botones; cantidad significa ID al actuar sobre una máquina.
	summary = Label.new()
	add_child(summary)
	machine_view = TextEdit.new()
	machine_view.editable = false
	machine_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	machine_view.custom_minimum_size.y = 100
	add_child(machine_view)
	action_input = OptionButton.new()
	for label in ["Comprar repuestos", "Ampliar bodega", "Comprar máquinas", "Retirar máquina (ID)", "Mantenimiento correctivo (ID)", "Programar preventivo (ID)", "Desactivar preventivo (ID)", "Comprar vehículos", "Vender vehículos"]:
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
	summary.text = "BODEGA\nCapacidad %d · ocupada %d · libre %d\nInsumos %d · repuestos %d · terminados %d\n\nPRODUCCIÓN\nMáquinas %d · capacidad %d · producidas %d\nInsumos consumidos %.2f · mantenimiento %.2f" % [warehouse.capacity, warehouse.occupied(company.inventory), warehouse.available(company.inventory), warehouse.inputs, warehouse.spares, company.inventory, ops.machines.size(), company.capacity, company.production, ops.materials_consumed, ops.maintenance_expense]
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var fleet = company.own_fleet
	if fleet != null:
		summary.text += "\n\nTRANSPORTE PROPIO\nVehículos %d · conductores %d\nCapacidad nominal %d · financiable %d\nFijos %.2f · combustible %.2f · por pagar %.2f\nArrendado %d · entregado %d / %d" % [fleet.vehicles, fleet.employees, company.own_logistics_capacity, fleet.effective_capacity, fleet.fixed_expense, fleet.fuel_expense, fleet.payable, company.contracted_capacity, company.distributed_units, company.distribution_limit]
	if not ops.penalties.is_empty():
		summary.text += "\n\nAviso: " + ops.penalties[-1]
	var lines := PackedStringArray()
	for machine in ops.machines:
		lines.append("#%d: capacidad %d, eficiencia %.2f, desgaste %.2f\n  Personal %d, insumos/u %d; preventivo %s, ciclos %d/%d\n  Mantenimiento: %d repuestos + %.2f; valor contable %.2f" % [machine.id, machine.capacity, machine.efficiency(), machine.wear, machine.staff_required, machine.inputs_per_unit, "sí" if machine.preventive else "no", machine.operating_cycles, machine.maintenance_interval, machine.maintenance_spares, machine.maintenance_labor, machine.book_value])
	machine_view.text = "Sin maquinaria." if lines.is_empty() else "\n".join(lines)
