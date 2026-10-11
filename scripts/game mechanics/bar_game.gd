class_name BarGame
extends Node2D

enum Phase { IDLE, OPENING, PREP, SERVE, FIGHT, DAY_END, COLLECTOR }

const GLASS_SCENE := preload("res://scenes/objects/glass.tscn")
const TABLE_SCENE := preload("res://scenes/objects/customer_table.tscn")
const MENU_SCENE := "res://scenes/menus/main_menu.tscn"
const WALK_SPEED := 0.2
const TABLE_CLEAR_DELAY := 0.7
const EMPTY_TRAY_DELAY := 1.5
const MAX_CUSTOMERS_PER_TABLE := 4
const AUTOSAVE_INTERVAL := 300.0
const HAND_HOME := Vector2(320.0, 120.0)
const HAND_TABLE_START := Vector2(320.0, 250.0)
const GLASS_SPAWN_FIRST_X := 26.0
const GLASS_SPAWN_STEP := 18.0
const GLASS_SPAWN_Y := -24.0

var phase := Phase.IDLE

var _round := 0
var _tables: Array[CustomerTable] = []
var _table_index := 0
var _approach := 0.0
var _walking := false
var _leaving := false
var _empty_timer := 0.0
var _week_over := false
var _last_summary: Dictionary = {}
var _phase_before_fight := Phase.SERVE
var _autosave_timer := 0.0

@onready var bar_layer: Node2D = $BarLayer
@onready var serve_layer: Node2D = $ServeLayer
@onready var tables_root: Node2D = $ServeLayer/Tables
@onready var counter_shape: CollisionShape2D = $BarLayer/Counter/CollisionShape2D
@onready var racks := [$BarLayer/MugRack, $BarLayer/GlassRack]
@onready var stations_root: Node2D = $BarLayer/Stations
@onready var glasses_root: Node2D = $Glasses
@onready var tray: Tray = $Tray
@onready var hand: Hand = $Hand
@onready var hud: Hud = $HUD
@onready var fight: FightMinigame = $Fight


func _ready() -> void:
	for rack in racks:
		(rack as GlassRack).requested.connect(_on_rack_requested)
	hud.serve_pressed.connect(_on_serve_pressed)
	hud.day_continue_pressed.connect(_on_day_continue)
	hud.debt_confirmed.connect(_on_debt_confirmed)
	hud.save_requested.connect(_on_save_requested)
	hud.open_requested.connect(_on_open_requested)
	_apply_pending()


func _process(delta: float) -> void:
	GameState.play_time += delta
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL and _can_autosave():
		_autosave_timer = 0.0
		if SaveManager.write_auto(capture_state()):
			hud.toast(Loc.t("toast_autosaved"), 1.5)


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
		var attacker := table.tick(delta)
		if attacker != null:
			hud.toast(Loc.t("toast_swing_patience"))
			_run_fight(table, attacker)
			return
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
			return
	GameState.reset()
	_show_opening()


func _can_autosave() -> bool:
	match phase:
		Phase.OPENING, Phase.PREP, Phase.DAY_END, Phase.COLLECTOR:
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
			return {"phase": "day_end", "summary": _last_summary, "week_over": _week_over}
		Phase.COLLECTOR:
			return {"phase": "collector"}
	return {"phase": "opening"}


func _restore_bar(bar: Dictionary) -> void:
	match String(bar.get("phase", "opening")):
		"prep", "serve":
			_restore_runtime(bar)
		"day_end":
			_last_summary = bar.get("summary", {})
			_week_over = bool(bar.get("week_over", false))
			phase = Phase.DAY_END
			_set_bar_active(false)
			if _last_summary.is_empty():
				_show_opening()
			else:
				hud.show_day_end(_last_summary)
		"collector":
			_week_over = true
			phase = Phase.COLLECTOR
			_set_bar_active(false)
			hud.show_collector(GameState.collector_info())
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
		var glass := GLASS_SCENE.instantiate() as Glass
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
	bar_layer.visible = true
	serve_layer.visible = false
	hud.show_orders("")
	hud.set_prompt("")
	hud.show_opening(SaveManager.current_slot)


func _on_open_requested() -> void:
	if phase != Phase.OPENING:
		return
	hud.hide_opening()
	_begin_day()


func _begin_day() -> void:
	GameState.start_day()
	_round = 0
	_begin_round()


func _begin_round() -> void:
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
		hud.toast(Loc.t("toast_put_glass"))
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
	hand.set_enabled(true, HAND_TABLE_START)


func _check_empty_tray(delta: float, table: CustomerTable) -> void:
	var out_of_glasses := tray.glass_count() == 0 and hand.held == null
	var in_trouble := table.find_agitated() != null
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
	var trouble := table.find_agitated()
	if trouble != null:
		hud.toast(Loc.t("toast_swing_leave"))
		await _run_fight(table, trouble)
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
	tray.balance_enabled = false
	tray.walk_factor = 0.0
	_clear_glasses()
	serve_layer.visible = false
	if _round < GameState.ROUNDS_PER_DAY:
		_begin_round()
	else:
		_finish_day()


