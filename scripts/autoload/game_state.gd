extends Node

signal money_changed(money: int)

const WEEKS_PER_MONTH := 4
const DAYS_PER_WEEK := 5
const ROUNDS_PER_DAY := 3

const BASE_MONTH_DEBT := 1200
const MONTH_DEBT_GROWTH := 250
const BASE_WEEKLY_TARGET := 300
const WEEKLY_TARGET_GROWTH := 60
const UNPAID_INTEREST := 0.25
const MISSED_TARGET_PENALTY := 0.05

const BASE_TRAY_SLOTS := 3
const BASE_TABLES := 2

const FIGHT_FAVOR_GAIN := 8
const FIGHT_TRUST_GAIN := 3
const FIGHT_FAVOR_LOSS := 8
const FIGHT_TRUST_LOSS := 15
const FIGHT_LOSS_CROWD_DAYS := 3
const CROWD_PENALTY_FACTOR := 0.6

const GLASS_TYPES := {
	&"mug": {"price": 14, "start": 4, "tint": Color(1.0, 0.85, 0.5, 0.3)},
	&"glass": {"price": 8, "start": 6, "tint": Color(0.8, 0.9, 1.0, 0.22)},
}

const UPGRADES := {
	&"tray_slots": {"base_cost": 80, "growth": 1.7, "max_level": 4},
	&"tables": {"base_cost": 100, "growth": 1.8, "max_level": 3},
	&"decor": {"base_cost": 60, "growth": 1.6, "max_level": 5},
}

var money := 0
var play_time := 0.0
var month := 1
var week := 1
var day := 1
var month_debt := BASE_MONTH_DEBT
var weekly_target := BASE_WEEKLY_TARGET
var week_earned := 0
var day_earned := 0

var trust := 80
var favor := 0
var fewer_customers_days := 0
var crowd_reduced_today := false

var glasses_owned: Dictionary = {}
var upgrade_levels: Dictionary = {}
var unlocked_drinks: Array[StringName] = []


func _ready() -> void:
	reset()
	_register_inputs()


# --- new game / save data ----------------------------------------------------

func reset() -> void:
	money = 0
	play_time = 0.0
	month = 1
	week = 1
	day = 1
	month_debt = BASE_MONTH_DEBT
	weekly_target = BASE_WEEKLY_TARGET
	week_earned = 0
	day_earned = 0
	trust = 80
	favor = 0
	fewer_customers_days = 0
	crowd_reduced_today = false
	upgrade_levels = {}
	unlocked_drinks = DrinkDB.default_unlocked()
	glasses_owned = {}
	for type in GLASS_TYPES:
		glasses_owned[type] = int(GLASS_TYPES[type]["start"])


func to_dict() -> Dictionary:
	var owned := {}
	for type in glasses_owned:
		owned[String(type)] = int(glasses_owned[type])
	var levels := {}
	for id in upgrade_levels:
		levels[String(id)] = int(upgrade_levels[id])
	var drinks: Array[String] = []
	for id in unlocked_drinks:
		drinks.append(String(id))
	return {
		"money": money,
		"play_time": play_time,
		"month": month,
		"week": week,
		"day": day,
		"month_debt": month_debt,
		"weekly_target": weekly_target,
		"week_earned": week_earned,
		"day_earned": day_earned,
		"trust": trust,
		"favor": favor,
		"fewer_customers_days": fewer_customers_days,
		"crowd_reduced_today": crowd_reduced_today,
		"glasses_owned": owned,
		"upgrade_levels": levels,
		"unlocked_drinks": drinks,
	}


func from_dict(data: Dictionary) -> void:
	reset()
	money = int(data.get("money", money))
	play_time = float(data.get("play_time", play_time))
	month = int(data.get("month", month))
	week = int(data.get("week", week))
	day = int(data.get("day", day))
	month_debt = int(data.get("month_debt", month_debt))
	weekly_target = int(data.get("weekly_target", weekly_target))
	week_earned = int(data.get("week_earned", week_earned))
	day_earned = int(data.get("day_earned", day_earned))
	trust = int(data.get("trust", trust))
	favor = int(data.get("favor", favor))
	fewer_customers_days = int(data.get("fewer_customers_days", fewer_customers_days))
	crowd_reduced_today = bool(data.get("crowd_reduced_today", crowd_reduced_today))
	var owned: Dictionary = data.get("glasses_owned", {})
	for type in owned:
		glasses_owned[StringName(type)] = int(owned[type])
	var levels: Dictionary = data.get("upgrade_levels", {})
	for id in levels:
		upgrade_levels[StringName(id)] = int(levels[id])
	var drinks: Array = data.get("unlocked_drinks", [])
	for id in drinks:
		if DrinkDB.get_drink(StringName(id)) != null and not unlocked_drinks.has(StringName(id)):
			unlocked_drinks.append(StringName(id))
	money_changed.emit(money)


# --- money -----------------------------------------------------------------

func spend(amount: int) -> bool:
	if amount > money:
		return false
	money -= amount
	money_changed.emit(money)
	return true


func register_sale(amount: int) -> void:
	money += amount
	day_earned += amount
	week_earned += amount
	money_changed.emit(money)


# --- glasses -----------------------------------------------------------------

func glass_count(type: StringName) -> int:
	return int(glasses_owned.get(type, 0))


func total_glasses() -> int:
	var total := 0
	for type in glasses_owned:
		total += int(glasses_owned[type])
	return total


func glass_price(type: StringName) -> int:
	return int(GLASS_TYPES[type]["price"])


func buy_glass(type: StringName) -> bool:
	if not spend(glass_price(type)):
		return false
	glasses_owned[type] = glass_count(type) + 1
	return true


