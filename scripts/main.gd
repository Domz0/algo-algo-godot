extends Control
## Conecta la pantalla al modelo sin incluir reglas económicas.

const EconomyConfig = preload("res://economy/economy_config.gd")
const Simulation = preload("res://economy/simulation.gd")
const CompanyPanel = preload("res://scripts/company_panel.gd")
const LogisticsPanel = preload("res://scripts/logistics_panel.gd")

var simulation
var cycle_timer: Timer
var automatic_running: bool = false
var company_panels: Array = []
var summary_label: Label
var status_label: Label
var events_view: TextEdit
var apply_button: Button
var advance_button: Button
var automatic_button: Button
var reports_view: TextEdit
var report_period: SpinBox
var sections: TabContainer
const AdministrationPanel = preload("res://scripts/administration_panel.gd")
const OperationsPanel = preload("res://scripts/operations_panel.gd")
var administration_panels: Array = []
var rental_panels: Array = []
var home_summaries: Array[Label] = []
var home_finances: Array[Label] = []
var recent_events: TextEdit
var logistics_panel


func _ready() -> void:
	## Acepta una simulación inyectada por pruebas o crea el escenario normal.
	if simulation == null:
		simulation = Simulation.new(EconomyConfig.new())
	if not simulation.errors.is_empty():
		var error_label := Label.new()
		error_label.text = "Configuración inválida: " + str(simulation.errors)
		add_child(error_label)
		return
	_build_screen()
	cycle_timer = Timer.new()
	cycle_timer.wait_time = simulation.config.seconds_per_cycle
	# El temporizador pide días completos; no ejecutamos economía en _process.
	cycle_timer.timeout.connect(_advance)
	add_child(cycle_timer)
	_refresh()


func _build_screen() -> void:
	## La portada resume; cada menú conserva A a la izquierda y B a la derecha.
	_apply_theme()
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)
	var toolbar := HBoxContainer.new()
	content.add_child(toolbar)
	var heading := Label.new()
	heading.text = "NIMBRA  /  Gestión económica"
	heading.add_theme_font_size_override("font_size", 22)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(heading)
	advance_button = _button(toolbar, "Avanzar período", _advance)
	automatic_button = _button(toolbar, "Iniciar reloj", _toggle_automatic)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.text = "Partida local · Cada columna administra su propia empresa."
	content.add_child(status_label)
	sections = TabContainer.new()
	sections.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(sections)
	var home := VBoxContainer.new()
	home.name = "Inicio"
	home.add_theme_constant_override("separation", 14)
	sections.add_child(home)
	summary_label = Label.new()
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	home.add_child(summary_label)
	var home_columns := HBoxContainer.new()
	home_columns.add_theme_constant_override("separation", 16)
	home.add_child(home_columns)
	for index in range(2):
		var card = _column(home_columns, index, false)
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 20)
		card.add_child(label)
		home_summaries.append(label)
		card.add_child(HSeparator.new())
		label = Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(label)
		home_finances.append(label)
	var recent_title := Label.new()
	recent_title.text = "EVENTOS RECIENTES"
	home.add_child(recent_title)
	recent_events = TextEdit.new()
	recent_events.editable = false
	recent_events.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	recent_events.size_flags_vertical = Control.SIZE_EXPAND_FILL
	home.add_child(recent_events)
	var results = _columns("Resultados")
	for index in range(2):
		var panel = CompanyPanel.new()
		_column(results, index).add_child(panel)
		panel.setup(simulation.state.companies[index], simulation.config)
		panel.title.hide()
		panel.decision_edited.connect(_mark_pending)
		panel.apply_requested.connect(_apply_company.bind(index))
		company_panels.append(panel)
	apply_button = company_panels[0].apply_button
	var resources = _columns("Logística")
	var administration = _columns("Administración")
	for index in range(2):
		var resource_column = _column(resources, index)
		var admin_column = _column(administration, index)
		if simulation.state.companies[index].operations == null:
			continue
		var ops = OperationsPanel.new()
		resource_column.add_child(ops)
		ops.operation_requested.connect(_manage_operations.bind(index))
		company_panels[index].operations_panel = ops
		var admin = AdministrationPanel.new()
		admin_column.add_child(admin)
		admin.setup(simulation, index)
		admin.target_requested.connect(_set_target.bind(index))
		admin.fire_requested.connect(_fire_staff.bind(index))
		admin.purchase_requested.connect(_set_purchases.bind(index))
		admin.manual_requested.connect(_manage_operations.bind(index))
		administration_panels.append(admin)
	var rentals = _columns("Arriendo de transportes")
	for index in range(2):
		var panel = LogisticsPanel.new()
		panel.simulation = simulation
		_column(rentals, index).add_child(panel)
		panel.setup(simulation.state, simulation.config, index)
		panel.contract_requested.connect(_request_contract)
		panel.cancellation_requested.connect(_cancel_contract)
		panel.acquisition_requested.connect(_acquire_logistics)
		panel.note_payment_requested.connect(_pay_note)
		panel.investment_requested.connect(_invest_logistics)
		rental_panels.append(panel)
	logistics_panel = rental_panels[0]
	var finance := VBoxContainer.new()
	finance.name = "Finanzas"
	sections.add_child(finance)
	var explanation := Label.new()
	explanation.text = "Desglose financiero · Selecciona un período cerrado"
	finance.add_child(explanation)
	report_period = SpinBox.new()
	report_period.min_value = 0
	report_period.max_value = 0
	report_period.value_changed.connect(_show_report)
	finance.add_child(report_period)
	reports_view = TextEdit.new()
	reports_view.editable = false
	reports_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	reports_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	finance.add_child(reports_view)
	events_view = TextEdit.new()
	events_view.name = "Eventos"
	events_view.editable = false
	events_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	sections.add_child(events_view)


