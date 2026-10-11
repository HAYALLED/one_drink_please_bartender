class_name LiquidVisual
extends Node2D

const SPILL_RATE := 1.6
const TIP_ANGLE := 1.25

@export var inner_size := Vector2(12.0, 20.0)
@export var bottom_y := 10.0
@export var stiffness := 110.0
@export var damping := 4.5
@export var accel_gain := 0.00018
@export var max_tilt := 0.85

var tilt := 0.0
var tilt_velocity := 0.0

var _glass: Glass
var _last_position := Vector2.ZERO
var _last_velocity := Vector2.ZERO
var _accel := Vector2.ZERO


func _ready() -> void:
	_glass = get_parent() as Glass
	if _glass != null:
		_last_position = _glass.global_position


func _physics_process(delta: float) -> void:
	if _glass == null or delta <= 0.0:
		return
	var pos := _glass.global_position
	var vel := (pos - _last_position) / delta
	var acc := (vel - _last_velocity) / delta
	_last_position = pos
	_last_velocity = vel
	_accel = _accel.lerp(acc, 1.0 - exp(-30.0 * delta))

	var target := -wrapf(_glass.global_rotation, -PI, PI) + clampf(_accel.x * accel_gain, -max_tilt, max_tilt)
	target = clampf(target, -max_tilt, max_tilt)
	tilt_velocity += ((target - tilt) * stiffness - tilt_velocity * damping) * delta
	tilt = clampf(tilt + tilt_velocity * delta, -max_tilt, max_tilt)

	_check_spill(delta)
	queue_redraw()


func _check_spill(delta: float) -> void:
	if _glass.fill <= 0.02:
		return
	if absf(wrapf(_glass.global_rotation, -PI, PI)) > TIP_ANGLE:
		_glass.spill(SPILL_RATE * delta)
		return
	var level_px := inner_size.y * _glass.fill
	var edge_rise := absf(tan(tilt)) * inner_size.x * 0.5
	var over := level_px + edge_rise - inner_size.y
	if over > 0.0:
		_glass.spill(minf(over / inner_size.y, 1.0) * SPILL_RATE * delta)


func _draw() -> void:
	if _glass == null:
		return
	var drink := DrinkDB.get_drink(_glass.drink_id)
	var half := inner_size.x * 0.5
	var bottom := bottom_y
	var top := bottom - inner_size.y

	if drink != null:
		var tick_y := bottom - inner_size.y * drink.target_fill
		draw_line(Vector2(half, tick_y), Vector2(half + 2.0, tick_y), Color(1, 1, 1, 0.6), 1.0)

	if _glass.fill <= 0.001:
		return
	var color := Color(0.45, 0.35, 0.3) if _glass.contaminated else (drink.color if drink != null else Color.WHITE)
	var level_y := bottom - inner_size.y * _glass.fill
	var slope := tan(tilt)
	var yl := clampf(level_y - slope * half, top, bottom)
	var yr := clampf(level_y + slope * half, top, bottom)
	if (bottom - yl) + (bottom - yr) < 0.3:
		return
	draw_colored_polygon(
		PackedVector2Array([Vector2(-half, yl), Vector2(half, yr), Vector2(half, bottom), Vector2(-half, bottom)]),
		color
	)
	draw_line(Vector2(-half, yl), Vector2(half, yr), color.lightened(0.3), 1.0)

	if drink != null and not _glass.contaminated and drink.foam_px > 0.0:
		var fl := maxf(yl - drink.foam_px, top)
		var fr := maxf(yr - drink.foam_px, top)
		if (yl - fl) + (yr - fr) > 0.3:
			draw_colored_polygon(
				PackedVector2Array([Vector2(-half, fl), Vector2(half, fr), Vector2(half, yr), Vector2(-half, yl)]),
				drink.foam_color
			)
