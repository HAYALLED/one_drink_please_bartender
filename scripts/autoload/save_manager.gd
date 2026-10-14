extends Node

const SAVE_DIR := "user://saves"
const SLOT_COUNT := 3
const FORMAT_VERSION := 1
const KIND_MANUAL := "manual"
const KIND_AUTO := "auto"
const KIND_CONTINUE := "continue"

var current_slot := 1
# Set by the menu right before the game scene loads.
# {"mode": "new"} or {"mode": "load", "kind": "manual" | "auto" | "continue"}
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


## A complete .tmp is always newer than the main file (a crash can hit between the two renames), so it is tried first.
## A half-written .tmp fails to parse and the loop falls through to the main file, then the backup.
func read_slot(slot: int) -> Dictionary:
	var path := slot_path(slot)
	for candidate in [path + ".tmp", path, path + ".bak"]:
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
	var data := read_slot(slot)
	for kind in [KIND_MANUAL, KIND_AUTO, KIND_CONTINUE]:
		if data.get(kind) is Dictionary and not (data[kind] as Dictionary).is_empty():
			return true
	return false


## Kind of the newest entry in the slot (manual, auto or continue), "" when the slot is empty.
## Ties go to the later kind in the list, so continue wins over auto, auto over manual.
func latest_kind(slot: int) -> String:
	var data := read_slot(slot)
	var best := ""
	var best_time := -1.0
	for kind in [KIND_MANUAL, KIND_AUTO, KIND_CONTINUE]:
		var value: Variant = data.get(kind)
		if not value is Dictionary or (value as Dictionary).is_empty():
			continue
		var saved_at := float((value as Dictionary).get("saved_at", 0.0))
		if saved_at >= best_time:
			best_time = saved_at
			best = kind
	return best


func load_state(slot: int, kind: String) -> Dictionary:
	var state: Variant = entry(slot, kind).get("state", {})
	return state as Dictionary if state is Dictionary else {}


# --- writing -------------------------------------------------------------------

func write_manual(state: Dictionary) -> bool:
	return _write_entry(current_slot, KIND_MANUAL, state)


## Day-start snapshot.
func write_auto(state: Dictionary) -> bool:
	return _write_entry(current_slot, KIND_AUTO, state)


## Rolling snapshot of whatever the player is doing. Always replaces the previous one, so the file never grows.
func write_continue(state: Dictionary) -> bool:
	return _write_entry(current_slot, KIND_CONTINUE, state)


func _write_entry(slot: int, kind: String, state: Dictionary) -> bool:
	var data := read_slot(slot)
	data["version"] = FORMAT_VERSION
	data[kind] = {
		"saved_at": Time.get_unix_time_from_system(),
		"meta": {
			"month": GameState.month,
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