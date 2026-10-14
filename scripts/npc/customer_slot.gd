class_name CustomerSlot
extends Area2D

signal kick_pressed(slot: CustomerSlot)

const SPEECH_TIME := 2.6
const SPEECH_FONT_SIZE := 8
const SPEECH_Y := -92.0
const SPEECH_LIFT := 13.0
const BRAWL_SHAKE := 1.5

var customer: Customer = null

var _speech: Label
var _speech_left := 0.0
var _trait_label: Label

@onready var body: Polygon2D = $Body
@onready var drink_label: Label = $DrinkLabel
@onready var alert_label: Label = $AlertLabel


func _ready() -> void:
	_speech = Label.new()
	_speech.visible = false
	_speech.z_as_relative = false
	_speech.z_index = 20
	_speech.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speech.add_theme_font_size_override("font_size", SPEECH_FONT_SIZE)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.0, 0.0, 0.0, 0.72)
	box.set_content_margin_all(2.0)
	_speech.add_theme_stylebox_override("normal", box)
	add_child(_speech)
	if OS.is_debug_build():
		_trait_label = Label.new()
		_trait_label.position = Vector2(-16.0, -4.0)
		_trait_label.size = Vector2(32.0, 10.0)
		_trait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_trait_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_trait_label.add_theme_font_size_override("font_size", 6)
		_trait_label.modulate = Color(1.0, 0.9, 0.3)
		add_child(_trait_label)
	Loc.language_changed.connect(_on_language_changed)


func _process(delta: float) -> void:
	if _speech_left > 0.0:
		_speech_left -= delta
		if _speech_left <= 0.0:
			_speech.visible = false
	var brawling := customer != null and customer.state == Customer.State.BRAWLING
	body.position = Vector2(randf_range(-BRAWL_SHAKE, BRAWL_SHAKE), randf_range(-BRAWL_SHAKE, BRAWL_SHAKE)) if brawling else Vector2.ZERO


func assign(value: Customer) -> void:
	customer = value
	_speech_left = 0.0
	_speech.visible = false
	refresh()


func kick() -> void:
	kick_pressed.emit(self)


## Shows a speech bubble above the customer for a short time. Empty text does nothing.
func say(text: String, duration: float = SPEECH_TIME) -> void:
	if text.is_empty() or customer == null or customer.state == Customer.State.LEFT:
		return
	_speech.text = text
	_speech.reset_size()
	var lift := SPEECH_LIFT if get_index() % 2 == 1 else 0.0
	_speech.position = Vector2(-_speech.size.x * 0.5, SPEECH_Y - lift)
	_speech.visible = true
	_speech_left = duration


func refresh() -> void:
	var active := customer != null and customer.state != Customer.State.LEFT
	visible = active
	if not active:
		set_deferred("monitorable", false)
		_speech.visible = false
		return
	body.color = Color.from_hsv(0.33 * customer.mood, 0.55, 0.85)
	var drink := DrinkDB.get_drink(customer.drink_id)
	drink_label.text = "" if customer.served else drink.name_text()
	alert_label.modulate = Color.WHITE
	match customer.state:
		Customer.State.AGITATED:
			alert_label.text = "!!"
			alert_label.modulate = Color.RED
		Customer.State.OBJECTING:
			alert_label.text = "..."
			alert_label.modulate = Color.ORANGE
		Customer.State.BRAWLING:
			alert_label.text = "XX"
			alert_label.modulate = Color.RED
		_:
			alert_label.text = "~" if customer.drunk > 0.5 else ""
	if _trait_label != null:
		_trait_label.text = CustomerTrait.name_text(customer.trait_id)


func _on_language_changed(_code: String) -> void:
	_speech.visible = false
	_speech_left = 0.0
	if customer != null:
		refresh()