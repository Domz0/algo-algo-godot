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
	## Contenedores y desplazamiento mantienen una sola pantalla utilizable al redimensionar.
	var scroll := ScrollContainer.new()
	add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	scroll.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)
	summary_label = Label.new()
	content.add_child(summary_label)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	content.add_child(columns)
	for company in simulation.state.companies:
		var panel = CompanyPanel.new()
		columns.add_child(panel)
		panel.setup(company, simulation.config)
		# Editar solo marca un borrador: todavía no altera decisiones del modelo.
		panel.decision_edited.connect(_mark_pending)
		panel.operation_requested.connect(_manage_operations.bind(company_panels.size()))
		company_panels.append(panel)
	var buttons := HBoxContainer.new()
	content.add_child(buttons)
	apply_button = _button(buttons, "Aplicar decisiones", _apply_decisions)
	advance_button = _button(buttons, "Avanzar un día", _advance)
	automatic_button = _button(buttons, "Iniciar reloj", _toggle_automatic)
	status_label = Label.new()
	status_label.text = "Edita los campos, aplica las decisiones y avanza un día."
	content.add_child(status_label)
	logistics_panel = LogisticsPanel.new()
	content.add_child(logistics_panel)
	logistics_panel.setup(simulation.state, simulation.config)
	# La vista emite solicitudes; solo Simulation puede aceptar o cancelar contratos.
	logistics_panel.contract_requested.connect(_request_contract)
	logistics_panel.cancellation_requested.connect(_cancel_contract)
	logistics_panel.acquisition_requested.connect(_acquire_logistics)
	logistics_panel.note_payment_requested.connect(_pay_note)
	logistics_panel.investment_requested.connect(_invest_logistics)
	var title := Label.new()
	title.text = "Registro de eventos (últimos 100)"
	content.add_child(title)
	events_view = TextEdit.new()
	events_view.editable = false
	events_view.custom_minimum_size.y = 140
	content.add_child(events_view)


func _button(parent: Container, caption: String, action: Callable) -> Button:
	## Cada botón se conecta a una sola operación del controlador.
	var button := Button.new()
	button.text = caption
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _mark_pending() -> void:
	## Los ciclos automáticos respetan decisiones aplicadas y conservan los borradores.
	status_label.text = "Cambios pendientes: pulsa Aplicar decisiones."


func _apply_decisions() -> void:
	## La API valida las entradas; aplicar no avanza el día ni consume caja.
	var accepted: bool = true
	for index in range(company_panels.size()):
		var panel = company_panels[index]
		panel.commit_fields()
		if not simulation.set_decision(index, panel.price_input.value, int(panel.production_input.value), panel.advertising_input.value):
			accepted = false
	status_label.text = "Decisiones aplicadas al próximo ciclo." if accepted else "Hay decisiones inválidas; revisa los campos."
	_refresh()


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
	summary_label.text = "%s | %s | Día %d | %s\nDemanda potencial: %d | Demanda estimada con venta, próximo día: %d\nÚltimo día: ventas totales %d | Demanda no atendida %d%s\nImportes en créditos ficticios. Cuota = participación en las ventas realizadas." % [state.locality_name, state.product_name, state.cycle, "AUTOMÁTICO" if automatic_running else "PAUSADO", simulation.config.market_demand, estimated_total, state.total_sales, state.unserved_demand, " (aún sin ciclos)" if state.cycle == 0 else ""]
	for index in range(company_panels.size()):
		company_panels[index].show_company(state.companies[index], estimate[index])
	events_view.text = "\n".join(state.events)
	events_view.scroll_vertical = events_view.get_line_count()
	logistics_panel.refresh(state)
	var consolidated: Dictionary = simulation.consolidated_result()
	if consolidated.available:
		logistics_panel.purchase_label.text += "\nGrupo del propietario, último día: ingresos %.2f | costos %.2f | beneficio %.2f\nServicios internos eliminados de ingresos y gastos: %.2f" % [consolidated.revenue, consolidated.costs, consolidated.profit, consolidated.eliminated]
		logistics_panel.purchase_label.text += "\nBeneficio neto consolidado %.2f | Interés interno eliminado %.2f" % [consolidated.net_profit, consolidated.internal_interest]
	elif state.logistics.owner_company_index >= 0:
		logistics_panel.purchase_label.text += "\nResultado consolidado: disponible tras el primer ciclo posterior a la compra."


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
	logistics_panel.purchase_result.text = result.message
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
