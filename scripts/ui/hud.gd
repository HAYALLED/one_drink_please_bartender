class_name Hud
extends CanvasLayer

signal serve_pressed
signal day_continue_pressed
signal debt_confirmed(amount: int)
signal save_requested
signal open_requested
signal collector_requested
signal collector_left
signal collector_event(kind: StringName)

enum CollectorMode { MENU, PAY, BORROW }

const FONT_SIZE := Ui.FONT_SIZE

var _status: Label
var _status2: Label
var _orders: Label
var _prompt: Label
var _toast: Label
var _serve_button: Button
var _day_panel: PanelContainer
var _day_text: Label
var _wallet_label: Label
var _shop_box: GridContainer
var _exchange_title: Label
var _exchange_box: GridContainer
var _continue_button: Button
var _debt_panel: PanelContainer
var _debt_text: Label
var _debt_amount: Label
var _debt_slider: HSlider
var _pay_button: Button
var _debt_cancel_button: Button
var _collector_menu: VBoxContainer
var _collector_amount_box: VBoxContainer
var _menu_pay_button: Button
var _menu_take_button: Button
var _menu_leave_button: Button
var _opening_panel: PanelContainer
var _opening_title: Label
var _opening_text: Label
var _opening_feedback: Label
var _save_button: Button
var _upgrades_button: Button
var _collector_button: Button
var _open_button: Button
var _toast_tween: Tween
var _opening_slot := 1
var _shop_from_opening := false
var _collector_forced := false
var _collector_mode := CollectorMode.MENU

const EXCHANGES: Array[StringName] = [&"bronze_to_silver", &"silver_to_gold", &"silver_to_bronze", &"gold_to_silver"]


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
		"day": GameState.day,
		"days": GameState.DAYS_PER_MONTH,
		"wallet": _wallet_text(),
		"debt": Loc.coins(GameState.month_debt),
	})
	var glass_parts: PackedStringArray = []
	for type in GameState.available_glass_types():
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
	_opening_slot = slot
	_shop_from_opening = false
	_collector_forced = false
	_day_panel.visible = false
	_debt_panel.visible = false
	_refresh_opening()
	_opening_panel.visible = true


func hide_opening() -> void:
	_opening_panel.visible = false


func set_opening_feedback(text: String) -> void:
	_opening_feedback.text = text


func show_day_end(summary: Dictionary) -> void:
	_serve_button.visible = false
	_shop_from_opening = false
	_continue_button.text = Loc.t("btn_continue")
	var text := Loc.t("day_end_summary", {
		"earned": Loc.coins(int(summary.get("earned", 0))),
		"month_earned": Loc.coins(int(summary.get("month_earned", GameState.month_earned))),
		"trust": GameState.trust,
		"favor": GameState.favor,
	})
	if bool(summary.get("no_glasses", false)):
		text += "\n" + Loc.t("day_end_no_glasses")
	if bool(summary.get("month_over", false)):
		text += "\n" + Loc.t("day_end_month_over", {"required": Loc.coins(int(summary.get("required", GameState.required_left())))})
	if GameState.fewer_customers_days > 0:
		text += "\n" + Loc.t("day_end_bad_rep", {"days": GameState.fewer_customers_days})
	_day_text.text = text
	_rebuild_shop()
	_day_panel.visible = true


## Month end: the collector wants his money. The player can only pay (at least the required part).
func show_collector() -> void:
	_open_collector(true)


func hide_day_panels() -> void:
	_day_panel.visible = false
	_debt_panel.visible = false


# --- internals ---------------------------------------------------------------

