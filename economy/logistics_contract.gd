extends RefCounted
## Condiciones congeladas al firmar; cada reserva ocupa capacidad durante todo su plazo.

var id: int
var client_index: int
var client_name: String
var capacity: int
var unit_rate: float
var fixed_fee: float
var unit_operating_cost: float
var fixed_operating_cost: float
var duration: int
var start_cycle: int
var end_cycle: int
# Pendiente permite desistir antes del inicio; activo exige cumplir el plazo.
var status: String = "pendiente"
var served_days: int = 0
var prepaid_balance: float = 0.0
var note_id: int = -1
var payment_terms: String = "anticipo"


func daily_fee() -> float:
	## La reserva se paga por día, independientemente de las ventas efectivas.
	return capacity * unit_rate + fixed_fee


func daily_cost() -> float:
	## El operador mantiene la capacidad lista aunque el cliente no venda.
	return capacity * unit_operating_cost + fixed_operating_cost


func reserves_capacity() -> bool:
	## Tanto los contratos pendientes como los activos bloquean nuevas reservas.
	return status == "pendiente" or status == "activo"
