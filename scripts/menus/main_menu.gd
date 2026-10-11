extends Control

const GAME_SCENE := "res://scenes/levels/bar_game.tscn"
const SLOT_CARD_SCENE: PackedScene = preload("res://scenes/menus/slot_card.tscn")

@onready var _main_box: VBoxContainer = $MainBox
@onready var _play_button: NinePatchButton = $MainBox/PlayButton
@onready var _settings_button: NinePatchButton = $MainBox/SettingsButton
@onready var _debug_button: NinePatchButton = $MainBox/DebugButton
@onready var _quit_button: NinePatchButton = $MainBox/QuitButton
@onready var _debug_box: VBoxContainer = $DebugBox
@onready var _debug_player_button: NinePatchButton = $DebugBox/PlayerButton
@onready var _debug_npc_button: NinePatchButton = $DebugBox/NpcButton
@onready var _debug_back_button: NinePatchButton = $DebugBox/DebugBackButton
@onready var _slots_panel: NinePatchRect = $SlotsPanel
@onready var _slots_row: HBoxContainer = $SlotsPanel/Margin/Content/SlotsRow
@onready var _slots_back: NinePatchButton = $SlotsPanel/Margin/Content/SlotsBack
@onready var _settings_menu: SettingsMenu = $SettingsMenu
@onready var _npc_creator: NpcCreator = $NpcCreator


func _ready() -> void:
	_play_button.pressed.connect(_show_slots)
	_settings_button.pressed.connect(_show_settings)
	_debug_button.visible = OS.is_debug_build()
	_debug_button.pressed.connect(_show_debug_box)
	_debug_player_button.pressed.connect(_show_creator.bind(NpcLibrary.KIND_PLAYER))
	_debug_npc_button.pressed.connect(_show_creator.bind(NpcLibrary.KIND_NPC))
	_debug_back_button.pressed.connect(_hide_debug_box)
	_quit_button.pressed.connect(_on_quit_pressed)
	_slots_back.pressed.connect(_hide_slots)
	_settings_menu.closed.connect(_on_settings_closed)
	_npc_creator.closed.connect(_on_npc_creator_closed)
	Loc.language_changed.connect(_on_language_changed)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	if _npc_creator.visible:
		_npc_creator.close()
	elif _debug_box.visible:
		_hide_debug_box()
	elif _settings_menu.visible:
		_settings_menu.close()
	elif _slots_panel.visible:
		_hide_slots()
	else:
		return
	get_viewport().set_input_as_handled()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_language_changed(_code: String) -> void:
	if _slots_panel.visible:
		_rebuild_slots()


func _on_settings_closed() -> void:
	_main_box.visible = true


func _on_npc_creator_closed() -> void:
	_debug_box.visible = true


func _show_debug_box() -> void:
	_main_box.visible = false
	_debug_box.visible = true


func _hide_debug_box() -> void:
	_debug_box.visible = false
	_main_box.visible = true


func _show_creator(kind: StringName) -> void:
	_debug_box.visible = false
	_npc_creator.open(kind)


func _show_settings() -> void:
	_main_box.visible = false
	_settings_menu.open()


func _show_slots() -> void:
	_main_box.visible = false
	_rebuild_slots()
	_slots_panel.visible = true


func _hide_slots() -> void:
	_slots_panel.visible = false
	_main_box.visible = true


func _rebuild_slots() -> void:
	for child in _slots_row.get_children():
		_slots_row.remove_child(child)
		child.queue_free()
	for slot in range(1, SaveManager.SLOT_COUNT + 1):
		var card := SLOT_CARD_SCENE.instantiate() as SlotCard
		_slots_row.add_child(card)
		card.setup(slot)
		card.load_requested.connect(_on_load_requested)
		card.new_game_requested.connect(_on_new_game_requested)
		card.delete_requested.connect(_on_delete_requested)


func _on_load_requested(slot: int, kind: String) -> void:
	SaveManager.begin_load(slot, kind)
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_new_game_requested(slot: int) -> void:
	SaveManager.start_new(slot)
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_delete_requested(slot: int) -> void:
	Ui.confirm(self, Loc.t("slot_delete_confirm", {"slot": slot}), _delete_slot.bind(slot))


func _delete_slot(slot: int) -> void:
	SaveManager.delete_slot(slot)
	_rebuild_slots()