func _apply_static_texts() -> void:
	_serve_button.text = Loc.t("btn_serve")
	_continue_button.text = Loc.t("btn_back" if _shop_from_opening else "btn_continue")
	_pay_button.text = Loc.t("btn_take" if _collector_mode == CollectorMode.BORROW else "btn_pay")
	_debt_cancel_button.text = Loc.t("btn_back")
	_menu_pay_button.text = Loc.t("btn_pay_debt")
	_menu_take_button.text = Loc.t("btn_take_debt")
	_menu_leave_button.text = Loc.t("btn_leave")
	_save_button.text = Loc.t("btn_save_game")
	_upgrades_button.text = Loc.t("btn_upgrades")
	_collector_button.text = Loc.t("btn_go_collector")
	_open_button.text = Loc.t("btn_open_shop")
	_exchange_title.text = Loc.t("shop_exchange_title")


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
	_upgrades_button = Ui.button("")
	_upgrades_button.pressed.connect(_on_upgrades_pressed)
	box.add_child(_upgrades_button)
	_collector_button = Ui.button("")
	_collector_button.pressed.connect(_on_collector_pressed)
	box.add_child(_collector_button)
	_open_button = Ui.button("")
	_open_button.pressed.connect(func() -> void: open_requested.emit())
	box.add_child(_open_button)


func _build_day_panel(root: Control) -> void:
	_day_panel = PanelContainer.new()
	_day_panel.position = Vector2(90, 8)
	_day_panel.custom_minimum_size = Vector2(460, 0)
	_day_panel.visible = false
	root.add_child(_day_panel)
	var box := VBoxContainer.new()
	_day_panel.add_child(box)
	_day_text = Ui.label("")
	box.add_child(_day_text)
	_wallet_label = Ui.label("")
	box.add_child(_wallet_label)
	_shop_box = GridContainer.new()
	_shop_box.columns = 2
	box.add_child(_shop_box)
	_exchange_title = Ui.label("")
	box.add_child(_exchange_title)
	_exchange_box = GridContainer.new()
	_exchange_box.columns = 2
	box.add_child(_exchange_box)
	_continue_button = Ui.button("")
	_continue_button.pressed.connect(_on_continue_pressed)
	box.add_child(_continue_button)


func _build_debt_panel(root: Control) -> void:
	_debt_panel = PanelContainer.new()
	_debt_panel.position = Vector2(150, 186)
	_debt_panel.custom_minimum_size = Vector2(340, 0)
	_debt_panel.visible = false
	root.add_child(_debt_panel)
	var box := VBoxContainer.new()
	_debt_panel.add_child(box)
	_debt_text = Ui.label("")
	box.add_child(_debt_text)
	_collector_menu = VBoxContainer.new()
	box.add_child(_collector_menu)
	_menu_pay_button = Ui.button("")
	_menu_pay_button.pressed.connect(_on_menu_pay_pressed)
	_collector_menu.add_child(_menu_pay_button)
	_menu_take_button = Ui.button("")
	_menu_take_button.pressed.connect(_show_collector_borrow)
	_collector_menu.add_child(_menu_take_button)
	_menu_leave_button = Ui.button("")
	_menu_leave_button.pressed.connect(_on_collector_leave_pressed)
	_collector_menu.add_child(_menu_leave_button)
	_collector_amount_box = VBoxContainer.new()
	box.add_child(_collector_amount_box)
	_debt_slider = HSlider.new()
	_debt_slider.custom_minimum_size = Vector2(300, 16)
	_debt_slider.value_changed.connect(_on_debt_slider_changed)
	_collector_amount_box.add_child(_debt_slider)
	_debt_amount = Ui.label("")
	_collector_amount_box.add_child(_debt_amount)
	var amount_buttons := HBoxContainer.new()
	_collector_amount_box.add_child(amount_buttons)
	_pay_button = Ui.button("")
	_pay_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pay_button.pressed.connect(_on_debt_confirm_pressed)
	amount_buttons.add_child(_pay_button)
	_debt_cancel_button = Ui.button("")
	_debt_cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_debt_cancel_button.pressed.connect(_on_debt_cancel_pressed)
	amount_buttons.add_child(_debt_cancel_button)


func _add_shop_button(text: String, disabled: bool, handler: Callable) -> void:
	var button := Ui.button(text, Vector2(220, 0))
	button.disabled = disabled
	button.pressed.connect(handler)
	_shop_box.add_child(button)


func _add_exchange_button(kind: StringName) -> void:
	var button := Ui.button(
		Loc.t("exchange_%s" % kind, {"count": GameState.exchange_amount(kind)}),
		Vector2(220, 0)
	)
	button.disabled = GameState.exchange_amount(kind) <= 0
	button.pressed.connect(_on_exchange_pressed.bind(kind))
	_exchange_box.add_child(button)


