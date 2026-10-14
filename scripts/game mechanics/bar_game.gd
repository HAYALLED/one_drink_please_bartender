class_name BarGame
extends Node2D

enum Phase { IDLE, OPENING, PREP, SERVE, FIGHT, DAY_END, COLLECTOR, VISIT }

const TABLE_SCENE := preload("res://scenes/objects/customer_table.tscn")
const COLLECTOR_PLACE_SCENE: PackedScene = preload("res://scenes/places/debt_collector_place.tscn")
const MENU_SCENE := "res://scenes/menus/main_menu.tscn"
const WALK_SPEED := 0.2
const TABLE_CLEAR_DELAY := 0.7
const EMPTY_TRAY_DELAY := 1.5
const MAX_CUSTOMERS_PER_TABLE := 4
const CONTINUE_INTERVAL := 120.0
const HAND_HOME := Vector2(320.0, 120.0)
const HAND_TABLE_START := Vector2(320.0, 250.0)
const GLASS_SPAWN_START_X := 150.0
const GLASS_SPAWN_GAP := 4.0
const GLASS_SPAWN_MAX_X := 620.0

var phase := Phase.IDLE

var _round := 0
var _tables: Array[CustomerTable] = []
var _table_index := 0
var _approach := 0.0
var _walking := false
var _leaving := false
var _empty_timer := 0.0
var _month_over := false
var _last_summary: Dictionary = {}
var _phase_before_fight := Phase.SERVE
var _continue_timer := 0.0
var _carry: Array[Dictionary] = []
var _collector_place: DebtCollectorPlace

@onready var bar_layer: Node2D = $BarLayer
@onready var serve_layer: Node2D = $ServeLayer
@onready var tables_root: Node2D = $ServeLayer/Tables
@onready var counter_shape: CollisionShape2D = $BarLayer/Counter/CollisionShape2D
@onready var stations_root: Node2D = $BarLayer/Stations
@onready var glasses_root: Node2D = $Glasses
@onready var tray: Tray = $Tray
@onready var hand: Hand = $Hand
@onready var hud: Hud = $HUD
@onready var fight: FightMinigame = $Fight


func _ready() -> void:
	_collector_place = COLLECTOR_PLACE_SCENE.instantiate() as DebtCollectorPlace
	_collector_place.visible = false
	add_child(_collector_place)
	for child in bar_layer.get_children():
		var rack := child as GlassRack
		if rack != null:
			rack.requested.connect(_on_rack_requested)
	hud.serve_pressed.connect(_on_serve_pressed)
	hud.day_continue_pressed.connect(_on_day_continue)
	hud.debt_confirmed.connect(_on_debt_confirmed)
	hud.save_requested.connect(_on_save_requested)
	hud.open_requested.connect(_on_open_requested)
	hud.collector_requested.connect(_on_collector_requested)
	hud.collector_left.connect(_on_collector_left)
	hud.collector_event.connect(_on_collector_event)
	_apply_pending()


func _process(delta: float) -> void:
	GameState.play_time += delta
	_continue_timer += delta
	if _continue_timer >= CONTINUE_INTERVAL and _can_continue_save():
		_continue_timer = 0.0
		SaveManager.write_continue(capture_state())


func _physics_process(delta: float) -> void:
	if phase != Phase.SERVE or _tables.is_empty() or _leaving:
		return
	var table := _tables[_table_index]
	if _walking:
		var pressing := Input.is_action_pressed(&"walk_forward")
		tray.walk_factor = move_toward(tray.walk_factor, 1.0 if pressing else 0.0, 4.0 * delta)
		if pressing:
			_approach = minf(_approach + WALK_SPEED * delta, 1.0)
			table.set_approach(_approach)
			if _approach >= 1.0:
				_arrive(table)
	else:
		tray.walk_factor = move_toward(tray.walk_factor, 0.0, 4.0 * delta)
		table.tick(delta)
		if Input.is_action_just_pressed(&"leave_table"):
			_leave_table()
			return
		_check_empty_tray(delta, table)


