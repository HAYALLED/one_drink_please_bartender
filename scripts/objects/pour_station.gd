class_name PourStation
extends Area2D

@export var drink_id: StringName = &"beer"

var _pouring := false
var _target: Glass = null

@onready var pour_area: Area2D = $PourArea
@onready var name_label: Label = $NameLabel


func _ready() -> void:
	var drink := DrinkDB.get_drink(drink_id)
	name_label.text = drink.name_text() if drink != null else String(drink_id)
	if drink != null:
		$Bottle.color = drink.color


func press(_hand: Node) -> void:
	_pouring = true


func release(_hand: Node) -> void:
	_pouring = false
	_target = null
	queue_redraw()


func set_available(on: bool) -> void:
	visible = on
	set_deferred("monitorable", on)
	if not on:
		_pouring = false
		_target = null


func _physics_process(delta: float) -> void:
	if not _pouring:
		return
	_target = _find_glass()
	if _target != null:
		var drink := DrinkDB.get_drink(drink_id)
		_target.pour(drink, drink.pour_rate * delta)
	queue_redraw()


func _find_glass() -> Glass:
	var best: Glass = null
	var best_offset := INF
	for body in pour_area.get_overlapping_bodies():
		var glass := body as Glass
		if glass == null or glass.held_by != null or glass.is_queued_for_deletion():
			continue
		var offset := absf(glass.global_position.x - global_position.x)
		if offset < best_offset:
			best = glass
			best_offset = offset
	return best


func _draw() -> void:
	if not _pouring or _target == null:
		return
	var drink := DrinkDB.get_drink(drink_id)
	var length := _target.global_position.y - Glass.SIZE.y * 0.5 - global_position.y
	if length > 0.0:
		draw_rect(Rect2(-1.0, 0.0, 2.0, length), Color(drink.color, 0.9))
