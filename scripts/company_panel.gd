extends VBoxContainer
## Vista de una empresa: edita borradores y muestra datos sin escribir en el modelo.

signal decision_edited
signal operation_requested(action: String, amount: int)
const OperationsPanel = preload("res://scripts/operations_panel.gd")
var operations_panel

var price_input: SpinBox
var production_input: SpinBox
var advertising_input: SpinBox
# Claves estables permiten actualizar y comprobar las etiquetas de resultados.
var metrics: Dictionary = {}
var logistics_label: Label


func setup(company, config) -> void:
	## Los límites de cada campo proceden de la configuración económica.
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = company.company_name
	add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	add_child(grid)
	for pair in [["cash", "Capital disponible (caja)"], ["price", "Precio aplicado"], ["production", "Producción / capacidad"], ["inventory", "Inventario final"], ["sales", "Ventas"], ["revenue", "Ingresos"], ["costs", "Costos operativos"], ["profit", "Beneficio operativo"], ["flow", "Flujo de caja"], ["share", "Cuota de mercado"], ["brand", "Reconocimiento de marca"], ["advertising", "Publicidad gastada"], ["estimate", "Ventas estimadas próximo día"]]:
		var label := Label.new()
		label.text = pair[1]
		grid.add_child(label)
		var value := Label.new()
		grid.add_child(value)
		metrics[pair[0]] = value
	logistics_label = Label.new()
	add_child(logistics_label)
	var inputs := GridContainer.new()
	inputs.columns = 2
	add_child(inputs)
	price_input = _create_input(inputs, "Precio próximo día", config.minimum_price, config.maximum_price, 0.01, company.price)
	production_input = _create_input(inputs, "Producción objetivo", 0, company.capacity, 1, company.production_target)
	advertising_input = _create_input(inputs, "Publicidad por día", 0, config.maximum_advertising, 0.01, company.advertising_budget)
	if company.operations != null:
		operations_panel = OperationsPanel.new()
		add_child(operations_panel)
		operations_panel.operation_requested.connect(_forward_operation)


func _create_input(parent: Container, caption: String, minimum: float, maximum: float, step_size: float, initial: float) -> SpinBox:
	## Conecta cambios a una notificación, nunca a una modificación económica directa.
	var label := Label.new()
	label.text = caption
	parent.add_child(label)
	var field := SpinBox.new()
	field.min_value = minimum
	field.max_value = maximum
	field.step = step_size
	field.value = initial
	field.custom_minimum_size.x = 150
	parent.add_child(field)
	field.value_changed.connect(_on_value_changed)
	field.get_line_edit().text_changed.connect(_on_text_changed)
	return field


func _on_value_changed(_value: float) -> void:
	## Incluye cambios con las flechas del campo numérico.
	decision_edited.emit()


func _on_text_changed(_text: String) -> void:
	## Avisa del borrador incluso antes de confirmar con Enter.
	decision_edited.emit()


func commit_fields() -> void:
	## Confirma texto aún enfocado antes de enviar las decisiones al modelo.
	for field in [price_input, production_input, advertising_input]:
		field.apply()


func show_company(company, estimate: int) -> void:
	## Solo formatea resultados; no recalcula las fórmulas económicas.
	metrics.cash.text = "%.2f" % company.cash
	metrics.price.text = "%.2f" % company.price
	metrics.production.text = "%d / %d" % [company.production, company.capacity]
	metrics.inventory.text = str(company.inventory)
	metrics.sales.text = str(company.sales)
	metrics.revenue.text = "%.2f" % company.revenue
	metrics.costs.text = "%.2f" % company.operating_costs
	metrics.profit.text = "%.2f" % company.operating_profit
	metrics.flow.text = "%.2f" % company.cash_flow
	metrics.share.text = "%.1f %%" % (company.market_share * 100.0)
	metrics.brand.text = "%.3f" % company.brand
	metrics.advertising.text = "%.2f" % company.advertising_spending
	metrics.estimate.text = str(estimate)
	production_input.max_value = company.capacity
	if operations_panel != null:
		operations_panel.refresh(company)
	logistics_label.text = "Logística próxima: propia %d + contratada %d = %d\nÚltimo día: distribuidas %d / límite %d; libres %d\nGasto logístico %.2f | Anticipo pendiente %.2f" % [company.own_logistics_capacity, company.contracted_capacity, company.logistics_capacity(), company.distributed_units, company.distribution_limit, maxi(0, company.distribution_limit - company.distributed_units), company.logistics_expense, company.prepaid_logistics]


func _forward_operation(action: String, amount: int) -> void:
	## Reenvía la petición al controlador que conoce qué empresa corresponde a este panel.
	operation_requested.emit(action, amount)