func can_pause() -> bool:
	return phase != Phase.FIGHT


# --- save / load ---------------------------------------------------------------

func _apply_pending() -> void:
	var pending := SaveManager.consume_pending()
	if pending.get("mode", "new") == "load":
		var state := SaveManager.load_state(SaveManager.current_slot, String(pending.get("kind", "manual")))
		if not state.is_empty():
			GameState.from_dict(state.get("game", {}))
			_restore_bar(state.get("bar", {}))
			# Saves from before glasses ended the day can hold a round without any glass.
			if (phase == Phase.PREP or phase == Phase.SERVE) and not GameState.has_glasses():
				_end_day_out_of_glasses()
			return
	GameState.reset()
	_show_opening()


# Fights run in their own paused minigame and cannot be captured. The timer keeps running, so the save
# happens on the first frame after the fight.
func _can_continue_save() -> bool:
	match phase:
		Phase.OPENING, Phase.PREP, Phase.DAY_END, Phase.COLLECTOR, Phase.VISIT:
			return true
		Phase.SERVE:
			return not _leaving
	return false


func capture_state() -> Dictionary:
	return {"game": GameState.to_dict(), "bar": _capture_bar()}


func _capture_bar() -> Dictionary:
	match phase:
		Phase.PREP, Phase.SERVE:
			var table_list: Array = []
			for table in _tables:
				table_list.append(table.to_dict())
			var glass_list: Array = []
			for glass in _live_glasses():
				glass_list.append(glass.to_dict())
			return {
				"phase": "prep" if phase == Phase.PREP else "serve",
				"round": _round,
				"table_index": _table_index,
				"approach": _approach,
				"walking": _walking,
				"tables": table_list,
				"glasses": glass_list,
				"tray": {"angle": tray.angle, "velocity": tray.angular_velocity},
				"hand": [hand.global_position.x, hand.global_position.y],
			}
		Phase.DAY_END:
			return {"phase": "day_end", "summary": _last_summary, "month_over": _month_over}
		Phase.COLLECTOR:
			return {"phase": "collector"}
	return {"phase": "opening"}


func _restore_bar(bar: Dictionary) -> void:
	match String(bar.get("phase", "opening")):
		"prep", "serve":
			_restore_runtime(bar)
		"day_end":
			_last_summary = bar.get("summary", {})
			_month_over = bool(bar.get("month_over", false))
			# Day-end data from before the coin / monthly debt update cannot be shown any more.
			if _last_summary.is_empty() or not _last_summary.has("month_over"):
				_show_opening()
				return
			phase = Phase.DAY_END
			_set_bar_active(false)
			hud.show_day_end(_last_summary)
		"collector":
			if not GameState.is_month_end():
				_show_opening()
				return
			_month_over = true
			phase = Phase.COLLECTOR
			_enter_collector_place(true)
			hud.show_collector()
		_:
			_show_opening()


