class_name SlotCard
extends VBoxContainer

signal load_requested(slot: int, kind: String)
signal new_game_requested(slot: int)
signal delete_requested(slot: int)

@onready var _manual_button: NinePatchButton = $ManualButton
@onready var _auto_button: NinePatchButton = $AutoButton
@onready var _delete_button: NinePatchButton = $DeleteButton

var _slot := 0
var _has_manual := false
var _has_auto := false


func _ready() -> void:
	_manual_button.pressed.connect(_on_manual_pressed)
	_auto_button.pressed.connect(_on_auto_pressed)
	_delete_button.pressed.connect(_on_delete_pressed)


func setup(slot: int) -> void:
	_slot = slot
	var manual := SaveManager.entry(slot, SaveManager.KIND_MANUAL)
	var auto := SaveManager.entry(slot, SaveManager.KIND_AUTO)
	_has_manual = not manual.is_empty()
	_has_auto = not auto.is_empty()
	var occupied := _has_manual or _has_auto
	var title := Loc.t("slot_title", {"slot": slot})

	if _has_manual:
		_manual_button.text = title + "\n\n" + _describe(manual, "slot_manual_text")
		_manual_button.disabled = false
	elif occupied:
		_manual_button.text = title + "\n\n" + Loc.t("slot_no_manual")
		_manual_button.disabled = true
	else:
		_manual_button.text = title + "\n\n" + Loc.t("slot_new_game")
		_manual_button.disabled = false

	if _has_auto:
		_auto_button.text = Loc.t("slot_autosave") + "\n" + _describe(auto, "slot_auto_text")
	else:
		_auto_button.text = Loc.t("slot_autosave") + "\n" + Loc.t("slot_no_autosave")
	_auto_button.disabled = not _has_auto

	_delete_button.disabled = not occupied


func _describe(entry: Dictionary, key: String) -> String:
	var meta: Dictionary = entry.get("meta", {})
	return Loc.t(key, {
		"day": int(meta.get("day", 1)),
		"week": int(meta.get("week", 1)),
		"month": int(meta.get("month", 1)),
		"money": Loc.gold(int(meta.get("money", 0))),
		"debt": Loc.gold(int(meta.get("debt", 0))),
		"playtime": SaveManager.format_playtime(float(meta.get("play_time", 0.0))),
		"date": SaveManager.format_timestamp(int(entry.get("saved_at", 0))),
	})


func _on_manual_pressed() -> void:
	if _has_manual:
		load_requested.emit(_slot, SaveManager.KIND_MANUAL)
	else:
		new_game_requested.emit(_slot)


func _on_auto_pressed() -> void:
	if _has_auto:
		load_requested.emit(_slot, SaveManager.KIND_AUTO)


func _on_delete_pressed() -> void:
	delete_requested.emit(_slot)
