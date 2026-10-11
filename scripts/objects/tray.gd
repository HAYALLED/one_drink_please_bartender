class_name Tray
extends AnimatableBody2D

@export var balance_enabled := false
@export var instability := 3.2
@export var control_power := 10.0
@export var angular_drag := 2.4
@export var glass_torque_gain := 0.012
@export var idle_sway := 0.8
@export var walk_sway := 1.8
@export var max_angle := 0.7

var angle := 0.0
var angular_velocity := 0.0
var walk_factor := 0.0

var _time := 0.0
var _phase_a := randf() * TAU
var _phase_b := randf() * TAU

@onready var surface: Area2D = $Surface


func _physics_process(delta: float) -> void:
	if balance_enabled:
		_simulate(delta)
	else:
		angle = lerpf(angle, 0.0, 1.0 - exp(-8.0 * delta))
		angular_velocity = 0.0
	rotation = angle


func get_glasses() -> Array[Glass]:
	var result: Array[Glass] = []
	for body in surface.get_overlapping_bodies():
		var glass := body as Glass
		if glass != null and glass.held_by == null and not glass.is_queued_for_deletion():
			result.append(glass)
	return result


func glass_count() -> int:
	return get_glasses().size()


func _simulate(delta: float) -> void:
	_time += delta
	var input := Input.get_axis(&"tray_left", &"tray_right")
	var torque := angle * instability
	torque += _glass_torque() * glass_torque_gain
	torque += _sway()
	torque += input * control_power
	torque -= angular_velocity * angular_drag
	angular_velocity += torque * delta
	angle += angular_velocity * delta
	if absf(angle) > max_angle:
		angle = clampf(angle, -max_angle, max_angle)
		angular_velocity = 0.0


func _glass_torque() -> float:
	var sum := 0.0
	for glass in get_glasses():
		sum += to_local(glass.global_position).x * glass.mass
	return sum


func _sway() -> float:
	var amplitude := idle_sway + walk_sway * walk_factor
	return amplitude * (sin(_time * 1.7 + _phase_a) * 0.6 + sin(_time * 3.1 + _phase_b) * 0.4)