func _restore_runtime(bar: Dictionary) -> void:
	_round = int(bar.get("round", 1))
	for table in _tables:
		table.queue_free()
	_tables.clear()
	for item in bar.get("tables", []):
		var table := TABLE_SCENE.instantiate() as CustomerTable
		tables_root.add_child(table)
		table.restore(item as Dictionary)
		_connect_table(table)
		_tables.append(table)
	var tray_data: Dictionary = bar.get("tray", {})
	tray.angle = float(tray_data.get("angle", 0.0))
	tray.angular_velocity = float(tray_data.get("velocity", 0.0))
	tray.rotation = tray.angle
	for item in bar.get("glasses", []):
		var glass: Glass = _glass_from_save(item as Dictionary)
		if glass == null:
			continue
		glass.apply_dict(item as Dictionary)
		glasses_root.add_child(glass)
		glass.shattered.connect(_on_glass_shattered)
	var hand_data: Array = bar.get("hand", [HAND_HOME.x, HAND_HOME.y])
	var hand_pos := Vector2(float(hand_data[0]), float(hand_data[1]))
	if String(bar.get("phase")) == "prep" or _tables.is_empty():
		phase = Phase.PREP
		_setup_prep(hand_pos)
		return
	phase = Phase.SERVE
	_set_bar_active(false)
	serve_layer.visible = true
	tray.balance_enabled = true
	hud.set_serve_button_visible(false)
	hud.set_prompt(Loc.t("prompt_serve"))
	_table_index = clampi(int(bar.get("table_index", 0)), 0, _tables.size() - 1)
	_walking = bool(bar.get("walking", true))
	_approach = float(bar.get("approach", 0.0))
	_leaving = false
	_empty_timer = 0.0
	for i in _tables.size():
		if i < _table_index:
			_tables[i].hide_table()
	var current := _tables[_table_index]
	current.visible = true
	current.set_approach(1.0 if not _walking else _approach)
	if _walking:
		hand.set_enabled(false)
	else:
		current.set_listening(true)
		hand.set_enabled(true, hand_pos)
	hud.show_orders(_orders_text())


# A saved glass remembers its own scene. Saves from before that fall back to the rack of the same glass type.
func _glass_from_save(data: Dictionary) -> Glass:
	var path := String(data.get("scene", ""))
	if path.begins_with("res://scenes/") and ResourceLoader.exists(path, "PackedScene"):
		var scene := load(path) as PackedScene
		if scene != null:
			var instance: Glass = scene.instantiate() as Glass
			if instance != null:
				return instance
	var type := StringName(data.get("type", "glass"))
	for child in bar_layer.get_children():
		var rack := child as GlassRack
		if rack != null and rack.glass_type == type:
			return rack.create_glass()
	return null


func _on_save_requested() -> void:
	if phase != Phase.OPENING:
		return
	if SaveManager.write_manual(capture_state()):
		hud.set_opening_feedback(Loc.t("opening_saved", {"slot": SaveManager.current_slot}))
	else:
		hud.set_opening_feedback(Loc.t("opening_save_failed"))


# --- day / round flow ---------------------------------------------------------

func _show_opening() -> void:
	phase = Phase.OPENING
	hand.set_enabled(false)
	_set_bar_active(false)
	_collector_place.close()
	bar_layer.visible = true
	serve_layer.visible = false
	hud.show_orders("")
	hud.set_prompt("")
	hud.show_opening(SaveManager.current_slot)


func _on_open_requested() -> void:
	if phase != Phase.OPENING:
		return
	if not GameState.has_glasses():
		hud.toast(Loc.t("toast_need_glass"))
		return
	# Day start = autosave. The opening screen has no runtime state, so loading it lands on this same screen.
	SaveManager.write_auto(capture_state())
	hud.hide_opening()
	_begin_day()


func _begin_day() -> void:
	GameState.start_day()
	_round = 0
	_begin_round()


func _begin_round() -> void:
	if not GameState.has_glasses():
		_carry.clear()
		_finish_day(true)
		return
	_round += 1
	_generate_orders()
	phase = Phase.PREP
	_setup_prep(HAND_HOME)
	hud.toast(Loc.t("toast_round", {"round": _round, "rounds": GameState.ROUNDS_PER_DAY}))


func _setup_prep(hand_pos: Vector2) -> void:
	serve_layer.visible = false
	_set_bar_active(true)
	tray.balance_enabled = false
	hand.set_enabled(true, hand_pos)
	hud.set_serve_button_visible(true)
	hud.show_orders(_orders_text())
	hud.set_prompt(Loc.t("prompt_prep"))


func _on_serve_pressed() -> void:
	if phase != Phase.PREP:
		return
	if tray.glass_count() == 0:
		if GameState.has_glasses():
			hud.toast(Loc.t("toast_put_glass"))
		else:
			_end_day_out_of_glasses()
		return
	_enter_serve()


