extends SceneTree
## Pruebas de integración: campos y botones reales, resultados visibles.

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

	var observed = Simulation.new(_legacy_config())
	var initial_cash: float = observed.state.companies[0].cash
	for unused in range(3):
		observed.estimate_next_sales()
	_near(observed.state.companies[0].cash, initial_cash, "Estimar no gasta caja")
	_check(observed.state.events.is_empty(), "Estimar no crea eventos")
	print("Integración de pantalla: %d comprobaciones, %d fallos." % [checks, failures])
	quit(0 if failures == 0 else 1)

func _legacy_config():
	## Aísla regresiones de etapas 1–4 sin recursos adicionales; la etapa 5 tiene su propia suite.
	var config = Config.new()
	config.extended_economy = false
	return config
