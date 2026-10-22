extends VBoxContainer
## Vista administrativa de una sola empresa; los sliders editan borradores de políticas del modelo.

signal target_requested(target: int)
signal fire_requested(count: int)
signal purchase_requested(enabled: bool, target: int, budget: float)
signal manual_requested(action: String, amount: int)
var model
var client_index: int
var staff_summary: Label
var plan_label: Label
var target_slider: HSlider
var target_number: SpinBox
var fire_slider: HSlider
var fire_number: SpinBox
var target_button: Button
var fire_button: Button
var progress: ProgressBar
var auto_check: CheckBox
var stock_target: SpinBox
var budget_input: SpinBox
var purchase_button: Button
var manual_amount: SpinBox
var manual_button: Button
var supply_summary: Label


func setup(simulation, index: int) -> void:
	## Se fija el cliente al construir la columna; ningún selector puede enviar decisiones al rival.
	model = simulation
	client_index = index
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	_label("PERSONAL", 18)
	staff_summary = _label("")
	progress = ProgressBar.new()
	progress.custom_minimum_size.y = 18
	add_child(progress)
	_label("Plantilla objetivo · incorporación gradual")
	var target_row := HBoxContainer.new()
	add_child(target_row)
	target_slider = _slider(target_row, model.config.maximum_staff_target)
	target_number = _number(target_row, model.config.maximum_staff_target)
	target_slider.value_changed.connect(_target_changed)
	target_number.value_changed.connect(_target_number_changed)
	var ops = model.state.companies[index].operations
	target_slider.value = maxi(ops.employees, ops.staff_target)
	target_number.value = target_slider.value
	plan_label = _label("")
	target_button = _button("Aplicar objetivo de personal", _apply_target)
	_label("Despido inmediato · paga un sueldo por empleado")
	var fire_row := HBoxContainer.new()
	add_child(fire_row)
	fire_slider = _slider(fire_row, ops.employees)
	fire_number = _number(fire_row, ops.employees)
	fire_slider.value_changed.connect(_fire_changed)
	fire_number.value_changed.connect(_fire_number_changed)
	fire_button = _button("Despedir", _apply_fire)
	add_child(HSeparator.new())
	_label("INSUMOS", 18)
	supply_summary = _label("")
	var manual_row := HBoxContainer.new()
	add_child(manual_row)
	manual_amount = _number(manual_row, model.config.maximum_input_target)
	manual_amount.min_value = 1
	manual_amount.value = 10
	manual_button = Button.new()
	manual_button.text = "Comprar insumos ahora"
	manual_button.pressed.connect(_manual)
	manual_row.add_child(manual_button)
	auto_check = CheckBox.new()
	auto_check.text = "Reponer automáticamente cada período"
	auto_check.button_pressed = ops.auto_inputs
	add_child(auto_check)
	var grid := GridContainer.new()
	grid.columns = 2
	add_child(grid)
	var label := Label.new()
	label.text = "Stock objetivo"
	grid.add_child(label)
	stock_target = _number(grid, model.config.maximum_input_target)
	stock_target.value = ops.input_target
	label = Label.new()
	label.text = "Presupuesto máximo / período"
	grid.add_child(label)
	budget_input = _number(grid, model.config.maximum_auto_purchase_budget)
	budget_input.step = 0.01
	budget_input.value = ops.input_budget
	purchase_button = _button("Aplicar política de compras", _apply_purchases)
	refresh()


func _label(text: String, font_size: int = 16) -> Label:
	## El ajuste de línea mantiene cada explicación dentro de su columna.
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	add_child(label)
	return label


func _number(parent: Container, maximum: float) -> SpinBox:
	## Entrada exacta complementaria al arrastre del slider.
	var field := SpinBox.new()
	field.max_value = maximum
	field.step = 1
	field.custom_minimum_size.x = 105
	parent.add_child(field)
	return field


