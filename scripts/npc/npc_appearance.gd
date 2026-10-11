class_name NpcAppearance
extends Resource

## One NPC look. Random NPCs get one from NpcGenerator; critical characters can
## be saved as a .tres of this resource and forced later.

@export var gender: StringName = &"male"
## Part folder name -> image path relative to res://assets/npc/<part>/ ("" = no layer).
@export var parts: Dictionary = {}
@export var skin_color := Color.WHITE
@export var hair_color := Color.WHITE


func part_file(part: String) -> String:
	return String(parts.get(part, ""))


## Identity of the part combination, colors ignored. Used to avoid twin NPCs.
func signature() -> String:
	var names := parts.keys()
	names.sort()
	var chunks := PackedStringArray()
	for part: String in names:
		var file := part_file(part)
		if not file.is_empty():
			chunks.append("%s=%s" % [part, file])
	return "|".join(chunks)
