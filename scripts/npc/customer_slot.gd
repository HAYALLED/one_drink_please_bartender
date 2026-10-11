class_name CustomerSlot
extends Area2D

signal kick_pressed(slot: CustomerSlot)

var customer: Customer = null

@onready var body: Polygon2D = $Body
@onready var drink_label: Label = $DrinkLabel
@onready var alert_label: Label = $AlertLabel


func assign(value: Customer) -> void:
	customer = value
	refresh()


func kick() -> void:
	kick_pressed.emit(self)


func refresh() -> void:
	var active := customer != null and customer.state != Customer.State.LEFT
	visible = active
	if not active:
		set_deferred("monitorable", false)
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
		_:
			alert_label.text = "~" if customer.drunk > 0.5 else ""
