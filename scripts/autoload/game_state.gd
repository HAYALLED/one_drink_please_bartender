extends Node

signal money_changed(money: int)

# Money is stored as three coin piles. All prices, debts and costs are written in bronze.
const BRONZE_PER_SILVER := 100
const SILVER_PER_GOLD := 100
const BRONZE_PER_GOLD := BRONZE_PER_SILVER * SILVER_PER_GOLD

const DAYS_PER_MONTH := 20
const ROUNDS_PER_DAY := 3

const BASE_MONTH_DEBT := 4 * BRONZE_PER_GOLD + 56 * BRONZE_PER_SILVER
const MONTH_DEBT_GROWTH := 95 * BRONZE_PER_SILVER
const MIN_PAYMENT_RATIO := 0.5
const UNPAID_INTEREST := 0.25

# Taking debt at the collector: the player gets the coins now, the debt grows by the amount plus this fee.
const BORROW_FEE := 0.2
const BORROW_MIN := 100
const BORROW_MAX := BRONZE_PER_GOLD
const BORROW_STEP := 100

# Old saves counted 1 coin where the new economy counts about 38 bronze.
const LEGACY_COIN_SCALE := 38
const LEGACY_DAYS_PER_WEEK := 5

const BASE_TRAY_SLOTS := 3
const BASE_TABLES := 2

const FIGHT_FAVOR_GAIN := 8
const FIGHT_TRUST_GAIN := 3
const FIGHT_FAVOR_LOSS := 8
const FIGHT_TRUST_LOSS := 15
const FIGHT_LOSS_CROWD_DAYS := 3
const CROWD_PENALTY_FACTOR := 0.6

const BRAWL_TRUST_LOSS := 8
const BRAWL_FAVOR_LOSS := 4
const BRAWL_DAMAGE_COST := 10 * BRONZE_PER_SILVER
const BRAWL_STOP_TRUST := 2
const BRAWL_STOP_FAVOR := 3

const GLASS_TYPES := {
	&"mug": {"price": 530, "start": 4},
	&"glass": {"price": 300, "start": 6},
	&"wine_glass": {"price": 450, "start": 0},
	&"tumbler": {"price": 380, "start": 0},
	&"shot": {"price": 220, "start": 0},
}

# Unlocking a drink for the first time hands out this many glasses of the type that drink is served in.
const UNLOCK_PROMO_GLASSES := 3

const UPGRADES := {
	&"tray_slots": {"base_cost": 3000, "growth": 1.7, "max_level": 4},
	&"tables": {"base_cost": 3800, "growth": 1.8, "max_level": 3},
	&"decor": {"base_cost": 2300, "growth": 1.6, "max_level": 5},
}

var bronze := 0
var silver := 0
var gold := 0
var money: int:
	get:
		return bronze + silver * BRONZE_PER_SILVER + gold * BRONZE_PER_GOLD
var play_time := 0.0
var month := 1
var day := 1
var month_debt := BASE_MONTH_DEBT
var month_required := 0
var month_paid := 0
var month_earned := 0
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
	bronze = 0
	silver = 0
	gold = 0
	play_time = 0.0
	month = 1
	day = 1
	month_debt = BASE_MONTH_DEBT
	month_required = _required_for(month_debt)
	month_paid = 0
	month_earned = 0
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
		"bronze": bronze,
		"silver": silver,
		"gold": gold,
		"play_time": play_time,
		"month": month,
		"day": day,
		"month_debt": month_debt,
		"month_required": month_required,
		"month_paid": month_paid,
		"month_earned": month_earned,
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
	# Saves from before the coin system have a single "money" number and a week/day calendar.
	var legacy := not data.has("bronze")
	var scale := LEGACY_COIN_SCALE if legacy else 1
	if legacy:
		var parts := split_coins(int(data.get("money", 0)) * scale)
		gold = parts.x
		silver = parts.y
		bronze = parts.z
	else:
		bronze = int(data.get("bronze", 0))
		silver = int(data.get("silver", 0))
		gold = int(data.get("gold", 0))
	play_time = float(data.get("play_time", play_time))
	month = int(data.get("month", month))
	if legacy:
		day = (int(data.get("week", 1)) - 1) * LEGACY_DAYS_PER_WEEK + int(data.get("day", 1))
	else:
		day = int(data.get("day", day))
	day = clampi(day, 1, DAYS_PER_MONTH)
	if data.has("month_debt"):
		month_debt = int(data["month_debt"]) * scale
	month_required = int(data.get("month_required", _required_for(month_debt)))
	month_paid = int(data.get("month_paid", 0))
	month_earned = int(data.get("month_earned", data.get("week_earned", 0))) * scale
	day_earned = int(data.get("day_earned", day_earned)) * scale
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
	# Saves from before a glass type existed: drinks that were already unlocked get the promo glasses now.
	for type in GLASS_TYPES:
		if owned.has(String(type)):
			continue
		for id in unlocked_drinks:
			if DrinkDB.get_drink(id).preferred_glass == type and DrinkDB.get_drink(id).unlock_cost > 0:
				glasses_owned[type] = glass_count(type) + UNLOCK_PROMO_GLASSES
	money_changed.emit(money)


