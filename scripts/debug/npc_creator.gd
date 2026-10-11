class_name NpcCreator
extends Control

## Debug tool (main menu, debug builds only): build an NPC by hand, roll a random one,
## and check which images are found in res://assets/npc/<part>/.

signal closed

const PART_LABEL_WIDTH := 90.0

@export var preview_scale := 2.0

@onready var _npc_view: NpcView = $Frame/Margin/Content/Body/PreviewFrame/PreviewCenter/NpcView
@onready var _info_label: Label = $Frame/Margin/Content/Body/Controls/InfoLabel
@onready var _gender_option: OptionButton = $Frame/Margin/Content/Body/Controls/GenderRow/GenderOption
@onready var _skin_picker: ColorPickerButton = $Frame/Margin/Content/Body/Controls/SkinRow/SkinPicker
@onready var _hair_picker: ColorPickerButton = $Frame/Margin/Content/Body/Controls/HairRow/HairPicker
@onready var _parts_list: VBoxContainer = $Frame/Margin/Content/Body/Controls/PartsScroll/PartsList
@onready var _randomize_button: NinePatchButton = $Frame/Margin/Content/Buttons/RandomizeButton
@onready var _rescan_button: NinePatchButton = $Frame/Margin/Content/Buttons/RescanButton
@onready var _back_button: NinePatchButton = $Frame/Margin/Content/Buttons/BackButton

var _appearance: NpcAppearance
var _part_options: Dictionary = {}
var _part_pools: Dictionary = {}
var _syncing := false
var _initialized := false


func _ready() -> void:
	_gender_option.item_selected.connect(_on_gender_selected)
	_skin_picker.color_changed.connect(_on_skin_changed)
	_hair_picker.color_changed.connect(_on_hair_changed)
	_randomize_button.pressed.connect(_on_randomize_pressed)
	_rescan_button.pressed.connect(_on_rescan_pressed)
	_back_button.pressed.connect(close)
	Loc.language_changed.connect(_on_language_changed)


func open() -> void:
	visible = true
	if not _initialized:
		_initialized = true
		NpcLibrary.rescan()
		_appearance = NpcGenerator.generate()
		_rebuild_all()


func close() -> void:
	visible = false
	closed.emit()


func _rebuild_all() -> void:
	_rebuild_gender_options()
	_rebuild_part_rows()
	_sync_controls()
	_refresh_preview()
	_refresh_info()


func _rebuild_gender_options() -> void:
	_syncing = true
	_gender_option.clear()
	for tag in NpcLibrary.genders():
		_gender_option.add_item(Loc.t("gender_%s" % tag))
		_gender_option.set_item_metadata(_gender_option.item_count - 1, tag)
	_syncing = false


func _rebuild_part_rows() -> void:
	for child in _parts_list.get_children():
		_parts_list.remove_child(child)
		child.queue_free()
	_part_options.clear()
	_part_pools.clear()
	for part in NpcLibrary.part_names():
		var pool := NpcLibrary.files(part, _appearance.gender)
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
		option.disabled = pool.is_empty()
		option.item_selected.connect(_on_part_selected.bind(part))
		row.add_child(option)
		_parts_list.add_child(row)
		_part_options[part] = option
		_part_pools[part] = pool


func _sync_controls() -> void:
	_syncing = true
	var genders := NpcLibrary.genders()
	_gender_option.select(maxi(genders.find(String(_appearance.gender)), 0))
	_skin_picker.color = _appearance.skin_color
	_hair_picker.color = _appearance.hair_color
	for part: String in _part_options:
		var pool: PackedStringArray = _part_pools[part]
		var index := pool.find(_appearance.part_file(part))
		(_part_options[part] as OptionButton).select(index + 1 if index >= 0 else 0)
	_syncing = false


func _refresh_preview() -> void:
	_npc_view.scale = Vector2.ONE * preview_scale
	_npc_view.apply(_appearance)


func _refresh_info() -> void:
	var chunks := PackedStringArray()
	var total := 0
	for part in NpcLibrary.part_names():
		var count := NpcLibrary.count(part)
		total += count
		chunks.append("%s %d" % [part, count])
	var text := Loc.t("npc_assets_report", {"report": ", ".join(chunks)})
	if total == 0:
		text += "\n" + Loc.t("npc_no_assets")
	_info_label.text = text


func _reroll(overrides: Dictionary) -> void:
	_appearance = NpcGenerator.generate(overrides)
	_rebuild_all()


func _on_randomize_pressed() -> void:
	_reroll({})


func _on_rescan_pressed() -> void:
	NpcLibrary.rescan()
	_reroll({})


func _on_gender_selected(index: int) -> void:
	if _syncing:
		return
	_reroll({
		"gender": StringName(_gender_option.get_item_metadata(index)),
		"skin_color": _appearance.skin_color,
		"hair_color": _appearance.hair_color,
	})


func _on_part_selected(index: int, part: String) -> void:
	if _syncing:
		return
	var pool: PackedStringArray = _part_pools[part]
	_appearance.parts[part] = "" if index == 0 else pool[index - 1]
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
	if _initialized:
		_rebuild_all()
