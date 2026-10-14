class_name NpcLibrary
extends RefCounted

## Scans the character art folders and knows which images exist.
## - Two kinds share one layout: &"npc" -> res://assets/npc, &"player" -> res://assets/player model.
## - Every sub folder of a root is a part (head, eye_1, hat, ...). New folder = new part, nothing to register.
## - Inside a part folder, sub folders named male / female / other limit those images to that gender.
##   Everything else (files in the part folder itself, other sub folders) is shared by all genders.
## - All images of one character must share the same canvas size; they are stacked on the same origin.
## - eye_2 has no folder: it is eye_1 drawn mirrored (flipped around the canvas center).
##   Draw only the left eye into eye_1; the right eye is generated.
##   The folder may be called eye_1 or eyes. eye_1 / eye_2 always show up in the debug creator.

const KIND_NPC := &"npc"
const KIND_PLAYER := &"player"
const ROOTS := {
	&"npc": "res://assets/npc",
	&"player": "res://assets/player model",
}
const IMAGE_EXTENSIONS: PackedStringArray = ["png", "webp", "jpg", "jpeg", "svg"]
const GENDER_TAGS: PackedStringArray = ["male", "female", "other"]
const DEFAULT_GENDERS: PackedStringArray = ["male", "female"]

## Virtual part -> part whose images it mirrors.
const MIRROR_PARTS := {"eye_2": "eye_1"}
## Folder name -> part name, for folders that were named differently. A folder called "eyes" is read as eye_1.
## A real folder with the part's own name wins over its alias.
const FOLDER_ALIASES := {"eyes": "eye_1"}
## Parts that always exist, even when their folder is missing or empty, so the debug creator always lists them.
const ALWAYS_PARTS: PackedStringArray = ["eye_1"]

## Draw order, bottom to top. Folders not listed here are drawn on top, alphabetically.
const LAYER_ORDER: PackedStringArray = [
	"body", "hands", "ears", "cloths", "head", "nose", "mouth", "eye_1", "eye_2",
	"eyebrows", "mustache", "beard", "hair", "glasses", "hat",
]
## Layers filled with the skin color (draw them white / light gray).
const SKIN_PARTS: PackedStringArray = ["body", "hands", "ears", "head", "nose"]
## Layers filled with the hair color.
const HAIR_PARTS: PackedStringArray = ["eyebrows", "mustache", "beard", "hair"]

## kind -> { part -> PackedStringArray of relative image paths }
static var _files: Dictionary = {}
## kind -> { part -> folder name on disk }
static var _folders: Dictionary = {}


static func root(kind: StringName) -> String:
	return String(ROOTS.get(kind, ROOTS[KIND_NPC]))


static func is_mirror(part: String) -> bool:
	return MIRROR_PARTS.has(part)


static func rescan(kind: StringName = KIND_NPC) -> void:
	var parts := {}
	var folders := {}
	var base := root(kind)
	for folder in DirAccess.get_directories_at(base):
		if folder.begins_with(".") or MIRROR_PARTS.has(folder):
			continue
		var part := String(FOLDER_ALIASES.get(folder, folder))
		if parts.has(part) and folder != part:
			continue
		parts[part] = _scan_folder(base.path_join(folder), "")
		folders[part] = folder
	for required in ALWAYS_PARTS:
		if not parts.has(required):
			parts[required] = PackedStringArray()
			folders[required] = required
	for mirror: String in MIRROR_PARTS:
		var source := String(MIRROR_PARTS[mirror])
		if parts.has(source):
			parts[mirror] = parts[source]
	_files[kind] = parts
	_folders[kind] = folders


## Part names in draw order (includes folders that are still empty).
static func part_names(kind: StringName = KIND_NPC) -> PackedStringArray:
	var table := _table(kind)
	var result := PackedStringArray()
	for part in LAYER_ORDER:
		if table.has(part):
			result.append(part)
	var extra: Array = table.keys().filter(func(part_name: String) -> bool: return not LAYER_ORDER.has(part_name))
	extra.sort()
	for part: String in extra:
		result.append(part)
	return result


## Genders that can be rolled: male + female, plus "other" once some part has an "other" sub folder.
static func genders(kind: StringName = KIND_NPC) -> PackedStringArray:
	var table := _table(kind)
	var result := DEFAULT_GENDERS.duplicate()
	for part: String in table:
		for path in (table[part] as PackedStringArray):
			if path.contains("/") and path.get_slice("/", 0) == "other" and not result.has("other"):
				result.append("other")
	return result


## Images of a part that a character of this gender may use (relative paths).
static func files(part: String, gender: StringName, kind: StringName = KIND_NPC) -> PackedStringArray:
	var result := PackedStringArray()
	for path in (_table(kind).get(part, PackedStringArray()) as PackedStringArray):
		var first := path.get_slice("/", 0) if path.contains("/") else ""
		if not GENDER_TAGS.has(first) or first == String(gender):
			result.append(path)
	return result


## Every image of a part, any gender. Mirror parts count as 0 (their images are counted once, in the source part).
static func count(part: String, kind: StringName = KIND_NPC) -> int:
	if is_mirror(part):
		return 0
	return (_table(kind).get(part, PackedStringArray()) as PackedStringArray).size()


static func texture(part: String, file: String, kind: StringName = KIND_NPC) -> Texture2D:
	_table(kind)
	var source := String(MIRROR_PARTS.get(part, part))
	var folder := String((_folders.get(kind, {}) as Dictionary).get(source, source))
	var path := root(kind).path_join(folder).path_join(file)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func _table(kind: StringName) -> Dictionary:
	if not _files.has(kind):
		rescan(kind)
	return _files[kind]


static func _scan_folder(base: String, relative: String) -> PackedStringArray:
	var path := base if relative.is_empty() else base.path_join(relative)
	var result := PackedStringArray()
	var seen := {}
	for file in DirAccess.get_files_at(path):
		# Exported games list "x.png.import" instead of "x.png".
		var image := file.trim_suffix(".import").trim_suffix(".remap")
		if image.begins_with(".") or seen.has(image):
			continue
		if IMAGE_EXTENSIONS.has(image.get_extension().to_lower()):
			seen[image] = true
			result.append(image if relative.is_empty() else relative.path_join(image))
	for folder in DirAccess.get_directories_at(path):
		if not folder.begins_with("."):
			result.append_array(_scan_folder(base, folder if relative.is_empty() else relative.path_join(folder)))
	result.sort()
	return result