func _finish_day() -> void:
	phase = Phase.DAY_END
	hand.set_enabled(false)
	_set_bar_active(false)
	_last_summary = GameState.end_day()
	_week_over = _last_summary["week_over"]
	hud.show_orders("")
	hud.set_prompt("")
	hud.show_day_end(_last_summary)


func _on_day_continue() -> void:
	if not _week_over:
		_show_opening()
		return
	phase = Phase.COLLECTOR
	if GameState.month_debt <= 0:
		_on_debt_confirmed(0)
	else:
		hud.show_collector(GameState.collector_info())


func _on_debt_confirmed(amount: int) -> void:
	var info := GameState.finish_week(amount)
	if info["forced"]:
		hud.toast(
			Loc.t("toast_month_closed", {
				"paid": Loc.gold(int(info["paid"])),
				"debt": Loc.gold(int(info["remaining"])),
				"carried": Loc.gold(int(info["carried"])),
			}),
			4.0
		)
	else:
		hud.toast(Loc.t("toast_paid", {"paid": Loc.gold(int(info["paid"])), "debt": Loc.gold(int(info["remaining"]))}), 3.0)
	_show_opening()


# --- customers / fights -----------------------------------------------------------

func _generate_orders() -> void:
	for table in _tables:
		table.queue_free()
	_tables.clear()
	var unlocked := GameState.unlocked_drink_ids()
	var slots := GameState.tray_slots()
	var total := maxi(1, roundi(randi_range(GameState.table_count(), slots) * GameState.flow_factor()))
	var table_n := mini(GameState.table_count(), total)
	var per_table: Array[int] = []
	per_table.resize(table_n)
	per_table.fill(1)
	var extra := total - table_n
	var attempts := 0
	while extra > 0 and attempts < 200:
		attempts += 1
		var i := randi() % table_n
		if per_table[i] < MAX_CUSTOMERS_PER_TABLE:
			per_table[i] += 1
			extra -= 1
	for i in table_n:
		var list: Array[Customer] = []
		for j in per_table[i]:
			list.append(Customer.create(unlocked.pick_random(), _round))
		var fraction := 0.5 if table_n == 1 else float(i) / float(table_n - 1)
		var table := TABLE_SCENE.instantiate() as CustomerTable
		tables_root.add_child(table)
		table.setup(i + 1, list, Vector2(lerpf(130.0, 510.0, fraction), 100.0))
		_connect_table(table)
		_tables.append(table)


func _connect_table(table: CustomerTable) -> void:
	table.order_served.connect(_on_order_served)
	table.glass_rejected.connect(_on_glass_rejected)
	table.kick_requested.connect(_on_kick_requested)
	table.customer_left.connect(_on_customer_left)
	table.cleared.connect(_on_table_cleared)


func _orders_text() -> String:
	var lines: PackedStringArray = []
	for table in _tables:
		lines.append(Loc.t("table_line", {"id": table.table_id, "list": table.summary()}))
	return "\n".join(lines)


func _on_order_served(_customer: Customer, payout: int, tip: int, glass_ok: bool) -> void:
	var text := Loc.t("toast_served", {"payout": Loc.gold(payout)})
	if tip > 0:
		text = Loc.t("toast_served_tip", {"payout": Loc.gold(payout), "tip": Loc.gold(tip)})
	if not glass_ok:
		text += "  " + Loc.t("toast_wrong_glass")
	hud.toast(text, 1.6)
	hud.show_orders(_orders_text())


func _on_glass_rejected(_glass: Glass) -> void:
	hud.toast(Loc.t("toast_bad_drink"))


func _on_customer_left(_customer: Customer) -> void:
	hud.toast(Loc.t("toast_grumbles"))
	hud.show_orders(_orders_text())


func _on_kick_requested(table: CustomerTable, customer: Customer) -> void:
	if phase != Phase.SERVE or _leaving:
		return
	var provoked := customer.state == Customer.State.AGITATED
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
	var glass := GLASS_SCENE.instantiate() as Glass
	glass.glass_type = type
	glasses_root.add_child(glass)
	glass.global_position = _free_spawn_position(rack)
	glass.shattered.connect(_on_glass_shattered)


func _free_spawn_position(rack: GlassRack) -> Vector2:
	var live := _live_glasses()
	for slot in 6:
		var candidate := rack.global_position + Vector2(GLASS_SPAWN_FIRST_X + slot * GLASS_SPAWN_STEP, GLASS_SPAWN_Y)
		var blocked := false
		for glass in live:
			var same_column := absf(glass.global_position.x - candidate.x) < GLASS_SPAWN_STEP * 0.9
			var near_counter := absf(glass.global_position.y - rack.global_position.y) < 50.0
			if same_column and near_counter:
				blocked = true
				break
		if not blocked:
			return candidate
	return rack.global_position + Vector2(GLASS_SPAWN_FIRST_X, GLASS_SPAWN_Y)


func _on_glass_shattered(glass: Glass) -> void:
	GameState.break_glass(glass.glass_type)
	hud.toast(Loc.t("toast_glass_broke", {
		"name": Loc.t("glass_%s" % glass.glass_type),
		"left": GameState.glass_count(glass.glass_type),
	}), 3.0)


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
