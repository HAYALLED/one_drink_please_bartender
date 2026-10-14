class_name Bottle
extends Node2D

# A drink bottle that lives on the shelf (child of a PourStation). The hand carries it
# by the neck (node origin = grip) and tilts it while the "pour" action is held.

const HOME_OFFSET := Vector2(0.0, -38.0)
const MOUTH := Vector2(0.0, -10.0)
const HOLD_OFFSET := Vector2(0.0, 1.0)
const FOLLOW := 28.0
const MAX_TILT := 1.95
const TILT_IN := 2.6
const TILT_OUT := 4.0
const FLOW_START := 0.45
const RETURN_TIME := 0.22
const WORLD_MASK := 1
const RAY_LENGTH := 420.0
const SPLASH_RATE := 60.0
const OUTLINE := Color(0.05, 0.04, 0.06)
const LABEL := Color("e9dfc8")
const BODY := [
	Vector2(-2, -7), Vector2(2, -7), Vector2(2, 4), Vector2(7, 10), Vector2(7, 36),
	Vector2(6, 38), Vector2(-6, 38), Vector2(-7, 36), Vector2(-7, 10), Vector2(-2, 4),
]

var drink_id: StringName = &"beer"
var tilt := 0.0

var _hand: Node2D = null
var _dir := 1.0
var _flow := 0.0
var _target: Glass = null
var _end_y := 0.0
var _tween: Tween = null
var _fx := DropFx.new()
var _splash_budget := 0.0


func _ready() -> void:
	top_level = true
	set_physics_process(false)
	reset()


func setup(id: StringName) -> void:
	drink_id = id
	queue_redraw()


func home_position() -> Vector2:
	return (get_parent() as Node2D).global_position + HOME_OFFSET


func is_held() -> bool:
	return _hand != null


func pick_up(hand: Node2D) -> void:
	_kill_tween()
	_hand = hand
	set_physics_process(true)


func put_back() -> void:
	if _hand == null:
		return
	_hand = null
	_flow = 0.0
	_target = null
	_fx.clear()
	_kill_tween()
	var from_position := global_position
	var from_tilt := tilt
	_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_return_step.bind(from_position, from_tilt), 0.0, 1.0, RETURN_TIME)
	set_physics_process(false)


# Instantly back on the shelf (used when the bar closes).
func reset() -> void:
	_kill_tween()
	_hand = null
	_flow = 0.0
	_target = null
	_fx.clear()
	tilt = 0.0
	set_physics_process(false)
	global_position = home_position()
	rotation = 0.0
	queue_redraw()


func mouth_position() -> Vector2:
	return to_global(MOUTH)


func _return_step(t: float, from_position: Vector2, from_tilt: float) -> void:
	global_position = from_position.lerp(home_position(), t)
	tilt = lerpf(from_tilt, 0.0, t)
	_apply_rotation()
	queue_redraw()


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _apply_rotation() -> void:
	rotation = _dir * smoothstep(0.0, 1.0, tilt) * MAX_TILT


func _physics_process(delta: float) -> void:
	if _hand == null:
		return
	var follow_to := _hand.global_position + HOLD_OFFSET
	global_position = global_position.lerp(follow_to, 1.0 - exp(-FOLLOW * delta))
	var pouring := Input.is_action_pressed(&"pour")
	if pouring and tilt <= 0.001:
		_dir = _pour_direction()
	tilt = move_toward(tilt, 1.0 if pouring else 0.0, (TILT_IN if pouring else TILT_OUT) * delta)
	_apply_rotation()
	_pour(delta)
	queue_redraw()


# Tilt toward the nearest glass so the mouth swings over it.
func _pour_direction() -> float:
	var best := _dir
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(&"glasses"):
		var glass := node as Glass
		if glass == null or glass.is_queued_for_deletion():
			continue
		var mouth_center := glass.to_global(Vector2((glass.style.opening.x + glass.style.opening.y) * 0.5, glass.style.rim_y))
		var distance := absf(mouth_center.x - global_position.x)
		if distance < best_distance and distance > 0.5:
			best_distance = distance
			best = signf(mouth_center.x - global_position.x)
	return best


func _pour(delta: float) -> void:
	_flow = smoothstep(FLOW_START, 1.0, tilt)
	_target = null
	if _flow <= 0.01:
		_fx.step(delta, INF)
		return
	var drink := DrinkDB.get_drink(drink_id)
	var mouth := mouth_position()
	_end_y = _find_landing(mouth)
	if _target != null:
		_target.receive_stream(drink, drink.pour_rate * _flow * delta, mouth)
	else:
		_splash(mouth.x, drink.color, delta)
	_fx.step(delta, _end_y)


# Sets _target when the stream enters a glass; returns the world y where the stream ends.
func _find_landing(mouth: Vector2) -> float:
	var end_y := mouth.y + RAY_LENGTH
	var query := PhysicsRayQueryParameters2D.create(mouth, mouth + Vector2(0.0, RAY_LENGTH), WORLD_MASK)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		end_y = (hit["position"] as Vector2).y
	for node in get_tree().get_nodes_in_group(&"glasses"):
		var glass := node as Glass
		if glass == null or glass.is_queued_for_deletion():
			continue
		if glass.opening_contains(mouth):
			var rim_world_y := glass.to_global(Vector2(glass.to_local(mouth).x, glass.style.rim_y)).y
			if rim_world_y < end_y:
				_target = glass
				end_y = maxf(rim_world_y, mouth.y)
		elif glass.body_contains_x(mouth):
			var top_world_y := glass.to_global(Vector2(glass.to_local(mouth).x, glass.style.top_y())).y
			if top_world_y < end_y:
				_target = null
				end_y = top_world_y
	return end_y


func _splash(x: float, color: Color, delta: float) -> void:
	_splash_budget += SPLASH_RATE * _flow * delta
	while _splash_budget >= 1.0:
		_splash_budget -= 1.0
		var side := 1.0 if randf() < 0.5 else -1.0
		_fx.emit(Vector2(x, _end_y - 1.0), Vector2(side * randf_range(8.0, 34.0), randf_range(-70.0, -25.0)), color, 0.6)


func _draw() -> void:
	var drink := DrinkDB.get_drink(drink_id)
	var base := drink.color if drink != null else Color.WHITE
	var glass_color := base.darkened(0.3)
	var points := PackedVector2Array(BODY)
	draw_colored_polygon(points, glass_color)
	draw_rect(Rect2(-5.0, 12.0, 2.0, 22.0), Color(1, 1, 1, 0.25))
	draw_rect(Rect2(-6.0, 18.0, 12.0, 11.0), LABEL)
	draw_rect(Rect2(-6.0, 22.0, 12.0, 3.0), base)
	var outline := PackedVector2Array(BODY)
	outline.append(BODY[0])
	draw_polyline(outline, OUTLINE, 1.0)
	draw_rect(Rect2(-3.0, -10.0, 6.0, 4.0), base.darkened(0.6))
	draw_rect(Rect2(-3.0, -10.0, 6.0, 4.0), OUTLINE, false, 1.0)

	if _flow <= 0.01 and _fx.is_empty():
		return
	draw_set_transform_matrix(get_global_transform().affine_inverse())
	if _flow > 0.01 and drink != null:
		var mouth := mouth_position()
		var length := _end_y - mouth.y
		if length > 0.5:
			var width := 3.0 if _flow > 0.75 else 2.0
			draw_rect(Rect2(floorf(mouth.x - width * 0.5), mouth.y, width, length), drink.color)
	_fx.draw(self)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _exit_tree() -> void:
	_kill_tween()
