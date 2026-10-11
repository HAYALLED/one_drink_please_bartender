extends Node

signal language_changed(code: String)

const DICTIONARY_PATH := "res://dictionary.csv"
const FALLBACK := "en"

var current := FALLBACK

var _table: Dictionary = {}
var _codes: Array[String] = []


func _init() -> void:
	_load()


# Reads dictionary.csv. Row 1 = "keys,<lang code>,<lang code>,..."; every other row = key + one text per language.
# New language = new column. Nothing else to register.
func _load() -> void:
	_table.clear()
	_codes.clear()
	var file := FileAccess.open(DICTIONARY_PATH, FileAccess.READ)
	if file == null:
		push_error("Loc: cannot open %s" % DICTIONARY_PATH)
		return
	var header := file.get_csv_line()
	for i in range(1, header.size()):
		var code := header[i].strip_edges()
		if code.is_empty():
			continue
		_codes.append(code)
		_table[code] = {}
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < 2:
			continue
		var key := row[0].strip_edges()
		if key.is_empty() or key.begins_with("#"):
			continue
		for i in range(1, mini(row.size(), header.size())):
			var code := header[i].strip_edges()
			if _table.has(code):
				(_table[code] as Dictionary)[key] = row[i].replace("\\n", "\n")


func codes() -> Array[String]:
	return _codes


func has_language(code: String) -> bool:
	return _codes.has(code)


func native_name(code: String) -> String:
	var native := _lookup(code, "lang_name")
	return code if native.is_empty() else native


func default_language() -> String:
	var os_language := OS.get_locale_language()
	return os_language if _codes.has(os_language) else FALLBACK


func set_language(code: String) -> void:
	if not _codes.has(code):
		code = FALLBACK
	if code == current:
		return
	current = code
	language_changed.emit(code)


func t(key: String, params: Dictionary = {}) -> String:
	var text := _lookup(current, key)
	if text.is_empty():
		text = _lookup(FALLBACK, key)
	if text.is_empty():
		return key
	return text.format(params) if not params.is_empty() else text


func gold(amount: int) -> String:
	return t("gold_fmt", {"amount": amount})


func _lookup(code: String, key: String) -> String:
	if not _table.has(code):
		return ""
	return String((_table[code] as Dictionary).get(key, ""))
