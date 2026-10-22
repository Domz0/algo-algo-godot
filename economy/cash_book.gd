extends RefCounted
## Libro de caja: registra movimientos brutos; el beneficio se calcula por separado.

var balance: float = 0.0
var opening: float = 0.0
var category: String = "Otros movimientos"
var movements: Array[Dictionary] = []
var pending_events: Array[Dictionary] = []
var reports: Array[Dictionary] = []


func initialize(amount: float) -> void:
	## La dotación inicial es un saldo de apertura, nunca una venta del primer día.
	balance = amount
	opening = amount


func change_to(amount: float) -> void:
	## Toda mutación de caja pasa por aquí, incluso cuando cobro y pago se compensan.
	var delta: float = amount - balance
	if delta != 0.0:
		var entry: Dictionary = {"reason": category, "change": delta, "before": balance, "after": amount}
		movements.append(entry)
		pending_events.append(entry.duplicate())
	balance = amount


func close(cycle: int, details: Dictionary) -> void:
	## Congela una conciliación por período, incluyendo decisiones tomadas entre cierres.
	var incoming: float = 0.0
	var outgoing: float = 0.0
	var categories: Dictionary = {}
	for entry in movements:
		if not categories.has(entry.reason):
			categories[entry.reason] = {"in": 0.0, "out": 0.0}
		if entry.change > 0.0:
			incoming += entry.change
			categories[entry.reason]["in"] += entry.change
		else:
			outgoing -= entry.change
			categories[entry.reason]["out"] -= entry.change
	var report: Dictionary = details.duplicate(true)
	report.merge({"cycle": cycle, "opening": opening, "incoming": incoming, "outgoing": outgoing, "closing": balance, "categories": categories, "movements": movements.duplicate(true), "difference": balance - (opening + incoming - outgoing)})
	reports.append(report)
	movements.clear()
	opening = balance
