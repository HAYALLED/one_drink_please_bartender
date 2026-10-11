class_name Hand
extends CharacterBody2D

const SKIN := Color("e8b98a")

@export var max_speed := 650.0
@export var push_strength := 70.0
@export var shoulder := Vector2(320.0, 420.0)
@export var bounds := Rect2(0.0, 0.0, 640.0, 360.0)

var held: Glass = null
var enabled := false

var _active_interactable: Area2D = null
var _prev_position := Vector2.ZERO
var _velocity_estimate := Vector2.ZERO

@onready var palm: CollisionShape2D = $Palm
@onready var grab_point: Area2D = $GrabPoint


func _ready() -> void:
	set_enabled(false)


func set_enabled(value: bool, at: Vector2 = Vector2.INF) -> void:
	if not value:
		force_release()
	enabled = value
	visible = value
	palm.set_deferred("disabled", not value)
	grab_point.set_deferred("monitoring", value)
	set_physics_process(value)
	if value and at != Vector2.INF:
		global_position = at
		_prev_position = at
		_velocity_estimate = Vector2.ZERO


func force_release() -> void:
	_let_go(false)


func _physics_process(delta: float) -> void:
	_move(delta)
	_velocity_estimate = _velocity_estimate.lerp((global_position - _prev_position) / delta, 0.35)
	_prev_position = global_position
	if Input.is_action_just_pressed(&"grab"):
		_press()
	elif Input.is_action_just_released(&"grab"):
		_let_go(true)
	if Input.is_action_just_pressed(&"kick_out"):
		_kick()
	queue_redraw()


func _move(delta: float) -> void:
	var target := get_global_mouse_position().clamp(bounds.position, bounds.end)
	var motion := target - global_position
	var max_step := max_speed * delta
	if motion.length() > max_step:
		motion = motion.normalized() * max_step
	var collision := move_and_collide(motion)
	if collision == null:
		return
	var body := collision.get_collider()
	if body is RigidBody2D:
		var speed_ratio := clampf(motion.length() / max_step, 0.2, 1.0)
		(body as RigidBody2D).apply_central_impulse(-collision.get_normal() * push_strength * speed_ratio)
	var slide := collision.get_remainder().slide(collision.get_normal())
	if slide.length_squared() > 0.0001:
		move_and_collide(slide)


func _press() -> void:
	var glass := _nearest_grabbable()
	if glass != null:
		held = glass
		add_collision_exception_with(glass)
		glass.hold(self)
		return
	for area in grab_point.get_overlapping_areas():
		if area.is_in_group(&"interactable") and area.has_method(&"press"):
			_active_interactable = area
			area.call(&"press", self)
			return


func _let_go(allow_serve: bool) -> void:
	if held != null:
		var glass := held
		held = null
		remove_collision_exception_with(glass)
		if allow_serve:
			for area in grab_point.get_overlapping_areas():
				if area.is_in_group(&"serve_zone") and area.has_method(&"accept_glass"):
					if area.call(&"accept_glass", glass):
						return
		glass.release(_velocity_estimate)
	if _active_interactable != null:
		if is_instance_valid(_active_interactable):
			_active_interactable.call(&"release", self)
		_active_interactable = null


func _kick() -> void:
	for area in grab_point.get_overlapping_areas():
		if area.is_in_group(&"customer_slot") and area.has_method(&"kick"):
			area.call(&"kick")
			return


func _nearest_grabbable() -> Glass:
	var best: Glass = null
	var best_distance := INF
	for area in grab_point.get_overlapping_areas():
		if not area.is_in_group(&"glass_grab"):
			continue
		var glass := area.get_parent() as Glass
		if glass == null or glass.held_by != null or glass.is_queued_for_deletion():
			continue
		var distance := glass.global_position.distance_squared_to(grab_point.global_position)
		if distance < best_distance:
			best = glass
			best_distance = distance
	return best


func _draw() -> void:
	draw_line(to_local(shoulder), Vector2(0.0, -2.0), SKIN.darkened(0.15), 5.0)
	draw_rect(Rect2(-5.0, -3.0, 10.0, 6.0), SKIN)
	for i in 4:
		draw_rect(Rect2(-5.0 + i * 2.6, 3.0, 2.0, 3.0), SKIN)
