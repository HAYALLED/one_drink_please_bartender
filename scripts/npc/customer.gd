class_name Customer
extends RefCounted

# BRAWLING is last on purpose: older saves store the other states as ints.
enum State { CALM, AGITATED, OBJECTING, LEFT, BRAWLING }

const AGITATE_THRESHOLD := 0.62
const ANGER_TIME := 9.0
const OBJECT_TIME := 4.0
const BRAWL_TIME := 7.0
const WRONG_GLASS_AGITATE_CHANCE := 0.35
const LATE_WARN_FRACTION := 0.6
const LEAVE_DELAY := 1.4
const MAX_STAY_ROUNDS := 2
const STAY_LINGER_WEIGHT := 0.4
const STAY_MOOD_WEIGHT := 0.2
const STAY_DRUNK_WEIGHT := 0.25
const STAY_ROUND_PENALTY := 0.25
const STAY_MAX_CHANCE := 0.85

var drink_id: StringName = &""
var mood := 0.6
var drunk := 0.0
var aggression := 0.3
var state := State.CALM
var served := false
var timer := 0.0

var trait_id: int = CustomerTrait.Id.NEUTRAL
## Stat 0..1: how much this customer likes hanging around. Drives the chance to stay for another round.
var linger := 0.4
## Seconds spent waiting for the current drink (counts only while the player is at the table).
var waited := 0.0
var late_warned := false
## Rolled when served: this customer stays at the bar for the next round.
var stays := false
var rounds_stayed := 0
## Seconds until a straight-forward customer walks out after paying. -1 = not leaving.
var leave_in := -1.0
var brawl_left := 0.0
var instigator := false

# Runtime links, not saved.
var brawl_target: Customer = null
var grudge: Customer = null


static func create(id: StringName, round_index: int) -> Customer:
	var customer := Customer.new()
	customer.drink_id = id
	customer.trait_id = CustomerTrait.roll()
	customer.mood = randf_range(0.45, 0.8)
	customer.drunk = randf() * (0.15 + 0.12 * round_index)
	customer.linger = randf()
	var base := pow(randf(), 1.6) + float(customer.profile()["aggression"])
	customer.aggression = clampf(base, 0.0, 1.0)
	customer.evaluate_agitation(0.0)
	return customer


func profile() -> Dictionary:
	return CustomerTrait.profile(trait_id)


func trait_key() -> StringName:
	return CustomerTrait.key(trait_id)


func can_fight() -> bool:
	return bool(profile()["can_fight"])


func can_be_target() -> bool:
	return bool(profile()["can_be_target"])


func incites() -> bool:
	return bool(profile()["incites"])


func can_chat() -> bool:
	return bool(profile()["chats"])


## Greedy customers are the hidden troublemakers even when they look calm.
func is_troublemaker() -> bool:
	return state == State.AGITATED or state == State.BRAWLING or incites()


func patience() -> float:
	return float(profile()["patience"])


func anger_time() -> float:
	return ANGER_TIME * float(profile()["anger_scale"])


func risk() -> float:
	return aggression * 0.35 + (1.0 - mood) * 0.4 + drunk * 0.5


func evaluate_agitation(extra_chance: float) -> void:
	if state != State.CALM or not can_fight():
		return
	if risk() > AGITATE_THRESHOLD or randf() < extra_chance:
		agitate()


func agitate() -> void:
	if state != State.CALM or not can_fight():
		return
	state = State.AGITATED
	timer = anger_time()


## Someone (a greedy customer) turned this customer against `against`.
func provoke(amount: float, against: Customer) -> void:
	mood = clampf(mood - amount, 0.0, 1.0)
	grudge = against
	evaluate_agitation(0.35)


## Random outburst for hot blooded customers. Returns true when one happened.
func flares(delta: float) -> bool:
	var chance := float(profile()["flare_per_sec"])
	if chance <= 0.0 or state != State.CALM or not can_fight():
		return false
	if randf() < chance * delta:
		agitate()
		return state == State.AGITATED
	return false


func begin_brawl(opponent: Customer, started_it: bool) -> void:
	state = State.BRAWLING
	brawl_target = opponent
	brawl_left = BRAWL_TIME
	instigator = started_it


func end_brawl() -> void:
	brawl_target = null
	brawl_left = 0.0
	instigator = false


func stay_chance() -> float:
	if state != State.CALM or bool(profile()["leaves_after_serve"]):
		return 0.0
	var chance := linger * STAY_LINGER_WEIGHT + mood * STAY_MOOD_WEIGHT + drunk * STAY_DRUNK_WEIGHT
	chance += float(profile()["linger_bonus"]) - STAY_ROUND_PENALTY * rounds_stayed
	return clampf(chance, 0.0, STAY_MAX_CHANCE)


