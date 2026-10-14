class_name DropFx
extends RefCounted

# Tiny pixel droplet simulation (world space). The owner calls step() every physics
# frame and draw() from its _draw() with a transform that maps world space to local.

const GRAVITY := 430.0
const MAX_DROPS := 80
const DROP_SIZE := Vector2(2.0, 2.0)


class Drop:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var color := Color.WHITE
	var life := 1.0


var _drops: Array[Drop] = []


func emit(pos: Vector2, vel: Vector2, color: Color, life: float = 1.0) -> void:
	if _drops.size() >= MAX_DROPS:
		return
	var drop := Drop.new()
	drop.pos = pos
	drop.vel = vel
	drop.color = color
	drop.life = life
	_drops.append(drop)


func step(delta: float, floor_y: float = INF) -> void:
	var i := _drops.size() - 1
	while i >= 0:
		var drop := _drops[i]
		drop.life -= delta
		drop.vel.y += GRAVITY * delta
		drop.pos += drop.vel * delta
		if drop.life <= 0.0 or (drop.pos.y >= floor_y and drop.vel.y > 0.0):
			_drops.remove_at(i)
		i -= 1


func draw(canvas: CanvasItem) -> void:
	for drop in _drops:
		canvas.draw_rect(Rect2(drop.pos.floor(), DROP_SIZE), drop.color)


func clear() -> void:
	_drops.clear()


func is_empty() -> bool:
	return _drops.is_empty()
