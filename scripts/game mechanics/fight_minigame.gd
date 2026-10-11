class_name FightMinigame
extends CanvasLayer

signal finished(won: bool)

const FIGHT_TIME := 7.0
const PRESS_GAIN := 0.05
const DRAIN_FACTOR := 0.5

var _power := 0.5
var _meter := 0.5
var _time_left := 0.0
var _last_side := 0
var _active := false

var _panel: PanelContainer
var _bar: ProgressBar
var _time_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_panel = PanelContainer.new()
	_panel.position = Vector2(170, 120)
	_panel.custom_minimum_size = Vector2(300, 0)
	root.add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	var title := Label.new()
	title.text = Loc.t("fight_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 10)
	box.add_child(title)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(280, 16)
	_bar.max_value = 100.0
	_bar.show_percentage = false
	box.add_child(_bar)
	_time_label = Label.new()
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.add_theme_font_size_override("font_size", 10)
	box.add_child(_time_label)
	visible = false


func start(enemy_power: float) -> bool:
	_power = enemy_power
	_meter = 0.5
	_time_left = FIGHT_TIME
	_last_side = 0
	_active = true
	visible = true
	get_tree().paused = true
	var won: bool = await finished
	return won


func _process(delta: float) -> void:
	if not _active:
		return
	_time_left -= delta
	var wobble := 1.0 + 0.3 * sin(_time_left * 9.0)
	_meter -= _power * DRAIN_FACTOR * wobble * delta
	if Input.is_action_just_pressed(&"tray_left") and _last_side != -1:
		_meter += PRESS_GAIN
		_last_side = -1
	if Input.is_action_just_pressed(&"tray_right") and _last_side != 1:
		_meter += PRESS_GAIN
		_last_side = 1
	_meter = clampf(_meter, 0.0, 1.0)
	_bar.value = _meter * 100.0
	_time_label.text = "%.1f" % maxf(_time_left, 0.0)
	if _meter >= 1.0:
		_finish(true)
	elif _meter <= 0.0:
		_finish(false)
	elif _time_left <= 0.0:
		_finish(_meter > 0.5)


func _finish(won: bool) -> void:
	_active = false
	visible = false
	get_tree().paused = false
	finished.emit(won)