func wants_to_stay() -> bool:
	return stays and served and state == State.CALM and rounds_stayed < MAX_STAY_ROUNDS


## Called when this customer stays for the next round: new drink, same person.
func begin_next_round(id: StringName) -> void:
	drink_id = id
	served = false
	stays = false
	waited = 0.0
	late_warned = false
	leave_in = -1.0
	rounds_stayed += 1
	grudge = null
	end_brawl()


func receive(glass: Glass) -> Dictionary:
	var drink := DrinkDB.get_drink(drink_id)
	var q := glass.quality()
	var glass_ok := drink.wrong_glass_penalty <= 0.0 or glass.glass_type == drink.preferred_glass
	var prof := profile()
	served = true
	waited = 0.0
	mood = clampf(mood + (q - 0.5) * 0.5 + (0.12 if glass_ok else -drink.wrong_glass_penalty), 0.0, 1.0)
	drunk = clampf(drunk + drink.alcohol, 0.0, 1.0)
	var payout := roundi(drink.price * lerpf(0.4, 1.0, q))
	var tip_scale := float(prof["tip_scale"])
	var tip := 0
	if tip_scale > 0.0:
		var chance := mood * 0.55 + (0.1 if glass_ok else -0.3) + GameState.tip_bonus() + float(prof["tip_chance"])
		if not glass_ok:
			chance *= 0.25
		if randf() < clampf(chance, 0.0, 0.95):
			tip = maxi(1, roundi(drink.price * (0.3 + 0.7 * mood) * GameState.tip_multiplier() * tip_scale))
	evaluate_agitation(0.0 if glass_ok else WRONG_GLASS_AGITATE_CHANCE)
	stays = state == State.CALM and randf() < stay_chance()
	if state == State.CALM and bool(prof["leaves_after_serve"]):
		leave_in = LEAVE_DELAY
	return {"payout": payout, "tip": tip, "glass_ok": glass_ok, "stays": stays}


# Returns &"left", &"objects", &"attacks" or &"player_attacks".
func react_to_kick() -> StringName:
	if state == State.OBJECTING:
		return &"player_attacks"
	var provoked := state == State.AGITATED
	var attack_chance := 0.0
	if can_fight():
		attack_chance = clampf((0.15 if provoked else 0.3) + aggression * 0.4 + drunk * 0.35, 0.0, 0.9)
	var roll := randf()
	if roll < attack_chance:
		return &"attacks"
	if roll < attack_chance + 0.35:
		state = State.OBJECTING
		timer = OBJECT_TIME
		return &"objects"
	state = State.LEFT
	return &"left"


func fight_strength() -> float:
	return clampf(0.35 + aggression * 0.3 + drunk * 0.15, 0.2, 0.9)


func pacify() -> void:
	state = State.CALM
	mood = 0.2
	timer = 0.0
	grudge = null
	end_brawl()


func to_dict() -> Dictionary:
	return {
		"drink": String(drink_id),
		"mood": mood,
		"drunk": drunk,
		"aggression": aggression,
		"state": int(state),
		"served": served,
		"timer": timer,
		"trait": String(trait_key()),
		"linger": linger,
		"waited": waited,
		"late_warned": late_warned,
		"stays": stays,
		"rounds_stayed": rounds_stayed,
		"leave_in": leave_in,
		"brawl_left": brawl_left,
		"instigator": instigator,
	}


static func from_dict(data: Dictionary) -> Customer:
	var customer := Customer.new()
	customer.drink_id = StringName(data.get("drink", "beer"))
	customer.mood = float(data.get("mood", 0.6))
	customer.drunk = float(data.get("drunk", 0.0))
	customer.aggression = float(data.get("aggression", 0.3))
	customer.state = clampi(int(data.get("state", 0)), 0, State.BRAWLING) as State
	customer.served = bool(data.get("served", false))
	customer.timer = float(data.get("timer", 0.0))
	customer.trait_id = CustomerTrait.from_key(String(data.get("trait", "neutral")))
	customer.linger = float(data.get("linger", 0.4))
	customer.waited = float(data.get("waited", 0.0))
	customer.late_warned = bool(data.get("late_warned", false))
	customer.stays = bool(data.get("stays", false))
	customer.rounds_stayed = int(data.get("rounds_stayed", 0))
	customer.leave_in = float(data.get("leave_in", -1.0))
	customer.brawl_left = float(data.get("brawl_left", 0.0))
	customer.instigator = bool(data.get("instigator", false))
	return customer