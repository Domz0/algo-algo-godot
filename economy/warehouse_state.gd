extends RefCounted
## Una bodega por productora; el stock terminado sigue en CompanyState para evitar duplicarlo.

var capacity: int
var inputs: int = 0
var spares: int = 0
var inputs_value: float = 0.0
var spares_value: float = 0.0
var construction_value: float = 0.0


func occupied(finished: int) -> int:
	## Cada insumo, repuesto y producto ocupa una unidad de volumen.
	return inputs + spares + finished


func available(finished: int) -> int:
	## El espacio se calcula desde las existencias reales, no desde contadores paralelos.
	return capacity - occupied(finished)
