class_name LiquidVisual
extends Node2D

const SPILL_RATE := 1.6
const TIP_ANGLE := 1.25
const SURFACE_LIGHTEN := 0.3
const FLAT_SLOPE := 0.0005
const STREAK_MAX := 26.0
const STREAK_STEP := 3.0
const STREAK_FADE := 18.0
const DROPS_PER_FILL := 90.0
const CONTAMINATED_COLOR := Color(0.45, 0.35, 0.3)

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
var _last_spilled := 0.0
var _drop_budget := 0.0
var _streaks := [0.0, 0.0]
var _fx := DropFx.new()


func _ready() -> void:
	_glass = get_parent() as Glass
	if _glass != null:
		_last_position = _glass.global_position
		_last_spilled = _glass.spilled


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
	_update_overflow(delta)
	queue_redraw()


func _check_spill(delta: float) -> void:
	if _glass.fill <= 0.02:
		return
	if absf(wrapf(_glass.global_rotation, -PI, PI)) > TIP_ANGLE:
		_glass.spill(SPILL_RATE * delta)
		return
	var size := _glass.style.liquid_size()
	var level_px := size.y * _glass.fill
	var edge_rise := absf(tan(tilt)) * size.x * 0.5
	var over := level_px + edge_rise - size.y
	if over > 0.0:
		_glass.spill(minf(over / size.y, 1.0) * SPILL_RATE * delta)


# Anything that leaves the glass (overpour or sloshing) runs down the outside and drips.
func _update_overflow(delta: float) -> void:
	var style := _glass.style
	var lost := _glass.spilled - _last_spilled
	_last_spilled = _glass.spilled
	var color := _liquid_color(DrinkDB.get_drink(_glass.drink_id))
	if lost > 0.0:
		_drop_budget += lost * DROPS_PER_FILL
	while _drop_budget >= 1.0:
		_drop_budget -= 1.0
		var side := -signf(tilt) if absf(tilt) > 0.06 else (1.0 if randf() < 0.5 else -1.0)
		var index := 1 if side > 0.0 else 0
		_streaks[index] = minf(_streaks[index] + STREAK_STEP, STREAK_MAX)
		var edge_x := style.wall_edges.y if index == 1 else style.wall_edges.x
		var tip := to_global(Vector2(edge_x + 0.5, float(style.first_row) + _streaks[index]))
		_fx.emit(tip, Vector2(side * randf_range(6.0, 26.0), randf_range(-30.0, 5.0)), color, 1.2)
	for i in 2:
		_streaks[i] = maxf(_streaks[i] - STREAK_FADE * delta, 0.0)
	var floor_y := _glass.global_position.y + style.body_center.y + style.body_size.y * 0.5
	_fx.step(delta, floor_y)


func _liquid_color(drink: DrinkData) -> Color:
	if _glass.contaminated:
		return CONTAMINATED_COLOR
	return drink.color if drink != null else Color.WHITE


func _draw() -> void:
	if _glass == null:
		return
	var style := _glass.style
	var drink := DrinkDB.get_drink(_glass.drink_id)
	var color := _liquid_color(drink)
	var span := float(style.bottom_y - style.full_y)
	var level := float(style.bottom_y) - span * _glass.fill

	if drink != null:
		var tick_y := roundf(float(style.bottom_y) - span * drink.target_fill)
		draw_rect(Rect2(style.tick_x, tick_y, 3.0, 1.0), Color(1, 1, 1, 0.6))
	_draw_streaks(style, color)
	_draw_liquid(style, drink, color, level)
	_draw_stream(style, level)
	draw_set_transform_matrix(get_global_transform().affine_inverse())
	_fx.draw(self)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_streaks(style: GlassStyle, color: Color) -> void:
	for i in 2:
		var length := floorf(_streaks[i])
		if length < 1.0:
			continue
		var edge_x := style.wall_edges.y if i == 1 else style.wall_edges.x
		draw_rect(Rect2(floorf(edge_x), float(style.first_row), 1.0, length), color)


func _draw_stream(style: GlassStyle, level: float) -> void:
	if _glass.stream_time <= 0.0:
		return
	var surface := level + tan(tilt) * (_glass.stream_x - style.center_x)
	var bottom := clampf(surface, _glass.stream_top, float(style.bottom_y))
	if bottom - _glass.stream_top < 0.5:
		return
	draw_rect(Rect2(floorf(_glass.stream_x - 1.0), _glass.stream_top, 2.0, bottom - _glass.stream_top), _glass.stream_color)


# Pixel-art liquid: one run per row for body, surface line and foam.
func _draw_liquid(style: GlassStyle, drink: DrinkData, color: Color, level: float) -> void:
	if _glass.fill <= 0.001:
		return
	var slope := tan(tilt)
	var suffix := slope < -FLAT_SLOPE
	var foam_px := 0.0
	var foam_color := Color.WHITE
	if drink != null and not _glass.contaminated:
		foam_px = drink.foam_px
		foam_color = drink.foam_color
	var surface_color := color.lightened(SURFACE_LIGHTEN)
	var half_width := style.liquid_size().x * 0.5
	var start_row := maxi(style.first_row, floori(level - foam_px - absf(slope) * half_width))
	for row in range(start_row, style.last_row() + 1):
		var index := row - style.first_row
		var left := style.span_left[index]
		var right := style.span_right[index]
		var yc := float(row) + 0.5
		var body := _cols(yc, 1.0, level, slope, style.center_x, left, right)
		var top := _cols(yc, 0.0, level, slope, style.center_x, left, right)
		_fill_run(row, body, color)
		_fill_run(row, _run_between(top, body, suffix), surface_color)
		if foam_px > 0.0:
			var foam := _cols(yc, -foam_px, level, slope, style.center_x, left, right)
			_fill_run(row, _run_between(foam, top, suffix), foam_color)


# Inclusive columns [x, y] of this row lying at or below the (tilted) line level + offset.
# Flat or right-lowering lines yield a prefix of the span, left-lowering lines a suffix.
func _cols(yc: float, offset: float, level: float, slope: float, cx: float, left: int, right: int) -> Vector2i:
	var base := yc - level - offset
	if absf(slope) < FLAT_SLOPE:
		return Vector2i(left, right) if base >= 0.0 else Vector2i(left, left - 1)
	var edge := cx + base / slope
	if slope > 0.0:
		return Vector2i(left, clampi(floori(edge - 0.5), left - 1, right))
	return Vector2i(clampi(ceili(edge - 0.5), left, right + 1), right)


# Columns inside `outer` but not inside `inner` (inner is nested in outer).
func _run_between(outer: Vector2i, inner: Vector2i, suffix: bool) -> Vector2i:
	if suffix:
		return Vector2i(outer.x, inner.x - 1)
	return Vector2i(inner.y + 1, outer.y)


func _fill_run(row: int, run: Vector2i, color: Color) -> void:
	if run.x <= run.y:
		draw_rect(Rect2(float(run.x), float(row), float(run.y - run.x + 1), 1.0), color)
