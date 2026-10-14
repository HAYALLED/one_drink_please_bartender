class_name Glass
extends RigidBody2D

signal shattered(glass: Glass)

const EMPTY_MASS := 0.6
const LIQUID_MASS := 0.9
const KILL_Y := 420.0
const HOLD_FOLLOW := 30.0
const MAX_FILL := 1.0
const STREAM_HOLD := 0.07
const OPENING_MAX_ANGLE := 0.6

# Set by the glass scene (glass.tscn = "glass", beer_mug.tscn = "mug"). Racks spawn glasses from their glass_scene.
@export var glass_type: StringName = &"glass"
var drink_id: StringName = &""
var fill := 0.0
var contaminated := false
var spilled := 0.0
var held_by: Node2D = null
var stream_x := 0.0
var stream_top := 0.0
var stream_time := 0.0
var stream_color := Color.WHITE

var style: GlassStyle:
	get:
		if _style == null:
			_style = GlassStyle.for_type(glass_type)
		return _style

var _style: GlassStyle = null
var _dead := false
var _hold_offset := Vector2.ZERO

@onready var _body: Polygon2D = get_node_or_null("Body")
@onready var _outline: Line2D = get_node_or_null("Outline")
@onready var _sprite: Sprite2D = $Sprite


func _ready() -> void:
	_update_mass()
	_apply_visuals()


# Look and collision shapes live in the glass scene. A scene with a Sprite texture shows the sprite,
# a scene without one shows the Body polygon + Outline line.
func _apply_visuals() -> void:
	var plain := _sprite.texture == null
	if _body != null:
		_body.visible = plain
	if _outline != null:
		_outline.visible = plain
	_sprite.visible = not plain


func _physics_process(delta: float) -> void:
	stream_time = maxf(stream_time - delta, 0.0)
	if held_by != null:
		var target := held_by.global_position + _hold_offset
		global_position = global_position.lerp(target, 1.0 - exp(-HOLD_FOLLOW * delta))
		global_rotation = lerp_angle(global_rotation, 0.0, 1.0 - exp(-12.0 * delta))
	if global_position.y > KILL_Y:
		shatter()


func pour(drink: DrinkData, amount: float) -> void:
	if drink_id == &"":
		drink_id = drink.id
	elif drink_id != drink.id:
		contaminated = true
	fill += amount
	if fill > MAX_FILL:
		spilled += fill - MAX_FILL
		fill = MAX_FILL
	_update_mass()


# True when a point (world space) is above the mouth of the glass so a stream would enter it.
func opening_contains(world_point: Vector2) -> bool:
	if absf(wrapf(global_rotation, -PI, PI)) > OPENING_MAX_ANGLE:
		return false
	var local_point := to_local(world_point)
	return local_point.x >= style.opening.x and local_point.x <= style.opening.y and local_point.y < style.full_y


# True when a point (world space) is above the glass but not over its mouth.
func body_contains_x(world_point: Vector2) -> bool:
	var local_point := to_local(world_point)
	var half := style.body_size.x * 0.5
	return absf(local_point.x - style.body_center.x) <= half and local_point.y < style.top_y()


func receive_stream(drink: DrinkData, amount: float, world_mouth: Vector2) -> void:
	var local_mouth := to_local(world_mouth)
	stream_x = local_mouth.x
	stream_top = maxf(local_mouth.y, style.rim_y)
	stream_time = STREAM_HOLD
	stream_color = drink.color
	pour(drink, amount)


func spill(amount: float) -> void:
	var lost := minf(amount, fill)
	fill -= lost
	spilled += lost
	_update_mass()


func hold(by: Node2D) -> void:
	held_by = by
	# Keep the spot where the hand grabbed (side or top), so the glass does not jump.
	_hold_offset = global_position - by.global_position
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	freeze = true


func release(throw_velocity: Vector2 = Vector2.ZERO) -> void:
	held_by = null
	freeze = false
	linear_velocity = throw_velocity
	angular_velocity = 0.0


func quality() -> float:
	var drink := DrinkDB.get_drink(drink_id)
	if drink == null or contaminated:
		return 0.0
	return clampf(1.0 - absf(fill - drink.target_fill) / drink.tolerance, 0.0, 1.0)


func shatter() -> void:
	if _dead:
		return
	_dead = true
	shattered.emit(self)
	queue_free()


func _update_mass() -> void:
	mass = EMPTY_MASS + LIQUID_MASS * fill


func to_dict() -> Dictionary:
	return {
		"scene": scene_file_path,
		"type": String(glass_type),
		"drink": String(drink_id),
		"fill": fill,
		"contaminated": contaminated,
		"spilled": spilled,
		"pos": [global_position.x, global_position.y],
		"rot": global_rotation,
		"vel": [linear_velocity.x, linear_velocity.y],
		"ang": angular_velocity,
	}


# Call before add_child so the liquid starts from the right position.
func apply_dict(data: Dictionary) -> void:
	if data.has("type"):
		glass_type = StringName(data["type"])
	drink_id = StringName(data.get("drink", ""))
	fill = float(data.get("fill", 0.0))
	contaminated = bool(data.get("contaminated", false))
	spilled = float(data.get("spilled", 0.0))
	var pos: Array = data.get("pos", [0.0, 0.0])
	position = Vector2(float(pos[0]), float(pos[1]))
	rotation = float(data.get("rot", 0.0))
	var vel: Array = data.get("vel", [0.0, 0.0])
	linear_velocity = Vector2(float(vel[0]), float(vel[1]))
	angular_velocity = float(data.get("ang", 0.0))