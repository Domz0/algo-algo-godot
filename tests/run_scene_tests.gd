extends SceneTree
## Pruebas de integración: campos y botones reales, resultados visibles y publicidad.

const Config = preload("res://economy/economy_config.gd")
const Simulation = preload("res://economy/simulation.gd")
var failures: int = 0
var checks: int = 0


func _init() -> void:
	## Espera a que el árbol pueda montar controles y temporizadores.
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	## Acumula errores para diagnosticar toda la integración en una ejecución.
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _near(actual: float, expected: float, description: String) -> void:
	## Usa tolerancia solo para la representación binaria de importes.
	_check(absf(actual - expected) < 0.00001, description)


func _scene():
	## Cada caso comienza con las mismas condiciones y sin resultados previos.
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.simulation = Simulation.new(_legacy_config())
	root.add_child(scene)
	return scene


func _run() -> void:
	## Compara decisiones editadas en pantalla con una partida de referencia.
	var baseline = Simulation.new(_legacy_config())
	baseline.advance_cycle()
	var scene = _scene()
	var panel = scene.company_panels[0]
	_check(scene.simulation.state.cycle == 0 and scene.cycle_timer.is_stopped(), "Inicio pausado")
	panel.price_input.get_line_edit().text = "40"
	_check(scene.simulation.state.companies[0].price == 20.0, "El borrador no cambia el modelo")
	scene.apply_button.pressed.emit()
	_check(scene.simulation.state.companies[0].price == 40.0, "Aplicar confirma texto sin Enter")
	_check(scene.simulation.state.cycle == 0, "Aplicar no avanza un día")
	_check(panel.metrics.price.text == "40.00", "Precio aplicado visible")
	var estimate: Array[int] = scene.simulation.estimate_next_sales()
	scene.advance_button.pressed.emit()
	var company = scene.simulation.state.companies[0]
	_check(company.sales < baseline.state.companies[0].sales, "Subir precio reduce ventas frente al control")
	_check(panel.metrics.sales.text == str(company.sales), "Ventas reales visibles")
	_check(panel.metrics.revenue.text == "%.2f" % company.revenue, "Ingresos reales visibles")
	_check(company.sales == estimate[0], "La estimación coincide con el siguiente ciclo")
	_check(scene.events_view.text.contains("precio 20.00 → 40.00") and scene.events_view.text.contains("vendió"), "Registro visible de precio y ventas")
	_check(scene.summary_label.text.contains("ventas totales %d" % scene.simulation.state.total_sales), "Resumen del mercado real")
	_near(company.market_share + scene.simulation.state.companies[1].market_share, 1.0, "Cuotas sobre ventas suman uno")
	panel.production_input.value = 7
	scene.advance_button.pressed.emit()
	_check(panel.production_input.value == 7, "Refrescar no borra decisiones pendientes")
	scene.cycle_timer.wait_time = 0.02
	scene.automatic_button.pressed.emit()
	await scene.cycle_timer.timeout
	scene.automatic_button.pressed.emit()
	_check(not scene.automatic_running and scene.cycle_timer.is_stopped(), "Reloj avanza y permite pausar")
	scene.queue_free()

	scene = _scene()
	panel = scene.company_panels[0]
	panel.production_input.get_line_edit().text = "5"
	scene.apply_button.pressed.emit()
	scene.advance_button.pressed.emit()
	company = scene.simulation.state.companies[0]
	_check(company.production == 5 and company.sales == 5, "Producción objetivo limita la oferta real")
	_check(company.sales < baseline.state.companies[0].sales, "Cambiar producción cambia las ventas")
	_check(panel.metrics.production.text == "5 / 100" and panel.metrics.sales.text == "5", "Cambio de producción visible")
	scene.queue_free()

	scene = _scene()
	panel = scene.company_panels[0]
	panel.advertising_input.get_line_edit().text = "100"
	scene.apply_button.pressed.emit()
	company = scene.simulation.state.companies[0]
	var initial_brand: float = company.brand
	var initial_cash: float = company.cash
	var event_count: int = scene.simulation.state.events.size()
	for unused in range(3):
		scene.simulation.estimate_next_sales()
	_near(company.cash, initial_cash, "Estimar no gasta caja")
	_near(company.brand, initial_brand, "Estimar no aumenta marca")
	_check(scene.simulation.state.events.size() == event_count, "Estimar no crea eventos")
	scene.advance_button.pressed.emit()
	_near(company.advertising_spending, 100.0, "Campaña pagada")
	_near(company.brand, 0.45, "Marca aumenta según configuración")
	_check(company.sales > baseline.state.companies[0].sales, "Publicidad modifica ventas")
	_near(company.cash, initial_cash + company.revenue - company.production_spending - company.fixed_cost_paid - 100.0, "Publicidad incluida en caja")
	_near(company.equity(), initial_cash + company.operating_profit, "Publicidad incluida en beneficio")
	_check(panel.metrics.advertising.text == "100.00" and panel.metrics.brand.text == "0.450", "Publicidad visible")
	_check(not scene.simulation.set_decision(0, 20.0, 80, -1.0), "Rechaza publicidad negativa")
	_check(not scene.simulation.set_decision(0, 20.0, 80, NAN), "Rechaza publicidad NaN")
	_check(not scene.simulation.set_decision(0, 20.0, 80, 1001.0), "Rechaza publicidad sobre el límite")
	scene.queue_free()
	_test_advertising_limits()
	print("Integración etapa 2: %d comprobaciones, %d fallos." % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_advertising_limits() -> void:
	## Verifica caja escasa, marca saturada, ausencia de ventas y registro acotado.
	var config = _legacy_config()
	config.market_demand = 0
	config.companies[0].cash = 65.0
	var sim = Simulation.new(config)
	sim.set_decision(0, 20.0, 0, 100.0)
	sim.advance_cycle()
	var company = sim.state.companies[0]
	_near(company.advertising_spending, 5.0, "Solo se gasta caja restante")
	_near(company.cash, 0.0, "Publicidad no crea caja negativa")
	_near(company.operating_profit, -65.0, "Pérdida incluye fijo y campaña")
	_near(company.market_share, 0.0, "Sin ventas cuota cero")
	_check(sim.state.events.size() > 0, "Problemas económicos generan eventos")
	sim.advance_cycle()
	_near(company.advertising_spending, 0.0, "Suspensión no gasta publicidad")
	config = _legacy_config()
	config.companies[0].cash = 10000.0
	sim = Simulation.new(config)
	sim.set_decision(0, 20.0, 0, 1000.0)
	sim.advance_cycle()
	_near(sim.state.companies[0].brand, 1.0, "Marca limitada a uno")
	for day in range(150):
		sim.advance_cycle()
	_check(sim.state.events.size() == 100, "Registro conserva solo cien eventos")


func _legacy_config():
	## Aísla regresiones de etapas 1–4 sin recursos adicionales; la etapa 5 tiene su propia suite.
	var config = Config.new()
	config.extended_economy = false
	return config