func _enter_serve() -> void:
	hud.set_serve_button_visible(false)
	hand.set_enabled(false)
	var keep := tray.get_glasses()
	for glass in _live_glasses():
		if not keep.has(glass):
			glass.queue_free()
	phase = Phase.SERVE
	_set_bar_active(false)
	serve_layer.visible = true
	tray.balance_enabled = true
	hud.set_prompt(Loc.t("prompt_serve"))
	_table_index = 0
	_start_table_walk()


func _start_table_walk() -> void:
	var table := _tables[_table_index]
	_approach = 0.0
	_walking = true
	_empty_timer = 0.0
	hand.set_enabled(false)
	table.visible = true
	table.set_approach(0.0)
	hud.show_orders(_orders_text())


func _arrive(table: CustomerTable) -> void:
	_walking = false
	_empty_timer = 0.0
	table.set_listening(true)
	table.greet()
	hand.set_enabled(true, HAND_TABLE_START)


func _check_empty_tray(delta: float, table: CustomerTable) -> void:
	var out_of_glasses := tray.glass_count() == 0 and hand.held == null
	var in_trouble := table.find_trouble() != null
	if out_of_glasses and not in_trouble:
		_empty_timer += delta
		if _empty_timer >= EMPTY_TRAY_DELAY:
			_leave_table()
	else:
		_empty_timer = 0.0


func _leave_table() -> void:
	if _leaving or phase != Phase.SERVE:
		return
	_leaving = true
	var table := _tables[_table_index]
	table.settle_trouble()
	var missed := table.pending_count()
	if missed > 0:
		hud.toast(Loc.t("toast_missed", {"table": table.table_id, "count": missed}))
	hand.set_enabled(false)
	table.hide_table()
	_table_index += 1
	_leaving = false
	if _table_index >= _tables.size():
		_end_round()
	else:
		_start_table_walk()


func _end_round() -> void:
	_collect_stayers()
	tray.balance_enabled = false
	tray.walk_factor = 0.0
	_clear_glasses()
	serve_layer.visible = false
	if _round < GameState.ROUNDS_PER_DAY:
		_begin_round()
	else:
		_finish_day()


func _finish_day(no_glasses := false) -> void:
	phase = Phase.DAY_END
	hand.set_enabled(false)
	_set_bar_active(false)
	_last_summary = GameState.end_day()
	_last_summary["no_glasses"] = no_glasses
	_month_over = _last_summary["month_over"]
	hud.show_orders("")
	hud.set_prompt("")
	hud.show_day_end(_last_summary)


func _on_day_continue() -> void:
	if not _month_over:
		_show_opening()
		return
	phase = Phase.COLLECTOR
	if GameState.month_debt <= 0:
		_on_debt_confirmed(0)
	else:
		_enter_collector_place(true)
		hud.show_collector()


func _on_debt_confirmed(amount: int) -> void:
	var info := GameState.finish_month(amount)
	hud.toast(
		Loc.t("toast_month_closed", {
			"paid": Loc.coins(int(info["paid"])),
			"debt": Loc.coins(int(info["new_debt"])),
			"carried": Loc.coins(int(info["carried"])),
		}),
		4.0
	)
	_show_opening()


# --- debt collector place -----------------------------------------------------------

## Hides the bar and shows the collector's office. forced = month end collection.
func _enter_collector_place(forced: bool) -> void:
	hand.set_enabled(false)
	_set_bar_active(false)
	serve_layer.visible = false
	hud.show_orders("")
	hud.set_prompt("")
	_collector_place.open(forced)


func _on_collector_requested() -> void:
	if phase != Phase.OPENING:
		return
	phase = Phase.VISIT
	_enter_collector_place(false)


func _on_collector_left() -> void:
	if phase != Phase.VISIT:
		return
	_show_opening()


func _on_collector_event(kind: StringName) -> void:
	_collector_place.react(kind)


