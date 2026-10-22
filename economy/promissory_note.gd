extends RefCounted
## Pagaré de un contrato: interés simple sobre principal vivo, sin multas arbitrarias.

var id: int
var client_index: int
var contract_id: int
var original_principal: float
var principal: float
var interest_due: float = 0.0
var interest_rate: float
var issued_cycle: int
var due_cycle: int
var blocks_credit_when_overdue: bool = true
var payments: Array[Dictionary] = []
var status: String = "vigente"


func balance() -> float:
	## Separa principal de intereses para no capitalizar interés de manera implícita.
	return principal + interest_due