func _columns(caption: String) -> HBoxContainer:
	## Las dos columnas usan exactamente el mismo espacio; la identidad nunca cambia al navegar.
	var columns := HBoxContainer.new()
	columns.name = caption
	columns.add_theme_constant_override("separation", 16)
	sections.add_child(columns)
	return columns


func _column(parent: Container, index: int, scrolling: bool = true) -> VBoxContainer:
	## El encabezado permanece visible y solo el detalle de cada empresa se desplaza.
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var label := Label.new()
	label.text = simulation.state.companies[index].company_name.to_upper()
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color("dfbb75") if index == 0 else Color("75c5be"))
	box.add_child(label)
	if not scrolling:
		return box
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	return body


func _apply_theme() -> void:
	## Jerarquía sobria de paneles: color solo para identificar empresas y controles seleccionados.
	var background := ColorRect.new()
	background.color = Color("101820")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Theme.new()
	theme.default_font_size = 16
	var card := StyleBoxFlat.new()
	card.bg_color = Color("1c2933")
	card.border_color = Color("384c59")
	card.set_border_width_all(1)
	card.set_content_margin_all(14)
	theme.set_stylebox("panel", "PanelContainer", card)
	var tabs: StyleBoxFlat = card.duplicate()
	tabs.bg_color = Color("14212a")
	tabs.set_content_margin_all(12)
	theme.set_stylebox("panel", "TabContainer", tabs)
	var button: StyleBoxFlat = card.duplicate()
	button.bg_color = Color("304755")
	button.set_content_margin_all(8)
	theme.set_stylebox("normal", "Button", button)
	var hover: StyleBoxFlat = button.duplicate()
	hover.bg_color = Color("415e6d")
	theme.set_stylebox("hover", "Button", hover)
	theme.set_color("font_color", "Label", Color("e5e9eb"))


