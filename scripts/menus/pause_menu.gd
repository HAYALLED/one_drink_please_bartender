class_name PauseMenu
extends CanvasLayer

const MENU_SCENE := "res://scenes/menus/main_menu.tscn"
const SETTINGS_SCENE: PackedScene = preload("res://scenes/menus/settings_menu.tscn")

var _root: Control
var _box_panel: PanelContainer
var _title: Label
var _resume: Button
var _settings_button: Button
var _menu_button: Button
var _settings: SettingsMenu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 15
	_root = Control.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_box_panel = PanelContainer.new()
	_box_panel.position = Vector2(240, 100)
	_box_panel.custom_minimum_size = Vector2(160, 0)
	_root.add_child(_box_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_box_panel.add_child(box)
	_title = Ui.label("", HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_title)
	_resume = Ui.button("", Vector2(0, 26))
	_resume.pressed.connect(resume)
	box.add_child(_resume)
	_settings_button = Ui.button("", Vector2(0, 26))
	_settings_button.pressed.connect(_open_settings)
	box.add_child(_settings_button)
	_menu_button = Ui.button("", Vector2(0, 26))
	_menu_button.pressed.connect(_ask_main_menu)
	box.add_child(_menu_button)

	_settings = SETTINGS_SCENE.instantiate() as SettingsMenu
	_settings.visible = false
	_settings.closed.connect(func() -> void: _box_panel.visible = true)
	_root.add_child(_settings)

	_refresh_texts()
	Loc.language_changed.connect(func(_code: String) -> void: _refresh_texts())


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	if _settings.visible:
		_settings.close()
	elif _root.visible:
		resume()
	elif (get_parent() as BarGame).can_pause():
		_open()
	else:
		return
	get_viewport().set_input_as_handled()


func resume() -> void:
	_root.visible = false
	get_tree().paused = false


func _open() -> void:
	_box_panel.visible = true
	_settings.visible = false
	_root.visible = true
	get_tree().paused = true


func _open_settings() -> void:
	_box_panel.visible = false
	_settings.open()


func _ask_main_menu() -> void:
	Ui.confirm(self, Loc.t("pause_confirm_menu"), func() -> void:
		get_tree().paused = false
		get_tree().change_scene_to_file(MENU_SCENE)
	)


func _refresh_texts() -> void:
	_title.text = Loc.t("pause_title")
	_resume.text = Loc.t("pause_resume")
	_settings_button.text = Loc.t("pause_settings")
	_menu_button.text = Loc.t("pause_main_menu")
