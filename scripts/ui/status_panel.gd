extends Control

# Top-left status in two slim rows: the level with an XP bar, then the HP bar.

const LEVEL_SIZE := 24
const BAR_LEFT := 62.0
const BAR_RIGHT := 196.0
const XP_TOP := 16.0
const XP_HEIGHT := 6.0
const HP_TOP := 42.0
const HP_HEIGHT := 14.0
const BAR_SKEW := 5.0

@export var hp_color := Color(1, 0.3, 0.38)
@export var hp_back := Color(0.3, 0.06, 0.1, 0.9)
@export var xp_color := Color(0.45, 1, 0.8)
@export var xp_back := Color(0.08, 0.2, 0.2, 0.9)
@export var text_color := Color(0.96, 0.97, 0.98)
@export var caption_color := Color(0.7, 0.85, 0.95, 0.75)

var level := 1
var xp_ratio := 0.0
var hp := 100
var max_hp := 100
var _time := 0.0


func set_values(new_level: int, new_xp_ratio: float, new_hp: int, new_max_hp: int, time: float) -> void:
	level = new_level
	xp_ratio = clampf(new_xp_ratio, 0.0, 1.0)
	hp = new_hp
	max_hp = new_max_hp
	_time = time
	queue_redraw()


func _bar(top: float, height: float, ratio: float, color: Color) -> void:
	var right := lerpf(BAR_LEFT, BAR_RIGHT, ratio)
	draw_colored_polygon(PackedVector2Array([
		Vector2(BAR_LEFT + BAR_SKEW, top), Vector2(right + BAR_SKEW, top),
		Vector2(right, top + height), Vector2(BAR_LEFT, top + height),
	]), color)


func _draw() -> void:
	var font := get_theme_font("font", "Label")
	draw_string(font, Vector2(0, XP_TOP + 10), "Lv", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, caption_color)
	draw_string(font, Vector2(20, XP_TOP + 12), str(level), HORIZONTAL_ALIGNMENT_LEFT, -1, LEVEL_SIZE, text_color)
	_bar(XP_TOP, XP_HEIGHT, 1.0, xp_back)
	if xp_ratio > 0.0:
		_bar(XP_TOP, XP_HEIGHT, xp_ratio, xp_color)
	draw_string(font, Vector2(0, HP_TOP + HP_HEIGHT - 1), "HP", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, hp_color)
	_bar(HP_TOP, HP_HEIGHT, 1.0, hp_back)
	var ratio := clampf(float(hp) / float(maxi(1, max_hp)), 0.0, 1.0)
	if ratio > 0.0:
		var fill := hp_color
		if ratio <= 0.3:
			fill = hp_color.lerp(Color.WHITE, 0.35 + 0.25 * sin(_time * 10.0))
		_bar(HP_TOP, HP_HEIGHT, ratio, fill)
