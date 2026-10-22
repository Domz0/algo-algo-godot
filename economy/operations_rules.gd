extends RefCounted
## Compras, personal y producción limitada por recursos; ninguna regla reside en la vista.

const Machine = preload("res://economy/machine_state.gd")


static func decide(company, config, action: String, amount: int) -> Dictionary:
	## Rechaza cambios no financiables; compras de inventario se limitan a caja y espacio.
	var ops = company.operations
	var warehouse = ops.warehouse
	if amount <= 0:
		return {"ok": false, "message": "Se requiere una cantidad o identificador positivo."}
	if action == "buy_vehicle" or action == "sell_vehicle":
		return company.own_fleet.decide(company, config, action, amount)
	if action == "cancel_vacancies":
		if amount > ops.vacancies:
			return {"ok": false, "message": "No hay tantas vacantes abiertas; los candidatos seleccionados conservan su incorporación."}
		ops.vacancies -= amount
		return {"ok": true, "message": "Vacantes canceladas sin reembolsar la selección ya pagada."}
	company.finance.category = {"inputs": "Compra de insumos", "spares": "Compra de repuestos", "expand": "Ampliación de bodega", "hire": "Selección de personal", "fire": "Indemnizaciones", "machine": "Compra de maquinaria"}.get(action, action)
	if action == "inputs" or action == "spares":
		var price: float = config.input_price if action == "inputs" else config.spare_price
		var units: int = mini(amount, warehouse.available(company.inventory))
		if price > 0.0:
			units = mini(units, int(floor(company.cash / price)))
		if units <= 0:
			return {"ok": false, "message": "Compra rechazada: falta caja o espacio en bodega."}
		company.cash -= units * price
		if action == "inputs":
			warehouse.inputs += units
			warehouse.inputs_value += units * price
		else:
			warehouse.spares += units
			warehouse.spares_value += units * price
		return {"ok": true, "message": "Compra de %s: %d de %d unidades; pago %.2f." % [action, units, amount, units * price]}
	if action == "maintenance" or action == "preventive_on" or action == "preventive_off" or action == "retire":
		for machine in ops.machines:
			if machine.id != amount:
				continue
			if action == "maintenance":
				return maintain(company, machine, false)
			if action == "retire":
				ops.pending_expenses += machine.book_value
				ops.machines.erase(machine)
				return {"ok": true, "message": "Máquina retirada sin reventa; baja contable registrada."}
			machine.preventive = action == "preventive_on"
			return {"ok": true, "message": "Programación preventiva actualizada."}
		return {"ok": false, "message": "Máquina inexistente."}
	var cost: float = 0.0
	match action:
		"expand": cost = amount * config.warehouse_expansion_unit_cost
		"hire": cost = amount * config.hiring_cost
		"fire":
			if amount > ops.employees:
				return {"ok": false, "message": "No hay tantos empleados contratados."}
			cost = amount * config.wage_per_employee
		"machine": cost = amount * config.machine_purchase_cost
		_: return {"ok": false, "message": "Operación desconocida."}
	if not is_finite(cost) or cost > company.cash:
		return {"ok": false, "message": "Capital insuficiente; operación sin cambios."}
	company.cash -= cost
	match action:
		"expand":
			warehouse.capacity += amount
			warehouse.construction_value += cost
		"hire":
			ops.vacancies += amount
			ops.pending_expenses += cost
		"fire":
			ops.employees -= amount
			ops.pending_expenses += cost
		"machine":
			for unused in range(amount):
				ops.machines.append(Machine.new(config, ops.next_machine_id, config.machine_purchase_capacity, config.machine_purchase_cost))
				ops.next_machine_id += 1
	return {"ok": true, "message": "%s: %d; pago %.2f." % [action, amount, cost]}


static func maintain(company, machine, in_cycle: bool) -> Dictionary:
	## Mantenimiento completo o rechazo sin consumo parcial; requiere repuestos y mano de obra.
	var ops = company.operations
	var warehouse = ops.warehouse
	if warehouse.spares < machine.maintenance_spares or company.cash < machine.maintenance_labor:
		return {"ok": false, "message": "Mantenimiento pendiente: faltan repuestos o caja."}
	var parts_cost: float = 0.0
	if warehouse.spares > 0:
		parts_cost = warehouse.spares_value * machine.maintenance_spares / warehouse.spares
	warehouse.spares -= machine.maintenance_spares
	warehouse.spares_value = maxf(0.0, warehouse.spares_value - parts_cost)
	company.finance.category = "Mantenimiento de maquinaria"
	company.cash -= machine.maintenance_labor
	if in_cycle:
		ops.maintenance_expense += parts_cost + machine.maintenance_labor
	else:
		ops.pending_maintenance += parts_cost + machine.maintenance_labor
	machine.wear = 0.0
	machine.operating_cycles = 0
	return {"ok": true, "message": "Mantenimiento máquina #%d: %d repuestos, mano de obra %.2f." % [machine.id, machine.maintenance_spares, machine.maintenance_labor]}


