class_name NpcCreator
extends Control

## Debug tool (main menu > Debug, debug builds only): build a character by hand, roll a random one,
## and check which images are found in the art folder.
## open(&"npc") edits res://assets/npc, open(&"player") edits res://assets/player model
## (the player look can be saved; NPC looks are rolled only).

signal closed

const PART_LABEL_WIDTH := 90.0
const MIRROR_TOGGLE_PART := "eye_2"

@export var preview_scale := 2.0

@onready var _title: LocLabel = $Frame/Margin/Content/Title
@onready var _npc_view: NpcView = $Frame/Margin/Content/Body/PreviewFrame/PreviewCenter/NpcView
@onready var _info_label: Label = $Frame/Margin/Content/Body/Controls/InfoLabel
@onready var _gender_option: OptionButton = $Frame/Margin/Content/Body/Controls/GenderRow/GenderOption
@onready var _skin_picker: ColorPickerButton = $Frame/Margin/Content/Body/Controls/SkinRow/SkinPicker
@onready var _hair_picker: ColorPickerButton = $Frame/Margin/Content/Body/Controls/HairRow/HairPicker
@onready var _parts_list: VBoxContainer = $Frame/Margin/Content/Body/Controls/PartsScroll/PartsList
@onready var _randomize_button: NinePatchButton = $Frame/Margin/Content/Buttons/RandomizeButton
@onready var _rescan_button: NinePatchButton = $Frame/Margin/Content/Buttons/RescanButton
@onready var _save_button: NinePatchButton = $Frame/Margin/Content/Buttons/SaveButton
@onready var _back_button: NinePatchButton = $Frame/Margin/Content/Buttons/BackButton

var _kind: StringName = NpcLibrary.KIND_NPC
var _appearances: Dictionary = {}
var _appearance: NpcAppearance
var _part_options: Dictionary = {}
var _part_pools: Dictionary = {}
var _mirror_check: CheckBox
var _syncing := false
var _opened := false
var _save_status := ""


func _ready() -> void:
	_gender_option.item_selected.connect(_on_gender_selected)
	_skin_picker.color_changed.connect(_on_skin_changed)
	_hair_picker.color_changed.connect(_on_hair_changed)
	_randomize_button.pressed.connect(_on_randomize_pressed)
	_rescan_button.pressed.connect(_on_rescan_pressed)
	_save_button.pressed.connect(_on_save_pressed)
	_back_button.pressed.connect(close)
	Loc.language_changed.connect(_on_language_changed)


func open(kind: StringName = NpcLibrary.KIND_NPC) -> void:
	_kind = kind
	visible = true
	_opened = true
	_save_status = ""
	_title.text_key = "player_creator_title" if _kind == NpcLibrary.KIND_PLAYER else "npc_creator_title"
	_save_button.visible = _kind == NpcLibrary.KIND_PLAYER
	if not _appearances.has(_kind):
		NpcLibrary.rescan(_kind)
		_appearances[_kind] = _initial_appearance()
	_appearance = _appearances[_kind]
	_rebuild_all()


func close() -> void:
	visible = false
	closed.emit()


func _initial_appearance() -> NpcAppearance:
	if _kind == NpcLibrary.KIND_PLAYER:
		var saved := NpcAppearance.load_player()
		if saved != null:
			return saved
	return NpcGenerator.generate({"kind": _kind})


func _rebuild_all() -> void:
	_rebuild_gender_options()
	_rebuild_part_rows()
	_sync_controls()
	_refresh_preview()
	_refresh_info()


func _rebuild_gender_options() -> void:
	_syncing = true
	_gender_option.clear()
	for tag in NpcLibrary.genders(_kind):
		_gender_option.add_item(Loc.t("gender_%s" % tag))
		_gender_option.set_item_metadata(_gender_option.item_count - 1, tag)
	_syncing = false


