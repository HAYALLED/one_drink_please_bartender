class_name SettingsMenu
extends Control

signal closed

@onready var _language_option: OptionButton = $Frame/Margin/Content/LanguageRow/LanguageOption
@onready var _master_slider: HSlider = $Frame/Margin/Content/MasterRow/MasterSlider
@onready var _music_slider: HSlider = $Frame/Margin/Content/MusicRow/MusicSlider
@onready var _sfx_slider: HSlider = $Frame/Margin/Content/SfxRow/SfxSlider
@onready var _fullscreen_check: CheckBox = $Frame/Margin/Content/FullscreenRow/FullscreenCheck
@onready var _back_button: NinePatchButton = $Frame/Margin/Content/BackButton

var _syncing := false


func _ready() -> void:
	for code in Loc.codes():
		_language_option.add_item(Loc.native_name(code))

	_language_option.item_selected.connect(_on_language_selected)
	_master_slider.value_changed.connect(_on_master_changed)
	_music_slider.value_changed.connect(_on_music_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_back_button.pressed.connect(close)
	visibility_changed.connect(_on_visibility_changed)

	_sync()


func open() -> void:
	visible = true


func close() -> void:
	visible = false
	closed.emit()


func _sync() -> void:
	_syncing = true
	_language_option.select(maxi(Loc.codes().find(Settings.language), 0))
	_master_slider.value = Settings.master_volume
	_music_slider.value = Settings.music_volume
	_sfx_slider.value = Settings.sfx_volume
	_fullscreen_check.button_pressed = Settings.fullscreen
	_syncing = false


func _on_visibility_changed() -> void:
	if visible:
		_sync()


func _on_language_selected(index: int) -> void:
	if not _syncing:
		Settings.set_language(Loc.codes()[index])


func _on_master_changed(value: float) -> void:
	if not _syncing:
		Settings.set_volume("master", value)


func _on_music_changed(value: float) -> void:
	if not _syncing:
		Settings.set_volume("music", value)


func _on_sfx_changed(value: float) -> void:
	if not _syncing:
		Settings.set_volume("sfx", value)


func _on_fullscreen_toggled(on: bool) -> void:
	if not _syncing:
		Settings.set_fullscreen(on)
