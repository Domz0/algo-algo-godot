extends SceneTree
## Comprueba políticas persistentes, compras reales y separación A/B en todos los menús.

const Config = preload("res://economy/economy_config.gd")
const Simulation = preload("res://economy/simulation.gd")
var checks: int = 0
var failures: int = 0


func _init() -> void:
	## Los controles deben montarse después de inicializar el árbol.
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	## Acumula fallos, conservando diagnósticos de todos los escenarios.
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _near(actual: float, expected: float, message: String) -> void:
	## Solo admite el error de representación binaria, nunca una diferencia de caja económica.
	_check(absf(actual - expected) < 0.00001, "%s: %.6f != %.6f" % [message, actual, expected])


func _config():
	## Aísla decisiones administrativas con liquidez suficiente y sin expansión automática externa.
	var config = Config.new()
	config.companies[0].cash = 10000.0
	config.companies[1].cash = 10000.0
	config.logistics_auto_expand = false
	return config


func _run() -> void:
	## Ejecuta reglas primero y luego los mismos cambios mediante señales reales de controles.
	_test_targets()
	_test_purchases()
	await _test_menus()
	print("Administración e interfaz: %d comprobaciones, %d fallos." % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_targets() -> void:
	## Una política crece hasta el objetivo sin reclutar dos veces al volver a aplicarla.
	var config = _config()
	var sim = Simulation.new(config)
	var company = sim.state.companies[0]
	var ops = company.operations
	var initial: float = company.cash
	_check(sim.set_staff_target(0, 9).ok, "Aplica plantilla objetivo")
	_near(company.cash, initial - 5 * config.hiring_cost, "Selección se paga por nuevas vacantes")
	_check(ops.employees == 4 and ops.vacancies == 5, "Objetivo no incorpora inmediatamente")
	initial = company.cash
	sim.set_staff_target(0, 9)
	_near(company.cash, initial, "Reaplicar no vuelve a cobrar selección")
	for expected in [4, 6, 8, 9, 9]:
		sim.advance_cycle()
		_check(ops.employees == expected, "Plantilla progresa por períodos y se detiene")
		_near(ops.salary_expense, expected * config.wage_per_employee, "Salario solo de personas incorporadas")
	_check(ops.vacancies == 0 and ops.pending_count() == 0, "No quedan vacantes al alcanzar objetivo")
	sim.set_staff_target(0, 14)
	sim.advance_cycle()
	_check(sim.set_staff_target(0, 10).ok, "Puede reducir un objetivo sin despedir actuales")
	for day in range(4):
		sim.advance_cycle()
	_check(ops.employees == 10, "Cancelar candidatos sobrantes evita exceder objetivo reducido")
	sim.set_staff_target(0, 15)
	initial = company.cash
	_check(sim.manage_operations(0, "fire", 3).ok, "Despido explícito permitido")
	_near(company.cash, initial - 3 * config.wage_per_employee, "Despido cobra un sueldo por persona")
	_check(ops.staff_target == 7 and ops.pending_count() == 0 and ops.vacancies == 0, "Despido ajusta política y detiene incorporaciones")
	sim.advance_cycle()
	_check(ops.employees == 7, "Política no recontrata a los despedidos")
	_check(not sim.set_staff_target(0, 6).ok and not sim.set_staff_target(0, -1).ok, "Reducir plantilla requiere despido pagado")
	_check(not sim.set_staff_target(2, 9).ok, "Cliente inexistente rechazado")
	company.cash = 0.0
	var target: int = ops.staff_target
	_check(not sim.set_staff_target(0, 20).ok and ops.staff_target == target, "Objetivo sin fondos es atómico")
	_check(not sim.manage_operations(0, "fire", 1).ok and ops.employees == 7, "Sin caja no cobra indemnizaciones ficticias")


func _test_purchases() -> void:
	## La reposición se limita por objetivo, presupuesto, espacio y reserva; observar no compra.
	var config = _config()
	config.initial_inputs = 0
	config.companies[0].production_target = 0
	var sim = Simulation.new(config)
	var company = sim.state.companies[0]
	var ops = company.operations
	var cash: float = company.cash
	_check(sim.set_auto_purchasing(0, true, 20, 12.0).ok, "Activa reposición con presupuesto")
	_near(company.cash, cash, "Guardar política no compra fuera del ciclo")
	for unused in range(3):
		sim.estimate_next_sales()
	_check(ops.warehouse.inputs == 0, "Pronóstico no repone inventario real")
	for expected in [6, 12, 18, 20, 20]:
		sim.advance_cycle()
		_check(ops.warehouse.inputs == expected, "Reposición gradual alcanza stock objetivo")
		_check(ops.auto_spent <= 12.0 and ops.auto_bought >= 0, "Respeta presupuesto por período")
		_near(company.finance.reports[-1].difference, 0.0, "Compra automática concilia efectivo")
	_check(ops.auto_bought == 0, "No gasta al estar abastecido")
	sim.set_auto_purchasing(0, false, 100, 100.0)
	sim.advance_cycle()
	_check(ops.warehouse.inputs == 20, "Modo manual desactiva reposición")
	_check(sim.manage_operations(0, "inputs", 3).ok and ops.warehouse.inputs == 23, "Compra manual sigue disponible")
	_check(not sim.set_auto_purchasing(0, true, -1, 20).ok, "Rechaza objetivo negativo")
	_check(not sim.set_auto_purchasing(0, true, 10, NAN).ok and not ops.auto_inputs, "Presupuesto inválido conserva política anterior")
	var poor = Simulation.new(config)
	poor.state.companies[0].cash = config.auto_purchase_cash_reserve
	poor.set_auto_purchasing(0, true, 50, 1000.0)
	poor.advance_cycle()
	_check(poor.state.companies[0].operations.auto_bought == 0, "Reserva nóminas y caja mínima antes de comprar")
	var full = Simulation.new(config)
	full.manage_operations(0, "spares", 10000)
	full.set_auto_purchasing(0, true, 50, 1000.0)
	full.advance_cycle()
	_check(full.state.companies[0].operations.auto_bought == 0, "Bodega llena impide reposición automática")
	var live = Simulation.new(_config())
	live.set_staff_target(1, 11)
	live.set_auto_purchasing(1, true, 150, 100.0)
	for day in range(12):
		var forecast: Array[int] = live.estimate_next_sales()
		live.advance_cycle()
		_check(forecast[1] == live.state.companies[1].sales, "Pronóstico incluye personal y compras automáticas")
		var b = live.state.companies[1]
		_near(b.finance.reports[-1].difference, 0.0, "Políticas conjuntas conservan conciliación")
		_check(b.operations.warehouse.occupied(b.inventory) <= b.operations.warehouse.capacity, "Políticas nunca desbordan bodega")


func _test_menus() -> void:
	## Todos los menús mantienen columnas y las señales de B nunca modifican A.
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.simulation = Simulation.new(_config())
	root.add_child(scene)
	_check(scene.sections.current_tab == 0 and scene.sections.get_tab_title(0) == "Inicio", "Abre en portada mínima")
	var expected_names: Array[String] = ["Inicio", "Resultados", "Logística", "Administración", "Arriendo de transportes", "Finanzas", "Eventos"]
	for index in range(expected_names.size()):
		_check(scene.sections.get_tab_title(index) == expected_names[index], "Menú presente: " + expected_names[index])
	var a = scene.simulation.state.companies[0]
	var b = scene.simulation.state.companies[1]
	var panel = scene.administration_panels[1]
	panel.target_slider.value = 10
	_check(b.operations.employees == 4 and b.operations.vacancies == 0, "Arrastrar solo edita borrador")
	await process_frame
	panel.target_button.pressed.emit()
	_check(b.operations.staff_target == 10 and a.operations.staff_target == -1, "Botón de B afecta solo su plantilla")
	scene.advance_button.pressed.emit()
	_check(panel.progress.value == 4 and b.operations.pending_count() == 2, "Barra representa incorporación real")
	scene.advance_button.pressed.emit()
	_check(panel.progress.value == 6, "Barra aumenta al llegar candidatos")
	panel.fire_slider.value = 2
	await process_frame
	var before: float = b.cash
	panel.fire_button.pressed.emit()
	_near(b.cash, before - 8.0, "Slider de despido descuenta indemnización al confirmar")
	panel.auto_check.button_pressed = true
	panel.stock_target.get_line_edit().text = "120"
	panel.budget_input.get_line_edit().text = "50"
	panel.purchase_button.pressed.emit()
	_check(b.operations.auto_inputs and not a.operations.auto_inputs, "Reposición independiente por empresa")
	panel.manual_amount.get_line_edit().text = "3"
	before = b.cash
	panel.manual_button.pressed.emit()
	_near(b.cash, before - 6.0, "Compra manual de B cobra solo a B")
	var rental = scene.rental_panels[1]
	rental.capacity_input.get_line_edit().text = "3"
	rental.days_input.get_line_edit().text = "2"
	rental.request_button.pressed.emit()
	_check(b.contracted_capacity == 3 and a.contracted_capacity == 0, "Arriendo de columna B se asigna a B")
	_check(rental.contracts_view.text.contains("Empresa B") and not scene.rental_panels[0].contracts_view.text.contains("Empresa B"), "Contratos filtrados por su cliente")
	rental.cancel_button.pressed.emit()
	_check(b.contracted_capacity == 0, "Cancelación desde la misma columna")
	for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		root.content_scale_size = Vector2i.ZERO
		for tab in range(scene.sections.get_tab_count()):
			scene.sections.current_tab = tab
			await process_frame
			await process_frame
			_check(scene.sections.get_global_rect().end.y <= resolution.y + 1, "Menús caben verticalmente en " + str(resolution))
			_check_horizontal(scene, float(resolution.x))
	_check(scene.home_summaries[1].text.contains("Ingresos") and scene.home_summaries[1].text.contains("Transportes"), "Portada contiene solo métricas principales")
	scene.queue_free()


func _check_horizontal(node: Node, width: float) -> void:
	## Ignora internals de editores y comprueba los controles visibles que recibe el jugador.
	if node is Control and node.is_visible_in_tree() and (node is Button or node is HSlider or node is SpinBox or node is Label):
		_check(node.get_global_rect().position.x >= -1 and node.get_global_rect().end.x <= width + 1, "Control dentro de ancho: " + str(node.get_path()))
		var ancestor = node.get_parent()
		while ancestor != null:
			if ancestor is ScrollContainer:
				_check(node.get_global_rect().end.x <= ancestor.get_global_rect().end.x + 1, "Control no invade la columna rival: " + str(node.get_path()))
				break
			ancestor = ancestor.get_parent()
	for child in node.get_children():
		_check_horizontal(child, width)
