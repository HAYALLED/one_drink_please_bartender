class_name DebtCollectorPlace
extends Node2D

## The debt collector's office. BarGame shows it for the month-end collection and for voluntary visits.
## "Collector" is the only one who talks. "GuardLeft" / "GuardRight" are scenery: no dialogue, no input.
## Each character is a Node2D whose origin is the feet. A "Placeholder" child (polygons) is shown until
## character art exists in the npc folders; then an NpcView replaces it.

const NPC_VIEW_SCENE: PackedScene = preload("res://scenes/npc/npc_view.tscn")
const SPEECH_TIME := 3.2
const SPEECH_FONT_SIZE := 8
## Top-center of the speech bubble.
const SPEECH_ANCHOR := Vector2(320.0, 58.0)
## Fixed seeds: every visit shows the same three characters.
const LOOKS := {
	"Collector": {"seed": 7101, "gender": &"male"},
	"GuardLeft": {"seed": 7202, "gender": &"male"},
	"GuardRight": {"seed": 7303, "gender": &"male"},
}
## What the collector says for each HUD event.
const REACTIONS := {
	&"paid": &"collector_paid",
	&"borrowed": &"collector_borrow",
	&"broke": &"collector_broke",
	&"no_debt": &"collector_no_debt",
}

@export var npc_scale := 1.0

var _speech: Label
var _speech_left := 0.0


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
	_build_characters()
	Loc.language_changed.connect(_on_language_changed)


func _process(delta: float) -> void:
	if _speech_left <= 0.0:
		return
	_speech_left -= delta
	if _speech_left <= 0.0:
		_speech.visible = false


## Shows the office. Month end: the collector comes to collect. Otherwise he greets a visitor.
func open(forced: bool) -> void:
	visible = true
	say(&"collector_forced" if forced else &"collector_greet")


func close() -> void:
	visible = false
	_speech.visible = false
	_speech_left = 0.0


## Collector reacts to something the player did. Unknown events are ignored.
func react(kind: StringName) -> void:
	if REACTIONS.has(kind):
		say(REACTIONS[kind])


func say(category: StringName) -> void:
	var text := NpcDialogue.line(category, &"")
	if text.is_empty():
		return
	_speech.text = text
	_speech.reset_size()
	_speech.position = Vector2(SPEECH_ANCHOR.x - _speech.size.x * 0.5, SPEECH_ANCHOR.y)
	_speech.visible = true
	_speech_left = SPEECH_TIME


func _build_characters() -> void:
	var used := PackedStringArray()
	for node_name: String in LOOKS:
		var holder := get_node_or_null(node_name) as Node2D
		if holder == null:
			continue
		var look: Dictionary = LOOKS[node_name]
		var rng := RandomNumberGenerator.new()
		rng.seed = int(look["seed"])
		var appearance := NpcGenerator.generate({"gender": look["gender"]}, used, rng)
		used.append(appearance.signature())
		_attach_view(holder, appearance)


func _attach_view(holder: Node2D, appearance: NpcAppearance) -> void:
	var view := NPC_VIEW_SCENE.instantiate() as NpcView
	view.name = "View"
	view.scale = Vector2.ONE * npc_scale
	holder.add_child(view)
	view.apply(appearance)
	var layers := view.get_node("Layers")
	if layers.get_child_count() == 0:
		holder.remove_child(view)
		view.queue_free()
		return
	var placeholder := holder.get_node_or_null("Placeholder") as CanvasItem
	if placeholder != null:
		placeholder.visible = false
	# Sprites are centered on the view origin: lift the view so the feet stand on the holder origin.
	var first := layers.get_child(0) as Sprite2D
	if first != null and first.texture != null:
		view.position.y = -float(first.texture.get_height()) * npc_scale * 0.5


func _on_language_changed(_code: String) -> void:
	_speech.visible = false
	_speech_left = 0.0