func _rebuild_shop() -> void:
	for child in _shop_box.get_children():
		_shop_box.remove_child(child)
		child.queue_free()
	for child in _exchange_box.get_children():
		_exchange_box.remove_child(child)
		child.queue_free()
	_wallet_label.text = Loc.t("shop_wallet", {"wallet": _wallet_text()})
	for type in GameState.available_glass_types():
		var price := GameState.glass_price(type)
		_add_shop_button(
			Loc.t("shop_buy_glass", {
				"name": Loc.t("glass_%s" % type),
				"count": GameState.glass_count(type),
				"price": Loc.coins(price),
			}),
			not GameState.can_afford(price),
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
				Loc.t("shop_upgrade", {"name": upgrade_name, "level": GameState.level(id), "price": Loc.coins(cost)}),
				not GameState.can_afford(cost),
				_on_upgrade_pressed.bind(id)
			)
	for id in DrinkDB.ids():
		if GameState.is_drink_unlocked(id):
			continue
		var drink := DrinkDB.get_drink(id)
		_add_shop_button(
			Loc.t("shop_unlock", {"name": drink.name_text(), "price": Loc.coins(drink.unlock_cost)}),
			not GameState.can_afford(drink.unlock_cost),
			_on_unlock_pressed.bind(id)
		)
	for kind in EXCHANGES:
		_add_exchange_button(kind)


func _on_glass_pressed(type: StringName) -> void:
	GameState.buy_glass(type)
	_rebuild_shop()


func _on_upgrade_pressed(id: StringName) -> void:
	GameState.buy_upgrade(id)
	_rebuild_shop()


func _on_unlock_pressed(id: StringName) -> void:
	if GameState.unlock_drink(id):
		var glass := DrinkDB.get_drink(id).preferred_glass
		toast(Loc.t("toast_glass_promo", {
			"count": GameState.UNLOCK_PROMO_GLASSES,
			"name": Loc.t("glass_%s" % glass),
		}), 3.0)
	_rebuild_shop()


func _on_exchange_pressed(kind: StringName) -> void:
	GameState.exchange(kind)
	_rebuild_shop()


func _on_continue_pressed() -> void:
	_day_panel.visible = false
	if _shop_from_opening:
		_shop_from_opening = false
		_refresh_opening()
		_opening_panel.visible = true
		return
	day_continue_pressed.emit()


func _on_upgrades_pressed() -> void:
	_shop_from_opening = true
	_opening_panel.visible = false
	_continue_button.text = Loc.t("btn_back")
	_day_text.text = Loc.t("shop_title")
	_rebuild_shop()
	_day_panel.visible = true


# --- debt collector ----------------------------------------------------------

func _on_collector_pressed() -> void:
	collector_requested.emit()
	_open_collector(false)


func _open_collector(forced: bool) -> void:
	_collector_forced = forced
	_opening_panel.visible = false
	_day_panel.visible = false
	if forced:
		_show_collector_pay()
	else:
		_show_collector_menu()
	_debt_panel.visible = true


func _debt_body() -> String:
	return Loc.t("debt_body", {
		"debt": Loc.coins(GameState.month_debt),
		"money": Loc.coins(GameState.money),
		"required": Loc.coins(GameState.required_left()),
	})


func _show_collector_menu() -> void:
	_collector_mode = CollectorMode.MENU
	_debt_text.text = Loc.t("collector_title") + "\n" + _debt_body()
	_collector_menu.visible = true
	_collector_amount_box.visible = false


func _on_menu_pay_pressed() -> void:
	if GameState.month_debt <= 0:
		collector_event.emit(&"no_debt")
	elif GameState.max_payment() <= 0:
		collector_event.emit(&"broke")
	else:
		_show_collector_pay()