func _slider(parent: Container, maximum: int) -> HSlider:
	## Cada paso representa personas enteras; arrastrar aún no contrata ni despide.
	var field := HSlider.new()
	field.max_value = maximum
	field.step = 1
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.custom_minimum_size.x = 150
	parent.add_child(field)
	return field


func _button(caption: String, action: Callable) -> Button:
	## La confirmación explícita evita gastos al explorar un objetivo con el slider.
	var button := Button.new()
	button.text = caption
	button.pressed.connect(action)
	add_child(button)
	return button


func _target_changed(value: float) -> void:
	## SpinBox necesita su señal para actualizar el texto que confirmará apply().
	## La vuelta al slider usa set_value_no_signal y corta la edición circular.
	target_number.value = value
	# Los controles en pestañas ocultas pueden diferir el redibujado; confirma también su texto.
	target_number.get_line_edit().text = str(int(value))
	if fire_button != null:
		refresh_quote()


func _target_number_changed(value: float) -> void:
	## Permite escribir objetivos precisos sin depender del tamaño del slider.
	target_slider.set_value_no_signal(value)
	if fire_button != null:
		refresh_quote()


func _fire_changed(value: float) -> void:
	## El costo mostrado se consulta al modelo y no se aplica mientras se arrastra.
	fire_number.value = value
	fire_number.get_line_edit().text = str(int(value))
	refresh_quote()


func _fire_number_changed(value: float) -> void:
	## Mantiene ambos editores del despido sobre el mismo borrador.
	fire_slider.set_value_no_signal(value)
	refresh_quote()


func refresh_quote() -> void:
	## La cotización pertenece a las reglas administrativas, no a esta vista.
	var quote: Dictionary = model.staff_plan(client_index, int(target_slider.value), int(fire_slider.value))
	plan_label.text = "Selección adicional: %.2f · hasta %d candidatos/período · espera %d períodos" % [quote.selection_cost, quote.speed, quote.delay]
	fire_button.text = "Despedir %d · costo %.2f" % [int(fire_slider.value), quote.severance]
	fire_button.disabled = fire_slider.value == 0


func refresh() -> void:
	## Actualiza progreso real sin sobrescribir las políticas que el jugador está editando.
	var company = model.state.companies[client_index]
	var ops = company.operations
	staff_summary.text = "Actuales %d · necesarios %d · vacantes %d · pendientes %d\nObjetivo aplicado: %s · sueldo %.2f · caja %.2f" % [ops.employees, ops.required_employees(), ops.vacancies, ops.pending_count(), str(ops.staff_target) if ops.staff_target >= 0 else "manual", ops.wage, company.cash]
	progress.max_value = maxi(1, maxi(ops.staff_target, ops.employees + ops.vacancies + ops.pending_count()))
	progress.value = ops.employees
	target_slider.min_value = ops.employees
	target_number.min_value = ops.employees
	fire_slider.max_value = ops.employees
	fire_number.max_value = ops.employees
	supply_summary.text = "En bodega %d · espacio libre %d\nModo aplicado: %s · última reposición %d por %.2f" % [ops.warehouse.inputs, ops.warehouse.available(company.inventory), "automático" if ops.auto_inputs else "manual", ops.auto_bought, ops.auto_spent]
	refresh_quote()


func _apply_target() -> void:
	## Confirma el campo escrito antes de enviar la política persistente.
	target_number.apply()
	target_requested.emit(int(target_number.value))


func _apply_fire() -> void:
	## El modelo vuelve a validar personal y caja antes de cobrar la indemnización.
	fire_number.apply()
	fire_requested.emit(int(fire_number.value))


func _apply_purchases() -> void:
	## Guardar la política no compra hoy; el ciclo ejecutará la reposición.
	stock_target.apply()
	budget_input.apply()
	purchase_requested.emit(auto_check.button_pressed, int(stock_target.value), budget_input.value)


func _manual() -> void:
	## Una compra manual sigue disponible aunque exista reposición automática.
	manual_amount.apply()
	manual_requested.emit("inputs", int(manual_amount.value))
