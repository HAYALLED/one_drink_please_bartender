extends Node

const SAVE_DIR := "user://saves"
const SLOT_COUNT := 3
const FORMAT_VERSION := 1
const KIND_MANUAL := "manual"
const KIND_AUTO := "auto"

var current_slot := 1
# Set by the menu right before the game scene loads.
# {"mode": "new"} or {"mode": "load", "kind": "manual" | "auto"}
var pending: Dictionary = {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


# --- menu API ----------------------------------------------------------------

func start_new(slot: int) -> void:
	delete_slot(slot)
	current_slot = slot
	pending = {"mode": "new"}


func begin_load(slot: int, kind: String) -> void:
	current_slot = slot
	pending = {"mode": "load", "kind": kind}


func consume_pending() -> Dictionary:
	var result := pending
	pending = {}
	return result


func delete_slot(slot: int) -> void:
	var path := slot_path(slot)
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)


# --- reading -------------------------------------------------------------------

func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]


func read_slot(slot: int) -> Dictionary:
	var path := slot_path(slot)
	for candidate in [path, path + ".bak", path + ".tmp"]:
		var data := _read_file(candidate)
		if not data.is_empty():
			return data
	return {}


func entry(slot: int, kind: String) -> Dictionary:
	var value: Variant = read_slot(slot).get(kind, {})
	return value as Dictionary if value is Dictionary else {}


func has_entry(slot: int, kind: String) -> bool:
	return not entry(slot, kind).is_empty()


func slot_has_game(slot: int) -> bool:
	return has_entry(slot, KIND_MANUAL) or has_entry(slot, KIND_AUTO)


func load_state(slot: int, kind: String) -> Dictionary:
	var state: Variant = entry(slot, kind).get("state", {})
	return state as Dictionary if state is Dictionary else {}


# --- writing -------------------------------------------------------------------

func write_manual(state: Dictionary) -> bool:
	return _write_entry(current_slot, KIND_MANUAL, state)


func write_auto(state: Dictionary) -> bool:
	return _write_entry(current_slot, KIND_AUTO, state)


func _write_entry(slot: int, kind: String, state: Dictionary) -> bool:
	var data := read_slot(slot)
	data["version"] = FORMAT_VERSION
	data[kind] = {
		"saved_at": Time.get_unix_time_from_system(),
		"meta": {
			"month": GameState.month,
			"week": GameState.week,
			"day": GameState.day,
			"money": GameState.money,
			"debt": GameState.month_debt,
			"play_time": GameState.play_time,
		},
		"state": state,
	}
	return _write_file(slot_path(slot), data)


# Crash-safe: the new data goes to .tmp first, the old file is kept as .bak until the swap is done.
func _write_file(path: String, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot write %s" % tmp)
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	file.close()
	var backup := path + ".bak"
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(path, backup)
	var result := DirAccess.rename_absolute(tmp, path)
	return result == OK


func _read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	return json.data as Dictionary if json.data is Dictionary else {}


# --- display helpers ---------------------------------------------------------------

func format_timestamp(unix: int) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(unix + bias)
	return "%04d-%02d-%02d %02d:%02d" % [d["year"], d["month"], d["day"], d["hour"], d["minute"]]


func format_playtime(seconds: float) -> String:
	var total := int(seconds)
	return Loc.t("playtime_fmt", {"h": floori(total / 3600.0), "m": floori((total % 3600) / 60.0)})
