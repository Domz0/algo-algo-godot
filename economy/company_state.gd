extends RefCounted
## Datos de una empresa humana; no decide precios ni ejecuta reglas económicas.

var company_name: String
var human_controlled: bool = true
# Capital inicial es la aportación de apertura; cash es el dinero gastable actual.
var initial_capital: float
const CashBook = preload("res://economy/cash_book.gd")
var finance = CashBook.new()
var cash: float:
	get:
		return finance.balance
	set(value):
		finance.change_to(value)
var price: float
var capacity: int
var production_target: int
var variable_unit_cost: float
var fixed_cost: float
var market_share: float = 0.0
# El anticipo es un activo: se convierte en gasto al consumir días de contrato.
var prepaid_logistics: float = 0.0
# Inversión al costo histórico: comprar participaciones no es un gasto operativo.
var logistics_investment: float = 0.0
var own_logistics_capacity: int
var contracted_capacity: int = 0
var logistics_expense: float = 0.0
# Límite y uso del último día, separados de las reservas del próximo día.
var distribution_limit: int = 0
var distributed_units: int = 0
var inventory: int = 0
# Valor contable del stock: permite conservar costos de ciclos anteriores.
var inventory_value: float = 0.0
# Estos resultados corresponden exclusivamente al último ciclo ejecutado.
var production: int = 0
var sales: int = 0
var revenue: float = 0.0
var production_spending: float = 0.0
var fixed_cost_paid: float = 0.0
var cost_of_goods_sold: float = 0.0
var operating_costs: float = 0.0
var operating_profit: float = 0.0
var cash_flow: float = 0.0
var active_this_cycle: bool = false
# Recursos físicos y obligaciones se mantienen separados de caja y beneficios.
var own_fleet
var operations
var wages_payable: float = 0.0
var note_debt: float = 0.0
var interest_expense: float = 0.0
var net_profit: float = 0.0
var discount_asset: float = 0.0
var discount_expense: float = 0.0
var cash_at_period_start: float = 0.0


func _init(parameters: Dictionary) -> void:
	## Copia los parámetros para que las decisiones no alteren el escenario original.
	company_name = parameters.name
	initial_capital = parameters.cash
	finance.initialize(initial_capital)
	cash_at_period_start = cash
	price = parameters.price
	capacity = parameters.capacity
	production_target = parameters.production_target
	variable_unit_cost = parameters.variable_cost
	fixed_cost = parameters.fixed_cost
	own_logistics_capacity = parameters.own_logistics_capacity


func reset_cycle_results() -> void:
	## Conserva caja y existencias, pero borra resultados que no deben acumularse.
	production = 0
	sales = 0
	revenue = 0.0
	production_spending = 0.0
	fixed_cost_paid = 0.0
	cost_of_goods_sold = 0.0
	operating_costs = 0.0
	operating_profit = 0.0
	cash_flow = 0.0
	active_this_cycle = false
	market_share = 0.0
	logistics_expense = 0.0
	distributed_units = 0
	distribution_limit = logistics_capacity()
	interest_expense = 0.0
	discount_expense = 0.0
	net_profit = 0.0


func equity() -> float:
	## Los anticipos pendientes conservan valor hasta consumir el servicio reservado.
	var resources: float = operations.asset_value() if operations != null else 0.0
	var fleet_assets: float = own_fleet.book_value() - own_fleet.payable if own_fleet != null else 0.0
	return fleet_assets + cash + inventory_value + prepaid_logistics + logistics_investment + resources + discount_asset - wages_payable - note_debt


func logistics_capacity() -> int:
	## Capacidad diaria habilitada por flota propia y reservas vigentes.
	return effective_own_capacity() + contracted_capacity


func estimated_value() -> float:
	## Referencia ficticia: patrimonio al costo más diez beneficios netos positivos del último día.
	return maxf(0.0, equity() + 10.0 * maxf(0.0, net_profit))


func effective_own_capacity() -> int:
	## La flota financiable puede ser menor que la nominal por falta de combustible o salarios.
	return own_fleet.effective_capacity if own_fleet != null else own_logistics_capacity