class_name GlassRack
extends Area2D

signal requested(rack: GlassRack)

@export var glass_type: StringName = &"glass"

@onready var name_label: Label = $NameLabel


func _ready() -> void:
	name_label.text = Loc.t("glass_%s" % glass_type)


func press(_hand: Node) -> void:
	requested.emit(self)


func release(_hand: Node) -> void:
	pass
