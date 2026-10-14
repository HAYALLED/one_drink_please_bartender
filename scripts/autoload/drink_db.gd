extends Node

var _drinks: Dictionary = {}
var _ids: Array[StringName] = []


# Prices and unlock costs are in bronze (100 bronze = 1 silver, 100 silver = 1 gold).
func _init() -> void:
	_add(&"beer", 303, Color("d9962b"), 0.8, 0.5, 0, {
		"foam_color": Color("fff3d1"), "foam_px": 3.0, "alcohol": 0.15, "glass": &"mug", "penalty": 0.4,
	})
	_add(&"water", 6, Color("8fd3ff"), 0.8, 0.7, 0, {"penalty": 0.0})
	_add(&"wine", 455, Color("7a1632"), 0.6, 0.45, 3800, {"alcohol": 0.2, "glass": &"wine_glass", "penalty": 0.15})
	_add(&"vodka", 380, Color("d9e2f2"), 0.7, 0.6, 4900, {"alcohol": 0.35, "glass": &"shot", "penalty": 0.1})
	_add(&"cider", 341, Color("e8cf5a"), 0.8, 0.5, 4600, {
		"foam_color": Color("fffbe0"), "foam_px": 2.0, "alcohol": 0.12, "glass": &"mug", "penalty": 0.2,
	})
	_add(&"whiskey", 606, Color("a8571a"), 0.5, 0.45, 5700, {"alcohol": 0.3, "glass": &"tumbler", "penalty": 0.15})
	_add(&"rum", 568, Color("6b2e12"), 0.5, 0.45, 7600, {"alcohol": 0.3, "glass": &"tumbler", "penalty": 0.15})


func _add(
	id: StringName,
	price: int,
	color: Color,
	target_fill: float,
	pour_rate: float,
	unlock_cost: int,
	extra: Dictionary = {}
) -> void:
	var drink := DrinkData.new()
	drink.id = id
	drink.price = price
	drink.color = color
	drink.target_fill = target_fill
	drink.pour_rate = pour_rate
	drink.unlock_cost = unlock_cost
	drink.foam_color = extra.get("foam_color", Color.WHITE) as Color
	drink.foam_px = float(extra.get("foam_px", 0.0))
	drink.alcohol = float(extra.get("alcohol", 0.0))
	drink.preferred_glass = StringName(extra.get("glass", &"glass"))
	drink.wrong_glass_penalty = float(extra.get("penalty", 0.15))
	_drinks[id] = drink
	_ids.append(id)


func get_drink(id: StringName) -> DrinkData:
	return _drinks.get(id) as DrinkData


func ids() -> Array[StringName]:
	return _ids


func default_unlocked() -> Array[StringName]:
	var result: Array[StringName] = []
	for id in _ids:
		if (_drinks[id] as DrinkData).unlock_cost == 0:
			result.append(id)
	return result