# --- customers / fights -----------------------------------------------------------

func _collect_stayers() -> void:
	_carry.clear()
	if _round >= GameState.ROUNDS_PER_DAY:
		return
	for i in _tables.size():
		for customer in _tables[i].customers:
			if customer.wants_to_stay():
				_carry.append({"table": i, "customer": customer})


func _generate_orders() -> void:
	for table in _tables:
		table.queue_free()
	_tables.clear()
	var unlocked := GameState.unlocked_drink_ids()
	var slots := GameState.tray_slots()
	var stayers := _carry.duplicate()
	_carry.clear()
	while stayers.size() > slots:
		stayers.pop_back()
	var total := maxi(1, roundi(randi_range(GameState.table_count(), slots) * GameState.flow_factor()))
	total = maxi(total, stayers.size())
	var table_n := mini(GameState.table_count(), total)
	var lists: Array = []
	for i in table_n:
		lists.append([])
	var placed := 0
	for item: Dictionary in stayers:
		var index := mini(int(item["table"]), table_n - 1)
		if (lists[index] as Array).size() >= MAX_CUSTOMERS_PER_TABLE:
			index = _list_with_room(lists)
		if index < 0:
			continue
		var customer: Customer = item["customer"]
		customer.begin_next_round(unlocked.pick_random())
		(lists[index] as Array).append(customer)
		placed += 1
	_spread_stayers(lists, maxi(total - placed, 0))
	var new_count := maxi(total - placed, 0)
	for list: Array in lists:
		if list.is_empty():
			list.append(Customer.create(unlocked.pick_random(), _round))
			new_count = maxi(new_count - 1, 0)
	var attempts := 0
	while new_count > 0 and attempts < 200:
		attempts += 1
		var list: Array = lists[randi() % table_n]
		if list.size() < MAX_CUSTOMERS_PER_TABLE:
			list.append(Customer.create(unlocked.pick_random(), _round))
			new_count -= 1
	for i in table_n:
		var typed: Array[Customer] = []
		typed.assign(lists[i])
		var fraction := 0.5 if table_n == 1 else float(i) / float(table_n - 1)
		var table := TABLE_SCENE.instantiate() as CustomerTable
		tables_root.add_child(table)
		table.setup(i + 1, typed, Vector2(lerpf(130.0, 510.0, fraction), 100.0))
		_connect_table(table)
		_tables.append(table)


func _list_with_room(lists: Array) -> int:
	var best := -1
	for i in lists.size():
		var size := (lists[i] as Array).size()
		if size < MAX_CUSTOMERS_PER_TABLE and (best < 0 or size < (lists[best] as Array).size()):
			best = i
	return best


# Stayers sit at their old table. If that leaves more empty tables than new customers to fill them,
# some stayers move so every table still gets someone.
func _spread_stayers(lists: Array, new_count: int) -> void:
	for _guard in 8:
		var empty_index := -1
		var empty_count := 0
		var fullest := 0
		for i in lists.size():
			var size := (lists[i] as Array).size()
			if size == 0:
				empty_count += 1
				if empty_index < 0:
					empty_index = i
			if size > (lists[fullest] as Array).size():
				fullest = i
		if empty_count == 0 or new_count >= empty_count or (lists[fullest] as Array).size() < 2:
			return
		(lists[empty_index] as Array).append((lists[fullest] as Array).pop_back())


func _connect_table(table: CustomerTable) -> void:
	table.order_served.connect(_on_order_served)
	table.glass_rejected.connect(_on_glass_rejected)
	table.kick_requested.connect(_on_kick_requested)
	table.customer_left.connect(_on_customer_left)
	table.customer_departed.connect(_on_customer_departed)
	table.customer_agitated.connect(_on_customer_agitated)
	table.brawl_started.connect(_on_brawl_started)
	table.brawl_wrecked.connect(_on_brawl_wrecked)
	table.cleared.connect(_on_table_cleared)