static func prepare(company, config) -> void:
	## Salarios se devengan incluso sin ventas; si no se pueden pagar, queda obligación y se suspende producción.
	var ops = company.operations
	var warehouse = ops.warehouse
	ops.penalties.clear()
	ops.wage = config.wage_per_employee
	ops.salary_expense = ops.employees * config.wage_per_employee
	ops.materials_consumed = 0.0
	ops.maintenance_expense = ops.pending_maintenance
	ops.other_expense = ops.pending_expenses
	ops.pending_expenses = 0.0
	ops.pending_maintenance = 0.0
	company.wages_payable += ops.salary_expense
	var salary_payment: float = minf(company.cash, company.wages_payable)
	company.finance.category = "Salarios de producción"
	company.cash -= salary_payment
	company.wages_payable -= salary_payment
	if company.wages_payable > 0.000001 or company.cash < company.fixed_cost:
		ops.penalties.append("Producción suspendida: falta caja para salarios o apertura.")
		return
	company.fixed_cost_paid = company.fixed_cost
	company.finance.category = "Costos fijos de producción"
	company.cash -= company.fixed_cost
	company.active_this_cycle = true
	for machine in ops.machines:
		if machine.preventive and machine.operating_cycles >= machine.maintenance_interval:
			var result: Dictionary = maintain(company, machine, true)
			ops.penalties.append(result.message)
	var required: int = 0
	for machine in ops.machines:
		required += machine.staff_required
	var staff_factor: float = 1.0
	if required > 0 and ops.employees < required:
		staff_factor = pow(float(ops.employees) / required, config.understaff_exponent)
		ops.penalties.append("Falta personal: capacidad reducida.")
	elif ops.employees > required:
		staff_factor = maxf(0.0, 1.0 - config.excess_staff_penalty * (ops.employees - required))
		ops.penalties.append("Personal de reserva: se paga toda la nómina.")
	var remaining: int = mini(company.production_target, ops.employees * config.employee_work_capacity)
	for machine in ops.machines:
		var units: int = mini(remaining, int(floor(machine.capacity * machine.efficiency() * staff_factor)))
		if machine.efficiency() < 1.0:
			ops.penalties.append("Máquina #%d: eficiencia %.2f, desgaste %.2f." % [machine.id, machine.efficiency(), machine.wear])
		if machine.inputs_per_unit > 0:
			var material_limit: int = warehouse.inputs / machine.inputs_per_unit
			if material_limit < units:
				units = int(floor(material_limit * config.input_shortage_efficiency))
				ops.penalties.append("Insumos insuficientes: producción limitada.")
		# Consumir insumos libera espacio antes de incorporar terminados; con consumo >=1 no aumenta volumen.
		if machine.inputs_per_unit == 0:
			units = mini(units, warehouse.available(company.inventory))
		if company.variable_unit_cost > 0.0:
			units = mini(units, int(floor(company.cash / company.variable_unit_cost)))
		units = maxi(0, units)
		var inputs_used: int = units * machine.inputs_per_unit
		var input_cost: float = 0.0
		if warehouse.inputs > 0:
			input_cost = warehouse.inputs_value * inputs_used / warehouse.inputs
		warehouse.inputs -= inputs_used
		warehouse.inputs_value = maxf(0.0, warehouse.inputs_value - input_cost)
		var payment: float = units * company.variable_unit_cost
		company.finance.category = "Conversión de productos"
		company.cash = maxf(0.0, company.cash - payment)
		company.production_spending += payment
		ops.materials_consumed += input_cost
		company.inventory += units
		company.inventory_value += input_cost + payment
		company.production += units
		remaining -= units
		if units > 0:
			var prior_wear: float = machine.wear
			machine.wear = minf(1.0, machine.wear + machine.wear_per_cycle)
			machine.operating_cycles += 1
			ops.penalties.append("Operación máquina #%d: %d unidades, desgaste %.2f → %.2f, eficiencia siguiente %.2f." % [machine.id, units, prior_wear, machine.wear, machine.efficiency()])
	if company.production < company.production_target:
		ops.penalties.append("Objetivo no alcanzado: revisar recursos, equipos y espacio.")
