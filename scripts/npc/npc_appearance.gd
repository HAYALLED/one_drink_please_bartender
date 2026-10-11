class_name NpcAppearance
extends Resource

## One character look (NPC or player). Random NPCs get one from NpcGenerator;
## the player look is saved to PLAYER_PATH from the debug creator.

const PLAYER_PATH := "user://player_appearance.tres"

@export var kind: StringName = &"npc"
@export var gender: StringName = &"male"
## Part folder name -> image path relative to the part folder ("" = no layer).
@export var parts: Dictionary = {}
@export var skin_color := Color.WHITE
@export var hair_color := Color.WHITE
## true: eye_2 always shows the same image as eye_1, mirrored. false: eye_2 uses its own entry in parts.
@export var mirror_eyes := true


func part_file(part: String) -> String:
	if mirror_eyes and NpcLibrary.MIRROR_PARTS.has(part):
		return part_file(String(NpcLibrary.MIRROR_PARTS[part]))
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


func save_as_player() -> Error:
	kind = NpcLibrary.KIND_PLAYER
	return ResourceSaver.save(self, PLAYER_PATH)


## The saved player look, or null when none was saved yet.
static func load_player() -> NpcAppearance:
	if not FileAccess.file_exists(PLAYER_PATH):
		return null
	var loaded := ResourceLoader.load(PLAYER_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as NpcAppearance
	if loaded != null:
		loaded.kind = NpcLibrary.KIND_PLAYER
	return loaded