func _apply_company(index: int) -> void:
	## El botón de cada empresa confirma únicamente sus propios borradores.
	var panel = company_panels[index]
	panel.commit_fields()
	var accepted: bool = simulation.set_decision(index, panel.price_input.value, int(panel.production_input.value))
	status_label.text = "Decisiones aplicadas: " + simulation.state.companies[index].company_name if accepted else "Revisa precio y producción."
	_refresh()


func _set_target(target: int, index: int) -> void:
	## La política mantiene el ritmo del modelo; la barra visual no incorpora empleados.
	status_label.text = simulation.set_staff_target(index, target).message
	_refresh()


func _fire_staff(count: int, index: int) -> void:
	## Reutiliza el despido validado y su indemnización de un sueldo por empleado.
	_manage_operations("fire", count, index)


func _set_purchases(enabled: bool, target: int, budget: float, index: int) -> void:
	## Guardar reposición no ejecuta compras fuera del ciclo económico.
	status_label.text = simulation.set_auto_purchasing(index, enabled, target, budget).message
	_refresh()

func _show_report(_value: float = 0.0) -> void:
	## Formatea instantáneas del modelo; no calcula resultados ni modifica caja.
	var lines := PackedStringArray()
	var entities: Array = simulation.state.companies.duplicate()
	entities.append(simulation.state.logistics)
	for entity in entities:
		lines.append(entity.company_name + " — Caja actual %.2f" % entity.cash)
		var index: int = int(report_period.value) - 1
		if index < 0 or index >= entity.finance.reports.size():
			lines.append("Todavía no hay un período cerrado.\n")
			continue
		var report: Dictionary = entity.finance.reports[index]
		lines.append("Día %d: inicial %.2f + entradas %.2f - salidas %.2f = final %.2f | diferencia %.8f" % [report.cycle, report.opening, report.incoming, report.outgoing, report.closing, report.difference])
		for category in report.categories:
			var amounts: Dictionary = report.categories[category]
			lines.append("  %s: entradas %.2f | salidas %.2f" % [category, amounts["in"], amounts["out"]])
		lines.append("Beneficio operativo %.2f | neto %.2f | deuda %.2f" % [report.operating_profit, report.net_profit, report.debt])
		if report.has("inventory"):
			lines.append("Terminados %d, costo %.2f | patrimonio %.2f" % [report.inventory, report.inventory_value, report.equity])
			if report.has("inputs"):
				lines.append("Insumos %d | Repuestos %d | Recursos y equipos al costo %.2f | Flota al costo %.2f" % [report.inputs, report.spares, report.resource_value, report.fleet_value])
		else:
			lines.append("Por cobrar %.2f | anticipos pendientes de devengar %.2f" % [report.receivables, report.deferred_revenue])
		lines.append("")
	reports_view.text = "\n".join(lines)

func _button(parent: Container, caption: String, action: Callable) -> Button:
	## Cada botón se conecta a una sola operación del controlador.
	var button := Button.new()
	button.text = caption
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _mark_pending() -> void:
	## Los ciclos automáticos respetan decisiones aplicadas y conservan los borradores.
	status_label.text = "Borrador pendiente: aplica el precio y la producción en su columna."


func _toggle_automatic() -> void:
	## Conserva el avance discreto y evita pasos manuales mientras corre el reloj.
	automatic_running = not automatic_running
	if automatic_running:
		cycle_timer.start()
	else:
		cycle_timer.stop()
	advance_button.disabled = automatic_running
	automatic_button.text = "Pausar reloj" if automatic_running else "Iniciar reloj"
	_refresh()


func _advance() -> void:
	## Presenta resultados después de que el modelo cierre las cuentas del día.
	if simulation.advance_cycle():
		_refresh()


