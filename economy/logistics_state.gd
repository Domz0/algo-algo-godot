extends RefCounted
## Empresa independiente con caja, ingresos diferidos y resultados por ciclo.

var company_name: String
var owner: String
# -1 identifica al vendedor externo; la etapa permite una única venta, sin reventa.
var owner_company_index: int = -1
var acquired_cycle: int = -1
var acquisition_paid: float = 0.0
var external_seller_proceeds: float = 0.0
var valuation_age: int = 0
var value_growth_rate: float
var purchase_multiplier: float
var total_capacity: int
var contracted_capacity: int = 0
var unit_rate: float
var fixed_fee: float
var cash: float
# Es una obligación por servicios aún no prestados, no ingreso ni dinero libre.
var deferred_revenue: float = 0.0
var revenue: float = 0.0
var operating_costs: float = 0.0
var operating_profit: float = 0.0
var cash_flow: float = 0.0
var distributed_units: int = 0
var contracts: Array = []
var next_contract_id: int = 1
var asset_value_per_unit: float
var profit_multiple: float
# Los pagarés son derechos de cobro, no efectivo utilizable para expandirse.
var extended: bool = false
var notes: Array = []
var receivables: float = 0.0
var interest_income: float = 0.0
var net_profit: float = 0.0
var operating_payable: float = 0.0
var fuel_expense: float = 0.0
var staff_expense: float = 0.0
var maintenance_expense: float = 0.0
var fixed_expense: float = 0.0
var cash_at_period_start: float
var investments: Array[Dictionary] = []
var discount_deferred: float = 0.0
var discount_income: float = 0.0
var expansion_book_value: float = 0.0
var expanded_units: int = 0
var requested_capacity: int = 0


func _init(config) -> void:
	## Copia parámetros para que las condiciones firmadas no dependan de la interfaz.
	company_name = config.logistics_name
	owner = config.logistics_owner
	total_capacity = config.logistics_capacity
	unit_rate = config.logistics_unit_rate
	fixed_fee = config.logistics_contract_fee
	cash = config.logistics_initial_cash
	asset_value_per_unit = config.logistics_asset_value_per_unit
	profit_multiple = config.logistics_profit_multiple
	value_growth_rate = config.logistics_value_growth_rate
	purchase_multiplier = config.logistics_purchase_multiplier
	extended = config.extended_economy
	cash_at_period_start = cash


func available_capacity() -> int:
	## Capacidad que todavía puede ofrecerse, sin contar dos veces las reservas.
	return total_capacity - contracted_capacity


func available_cash() -> float:
	## Separa anticipos comprometidos del dinero libre del operador.
	# Solo principal sin cobrar financia anticipos pendientes. El interés por cobrar nunca libera caja.
	var unfunded: float = 0.0
	for contract in contracts:
		if contract.note_id >= 0:
			unfunded += minf(contract.prepaid_balance, notes[contract.note_id - 1].principal)
	return maxf(0.0, cash - maxf(0.0, deferred_revenue - unfunded) - operating_payable)


func estimated_value() -> float:
	## Base económica por crecimiento lineal: la revalorización no entra en ninguna cuenta.
	var base: float = available_cash() + total_capacity * asset_value_per_unit + maxf(0.0, operating_profit) * profit_multiple
	if extended:
		# Flota nueva al 110% de costo estimado, en lugar de contar dos veces sus unidades.
		base += expansion_book_value * 1.1 - expanded_units * asset_value_per_unit
	return maxf(0.0, base * (1.0 + value_growth_rate * valuation_age))


func acquisition_price() -> float:
	## Multiplicador configurable sobre la estimación; no es el saldo bancario del operador.
	return estimated_value() * purchase_multiplier


func book_equity() -> float:
	## Patrimonio individual: flota al costo, cuentas por cobrar y obligaciones reales; sin revalorización.
	var initial_fleet: float = (total_capacity - expanded_units) * asset_value_per_unit
	return cash + receivables + initial_fleet + expansion_book_value - deferred_revenue - discount_deferred - operating_payable
