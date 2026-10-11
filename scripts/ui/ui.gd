class_name Ui
extends RefCounted

const FONT_SIZE := 10


static func label(text: String = "", align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var node := Label.new()
	node.text = text
	node.horizontal_alignment = align
	node.add_theme_font_size_override("font_size", FONT_SIZE)
	return node


static func button(text: String = "", min_size: Vector2 = Vector2.ZERO) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size = min_size
	node.add_theme_font_size_override("font_size", FONT_SIZE)
	return node


static func confirm(parent: Node, text: String, on_confirmed: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = text
	dialog.ok_button_text = Loc.t("btn_yes")
	dialog.cancel_button_text = Loc.t("btn_no")
	dialog.add_theme_font_size_override("font_size", FONT_SIZE)
	dialog.get_label().add_theme_font_size_override("font_size", FONT_SIZE)
	dialog.get_ok_button().add_theme_font_size_override("font_size", FONT_SIZE)
	dialog.get_cancel_button().add_theme_font_size_override("font_size", FONT_SIZE)
	dialog.confirmed.connect(on_confirmed)
	dialog.canceled.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	parent.add_child(dialog)
	dialog.popup_centered(Vector2i(300, 90))