func _refresh() -> void:
	## Consulta estado y proyección del modelo; solo suma y formatea para presentar.
	var state = simulation.state
	var estimate: Array[int] = simulation.estimate_next_sales()
	var estimated_total: int = 0
	for units in estimate:
		estimated_total += units
	summary_label.text = "%s · Período %d · ventas totales %d · %s" % [state.locality_name, state.cycle, state.total_sales, "EN MARCHA" if automatic_running else "PAUSADO"]
	for index in range(company_panels.size()):
		company_panels[index].show_company(state.companies[index], estimate[index])
	report_period.max_value = state.cycle
	if state.cycle > 0 and int(report_period.value) >= state.cycle - 1:
		report_period.value = state.cycle
	_show_report()
	events_view.text = "\n".join(state.events)
	events_view.scroll_vertical = events_view.get_line_count()
	for panel in rental_panels:
		panel.refresh(state)
	for panel in administration_panels:
		panel.refresh()
	for index in range(2):
		var company = state.companies[index]
		var employees: int = company.operations.employees if company.operations != null else 0
		var vehicles: int = company.own_fleet.vehicles if company.own_fleet != null else 0
		home_summaries[index].text = "Ingresos   %.2f\nGastos      %.2f\nEmpleados   %d\nTransportes   %d" % [company.revenue, company.operating_costs, employees, vehicles]
		home_summaries[index].tooltip_text = "Resultados del último cierre. Empleados de producción y vehículos propios; conductores y capacidad arrendada en Logística."
		home_finances[index].text = "FINANZAS\nEfectivo %.2f · beneficio neto %.2f\nDeuda %.2f" % [company.cash, company.net_profit, company.note_debt + company.wages_payable + (company.own_fleet.payable if company.own_fleet != null else 0.0)]
	var recent := PackedStringArray()
	# La portada prioriza decisiones y resultados; los movimientos de caja siguen en Eventos/Finanzas.
	for event in state.events:
		if not event.contains("; caja "):
			recent.append(event)
			if recent.size() > 6:
				recent.remove_at(0)
	recent_events.text = "Sin eventos. Avanza un período para iniciar la economía." if recent.is_empty() else "\n".join(recent)
	var consolidated: Dictionary = simulation.consolidated_result()
	for panel in rental_panels:
		if consolidated.available:
			panel.purchase_label.text += "\nGrupo: beneficio neto %.2f\nServicios internos eliminados: %.2f" % [consolidated.net_profit, consolidated.eliminated]

func _request_contract(client_index: int, capacity: int, days: int, allow_credit: bool = false) -> void:
	## Muestra la respuesta real y refresca caja, reservas, estimación y eventos.
	var result: Dictionary = simulation.request_contract(client_index, capacity, days, allow_credit)
	status_label.text = result.message
	_refresh()


func _cancel_contract(contract_id: int) -> void:
	## Las condiciones de duración se verifican en el modelo, incluso si el botón se pulsa.
	var result: Dictionary = simulation.cancel_contract(contract_id)
	status_label.text = result.message
	_refresh()


func _acquire_logistics(buyer_index: int, quoted_price: float) -> void:
	## El mensaje de compra permanece visible aunque luego se soliciten contratos.
	var result: Dictionary = simulation.acquire_logistics(buyer_index, quoted_price)
	rental_panels[buyer_index].purchase_result.text = result.message
	_refresh()


func _manage_operations(action: String, amount: int, client_index: int) -> void:
	## Los índices se fijan al conectar cada panel; las reglas validan la operación.
	var result: Dictionary = simulation.manage_operations(client_index, action, amount)
	status_label.text = result.message
	_refresh()


func _pay_note(client_index: int, note_id: int, amount: float) -> void:
	## Presenta la respuesta del acreedor y actualiza ambos saldos reales.
	var result: Dictionary = simulation.pay_note(client_index, note_id, amount)
	status_label.text = result.message
	_refresh()


func _invest_logistics(client_index: int, units: int) -> void:
	## Mantiene la inversión para descuentos separada del botón de adquisición.
	var result: Dictionary = simulation.invest_in_logistics(client_index, units)
	status_label.text = result.message
	_refresh()
