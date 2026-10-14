class_name PourStation
extends Area2D

# Shelf slot holding one drink bottle. Pressing it picks the bottle up (hand holds it
# while the grab button is down); releasing sends it back to the shelf.

@export var drink_id: StringName = &"beer"

@onready var bottle: Bottle = $Bottle
@onready var name_label: Label = $NameLabel


func _ready() -> void:
	var drink := DrinkDB.get_drink(drink_id)
	name_label.text = drink.name_text() if drink != null else String(drink_id)
	bottle.setup(drink_id)


func press(hand: Node) -> void:
	bottle.pick_up(hand as Node2D)


func release(_hand: Node) -> void:
	bottle.put_back()


func set_available(on: bool) -> void:
	visible = on
	set_deferred("monitorable", on)
	if not on:
		bottle.reset()
