class_name Hud
extends CanvasLayer

signal serve_pressed
signal day_continue_pressed
signal debt_confirmed(amount: int)
signal save_requested
signal open_requested

const FONT_SIZE := Ui.FONT_SIZE

var _status: Label
var _status2: Label
var _orders: Label
var _prompt: Label
var _toast: Label
var _serve_button: Button
var _day_panel: PanelContainer
var _day_text: Label
var _shop_box: GridContainer
var _continue_button: Button
var _debt_panel: PanelContainer
var _debt_text: Label
var _debt_amount: Label
var _debt_slider: HSlider
var _pay_button: Button
var _opening_panel: PanelContainer
var _opening_title: Label
var _opening_text: Label
var _opening_feedback: Label
var _save_button: Button
var _open_button: Button
var _toast_tween: Tween


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_status = _make_label(root, Vector2(6, 4), Vector2(628, 14))
	_status2 = _make_label(root, Vector2(6, 17), Vector2(460, 14))
	_orders = _make_label(root, Vector2(430, 30), Vector2(204, 90))
	_orders.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_prompt = _make_label(root, Vector2(6, 342), Vector2(520, 14))
	_toast = _make_label(root, Vector2(120, 50), Vector2(400, 20))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0

	_serve_button = Ui.button("")
	_serve_button.position = Vector2(560, 318)
	_serve_button.size = Vector2(72, 24)
	_serve_button.pressed.connect(func() -> void: serve_pressed.emit())
	_serve_button.visible = false
	root.add_child(_serve_button)

	_build_opening_panel(root)
	_build_day_panel(root)
	_build_debt_panel(root)
	_apply_static_texts()
	Loc.language_changed.connect(func(_code: String) -> void: _apply_static_texts())


func _process(_delta: float) -> void:
	_status.text = Loc.t("hud_status", {
		"month": GameState.month,
		"week": GameState.week,
		"weeks": GameState.WEEKS_PER_MONTH,
		"day": GameState.day,
		"days": GameState.DAYS_PER_WEEK,
		"money": Loc.gold(GameState.money),
		"debt": Loc.gold(GameState.month_debt),
		"earned": Loc.gold(GameState.week_earned),
		"target": Loc.gold(GameState.weekly_target),
	})
	var glass_parts: PackedStringArray = []
	for type in GameState.GLASS_TYPES:
		glass_parts.append(Loc.t("hud_glass_count", {"name": Loc.t("glass_%s" % type), "count": GameState.glass_count(type)}))
	_status2.text = Loc.t("hud_status2", {
		"glasses": "  ".join(glass_parts),
		"trust": GameState.trust,
		"favor": GameState.favor,
	})


# --- public API -------------------------------------------------------------

func set_serve_button_visible(value: bool) -> void:
	_serve_button.visible = value


func show_orders(text: String) -> void:
	_orders.text = text


func set_prompt(text: String) -> void:
	_prompt.text = text


func toast(text: String, seconds := 2.0) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)


func show_opening(slot: int) -> void:
	_serve_button.visible = false
	_opening_title.text = Loc.t("opening_title", {
		"day": GameState.day,
		"days": GameState.DAYS_PER_WEEK,
		"week": GameState.week,
		"weeks": GameState.WEEKS_PER_MONTH,
		"month": GameState.month,
	})
	_opening_text.text = Loc.t("opening_info", {
		"money": Loc.gold(GameState.money),
		"debt": Loc.gold(GameState.month_debt),
		"earned": Loc.gold(GameState.week_earned),
		"target": Loc.gold(GameState.weekly_target),
		"slot": slot,
	})
	_opening_feedback.text = ""
	_opening_panel.visible = true


func hide_opening() -> void:
	_opening_panel.visible = false


func set_opening_feedback(text: String) -> void:
	_opening_feedback.text = text


func show_day_end(summary: Dictionary) -> void:
	_serve_button.visible = false
	var text := Loc.t("day_end_summary", {
		"earned": Loc.gold(int(summary["earned"])),
		"week_earned": Loc.gold(int(summary["week_earned"])),
		"target": Loc.gold(int(summary["weekly_target"])),
		"trust": GameState.trust,
		"favor": GameState.favor,
	})
	if summary["week_over"]:
		if summary["target_met"]:
			text += "\n" + Loc.t("day_end_target_met")
		else:
			text += "\n" + Loc.t("day_end_target_missed", {"penalty": Loc.gold(int(summary["penalty"]))})
		text += "\n" + Loc.t("day_end_collector_next")
	if GameState.fewer_customers_days > 0:
		text += "\n" + Loc.t("day_end_bad_rep", {"days": GameState.fewer_customers_days})
	_day_text.text = text
	_rebuild_shop()
	_day_panel.visible = true


func show_collector(info: Dictionary) -> void:
	var max_pay := mini(int(info["money"]), int(info["month_debt"]))
	var forced: bool = info["forced"]
	_debt_slider.min_value = 0
	_debt_slider.max_value = max_pay
	_debt_slider.step = 1
	_debt_slider.value = max_pay if forced else clampi(int(info["suggested"]), 0, max_pay)
	_debt_slider.editable = not forced
	var text := Loc.t("collector_text", {
		"debt": Loc.gold(int(info["month_debt"])),
		"money": Loc.gold(int(info["money"])),
	})
	if forced:
		text += "\n" + Loc.t("collector_forced", {"interest": roundi(GameState.UNPAID_INTEREST * 100.0)})
	else:
		text += "\n" + Loc.t("collector_suggested", {"amount": Loc.gold(int(info["suggested"]))})
	_debt_text.text = text
	_on_debt_slider_changed(_debt_slider.value)
	_debt_panel.visible = true