# --- money -----------------------------------------------------------------

## amount (bronze) -> Vector3i(gold, silver, bronze)
func split_coins(amount: int) -> Vector3i:
	amount = maxi(amount, 0)
	var gold_part := floori(amount / float(BRONZE_PER_GOLD))
	var rest := amount - gold_part * BRONZE_PER_GOLD
	var silver_part := floori(rest / float(BRONZE_PER_SILVER))
	return Vector3i(gold_part, silver_part, rest - silver_part * BRONZE_PER_SILVER)


## Adds coins in the biggest denominations that fit. Nothing is converted automatically afterwards.
func add_money(amount: int) -> void:
	if amount <= 0:
		return
	var parts := split_coins(amount)
	gold += parts.x
	silver += parts.y
	bronze += parts.z
	money_changed.emit(money)


## Pays with small coins first and breaks bigger coins only when needed. Change comes back in smaller coins.
func spend(amount: int) -> bool:
	if amount < 0 or amount > money:
		return false
	var remaining := amount
	var from_bronze := mini(bronze, remaining)
	bronze -= from_bronze
	remaining -= from_bronze
	if remaining > 0:
		var silver_needed := ceili(remaining / float(BRONZE_PER_SILVER))
		var used := mini(silver, silver_needed)
		silver -= used
		var paid := used * BRONZE_PER_SILVER
		if paid >= remaining:
			bronze += paid - remaining
			remaining = 0
		else:
			remaining -= paid
	if remaining > 0:
		var gold_needed := ceili(remaining / float(BRONZE_PER_GOLD))
		gold -= gold_needed
		var change := split_coins(gold_needed * BRONZE_PER_GOLD - remaining)
		silver += change.y
		bronze += change.z
	money_changed.emit(money)
	return true


func can_afford(amount: int) -> bool:
	return amount <= money


func register_sale(amount: int) -> void:
	day_earned += amount
	month_earned += amount
	add_money(amount)


# --- coin exchange ---------------------------------------------------------------

## How many coins of the target type an exchange would give right now. Upward exchanges convert every full pile,
## downward exchanges break one coin.
func exchange_amount(kind: StringName) -> int:
	match kind:
		&"bronze_to_silver":
			return floori(bronze / float(BRONZE_PER_SILVER))
		&"silver_to_gold":
			return floori(silver / float(SILVER_PER_GOLD))
		&"silver_to_bronze":
			return mini(silver, 1)
		&"gold_to_silver":
			return mini(gold, 1)
	return 0


func exchange(kind: StringName) -> bool:
	var count := exchange_amount(kind)
	if count <= 0:
		return false
	match kind:
		&"bronze_to_silver":
			bronze -= count * BRONZE_PER_SILVER
			silver += count
		&"silver_to_gold":
			silver -= count * SILVER_PER_GOLD
			gold += count
		&"silver_to_bronze":
			silver -= 1
			bronze += BRONZE_PER_SILVER
		&"gold_to_silver":
			gold -= 1
			silver += SILVER_PER_GOLD
	money_changed.emit(money)
	return true


# --- debt ------------------------------------------------------------------------

func _required_for(debt: int) -> int:
	return ceili(debt * MIN_PAYMENT_RATIO)


## Part of this month's debt that still has to be paid by month end.
func required_left() -> int:
	return maxi(month_required - month_paid, 0)


func max_payment() -> int:
	return mini(money, month_debt)


## Pays debt any day. Returns what was actually paid.
func pay_debt(amount: int) -> int:
	var paid := clampi(amount, 0, max_payment())
	if paid <= 0 or not spend(paid):
		return 0
	month_debt -= paid
	month_paid += paid
	return paid