func break_glass(type: StringName) -> void:
	glasses_owned[type] = maxi(glass_count(type) - 1, 0)


# --- upgrades --------------------------------------------------------------

func level(id: StringName) -> int:
	return int(upgrade_levels.get(id, 0))


func is_maxed(id: StringName) -> bool:
	return level(id) >= int(UPGRADES[id]["max_level"])


func upgrade_cost(id: StringName) -> int:
	var data: Dictionary = UPGRADES[id]
	return roundi(float(data["base_cost"]) * pow(float(data["growth"]), level(id)))


func buy_upgrade(id: StringName) -> bool:
	if is_maxed(id) or not spend(upgrade_cost(id)):
		return false
	upgrade_levels[id] = level(id) + 1
	return true


func is_drink_unlocked(id: StringName) -> bool:
	return unlocked_drinks.has(id)


func unlock_drink(id: StringName) -> bool:
	if is_drink_unlocked(id):
		return false
	var drink := DrinkDB.get_drink(id)
	if drink == null or not spend(drink.unlock_cost):
		return false
	unlocked_drinks.append(id)
	return true


func unlocked_drink_ids() -> Array[StringName]:
	return unlocked_drinks


func tray_slots() -> int:
	return BASE_TRAY_SLOTS + level(&"tray_slots")


func table_count() -> int:
	return mini(BASE_TABLES + level(&"tables"), tray_slots())


func tip_multiplier() -> float:
	return 1.0 + 0.25 * level(&"decor")


func tip_bonus() -> float:
	return favor * 0.002 + 0.03 * level(&"decor")


# --- reputation ------------------------------------------------------------------

func flow_factor() -> float:
	var factor := lerpf(0.6, 1.0, trust / 100.0)
	if crowd_reduced_today:
		factor *= CROWD_PENALTY_FACTOR
	return factor


func fight_won() -> void:
	favor = mini(favor + FIGHT_FAVOR_GAIN, 100)
	trust = mini(trust + FIGHT_TRUST_GAIN, 100)


func fight_lost() -> void:
	favor = maxi(favor - FIGHT_FAVOR_LOSS, 0)
	trust = maxi(trust - FIGHT_TRUST_LOSS, 0)
	fewer_customers_days = FIGHT_LOSS_CROWD_DAYS


func good_kick() -> void:
	favor = mini(favor + 1, 100)
	trust = mini(trust + 2, 100)


func wrongful_kick() -> void:
	favor = maxi(favor - 2, 0)
	trust = maxi(trust - 4, 0)


# --- day / week / month ----------------------------------------------------

func start_day() -> void:
	day_earned = 0
	crowd_reduced_today = fewer_customers_days > 0
	if crowd_reduced_today:
		fewer_customers_days -= 1
	trust = mini(trust + 1, 100)
	if total_glasses() == 0:
		glasses_owned[&"glass"] = 1


func end_day() -> Dictionary:
	var week_over := day >= DAYS_PER_WEEK
	var target_met := week_earned >= weekly_target
	var penalty := 0
	if week_over:
		if not target_met and month_debt > 0:
			penalty = roundi(month_debt * MISSED_TARGET_PENALTY)
			month_debt += penalty
	else:
		day += 1
	return {
		"earned": day_earned,
		"week_earned": week_earned,
		"weekly_target": weekly_target,
		"week_over": week_over,
		"target_met": target_met,
		"penalty": penalty,
	}


func is_month_end() -> bool:
	return week >= WEEKS_PER_MONTH


func collector_info() -> Dictionary:
	var weeks_left := WEEKS_PER_MONTH - week + 1
	return {
		"week": week,
		"month_debt": month_debt,
		"money": money,
		"forced": is_month_end(),
		"suggested": ceili(month_debt / float(weeks_left)),
	}


func finish_week(requested: int) -> Dictionary:
	var forced := is_month_end()
	var payment := mini(money, month_debt)
	if not forced:
		payment = mini(payment, maxi(requested, 0))
	money -= payment
	month_debt -= payment
	money_changed.emit(money)
	var info := {
		"paid": payment,
		"remaining": month_debt,
		"forced": forced,
		"new_month": false,
		"carried": 0,
	}
	week_earned = 0
	day = 1
	if forced:
		var carried := roundi(month_debt * (1.0 + UNPAID_INTEREST))
		month += 1
		week = 1
		month_debt = BASE_MONTH_DEBT + MONTH_DEBT_GROWTH * (month - 1) + carried
		weekly_target = BASE_WEEKLY_TARGET + WEEKLY_TARGET_GROWTH * (month - 1)
		info["new_month"] = true
		info["carried"] = carried
		info["remaining"] = month_debt
	else:
		week += 1
	return info


# --- input -----------------------------------------------------------------

func _register_inputs() -> void:
	_bind_keys(&"tray_left", [KEY_A, KEY_LEFT])
	_bind_keys(&"tray_right", [KEY_D, KEY_RIGHT])
	_bind_keys(&"walk_forward", [KEY_W, KEY_UP])
	_bind_keys(&"leave_table", [KEY_SPACE])
	if not InputMap.has_action(&"grab"):
		InputMap.add_action(&"grab")
		var left_click := InputEventMouseButton.new()
		left_click.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event(&"grab", left_click)
	if not InputMap.has_action(&"kick_out"):
		_bind_keys(&"kick_out", [KEY_E])
		var right_click := InputEventMouseButton.new()
		right_click.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event(&"kick_out", right_click)


func _bind_keys(action: StringName, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key as Key
		InputMap.action_add_event(action, event)
