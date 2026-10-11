@tool
class_name NinePatchButton
extends Button

## dictionary.csv key. Leave empty when the text is set from code.
@export var text_key: String = "":
	set(value):
		text_key = value
		if is_inside_tree():
			_refresh_text()

@export_group("Frame tint")
@export var normal_tint := Color(0.7, 0.7, 0.8)
@export var hover_tint := Color(1.0, 1.0, 1.0)
@export var pressed_tint := Color(0.5, 0.5, 0.6)
@export var disabled_tint := Color(0.35, 0.35, 0.4, 0.8)

@onready var _frame: NinePatchRect = $Frame


func _ready() -> void:
	draw.connect(_update_frame)
	if not Engine.is_editor_hint():
		Loc.language_changed.connect(_on_language_changed)
	_refresh_text()
	_update_frame()


func _on_language_changed(_code: String) -> void:
	_refresh_text()


func _refresh_text() -> void:
	if text_key.is_empty():
		return
	text = text_key if Engine.is_editor_hint() else Loc.t(text_key)


func _update_frame() -> void:
	match get_draw_mode():
		DRAW_PRESSED, DRAW_HOVER_PRESSED:
			_frame.self_modulate = pressed_tint
		DRAW_HOVER:
			_frame.self_modulate = hover_tint
		DRAW_DISABLED:
			_frame.self_modulate = disabled_tint
		_:
			_frame.self_modulate = normal_tint
