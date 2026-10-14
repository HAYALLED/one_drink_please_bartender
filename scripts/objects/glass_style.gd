class_name GlassStyle
extends RefCounted

# Liquid + logic geometry of a glass type. All numbers are glass-local pixels (node origin = 0,0).
# Liquid rows are inclusive and index span_left / span_right.
# Look and collision shapes are NOT here: they live in the glass scene (glass.tscn, beer_mug.tscn).
# body_size / body_center must match the scene's CollisionShape2D.

# Sprite pixel that sits on the node origin.
const MUG_ORIGIN := Vector2i(27, 37)
# Sprite rows: [from_row, to_row, left_col, right_col] of the inside of the mug.
# Row 26 is the top band (dcd9d9 between the black lines) = full level.
const MUG_FIRST_ROW := 22
const MUG_FULL_ROW := 26
const MUG_FLOOR_ROW := 59
const MUG_SEGMENTS := [
	[22, 22, 19, 44], [23, 23, 20, 43], [24, 24, 21, 42], [25, 28, 19, 44],
	[29, 35, 18, 45], [36, 52, 19, 44], [53, 57, 20, 43], [58, 58, 21, 42],
]

# Plain (polygon) glasses. "edges" = [from_row, to_row, e] segments: the glass wall sits at x = -e / +e in those rows,
# so the liquid covers columns -(e-1) .. e-2. rim_edge = e at the rim (the mouth). All rows are glass-local.
# body = size of the scene's CollisionShape2D, which has to match.
const SHAPES := {
	&"glass": {
		"body": Vector2(14.0, 22.0), "first_row": -10, "full_y": -10, "bottom_y": 10, "rim_y": -11.0,
		"rim_edge": 7, "edges": [[-10, 9, 7]],
	},
	&"wine_glass": {
		"body": Vector2(14.0, 28.0), "first_row": -13, "full_y": -13, "bottom_y": 1, "rim_y": -14.0,
		"rim_edge": 6, "edges": [[-13, -13, 6], [-12, -6, 7], [-5, -3, 6], [-2, -2, 5], [-1, -1, 4], [0, 0, 3]],
	},
	&"tumbler": {
		"body": Vector2(18.0, 16.0), "first_row": -7, "full_y": -7, "bottom_y": 6, "rim_y": -8.0,
		"rim_edge": 9, "edges": [[-7, -1, 9], [0, 5, 8]],
	},
	&"shot": {
		"body": Vector2(12.0, 16.0), "first_row": -7, "full_y": -7, "bottom_y": 6, "rim_y": -8.0,
		"rim_edge": 6, "edges": [[-7, -1, 6], [0, 5, 5]],
	},
}

static var _cache: Dictionary = {}

var body_size := Vector2(14.0, 22.0)
var body_center := Vector2.ZERO
var first_row := -10
var full_y := -10
var bottom_y := 10
var span_left := PackedInt32Array()
var span_right := PackedInt32Array()
var opening := Vector2(-6.0, 6.0)
var rim_y := -11.0
var wall_edges := Vector2(-8.0, 7.0)
var tick_x := 8.0
var center_x := 0.0


static func for_type(type: StringName) -> GlassStyle:
	if not _cache.has(type):
		_cache[type] = _make_mug() if type == &"mug" else _make_plain(type)
	return _cache[type] as GlassStyle


func liquid_size() -> Vector2:
	return Vector2(opening.y - opening.x, float(bottom_y - full_y))


func last_row() -> int:
	return first_row + span_left.size() - 1


func top_y() -> float:
	return body_center.y - body_size.y * 0.5


static func _make_plain(type: StringName) -> GlassStyle:
	var shape: Dictionary = SHAPES.get(type, SHAPES[&"glass"])
	var style := GlassStyle.new()
	style.body_size = shape["body"] as Vector2
	style.first_row = int(shape["first_row"])
	style.full_y = int(shape["full_y"])
	style.bottom_y = int(shape["bottom_y"])
	style.rim_y = float(shape["rim_y"])
	var widest := 0
	for segment: Array in shape["edges"]:
		var wall := int(segment[2])
		widest = maxi(widest, wall)
		for row in range(int(segment[0]), int(segment[1]) + 1):
			style.span_left.append(-(wall - 1))
			style.span_right.append(wall - 2)
	var rim_edge := int(shape["rim_edge"])
	style.opening = Vector2(-(rim_edge - 1), rim_edge - 1)
	style.wall_edges = Vector2(-widest - 1, widest)
	style.tick_x = float(widest + 1)
	style.center_x = 0.0
	return style


static func _make_mug() -> GlassStyle:
	var style := GlassStyle.new()
	var origin := Vector2(MUG_ORIGIN)
	style.body_size = Vector2(47.0, 51.0)
	style.body_center = Vector2(0.5, 0.5)
	style.first_row = MUG_FIRST_ROW - MUG_ORIGIN.y
	style.full_y = MUG_FULL_ROW - MUG_ORIGIN.y
	style.bottom_y = MUG_FLOOR_ROW - MUG_ORIGIN.y
	for segment in MUG_SEGMENTS:
		for row in range(int(segment[0]), int(segment[1]) + 1):
			style.span_left.append(int(segment[2]) - MUG_ORIGIN.x)
			style.span_right.append(int(segment[3]) - MUG_ORIGIN.x)
	style.opening = Vector2(18.0 - origin.x - 0.0, 46.0 - origin.x)
	style.rim_y = 19.0 - origin.y
	style.wall_edges = Vector2(14.0 - origin.x, 49.0 - origin.x)
	style.tick_x = 51.0 - origin.x
	style.center_x = 32.0 - origin.x
	return style