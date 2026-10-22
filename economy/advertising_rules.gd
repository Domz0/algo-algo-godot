extends RefCounted
## Campaña local sencilla: gasto del período que incrementa el reconocimiento de marca.


static func apply(company, config) -> void:
	## La campaña usa la caja sobrante tras producir; nunca crea deuda ni inventario.
	if not company.active_this_cycle:
		return
	company.advertising_spending = minf(company.advertising_budget, company.cash)
	company.cash -= company.advertising_spending
	# El reconocimiento acumulado persiste y se limita a 1; no hay desgaste todavía.
	company.brand = minf(1.0, company.brand + company.advertising_spending * config.advertising_brand_gain)
