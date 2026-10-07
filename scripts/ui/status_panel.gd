extends Control

# Top-left status: a hexagon level badge whose rim fills with XP, and an HP bar that grows with max HP.

const Palette := preload("res://scripts/palette.gd")

const BADGE_CENTER := Vector2(36, 40)
const BADGE_RADIUS := 30.0
const BAR_LEFT := 112.0
const BAR_TOP := 16.0
const BAR_HEIGHT := 16.0
const BAR_SKEW := 6.0
const PX_PER_HP := 1.6
const TICK_HP := 20

@export var hp_color := Color(1, 0.3, 0.38)
@export var hp_back := Color(0.3, 0.06, 0.1, 0.9)
@export var xp_color := Color(0.45, 1, 0.8)
@export var badge_fill := Color(0.04, 0.12, 0.14, 0.9)
@export var text_color := Color(0.96, 0.97, 0.98)
@export var caption_color := Color(0.7, 0.85, 0.95, 0.75)

var level := 1
var xp_ratio := 0.0
var hp := 100
var max_hp := 100
var _time := 0.0


static func bar_width(maximum: int) -> float:
	return PX_PER_HP * float(maxi(1, maximum))


func set_values(new_level: int, new_xp_ratio: float, new_hp: int, new_max_hp: int, time: float) -> void:
	level = new_level
	xp_ratio = clampf(new_xp_ratio, 0.0, 1.0)
	hp = new_hp
	max_hp = new_max_hp
	_time = time
	queue_redraw()


func _hexagon(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for k in 6:
		points.append(center + Vector2.from_angle(-PI / 2.0 + TAU * float(k) / 6.0) * radius)
	return points


func _bar(left: float, width: float, color: Color) -> void:
	var top := BAR_TOP
	var bottom := BAR_TOP + BAR_HEIGHT
	draw_colored_polygon(PackedVector2Array([
		Vector2(left + BAR_SKEW, top), Vector2(left + width + BAR_SKEW, top),
		Vector2(left + width, bottom), Vector2(left, bottom),
	]), color)


func _draw() -> void:
	var font := get_theme_font("font", "Label")
	# Level badge: hexagon with the level inside; the rim traces XP from the top corner clockwise.
	var hex := _hexagon(BADGE_CENTER, BADGE_RADIUS)
	draw_colored_polygon(hex, badge_fill)
	var dim := xp_color
	dim.a = 0.25
	draw_polyline(Palette.closed(hex), dim, 3.0, true)
	if xp_ratio > 0.0:
		var rim := PackedVector2Array([hex[0]])
		var sides := xp_ratio * 6.0
		for k in int(sides):
			rim.append(hex[(k + 1) % 6])
		var part := sides - floorf(sides)
		if part > 0.0:
			var a := hex[int(sides) % 6]
			rim.append(a.lerp(hex[(int(sides) + 1) % 6], part))
		draw_polyline(rim, xp_color, 3.0, true)
	draw_string(font, BADGE_CENTER + Vector2(-BADGE_RADIUS, -14), "LV", HORIZONTAL_ALIGNMENT_CENTER, BADGE_RADIUS * 2.0, 12, caption_color)
	draw_string(font, BADGE_CENTER + Vector2(-BADGE_RADIUS, 13), str(level), HORIZONTAL_ALIGNMENT_CENTER, BADGE_RADIUS * 2.0, 26, text_color)
	# HP bar: a fixed length per HP so a bigger max HP visibly lengthens it, with a tick every TICK_HP.
	draw_string(font, Vector2(BAR_LEFT - 36, BAR_TOP + BAR_HEIGHT - 1), "HP", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, hp_color)
	var full := bar_width(max_hp)
	_bar(BAR_LEFT, full, hp_back)
	var ratio := clampf(float(hp) / float(maxi(1, max_hp)), 0.0, 1.0)
	if ratio > 0.0:
		var fill := hp_color
		if ratio <= 0.3:
			fill = hp_color.lerp(Color.WHITE, 0.35 + 0.25 * sin(_time * 10.0))
		_bar(BAR_LEFT, full * ratio, fill)
	var tick := Color(0.02, 0.03, 0.06, 0.8)
	for value in range(TICK_HP, max_hp, TICK_HP):
		var x := BAR_LEFT + PX_PER_HP * float(value)
		draw_line(Vector2(x + BAR_SKEW, BAR_TOP), Vector2(x, BAR_TOP + BAR_HEIGHT), tick, 2.0)
	var edge := hp_color
	edge.a = 0.6
	draw_polyline(PackedVector2Array([
		Vector2(BAR_LEFT + BAR_SKEW, BAR_TOP), Vector2(BAR_LEFT + full + BAR_SKEW, BAR_TOP),
		Vector2(BAR_LEFT + full, BAR_TOP + BAR_HEIGHT), Vector2(BAR_LEFT, BAR_TOP + BAR_HEIGHT),
		Vector2(BAR_LEFT + BAR_SKEW, BAR_TOP),
	]), edge, 1.0, true)

