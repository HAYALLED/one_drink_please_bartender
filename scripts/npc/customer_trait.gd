class_name CustomerTrait
extends RefCounted

## Personality of a customer. Every number a trait changes lives in PROFILES, so balancing = editing this table.
##
## weight          spawn weight
## patience        seconds at the table before an unserved customer loses patience
## aggression      added to the customer's base aggression (clamped 0..1)
## anger_scale     multiplies how long an angry customer waits before swinging at someone
## tip_chance      added to the tip chance
## tip_scale       multiplies the tip amount (0 = never tips)
## can_fight       can get angry and start a brawl
## can_be_target   can be picked as the opponent of an angry customer
## flare_per_sec   chance per second (while calm and at the table) of a sudden outburst
## linger_bonus    added to the chance of staying for another round after drinking
## leaves_after_serve  walks out right after paying
## incites         secretly riles other customers up against each other
## chats           takes part in small talk

enum Id { NEUTRAL, INNOCENT, HOT_BLOODED, GREEDY, STRAIGHT_FORWARD }

const KEYS := {
	Id.NEUTRAL: &"neutral",
	Id.INNOCENT: &"innocent",
	Id.HOT_BLOODED: &"hot_blooded",
	Id.GREEDY: &"greedy",
	Id.STRAIGHT_FORWARD: &"straight_forward",
}

const PROFILES := {
	Id.NEUTRAL: {
		"weight": 0.36, "patience": 24.0, "aggression": 0.0, "anger_scale": 1.0,
		"tip_chance": 0.0, "tip_scale": 1.0, "can_fight": true, "can_be_target": true,
		"flare_per_sec": 0.0, "linger_bonus": 0.0, "leaves_after_serve": false,
		"incites": false, "chats": true,
	},
	Id.INNOCENT: {
		"weight": 0.2, "patience": 36.0, "aggression": -1.0, "anger_scale": 1.0,
		"tip_chance": 0.25, "tip_scale": 1.5, "can_fight": false, "can_be_target": false,
		"flare_per_sec": 0.0, "linger_bonus": 0.15, "leaves_after_serve": false,
		"incites": false, "chats": true,
	},
	Id.HOT_BLOODED: {
		"weight": 0.16, "patience": 14.0, "aggression": 0.35, "anger_scale": 0.6,
		"tip_chance": -0.05, "tip_scale": 0.9, "can_fight": true, "can_be_target": true,
		"flare_per_sec": 0.012, "linger_bonus": 0.05, "leaves_after_serve": false,
		"incites": false, "chats": true,
	},
	Id.GREEDY: {
		"weight": 0.14, "patience": 28.0, "aggression": 0.0, "anger_scale": 1.0,
		"tip_chance": 0.0, "tip_scale": 0.0, "can_fight": false, "can_be_target": false,
		"flare_per_sec": 0.0, "linger_bonus": 0.1, "leaves_after_serve": false,
		"incites": true, "chats": true,
	},
	Id.STRAIGHT_FORWARD: {
		"weight": 0.14, "patience": 16.0, "aggression": -0.2, "anger_scale": 1.0,
		"tip_chance": 0.0, "tip_scale": 1.0, "can_fight": true, "can_be_target": true,
		"flare_per_sec": 0.0, "linger_bonus": 0.0, "leaves_after_serve": true,
		"incites": false, "chats": false,
	},
}


static func profile(id: int) -> Dictionary:
	return PROFILES.get(id, PROFILES[Id.NEUTRAL])


static func key(id: int) -> StringName:
	return KEYS.get(id, &"neutral")


static func from_key(value: String) -> int:
	for id: int in KEYS:
		if String(KEYS[id]) == value:
			return id
	return Id.NEUTRAL


static func name_text(id: int) -> String:
	return Loc.t("trait_%s" % key(id))


static func roll(rng: RandomNumberGenerator = null) -> int:
	var total := 0.0
	for id: int in PROFILES:
		total += float((PROFILES[id] as Dictionary)["weight"])
	var value := (rng.randf() if rng != null else randf()) * total
	for id: int in PROFILES:
		value -= float((PROFILES[id] as Dictionary)["weight"])
		if value < 0.0:
			return id
	return Id.NEUTRAL
