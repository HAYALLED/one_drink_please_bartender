class_name CustomerTable
extends Area2D

signal order_served(customer: Customer, payout: int, tip: int, glass_ok: bool)
signal glass_rejected(glass: Glass)
signal kick_requested(table: CustomerTable, customer: Customer)
signal customer_left(customer: Customer)
signal cleared

@export var near_position := Vector2(320.0, 160.0)
@export var far_scale := 0.45
@export var near_scale := 1.0
@export var min_fill_to_serve := 0.1

var table_id := 0
var customers: Array[Customer] = []
var far_position := Vector2(320.0, 100.0)

var _slots: Array[CustomerSlot] = []
var _cleared_sent := false


func _ready() -> void:
	for child in $Slots.get_children():
		var slot := child as CustomerSlot
		slot.kick_pressed.connect(_on_slot_kick)
		_slots.append(slot)


func setup(id: int, list: Array[Customer], far_pos: Vector2) -> void:
	table_id = id
	customers.assign(list)
	far_position = far_pos
	for i in _slots.size():
		_slots[i].assign(customers[i] if i < customers.size() else null)
	set_approach(0.0)
	set_listening(false)


func set_approach(t: float) -> void:
	var eased := smoothstep(0.0, 1.0, t)
	position = far_position.lerp(near_position, eased)
	scale = Vector2.ONE * lerpf(far_scale, near_scale, eased)


func set_listening(on: bool) -> void:
	set_deferred("monitorable", on)
	for slot in _slots:
		var active := slot.customer != null and slot.customer.state != Customer.State.LEFT
		slot.set_deferred("monitorable", on and active)


func hide_table() -> void:
	visible = false
	set_listening(false)


func refresh_slots() -> void:
	for slot in _slots:
		slot.refresh()


# Returns a customer who loses patience and attacks, or null.
func tick(delta: float) -> Customer:
	var attacker: Customer = null
	for customer in customers:
		match customer.state:
			Customer.State.AGITATED:
				customer.timer -= delta
				if customer.timer <= 0.0 and attacker == null:
					attacker = customer
			Customer.State.OBJECTING:
				customer.timer -= delta
				if customer.timer <= 0.0:
					remove_customer(customer)
					customer_left.emit(customer)
	refresh_slots()
	return attacker


func remove_customer(customer: Customer) -> void:
	customer.state = Customer.State.LEFT
	refresh_slots()
	check_cleared()


func find_agitated() -> Customer:
	for customer in customers:
		if customer.state == Customer.State.AGITATED:
			return customer
	return null


func pending_count() -> int:
	var count := 0
	for customer in customers:
		if customer.state != Customer.State.LEFT and not customer.served:
			count += 1
	return count


func is_resolved() -> bool:
	for customer in customers:
		if customer.state == Customer.State.LEFT:
			continue
		if not customer.served:
			return false
		if customer.state == Customer.State.AGITATED or customer.state == Customer.State.OBJECTING:
			return false
	return true


func check_cleared() -> void:
	if not _cleared_sent and is_resolved():
		_cleared_sent = true
		cleared.emit()


func summary() -> String:
	var parts: PackedStringArray = []
	for customer in customers:
		if customer.state == Customer.State.LEFT:
			parts.append(Loc.t("table_out"))
		elif customer.served:
			parts.append(Loc.t("table_ok") + ("!" if customer.state == Customer.State.AGITATED else ""))
		else:
			var label := DrinkDB.get_drink(customer.drink_id).name_text()
			parts.append(label + ("!" if customer.state == Customer.State.AGITATED else ""))
	return ", ".join(parts)


func accept_glass(glass: Glass) -> bool:
	if glass.drink_id == &"" or glass.contaminated or glass.fill < min_fill_to_serve:
		glass_rejected.emit(glass)
		return false
	var target := _pick_customer(glass)
	if target == null:
		glass_rejected.emit(glass)
		return false
	var result := target.receive(glass)
	var payout: int = result["payout"] + result["tip"]
	GameState.register_sale(payout)
	order_served.emit(target, result["payout"], result["tip"], result["glass_ok"])
	glass.queue_free()
	refresh_slots()
	check_cleared()
	return true


func _pick_customer(glass: Glass) -> Customer:
	var best: Customer = null
	var best_distance := INF
	for slot in _slots:
		var customer := slot.customer
		if customer == null or customer.served or customer.state == Customer.State.LEFT:
			continue
		if customer.drink_id != glass.drink_id:
			continue
		var distance := absf(slot.global_position.x - glass.global_position.x)
		if distance < best_distance:
			best = customer
			best_distance = distance
	return best


func _on_slot_kick(slot: CustomerSlot) -> void:
	if slot.customer != null and slot.customer.state != Customer.State.LEFT:
		kick_requested.emit(self, slot.customer)


func to_dict() -> Dictionary:
	var list: Array = []
	for customer in customers:
		list.append(customer.to_dict())
	return {
		"id": table_id,
		"far": [far_position.x, far_position.y],
		"customers": list,
		"cleared_sent": _cleared_sent,
	}


# Call after add_child. Returns the table ready for set_approach / set_listening.
func restore(data: Dictionary) -> void:
	var list: Array[Customer] = []
	for item in data.get("customers", []):
		list.append(Customer.from_dict(item as Dictionary))
	var far: Array = data.get("far", [320.0, 100.0])
	setup(int(data.get("id", 1)), list, Vector2(float(far[0]), float(far[1])))
	_cleared_sent = bool(data.get("cleared_sent", false))
