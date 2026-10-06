extends Node2D

const Palette := preload("res://scripts/palette.gd")

const LOGO_SIZE := 88
const LOGO_SPACING := 8.0
const SUB_SIZE := 22
const PINK := Color(1.0, 0.3, 0.72)
const CYAN := Color(0.35, 0.95, 1.0)

var camera: Camera2D
var sub_font: Font
var _logo_font := SystemFont.new()
var _time := 0.0


func _ready() -> void:
	z_index = 10
	_logo_font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	_logo_font.font_weight = 700


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if camera == null:
		return
	var center := camera.get_screen_center_position() + Vector2(0, -110)
	var layers := [
		[6, 150.0, 0.25, Palette.PLAYER, 0.9],
		[3, 118.0, -0.4, Palette.ENEMIES[0], 0.8],
		[5, 92.0, 0.6, Palette.ENEMIES[2], 0.8],
		[6, 210.0, -0.12, Palette.PLAYER, 0.35],
	]
	for layer in layers:
		var sides: int = layer[0]
		var base_radius: float = layer[1]
		var radius := base_radius * (1.0 + 0.03 * sin(_time * 1.5 + base_radius * 0.05))
		var shape := Palette.regular_polygon(sides, radius, _time * float(layer[2]))
		for i in shape.size():
			shape[i] += center
		draw_polyline(Palette.closed(shape), Palette.hdr(layer[3], layer[4]), 2.0, true)
	_draw_logo(center)


func _draw_logo(center: Vector2) -> void:
	var words := [["NEON", PINK], ["GEOMETRY", CYAN]]
	var gap := 34.0
	var total := gap
	for word in words:
		total += _word_width(word[0])
	var x := center.x - total * 0.5
	var baseline := center.y + LOGO_SIZE * 0.3
	for word in words:
		for ch in str(word[0]):
			var code := ch.unicode_at(0)
			_draw_neon_char(Vector2(x, baseline), code, word[1])
			x += _logo_font.get_char_size(code, LOGO_SIZE).x + LOGO_SPACING
		x += gap - LOGO_SPACING
	# Tube lines framing the logo.
	var half := total * 0.5 + 20.0
	var top := center.y - LOGO_SIZE * 0.62
	var bottom := center.y + LOGO_SIZE * 0.52
	_neon_line(Vector2(center.x - half, top), Vector2(center.x + half * 0.35, top), CYAN)
	_neon_line(Vector2(center.x - half * 0.35, bottom), Vector2(center.x + half, bottom), PINK)
	if sub_font:
		var sub := "幾　何　学　サ　バ　イ　バ　ー"
		var sub_pos := Vector2(center.x - 400.0, bottom + 42.0)
		for pass_data in [[16, 0.04], [9, 0.08]]:
			var glow := PINK
			glow.a = pass_data[1]
			draw_string_outline(sub_font, sub_pos, sub, HORIZONTAL_ALIGNMENT_CENTER, 800.0, SUB_SIZE, pass_data[0], glow)
		draw_string(sub_font, sub_pos, sub, HORIZONTAL_ALIGNMENT_CENTER, 800.0, SUB_SIZE, PINK.lerp(Color.WHITE, 0.35))


func _word_width(word: String) -> float:
	var width := 0.0
	for ch in word:
		width += _logo_font.get_char_size(ch.unicode_at(0), LOGO_SIZE).x + LOGO_SPACING
	return width - LOGO_SPACING


# Many wide, very faint outlines stack into a soft haze; the core stays saturated so it never blows out.
const HAZE := [[64, 0.045], [50, 0.055], [38, 0.07], [27, 0.085], [17, 0.1], [9, 0.13]]


func _draw_neon_char(pos: Vector2, code: int, color: Color) -> void:
	var text := String.chr(code)
	for pass_data in HAZE:
		var glow := color
		glow.a = pass_data[1]
		draw_char_outline(_logo_font, pos, text, LOGO_SIZE, pass_data[0], glow)
	draw_char(_logo_font, pos, text, LOGO_SIZE, Palette.hdr(color.lerp(Color.WHITE, 0.15), 1.15))


func _neon_line(a: Vector2, b: Vector2, color: Color) -> void:
	for pass_data in [[22.0, 0.025], [12.0, 0.05], [6.0, 0.09]]:
		var halo := color
		halo.a = pass_data[1]
		draw_line(a, b, halo, pass_data[0], true)
	draw_line(a, b, Palette.hdr(color.lerp(Color.WHITE, 0.15), 1.1), 2.0, true)
