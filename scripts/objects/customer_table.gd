class_name CustomerTable
extends Area2D

signal order_served(customer: Customer, payout: int, tip: int, glass_ok: bool)
signal glass_rejected(glass: Glass)
signal kick_requested(table: CustomerTable, customer: Customer)
## An objecting customer gave up and walked out.
signal customer_left(customer: Customer)
## reason: &"straight" (paid and left), &"gave_up" (tired of waiting), &"stormed_out" (angry, nobody to fight).
signal customer_departed(customer: Customer, reason: StringName)
signal customer_agitated(customer: Customer)
signal brawl_started(first: Customer, second: Customer)
## A brawl ran its full time: both fighters are gone and the bar pays for it.
signal brawl_wrecked(first: Customer, second: Customer)
signal cleared

const CHAT_MIN := 5.0
const CHAT_MAX := 9.0
const REPLY_CHANCE := 0.7
const DRUNK_TALK_LEVEL := 0.55
const DRUNK_TALK_CHANCE := 0.6
const INCITE_MIN := 7.0
const INCITE_MAX := 13.0
const INCITE_CHANCE := 0.6
const INCITE_MOOD_HIT := 0.25
const WHISPER_VISIBLE_CHANCE := 0.5
const GRUDGE_PICK_CHANCE := 0.8
const GREET_CHANCE := 0.7
const GREET_STAGGER := 0.35
const PLEAD_CHANCE := 0.6

@export var near_position := Vector2(320.0, 160.0)
@export var far_scale := 0.45
@export var near_scale := 1.0
@export var min_fill_to_serve := 0.1

var table_id := 0
var customers: Array[Customer] = []
var far_position := Vector2(320.0, 100.0)

var _slots: Array[CustomerSlot] = []
var _cleared_sent := false
var _chat_timer := 0.0
var _incite_timer := 0.0
var _speech_queue: Array[Dictionary] = []


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
	_reset_timers()
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


## The player just reached the table: customers greet one after another.
func greet() -> void:
	var delay := 0.0
	for customer in customers:
		if customer.state == Customer.State.LEFT or randf() > GREET_CHANCE:
			continue
		_queue_say(customer, &"greet", delay)
		delay += GREET_STAGGER + randf() * 0.3


# --- per-frame simulation ------------------------------------------------------------

func tick(delta: float) -> void:
	for customer: Customer in customers.duplicate():
		if customer.state != Customer.State.LEFT:
			_tick_customer(customer, delta)
	_tick_incite(delta)
	_tick_chat(delta)
	_tick_queue(delta)
	refresh_slots()


func _tick_customer(customer: Customer, delta: float) -> void:
	match customer.state:
		Customer.State.CALM:
			_tick_calm(customer, delta)
		Customer.State.AGITATED:
			customer.timer -= delta
			if customer.timer <= 0.0:
				_start_brawl(customer)
		Customer.State.OBJECTING:
			customer.timer -= delta
			if customer.timer <= 0.0:
				remove_customer(customer)
				customer_left.emit(customer)
		Customer.State.BRAWLING:
			customer.brawl_left -= delta
			if customer.brawl_left <= 0.0:
				_wreck_brawl(customer)


func _tick_calm(customer: Customer, delta: float) -> void:
	if customer.leave_in >= 0.0:
		customer.leave_in -= delta
		if customer.leave_in <= 0.0:
			remove_customer(customer)
			customer_departed.emit(customer, &"straight")
		return
	if not customer.served:
		customer.waited += delta
		if not customer.late_warned and customer.waited >= customer.patience() * Customer.LATE_WARN_FRACTION:
			customer.late_warned = true
			_say(customer, &"late")
		if customer.waited >= customer.patience():
			_lose_patience(customer)
			return
	if customer.flares(delta):
		_on_agitated(customer)


func _lose_patience(customer: Customer) -> void:
	if customer.can_fight():
		customer.agitate()
		_on_agitated(customer)
	else:
		remove_customer(customer)
		customer_departed.emit(customer, &"gave_up")


func _on_agitated(customer: Customer) -> void:
	_say(customer, &"threat")
	customer_agitated.emit(customer)


## Call after something changed a customer's state from outside (served, provoked).
func _watch(customer: Customer, before: Customer.State) -> void:
	if before != Customer.State.AGITATED and customer.state == Customer.State.AGITATED:
		_on_agitated(customer)


# --- brawls ---------------------------------------------------------------------------

func _is_valid_target(candidate: Customer, attacker: Customer) -> bool:
	return (
		candidate != attacker
		and candidate.state != Customer.State.LEFT
		and candidate.state != Customer.State.BRAWLING
		and candidate.can_be_target()
	)