func _orders_text() -> String:
	var lines: PackedStringArray = []
	for table in _tables:
		lines.append(Loc.t("table_line", {"id": table.table_id, "list": table.summary()}))
	return "\n".join(lines)


func _on_order_served(_customer: Customer, payout: int, tip: int, glass_ok: bool) -> void:
	var text := Loc.t("toast_served", {"payout": Loc.coins(payout)})
	if tip > 0:
		text = Loc.t("toast_served_tip", {"payout": Loc.coins(payout), "tip": Loc.coins(tip)})
	if not glass_ok:
		text += "  " + Loc.t("toast_wrong_glass")
	hud.toast(text, 1.6)
	hud.show_orders(_orders_text())


func _on_glass_rejected(_glass: Glass) -> void:
	hud.toast(Loc.t("toast_bad_drink"))


func _on_customer_left(_customer: Customer) -> void:
	hud.toast(Loc.t("toast_grumbles"))
	hud.show_orders(_orders_text())


func _on_customer_departed(_customer: Customer, reason: StringName) -> void:
	match reason:
		&"gave_up":
			hud.toast(Loc.t("toast_gave_up"), 2.5)
		&"stormed_out":
			hud.toast(Loc.t("toast_stormed_out"), 2.5)
	hud.show_orders(_orders_text())


func _on_customer_agitated(_customer: Customer) -> void:
	hud.toast(Loc.t("toast_agitated"), 2.0)
	hud.show_orders(_orders_text())


func _on_brawl_started(_first: Customer, _second: Customer) -> void:
	hud.toast(Loc.t("toast_brawl"), 3.0)
	hud.show_orders(_orders_text())


func _on_brawl_wrecked(_first: Customer, _second: Customer) -> void:
	var cost := GameState.brawl_wrecked()
	hud.toast(Loc.t("toast_brawl_wrecked", {"cost": Loc.coins(cost)}), 4.0)
	hud.show_orders(_orders_text())


func _on_kick_requested(table: CustomerTable, customer: Customer) -> void:
	if phase != Phase.SERVE or _leaving:
		return
	if customer.state == Customer.State.BRAWLING:
		table.break_up(customer)
		GameState.brawl_stopped()
		hud.toast(Loc.t("toast_brawl_stopped"), 2.5)
		hud.show_orders(_orders_text())
		return
	var provoked := customer.is_troublemaker()
	var objecting := customer.state == Customer.State.OBJECTING
	var outcome := customer.react_to_kick()
	if outcome == &"left":
		table.remove_customer(customer)
		if provoked:
			GameState.good_kick()
			hud.toast(Loc.t("toast_kick_quiet"))
		else:
			GameState.wrongful_kick()
			hud.toast(Loc.t("toast_kick_innocent"))
	elif outcome == &"objects":
		table.say_objection(customer)
		table.refresh_slots()
		hud.toast(Loc.t("toast_kick_objects"), 3.0)
	elif outcome == &"attacks":
		if not provoked and not objecting:
			GameState.wrongful_kick()
		hud.toast(Loc.t("toast_swing"))
		_run_fight(table, customer)
	else:
		hud.toast(Loc.t("toast_you_attack"))
		_run_fight(table, customer)
	hud.show_orders(_orders_text())


func _run_fight(table: CustomerTable, customer: Customer) -> void:
	_phase_before_fight = phase
	phase = Phase.FIGHT
	var won: bool = await fight.start(customer.fight_strength())
	phase = _phase_before_fight
	if won:
		GameState.fight_won()
		table.remove_customer(customer)
		hud.toast(Loc.t("toast_fight_won"), 3.0)
	else:
		GameState.fight_lost()
		customer.pacify()
		table.refresh_slots()
		table.check_cleared()
		hud.toast(Loc.t("toast_fight_lost"), 4.0)
	hud.show_orders(_orders_text())