func _rebuild_part_rows() -> void:
	for child in _parts_list.get_children():
		_parts_list.remove_child(child)
		child.queue_free()
	_part_options.clear()
	_part_pools.clear()
	_mirror_check = null
	for part in NpcLibrary.part_names(_kind):
		if part == MIRROR_TOGGLE_PART:
			_add_mirror_toggle()
		var pool := NpcLibrary.files(part, _appearance.gender, _kind)
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = part
		label.custom_minimum_size = Vector2(PART_LABEL_WIDTH, 0)
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(label)
		var option := OptionButton.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.clip_text = true
		option.add_item(Loc.t("npc_none"))
		for file in pool:
			option.add_item(file)
		option.item_selected.connect(_on_part_selected.bind(part))
		row.add_child(option)
		_parts_list.add_child(row)
		_part_options[part] = option
		_part_pools[part] = pool


func _add_mirror_toggle() -> void:
	_mirror_check = CheckBox.new()
	_mirror_check.text = Loc.t("npc_mirror_eyes")
	_mirror_check.toggled.connect(_on_mirror_toggled)
	_parts_list.add_child(_mirror_check)


func _sync_controls() -> void:
	_syncing = true
	var genders := NpcLibrary.genders(_kind)
	_gender_option.select(maxi(genders.find(String(_appearance.gender)), 0))
	_skin_picker.color = _appearance.skin_color
	_hair_picker.color = _appearance.hair_color
	if _mirror_check != null:
		_mirror_check.button_pressed = _appearance.mirror_eyes
	for part: String in _part_options:
		var pool: PackedStringArray = _part_pools[part]
		var option := _part_options[part] as OptionButton
		var index := pool.find(_appearance.part_file(part))
		option.select(index + 1 if index >= 0 else 0)
		option.disabled = pool.is_empty() or (_appearance.mirror_eyes and NpcLibrary.is_mirror(part))
	_syncing = false


func _refresh_preview() -> void:
	_npc_view.scale = Vector2.ONE * preview_scale
	_npc_view.apply(_appearance)


func _refresh_info() -> void:
	var chunks := PackedStringArray()
	var total := 0
	for part in NpcLibrary.part_names(_kind):
		if NpcLibrary.is_mirror(part):
			continue
		var count := NpcLibrary.count(part, _kind)
		total += count
		chunks.append("%s %d" % [part, count])
	var text := Loc.t("npc_assets_report", {"report": ", ".join(chunks)})
	if total == 0:
		text += "\n" + Loc.t("npc_no_assets", {"path": NpcLibrary.root(_kind)})
	if not _save_status.is_empty():
		text += "\n" + _save_status
	_info_label.text = text


func _reroll(overrides: Dictionary) -> void:
	overrides["kind"] = _kind
	_appearance = NpcGenerator.generate(overrides)
	_appearances[_kind] = _appearance
	_save_status = ""
	_rebuild_all()


func _on_randomize_pressed() -> void:
	_reroll({})


func _on_rescan_pressed() -> void:
	NpcLibrary.rescan(_kind)
	_reroll({})


func _on_save_pressed() -> void:
	var error := _appearance.save_as_player()
	_save_status = Loc.t("player_saved") if error == OK else Loc.t("player_save_failed", {"error": error_string(error)})
	_refresh_info()


func _on_gender_selected(index: int) -> void:
	if _syncing:
		return
	_reroll({
		"gender": StringName(_gender_option.get_item_metadata(index)),
		"skin_color": _appearance.skin_color,
		"hair_color": _appearance.hair_color,
		"mirror_eyes": _appearance.mirror_eyes,
	})


func _on_part_selected(index: int, part: String) -> void:
	if _syncing:
		return
	var pool: PackedStringArray = _part_pools[part]
	_appearance.parts[part] = "" if index == 0 else pool[index - 1]
	_sync_controls()
	_refresh_preview()


func _on_mirror_toggled(pressed: bool) -> void:
	if _syncing:
		return
	if not pressed:
		# Keep the look: eye_2 starts as a copy of what it mirrored.
		_appearance.parts[MIRROR_TOGGLE_PART] = _appearance.part_file(MIRROR_TOGGLE_PART)
	_appearance.mirror_eyes = pressed
	_sync_controls()
	_refresh_preview()


func _on_skin_changed(color: Color) -> void:
	if _syncing:
		return
	_appearance.skin_color = color
	_refresh_preview()


func _on_hair_changed(color: Color) -> void:
	if _syncing:
		return
	_appearance.hair_color = color
	_refresh_preview()


func _on_language_changed(_code: String) -> void:
	if _opened:
		_rebuild_all()