func _pick_brawl_target(attacker: Customer) -> Customer:
	var grudge := attacker.grudge
	if grudge != null and _is_valid_target(grudge, attacker) and randf() < GRUDGE_PICK_CHANCE:
		return grudge
	var options: Array[Customer] = []
	for candidate in customers:
		if _is_valid_target(candidate, attacker):
			options.append(candidate)
	if options.is_empty():
		return null
	return options.pick_random()


func _start_brawl(attacker: Customer) -> void:
	var target := _pick_brawl_target(attacker)
	if target == null:
		remove_customer(attacker)
		customer_departed.emit(attacker, &"stormed_out")
		return
	_begin_brawl(attacker, target)
	_say(attacker, &"brawl")
	_say(target, &"brawl")
	for other in customers:
		if other != attacker and other != target and other.state != Customer.State.LEFT and other.trait_id == CustomerTrait.Id.INNOCENT:
			if randf() < PLEAD_CHANCE:
				_queue_say(other, &"plead", randf_range(0.3, 0.9))
	brawl_started.emit(attacker, target)


func _begin_brawl(attacker: Customer, target: Customer) -> void:
	attacker.begin_brawl(target, true)
	target.begin_brawl(attacker, false)


func _wreck_brawl(customer: Customer) -> void:
	var other := customer.brawl_target
	customer.end_brawl()
	remove_customer(customer)
	if other != null and other.state == Customer.State.BRAWLING:
		other.end_brawl()
		remove_customer(other)
	brawl_wrecked.emit(customer, other)


## The player kicked one of the fighters: both are thrown out and the brawl is over.
func break_up(customer: Customer) -> void:
	var other := customer.brawl_target
	customer.end_brawl()
	remove_customer(customer)
	if other != null and other.state == Customer.State.BRAWLING:
		other.end_brawl()
		remove_customer(other)


## The player walks away from the table: every angry customer fights right now, every running brawl is wrecked.
func settle_trouble() -> void:
	for customer: Customer in customers.duplicate():
		if customer.state != Customer.State.AGITATED:
			continue
		var target := _pick_brawl_target(customer)
		if target == null:
			remove_customer(customer)
			customer_departed.emit(customer, &"stormed_out")
		else:
			_begin_brawl(customer, target)
	for customer: Customer in customers.duplicate():
		if customer.state == Customer.State.BRAWLING:
			_wreck_brawl(customer)


# --- greedy customers: gossip that sets others against each other ------------------

func _tick_incite(delta: float) -> void:
	_incite_timer -= delta
	if _incite_timer > 0.0:
		return
	_incite_timer = randf_range(INCITE_MIN, INCITE_MAX)
	if randf() > INCITE_CHANCE:
		return
	var inciters: Array[Customer] = []
	var victims: Array[Customer] = []
	for customer in customers:
		if customer.state != Customer.State.CALM:
			continue
		if customer.incites():
			inciters.append(customer)
		elif customer.can_fight():
			victims.append(customer)
	if inciters.is_empty() or victims.is_empty():
		return
	var inciter: Customer = inciters.pick_random()
	var victim: Customer = victims.pick_random()
	var rivals: Array[Customer] = []
	for customer in customers:
		if customer != victim and customer != inciter and _is_valid_target(customer, victim):
			rivals.append(customer)
	if rivals.is_empty():
		return
	var before := victim.state
	victim.provoke(INCITE_MOOD_HIT, rivals.pick_random())
	if randf() < WHISPER_VISIBLE_CHANCE:
		_say(inciter, &"whisper")
	_queue_say(victim, &"provoked", 1.1)
	_watch(victim, before)


# --- small talk -----------------------------------------------------------------------

func _tick_chat(delta: float) -> void:
	_chat_timer -= delta
	if _chat_timer > 0.0:
		return
	_chat_timer = randf_range(CHAT_MIN, CHAT_MAX)
	var talkers: Array[Customer] = []
	for customer in customers:
		if customer.state == Customer.State.CALM and customer.can_chat() and customer.leave_in < 0.0:
			talkers.append(customer)
	if talkers.is_empty():
		return
	var speaker: Customer = talkers.pick_random()
	if speaker.drunk > DRUNK_TALK_LEVEL and randf() < DRUNK_TALK_CHANCE:
		_say(speaker, &"drunk")
		return
	_say(speaker, &"smalltalk")
	var listeners: Array[Customer] = []
	for customer in talkers:
		if customer != speaker:
			listeners.append(customer)
	if not listeners.is_empty() and randf() < REPLY_CHANCE:
		_queue_say(listeners.pick_random(), &"reply", randf_range(1.0, 1.8))