func hide_day_panels() -> void:
	_day_panel.visible = false
	_debt_panel.visible = false


# --- internals ---------------------------------------------------------------

func _apply_static_texts() -> void:
	_serve_button.text = Loc.t("btn_serve")
	_continue_button.text = Loc.t("btn_continue")
	_pay_button.text = Loc.t("btn_pay")
	_save_button.text = Loc.t("btn_save_game")
	_open_button.text = Loc.t("btn_open_shop")


func _make_label(parent: Control, pos: Vector2, label_size: Vector2) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = label_size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	parent.add_child(label)
	return label


func _build_opening_panel(root: Control) -> void:
	_opening_panel = PanelContainer.new()
	_opening_panel.position = Vector2(170, 90)
	_opening_panel.custom_minimum_size = Vector2(300, 0)
	_opening_panel.visible = false
	root.add_child(_opening_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_opening_panel.add_child(box)
	_opening_title = Ui.label("", HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_opening_title)
	_opening_text = Ui.label("", HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_opening_text)
	_opening_feedback = Ui.label("", HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_opening_feedback)
	_save_button = Ui.button("")
	_save_button.pressed.connect(func() -> void: save_requested.emit())
	box.add_child(_save_button)
	_open_button = Ui.button("")
	_open_button.pressed.connect(func() -> void: open_requested.emit())
	box.add_child(_open_button)


func _build_day_panel(root: Control) -> void:
	_day_panel = PanelContainer.new()
	_day_panel.position = Vector2(90, 16)
	_day_panel.custom_minimum_size = Vector2(460, 0)
	_day_panel.visible = false
	root.add_child(_day_panel)
	var box := VBoxContainer.new()
	_day_panel.add_child(box)
	_day_text = Ui.label("")
	box.add_child(_day_text)
	_shop_box = GridContainer.new()
	_shop_box.columns = 2
	box.add_child(_shop_box)
	_continue_button = Ui.button("")
	_continue_button.pressed.connect(_on_continue_pressed)
	box.add_child(_continue_button)


func _build_debt_panel(root: Control) -> void:
	_debt_panel = PanelContainer.new()
	_debt_panel.position = Vector2(150, 70)
	_debt_panel.custom_minimum_size = Vector2(340, 0)
	_debt_panel.visible = false
	root.add_child(_debt_panel)
	var box := VBoxContainer.new()
	_debt_panel.add_child(box)
	_debt_text = Ui.label("")
	box.add_child(_debt_text)
	_debt_slider = HSlider.new()
	_debt_slider.custom_minimum_size = Vector2(300, 16)
	_debt_slider.value_changed.connect(_on_debt_slider_changed)
	box.add_child(_debt_slider)
	_debt_amount = Ui.label("")
	box.add_child(_debt_amount)
	_pay_button = Ui.button("")
	_pay_button.pressed.connect(_on_debt_confirm_pressed)
	box.add_child(_pay_button)


func _add_shop_button(text: String, disabled: bool, handler: Callable) -> void:
	var button := Ui.button(text, Vector2(220, 0))
	button.disabled = disabled
	button.pressed.connect(handler)
	_shop_box.add_child(button)


func _rebuild_shop() -> void:
	for child in _shop_box.get_children():
		child.queue_free()
	for type in GameState.GLASS_TYPES:
		var price := GameState.glass_price(type)
		_add_shop_button(
			Loc.t("shop_buy_glass", {
				"name": Loc.t("glass_%s" % type),
				"count": GameState.glass_count(type),
				"price": Loc.gold(price),
			}),
			GameState.money < price,
			_on_glass_pressed.bind(type)
		)
	for id in GameState.UPGRADES:
		var upgrade_name := Loc.t("upgrade_%s" % id)
		if GameState.is_maxed(id):
			_add_shop_button(
				Loc.t("shop_upgrade_max", {"name": upgrade_name, "level": GameState.level(id)}),
				true,
				_on_upgrade_pressed.bind(id)
			)
		else:
			var cost := GameState.upgrade_cost(id)
			_add_shop_button(
				Loc.t("shop_upgrade", {"name": upgrade_name, "level": GameState.level(id), "price": Loc.gold(cost)}),
				GameState.money < cost,
				_on_upgrade_pressed.bind(id)
			)
	for id in DrinkDB.ids():
		if GameState.is_drink_unlocked(id):
			continue
		var drink := DrinkDB.get_drink(id)
		_add_shop_button(
			Loc.t("shop_unlock", {"name": drink.name_text(), "price": Loc.gold(drink.unlock_cost)}),
			GameState.money < drink.unlock_cost,
			_on_unlock_pressed.bind(id)
		)


func _on_glass_pressed(type: StringName) -> void:
	GameState.buy_glass(type)
	_rebuild_shop()


func _on_upgrade_pressed(id: StringName) -> void:
	GameState.buy_upgrade(id)
	_rebuild_shop()


func _on_unlock_pressed(id: StringName) -> void:
	GameState.unlock_drink(id)
	_rebuild_shop()


func _on_continue_pressed() -> void:
	_day_panel.visible = false
	day_continue_pressed.emit()


func _on_debt_slider_changed(value: float) -> void:
	_debt_amount.text = Loc.t("collector_pay_label", {"amount": Loc.gold(int(value))})


func _on_debt_confirm_pressed() -> void:
	_debt_panel.visible = false
	debt_confirmed.emit(int(_debt_slider.value))