## Debt that taking this many coins adds (the coins plus the fee).
func borrow_debt_added(amount: int) -> int:
	return ceili(amount * (1.0 + BORROW_FEE))


## Takes debt any day, as often as needed. The new debt is also required by month end in the usual ratio.
## Returns the coins received.
func borrow(amount: int) -> int:
	var taken := clampi(amount, 0, BORROW_MAX)
	if taken <= 0:
		return 0
	var added := borrow_debt_added(taken)
	month_debt += added
	month_required += _required_for(added)
	add_money(taken)
	return taken


# --- glasses -----------------------------------------------------------------

func glass_count(type: StringName) -> int:
	return int(glasses_owned.get(type, 0))


func total_glasses() -> int:
	var total := 0
	for type in glasses_owned:
		total += int(glasses_owned[type])
	return total


func has_glasses() -> bool:
	return total_glasses() > 0


## Price of the cheapest glass the shop sells right now.
func cheapest_glass_price() -> int:
	var best := -1
	for type in available_glass_types():
		var price := glass_price(type)
		if best < 0 or price < best:
			best = price
	return maxi(best, 0)


## A glass type shows up (rack, shop, HUD) once an unlocked drink is served in it.
func glass_available(type: StringName) -> bool:
	for id in unlocked_drinks:
		if DrinkDB.get_drink(id).preferred_glass == type:
			return true
	return false


func available_glass_types() -> Array[StringName]:
	var result: Array[StringName] = []
	for type in GLASS_TYPES:
		if glass_available(type):
			result.append(type)
	return result


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
	glasses_owned[drink.preferred_glass] = glass_count(drink.preferred_glass) + UNLOCK_PROMO_GLASSES
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


## A brawl between customers ran its course. Returns the gold the bar paid for the damage.
func brawl_wrecked() -> int:
	trust = maxi(trust - BRAWL_TRUST_LOSS, 0)
	favor = maxi(favor - BRAWL_FAVOR_LOSS, 0)
	var cost := mini(money, BRAWL_DAMAGE_COST)
	if cost > 0:
		spend(cost)
	return cost


func brawl_stopped() -> void:
	favor = mini(favor + BRAWL_STOP_FAVOR, 100)
	trust = mini(trust + BRAWL_STOP_TRUST, 100)


func good_kick() -> void:
	favor = mini(favor + 1, 100)
	trust = mini(trust + 2, 100)


func wrongful_kick() -> void:
	favor = maxi(favor - 2, 0)
	trust = maxi(trust - 4, 0)


# --- day / month ----------------------------------------------------------

func start_day() -> void:
	day_earned = 0
	crowd_reduced_today = fewer_customers_days > 0
	if crowd_reduced_today:
		fewer_customers_days -= 1
	trust = mini(trust + 1, 100)


func end_day() -> Dictionary:
	var month_over := is_month_end()
	if not month_over:
		day += 1
	return {
		"earned": day_earned,
		"month_earned": month_earned,
		"month_over": month_over,
		"required": required_left(),
	}


func is_month_end() -> bool:
	return day >= DAYS_PER_MONTH


func collector_info(forced := true) -> Dictionary:
	var max_pay := max_payment()
	return {
		"month_debt": month_debt,
		"money": money,
		"forced": forced,
		"required": required_left(),
		"min_pay": mini(required_left(), max_pay) if forced else 0,
		"max_pay": max_pay,
	}


## Month end. At least the still-required part is taken (as far as the player has coins).
## Whatever stays unpaid comes back next month with interest.
func finish_month(requested: int) -> Dictionary:
	var max_pay := max_payment()
	var min_pay := mini(required_left(), max_pay)
	var paid := pay_debt(clampi(requested, min_pay, max_pay))
	var remaining := month_debt
	var carried := roundi(remaining * (1.0 + UNPAID_INTEREST))
	month += 1
	day = 1
	month_earned = 0
	month_debt = BASE_MONTH_DEBT + MONTH_DEBT_GROWTH * (month - 1) + carried
	month_required = _required_for(month_debt)
	month_paid = 0
	return {
		"paid": paid,
		"remaining": remaining,
		"carried": carried,
		"new_debt": month_debt,
	}


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
	if not InputMap.has_action(&"pour"):
		_bind_keys(&"pour", [KEY_F])
		var pour_click := InputEventMouseButton.new()
		pour_click.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event(&"pour", pour_click)


func _bind_keys(action: StringName, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key as Key
		InputMap.action_add_event(action, event)