func _tick_queue(delta: float) -> void:
	for i in range(_speech_queue.size() - 1, -1, -1):
		var item := _speech_queue[i]
		item["left"] = float(item["left"]) - delta
		if float(item["left"]) <= 0.0:
			_speech_queue.remove_at(i)
			_say(item["customer"] as Customer, item["category"] as StringName)


func _queue_say(customer: Customer, category: StringName, delay: float) -> void:
	_speech_queue.append({"customer": customer, "category": category, "left": delay})


func _say(customer: Customer, category: StringName) -> void:
	if customer.state == Customer.State.LEFT:
		return
	var slot := _slot_of(customer)
	if slot != null:
		slot.say(NpcDialogue.line(category, customer.trait_key()))


func _slot_of(customer: Customer) -> CustomerSlot:
	for slot in _slots:
		if slot.customer == customer:
			return slot
	return null


func _reset_timers() -> void:
	_chat_timer = randf_range(3.0, CHAT_MIN)
	_incite_timer = randf_range(INCITE_MIN, INCITE_MAX)
	_speech_queue.clear()


# --- state queries --------------------------------------------------------------------

func remove_customer(customer: Customer) -> void:
	customer.end_brawl()
	customer.state = Customer.State.LEFT
	refresh_slots()
	check_cleared()


## First customer who is angry or already fighting, or null.
func find_trouble() -> Customer:
	for customer in customers:
		if customer.state == Customer.State.AGITATED or customer.state == Customer.State.BRAWLING:
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
		if not customer.served or customer.state != Customer.State.CALM:
			return false
	return true


func check_cleared() -> void:
	if not _cleared_sent and is_resolved():
		_cleared_sent = true
		cleared.emit()


func summary() -> String:
	var parts: PackedStringArray = []
	for customer in customers:
		var flag := ""
		match customer.state:
			Customer.State.AGITATED:
				flag = "!"
			Customer.State.BRAWLING:
				flag = "X"
		if customer.state == Customer.State.LEFT:
			parts.append(Loc.t("table_out"))
		elif customer.served:
			parts.append(Loc.t("table_ok") + flag)
		else:
			parts.append(DrinkDB.get_drink(customer.drink_id).name_text() + flag)
	return ", ".join(parts)


func accept_glass(glass: Glass) -> bool:
	if glass.drink_id == &"" or glass.contaminated or glass.fill < min_fill_to_serve:
		glass_rejected.emit(glass)
		return false
	var target := _pick_customer(glass)
	if target == null:
		glass_rejected.emit(glass)
		return false
	var before := target.state
	var result := target.receive(glass)
	var payout: int = result["payout"] + result["tip"]
	GameState.register_sale(payout)
	order_served.emit(target, result["payout"], result["tip"], result["glass_ok"])
	_say(target, &"thanks" if result["glass_ok"] else &"wrong")
	if result["stays"]:
		_queue_say(target, &"stay", 1.6)
	_watch(target, before)
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


## Called by the game when a kicked customer objects.
func say_objection(customer: Customer) -> void:
	_say(customer, &"objects")


func to_dict() -> Dictionary:
	var list: Array = []
	for customer in customers:
		var item := customer.to_dict()
		item["brawl_with"] = customers.find(customer.brawl_target) if customer.brawl_target != null else -1
		list.append(item)
	return {
		"id": table_id,
		"far": [far_position.x, far_position.y],
		"customers": list,
		"cleared_sent": _cleared_sent,
	}


# Call after add_child. Returns the table ready for set_approach / set_listening.
func restore(data: Dictionary) -> void:
	var list: Array[Customer] = []
	var items: Array = data.get("customers", [])
	for item in items:
		list.append(Customer.from_dict(item as Dictionary))
	for i in list.size():
		var link := int((items[i] as Dictionary).get("brawl_with", -1))
		if link >= 0 and link < list.size() and link != i:
			list[i].brawl_target = list[link]
	for customer in list:
		if customer.state == Customer.State.BRAWLING and (customer.brawl_target == null or customer.brawl_target.state != Customer.State.BRAWLING):
			customer.end_brawl()
			customer.state = Customer.State.AGITATED
			customer.timer = 3.0
	var far: Array = data.get("far", [320.0, 100.0])
	setup(int(data.get("id", 1)), list, Vector2(float(far[0]), float(far[1])))
	_cleared_sent = bool(data.get("cleared_sent", false))