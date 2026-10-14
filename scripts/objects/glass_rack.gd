class_name GlassRack
extends Area2D

signal requested(rack: GlassRack)

## The glass this rack hands out. The glass type is read from this scene.
@export var glass_scene: PackedScene

var glass_type: StringName = &"glass"

@onready var name_label: Label = $NameLabel


func _ready() -> void:
	var probe: Glass = create_glass()
	if probe == null:
		set_available(false)
		return
	glass_type = probe.glass_type
	probe.free()
	name_label.text = Loc.t("glass_%s" % glass_type)


## A new glass from this rack's scene, not in the tree yet. Null when no scene is set.
func create_glass() -> Glass:
	if glass_scene == null:
		push_error("GlassRack %s has no glass_scene" % name)
		return null
	return glass_scene.instantiate() as Glass


## A rack is only shown (and clickable) while one of the unlocked drinks uses its glass.
func set_available(on: bool) -> void:
	on = on and glass_scene != null
	visible = on
	set_deferred("monitorable", on)


func press(_hand: Node) -> void:
	requested.emit(self)


func release(_hand: Node) -> void:
	pass