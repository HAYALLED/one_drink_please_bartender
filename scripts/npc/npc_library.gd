class_name NpcLibrary
extends RefCounted

## Scans res://assets/npc/<part>/ and knows which images exist.
## - Every sub folder of ROOT is a part (head, eyes, hat, ...). New folder = new part, nothing to register.
## - Inside a part folder, sub folders named male / female / other limit those images to that gender.
##   Everything else (files in the part folder itself, other sub folders) is shared by all genders.
## - All images of one NPC must share the same canvas size; they are stacked on the same origin.

const ROOT := "res://assets/npc"
const IMAGE_EXTENSIONS: PackedStringArray = ["png", "webp", "jpg", "jpeg", "svg"]
const GENDER_TAGS: PackedStringArray = ["male", "female", "other"]
const DEFAULT_GENDERS: PackedStringArray = ["male", "female"]

## Draw order, bottom to top. Folders not listed here are drawn on top, alphabetically.
const LAYER_ORDER: PackedStringArray = [
	"body", "hands", "ears", "cloths", "head", "nose", "mouth", "eyes",
	"eyebrows", "mustache", "beard", "hair", "glasses", "hat",
]
## Layers filled with the NPC skin color (draw them white / light gray).
const SKIN_PARTS: PackedStringArray = ["body", "hands", "ears", "head", "nose"]
## Layers filled with the NPC hair color.
const HAIR_PARTS: PackedStringArray = ["eyebrows", "mustache", "beard", "hair"]

static var _files: Dictionary = {}
static var _loaded := false


static func rescan() -> void:
	_files.clear()
	for folder in DirAccess.get_directories_at(ROOT):
		if folder.begins_with("."):
			continue
		_files[folder] = _scan_folder(ROOT.path_join(folder), "")
	_loaded = true


## Part folders in draw order (includes folders that are still empty).
static func part_names() -> PackedStringArray:
	_ensure_loaded()
	var result := PackedStringArray()
	for part in LAYER_ORDER:
		if _files.has(part):
			result.append(part)
	var extra: Array = _files.keys().filter(func(name: String) -> bool: return not LAYER_ORDER.has(name))
	extra.sort()
	for part: String in extra:
		result.append(part)
	return result


## Genders that can be rolled: male + female, plus "other" once some part has an "other" sub folder.
static func genders() -> PackedStringArray:
	_ensure_loaded()
	var result := DEFAULT_GENDERS.duplicate()
	for part: String in _files:
		for path in (_files[part] as PackedStringArray):
			if path.get_slice("/", 0) == "other" and path.contains("/") and not result.has("other"):
				result.append("other")
	return result


## Images of a part that a NPC of this gender may use (relative paths).
static func files(part: String, gender: StringName) -> PackedStringArray:
	_ensure_loaded()
	var result := PackedStringArray()
	for path in (_files.get(part, PackedStringArray()) as PackedStringArray):
		var first := path.get_slice("/", 0) if path.contains("/") else ""
		if not GENDER_TAGS.has(first) or first == String(gender):
			result.append(path)
	return result


## Every image of a part, any gender.
static func count(part: String) -> int:
	_ensure_loaded()
	return (_files.get(part, PackedStringArray()) as PackedStringArray).size()


static func texture(part: String, file: String) -> Texture2D:
	var path := ROOT.path_join(part).path_join(file)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func _ensure_loaded() -> void:
	if not _loaded:
		rescan()


static func _scan_folder(base: String, relative: String) -> PackedStringArray:
	var path := base if relative.is_empty() else base.path_join(relative)
	var result := PackedStringArray()
	var seen := {}
	for file in DirAccess.get_files_at(path):
		# Exported games list "x.png.import" instead of "x.png".
		var name := file.trim_suffix(".import").trim_suffix(".remap")
		if name.begins_with(".") or seen.has(name):
			continue
		if IMAGE_EXTENSIONS.has(name.get_extension().to_lower()):
			seen[name] = true
			result.append(name if relative.is_empty() else relative.path_join(name))
	for folder in DirAccess.get_directories_at(path):
		if not folder.begins_with("."):
			result.append_array(_scan_folder(base, folder if relative.is_empty() else relative.path_join(folder)))
	result.sort()
	return result
