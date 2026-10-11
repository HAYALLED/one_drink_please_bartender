class_name Customer
extends RefCounted

enum State { CALM, AGITATED, OBJECTING, LEFT }

const AGITATE_THRESHOLD := 0.62
const ANGER_TIME := 9.0
const OBJECT_TIME := 4.0
const WRONG_GLASS_AGITATE_CHANCE := 0.35

var drink_id: StringName = &""
var mood := 0.6
var drunk := 0.0
var aggression := 0.3
var state := State.CALM
var served := false
var timer := 0.0


static func create(id: StringName, round_index: int) -> Customer:
	var customer := Customer.new()
	customer.drink_id = id
	customer.mood = randf_range(0.45, 0.8)
	customer.drunk = randf() * (0.15 + 0.12 * round_index)
	customer.aggression = pow(randf(), 1.6)
	customer.evaluate_agitation(0.0)
	return customer


func risk() -> float:
	return aggression * 0.35 + (1.0 - mood) * 0.4 + drunk * 0.5


func evaluate_agitation(extra_chance: float) -> void:
	if state != State.CALM:
		return
	if risk() > AGITATE_THRESHOLD or randf() < extra_chance:
		state = State.AGITATED
		timer = ANGER_TIME


func receive(glass: Glass) -> Dictionary:
	var drink := DrinkDB.get_drink(drink_id)
	var q := glass.quality()
	var glass_ok := drink.wrong_glass_penalty <= 0.0 or glass.glass_type == drink.preferred_glass
	served = true
	mood = clampf(mood + (q - 0.5) * 0.5 + (0.12 if glass_ok else -drink.wrong_glass_penalty), 0.0, 1.0)
	drunk = clampf(drunk + drink.alcohol, 0.0, 1.0)
	var payout := roundi(drink.price * lerpf(0.4, 1.0, q))
	var chance := mood * 0.55 + (0.1 if glass_ok else -0.3) + GameState.tip_bonus()
	if not glass_ok:
		chance *= 0.25
	var tip := 0
	if randf() < clampf(chance, 0.0, 0.95):
		tip = maxi(1, roundi(drink.price * (0.3 + 0.7 * mood) * GameState.tip_multiplier()))
	evaluate_agitation(0.0 if glass_ok else WRONG_GLASS_AGITATE_CHANCE)
	return {"payout": payout, "tip": tip, "glass_ok": glass_ok}


# Returns &"left", &"objects", &"attacks" or &"player_attacks".
func react_to_kick() -> StringName:
	if state == State.OBJECTING:
		return &"player_attacks"
	var provoked := state == State.AGITATED
	var attack_chance := clampf((0.15 if provoked else 0.3) + aggression * 0.4 + drunk * 0.35, 0.0, 0.9)
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


func to_dict() -> Dictionary:
	return {
		"drink": String(drink_id),
		"mood": mood,
		"drunk": drunk,
		"aggression": aggression,
		"state": int(state),
		"served": served,
		"timer": timer,
	}


static func from_dict(data: Dictionary) -> Customer:
	var customer := Customer.new()
	customer.drink_id = StringName(data.get("drink", "beer"))
	customer.mood = float(data.get("mood", 0.6))
	customer.drunk = float(data.get("drunk", 0.0))
	customer.aggression = float(data.get("aggression", 0.3))
	customer.state = clampi(int(data.get("state", 0)), 0, State.LEFT) as State
	customer.served = bool(data.get("served", false))
	customer.timer = float(data.get("timer", 0.0))
	return customer
