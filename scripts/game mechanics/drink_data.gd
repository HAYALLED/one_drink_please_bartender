class_name DrinkData
extends Resource

@export var id: StringName = &""
@export var price: int = 10
@export var color: Color = Color.WHITE
@export var foam_color: Color = Color.WHITE
@export_range(0.0, 8.0, 0.5) var foam_px: float = 0.0
@export_range(0.1, 1.0, 0.05) var target_fill: float = 0.8
@export_range(0.05, 0.6, 0.01) var tolerance: float = 0.25
@export var pour_rate: float = 0.5
@export var unlock_cost: int = 0
@export_range(0.0, 1.0, 0.01) var alcohol: float = 0.0
@export var preferred_glass: StringName = &"glass"
@export_range(0.0, 1.0, 0.05) var wrong_glass_penalty: float = 0.15


func name_text() -> String:
	return Loc.t("drink_%s" % id)