func _on_table_cleared() -> void:
	await get_tree().create_timer(TABLE_CLEAR_DELAY).timeout
	if phase != Phase.SERVE or _walking or _tables.is_empty():
		return
	if _tables[_table_index].is_resolved():
		_leave_table()


# --- glasses / bar --------------------------------------------------------------

func _on_rack_requested(rack: GlassRack) -> void:
	if phase != Phase.PREP:
		return
	var type := rack.glass_type
	if _live_count(type) >= GameState.glass_count(type):
		hud.toast(Loc.t("toast_no_glass", {"name": Loc.t("glass_%s" % type)}))
		return
	if _live_glasses().size() >= GameState.tray_slots():
		hud.toast(Loc.t("toast_tray_full"))
		return
	var glass: Glass = rack.create_glass()
	if glass == null:
		return
	glasses_root.add_child(glass)
	glass.global_position = _free_spawn_position(rack)
	glass.shattered.connect(_on_glass_shattered)


func _free_spawn_position(rack: GlassRack) -> Vector2:
	var half := GlassStyle.for_type(rack.glass_type).body_size * 0.5
	var counter_top := counter_shape.global_position.y - (counter_shape.shape as RectangleShape2D).size.y * 0.5
	var y := counter_top - half.y - 1.0
	var live := _live_glasses()
	var x := GLASS_SPAWN_START_X + half.x
	for _attempt in 16:
		var moved := false
		for glass in live:
			if absf(glass.global_position.y - y) > 60.0:
				continue
			var other_half := glass.style.body_size.x * 0.5
			if absf(glass.global_position.x - x) < half.x + other_half + GLASS_SPAWN_GAP:
				x = glass.global_position.x + other_half + GLASS_SPAWN_GAP + half.x
				moved = true
		if not moved:
			break
	if x + half.x > GLASS_SPAWN_MAX_X:
		x = GLASS_SPAWN_START_X + half.x
	return Vector2(x, y)


func _on_glass_shattered(glass: Glass) -> void:
	GameState.break_glass(glass.glass_type)
	hud.toast(Loc.t("toast_glass_broke", {
		"name": Loc.t("glass_%s" % glass.glass_type),
		"left": GameState.glass_count(glass.glass_type),
	}), 3.0)
	if not GameState.has_glasses():
		_end_day_out_of_glasses.call_deferred()


## Every glass is gone for good: nothing left to serve with, so the day ends right here.
func _end_day_out_of_glasses() -> void:
	if phase != Phase.PREP and phase != Phase.SERVE:
		return
	if phase == Phase.SERVE and _table_index < _tables.size():
		_tables[_table_index].settle_trouble()
	_carry.clear()
	_leaving = false
	tray.balance_enabled = false
	tray.walk_factor = 0.0
	_clear_glasses()
	serve_layer.visible = false
	_finish_day(true)


func _live_glasses() -> Array[Glass]:
	var result: Array[Glass] = []
	for node in get_tree().get_nodes_in_group(&"glasses"):
		var glass := node as Glass
		if glass != null and not glass.is_queued_for_deletion():
			result.append(glass)
	return result


func _live_count(type: StringName) -> int:
	var count := 0
	for glass in _live_glasses():
		if glass.glass_type == type:
			count += 1
	return count


func _clear_glasses() -> void:
	hand.force_release()
	for glass in _live_glasses():
		glass.queue_free()


func _set_bar_active(active: bool) -> void:
	bar_layer.visible = active
	counter_shape.set_deferred("disabled", not active)
	for node in get_tree().get_nodes_in_group(&"interactable"):
		(node as Area2D).set_deferred("monitorable", active)
	for child in stations_root.get_children():
		var station := child as PourStation
		station.set_available(active and GameState.is_drink_unlocked(station.drink_id))
	for child in bar_layer.get_children():
		var rack := child as GlassRack
		if rack != null:
			rack.set_available(active and GameState.glass_available(rack.glass_type))