func _show_collector_pay() -> void:
	_collector_mode = CollectorMode.PAY
	var info := GameState.collector_info(_collector_forced)
	var min_pay := int(info["min_pay"])
	var max_pay := maxi(int(info["max_pay"]), min_pay)
	_debt_slider.min_value = min_pay
	_debt_slider.max_value = max_pay
	_debt_slider.step = 100 if max_pay - min_pay >= 1000 else 1
	_debt_slider.editable = max_pay > min_pay
	_debt_slider.value = clampi(int(info["required"]), min_pay, max_pay)
	var text := Loc.t("collector_title" if _collector_forced else "paydebt_title") + "\n" + _debt_body()
	if _collector_forced:
		text += "\n" + Loc.t("collector_forced", {"interest": roundi(GameState.UNPAID_INTEREST * 100.0)})
	else:
		text += "\n" + Loc.t("paydebt_hint")
	_debt_text.text = text
	_pay_button.text = Loc.t("btn_pay")
	_debt_cancel_button.visible = not _collector_forced
	_collector_menu.visible = false
	_collector_amount_box.visible = true
	_on_debt_slider_changed(_debt_slider.value)


func _show_collector_borrow() -> void:
	_collector_mode = CollectorMode.BORROW
	_debt_slider.min_value = GameState.BORROW_MIN
	_debt_slider.max_value = GameState.BORROW_MAX
	_debt_slider.step = GameState.BORROW_STEP
	_debt_slider.editable = true
	var suggested := ceili(GameState.cheapest_glass_price() / float(GameState.BORROW_STEP)) * GameState.BORROW_STEP
	_debt_slider.value = clampi(suggested, GameState.BORROW_MIN, GameState.BORROW_MAX)
	_debt_text.text = Loc.t("borrow_title") + "\n" + _debt_body()
	_debt_text.text += "\n" + Loc.t("borrow_hint", {"fee": roundi(GameState.BORROW_FEE * 100.0)})
	_pay_button.text = Loc.t("btn_take")
	_debt_cancel_button.visible = true
	_collector_menu.visible = false
	_collector_amount_box.visible = true
	_on_debt_slider_changed(_debt_slider.value)


func _on_debt_slider_changed(value: float) -> void:
	if _collector_mode == CollectorMode.BORROW:
		_debt_amount.text = Loc.t("collector_borrow_label", {
			"amount": Loc.coins(int(value)),
			"added": Loc.coins(GameState.borrow_debt_added(int(value))),
		})
	else:
		_debt_amount.text = Loc.t("collector_pay_label", {"amount": Loc.coins(int(value))})


func _on_debt_confirm_pressed() -> void:
	var amount := int(_debt_slider.value)
	if _collector_mode == CollectorMode.BORROW:
		var taken := GameState.borrow(amount)
		if taken > 0:
			toast(Loc.t("toast_borrowed", {"amount": Loc.coins(taken), "debt": Loc.coins(GameState.month_debt)}), 3.0)
			collector_event.emit(&"borrowed")
		_show_collector_menu()
		return
	if _collector_forced:
		_debt_panel.visible = false
		debt_confirmed.emit(amount)
		return
	var paid := GameState.pay_debt(amount)
	if paid > 0:
		toast(Loc.t("toast_paid", {"paid": Loc.coins(paid), "debt": Loc.coins(GameState.month_debt)}), 3.0)
		collector_event.emit(&"paid")
	_show_collector_menu()


func _on_debt_cancel_pressed() -> void:
	_show_collector_menu()


func _on_collector_leave_pressed() -> void:
	_debt_panel.visible = false
	collector_left.emit()


func _wallet_text() -> String:
	return Loc.t("wallet_fmt", {"gold": GameState.gold, "silver": GameState.silver, "bronze": GameState.bronze})


func _refresh_opening() -> void:
	_opening_title.text = Loc.t("opening_title", {
		"day": GameState.day,
		"days": GameState.DAYS_PER_MONTH,
		"month": GameState.month,
	})
	_opening_text.text = Loc.t("opening_info", {
		"wallet": _wallet_text(),
		"debt": Loc.coins(GameState.month_debt),
		"required": Loc.coins(GameState.required_left()),
		"slot": _opening_slot,
	})
	_open_button.disabled = not GameState.has_glasses()
	_opening_feedback.text = _glass_hint()


## Shown on the opening screen while the player has no glass at all.
func _glass_hint() -> String:
	if GameState.has_glasses():
		return ""
	if GameState.can_afford(GameState.cheapest_glass_price()):
		return Loc.t("opening_need_glass")
	return Loc.t("opening_need_money")