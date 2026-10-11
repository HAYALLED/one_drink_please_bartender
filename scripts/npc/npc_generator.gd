class_name NpcGenerator
extends RefCounted

## Rolls a random NPC from whatever images NpcLibrary finds.
## Forced looks (critical characters): pass overrides, e.g.
##   NpcGenerator.generate({"gender": &"female", "parts": {"hat": "", "head": "head_03.png"}, "skin_color": Color.WHITE})
## Parts that are not forced are still rolled randomly.

const MAX_UNIQUE_TRIES := 32
const GENDER_WEIGHTS := {"male": 1.0, "female": 1.0, "other": 0.25}

## Realistic skin tones, light to dark. A roll blends two neighbours, then jitters a little.
## Art for skin layers should be white / light gray: the color is multiplied onto it.
const SKIN_RAMP: Array[Color] = [
	Color("ffe0c8"), Color("f5cba7"), Color("e8b98a"), Color("d09866"),
	Color("b07a4e"), Color("8d5a3b"), Color("6b4226"), Color("4a2c1a"),
]

const HAIR_COLORS: Array[Color] = [
	Color("1b1613"), Color("3b2616"), Color("5a3a22"), Color("84593a"),
	Color("c9a35f"), Color("a5481f"), Color("8f8f8f"), Color("e6e3dc"),
]
const HAIR_WEIGHTS: Array[float] = [0.22, 0.28, 0.22, 0.10, 0.08, 0.05, 0.04, 0.01]

## Chance that an optional part shows up, per gender. Parts not listed: see CORE_PARTS / EXTRA_CHANCE.
const SPAWN_CHANCE := {
	"hat": {"male": 0.35, "female": 0.2, "other": 0.3},
	"glasses": {"male": 0.15, "female": 0.18, "other": 0.15},
	"hair": {"male": 0.9, "female": 0.98, "other": 0.95},
	"mustache": {"male": 0.3, "female": 0.0, "other": 0.1},
	"beard": {"male": 0.25, "female": 0.0, "other": 0.1},
}
const CORE_PARTS: PackedStringArray = ["body", "hands", "ears", "cloths", "head", "nose", "mouth", "eyes", "eyebrows"]
const EXTRA_CHANCE := 0.5
const MUSTACHE_WITH_BEARD_CHANCE := 0.6


## overrides keys (all optional): "gender" (StringName), "parts" (Dictionary), "skin_color", "hair_color".
## avoid: signatures (NpcAppearance.signature()) of NPCs already in the bar; a different combination is preferred.
static func generate(
	overrides: Dictionary = {},
	avoid: PackedStringArray = PackedStringArray(),
	rng: RandomNumberGenerator = null
) -> NpcAppearance:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var result := NpcAppearance.new()
	result.gender = StringName(overrides["gender"]) if overrides.has("gender") else _roll_gender(rng)
	var forced: Dictionary = overrides.get("parts", {})
	for _attempt in MAX_UNIQUE_TRIES:
		result.parts = _roll_parts(result.gender, forced, rng)
		if not avoid.has(result.signature()):
			break
	result.skin_color = overrides["skin_color"] if overrides.has("skin_color") else random_skin(rng)
	result.hair_color = overrides["hair_color"] if overrides.has("hair_color") else random_hair(rng)
	return result


static func random_skin(rng: RandomNumberGenerator) -> Color:
	var position := rng.randf() * float(SKIN_RAMP.size() - 1)
	var index := int(position)
	var color := SKIN_RAMP[index].lerp(SKIN_RAMP[mini(index + 1, SKIN_RAMP.size() - 1)], position - float(index))
	return _jitter(color, rng, 0.012, 0.03, 0.03)


static func random_hair(rng: RandomNumberGenerator) -> Color:
	return _jitter(HAIR_COLORS[_weighted_index(HAIR_WEIGHTS, rng)], rng, 0.01, 0.05, 0.05)


static func _roll_gender(rng: RandomNumberGenerator) -> StringName:
	var options := NpcLibrary.genders()
	var weights: Array[float] = []
	for gender in options:
		weights.append(float(GENDER_WEIGHTS.get(gender, 1.0)))
	return StringName(options[_weighted_index(weights, rng)])


static func _roll_parts(gender: StringName, forced: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	# Beard first: a beard makes a mustache more likely.
	var order: Array[String] = []
	for part in NpcLibrary.part_names():
		order.append(part)
	if order.has("beard"):
		order.erase("beard")
		order.push_front("beard")
	var parts := {}
	for part in order:
		if forced.has(part):
			parts[part] = String(forced[part])
			continue
		var pool := NpcLibrary.files(part, gender)
		if pool.is_empty():
			continue
		if rng.randf() < _chance(part, gender, parts):
			parts[part] = pool[rng.randi_range(0, pool.size() - 1)]
		else:
			parts[part] = ""
	return parts


static func _chance(part: String, gender: StringName, parts: Dictionary) -> float:
	if part == "mustache" and gender != &"female" and not String(parts.get("beard", "")).is_empty():
		return MUSTACHE_WITH_BEARD_CHANCE
	if SPAWN_CHANCE.has(part):
		return float((SPAWN_CHANCE[part] as Dictionary).get(String(gender), 0.2))
	return 1.0 if CORE_PARTS.has(part) else EXTRA_CHANCE


static func _weighted_index(weights: Array[float], rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for weight in weights:
		total += weight
	var roll := rng.randf() * total
	for i in weights.size():
		roll -= weights[i]
		if roll < 0.0:
			return i
	return weights.size() - 1


static func _jitter(color: Color, rng: RandomNumberGenerator, hue: float, saturation: float, value: float) -> Color:
	var result := color
	result.h = wrapf(color.h + rng.randf_range(-hue, hue), 0.0, 1.0)
	result.s = clampf(color.s + rng.randf_range(-saturation, saturation), 0.0, 1.0)
	result.v = clampf(color.v + rng.randf_range(-value, value), 0.0, 1.0)
	return result
