class_name NpcView
extends Node2D

## Draws a NpcAppearance: one Sprite2D per layer, stacked on the same origin.

@onready var _layers: Node2D = $Layers


func apply(appearance: NpcAppearance) -> void:
	for child in _layers.get_children():
		_layers.remove_child(child)
		child.queue_free()
	if appearance == null:
		return
	for part in NpcLibrary.part_names():
		var file := appearance.part_file(part)
		if file.is_empty():
			continue
		var texture := NpcLibrary.texture(part, file)
		if texture == null:
			continue
		var sprite := Sprite2D.new()
		sprite.name = part
		sprite.texture = texture
		sprite.modulate = _tint(part, appearance)
		_layers.add_child(sprite)


func _tint(part: String, appearance: NpcAppearance) -> Color:
	if NpcLibrary.SKIN_PARTS.has(part):
		return appearance.skin_color
	if NpcLibrary.HAIR_PARTS.has(part):
		return appearance.hair_color
	return Color.WHITE
