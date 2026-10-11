class_name Glass
extends RigidBody2D

signal shattered(glass: Glass)

const SIZE := Vector2(14.0, 22.0)
const EMPTY_MASS := 0.6
const LIQUID_MASS := 0.9
const KILL_Y := 420.0
const HOLD_FOLLOW := 30.0
const MAX_FILL := 1.0

var glass_type: StringName = &"glass"
var drink_id: StringName = &""
var fill := 0.0
var contaminated := false
var spilled := 0.0
var held_by: Node2D = null

var _dead := false


func _ready() -> void:
	_update_mass()
	var info: Dictionary = GameState.GLASS_TYPES.get(glass_type, {})
	if info.has("tint"):
		$Body.color = info["tint"] as Color


func _physics_process(delta: float) -> void:
	if held_by != null:
		var target := held_by.global_position + Vector2(0.0, SIZE.y * 0.4)
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


func spill(amount: float) -> void:
	var lost := minf(amount, fill)
	fill -= lost
	spilled += lost
	_update_mass()


func hold(by: Node2D) -> void:
	held_by = by
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
	glass_type = StringName(data.get("type", "glass"))
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
