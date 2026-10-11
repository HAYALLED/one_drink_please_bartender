@tool
class_name LocLabel
extends Label

## dictionary.csv key. Text is refreshed automatically when the language changes.
@export var text_key: String = "":
	set(value):
		text_key = value
		if is_inside_tree():
			_refresh()


func _ready() -> void:
	if not Engine.is_editor_hint():
		Loc.language_changed.connect(_on_language_changed)
	_refresh()


func _on_language_changed(_code: String) -> void:
	_refresh()


func _refresh() -> void:
	if text_key.is_empty():
		return
	text = text_key if Engine.is_editor_hint() else Loc.t(text_key)
