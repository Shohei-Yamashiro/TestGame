extends Node2D

const Palette := preload("res://scripts/palette.gd")

const SIDE := 96.0
const ROW := SIDE * 0.8660254
const ACCENT_CELL := 560.0
const LINE_COLOR := Color(0.45, 0.7, 1.0, 0.06)
const TILE_CHANCE := 0.07

var camera: Camera2D
var _time := 0.0


func _ready() -> void:
	z_index = -100


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if camera == null:
		return
	var size := get_viewport_rect().size
	var center := camera.get_screen_center_position()
	var top_left := center - size * 0.5 - Vector2(SIDE, SIDE)
	var bottom_right := center + size * 0.5 + Vector2(SIDE, SIDE)
	_draw_tiles(top_left, bottom_right)
	_draw_lattice(top_left, bottom_right)
	_draw_accents(top_left, bottom_right)


func _lattice_point(i: int, j: int) -> Vector2:
	return Vector2(i * SIDE + j * SIDE * 0.5, j * ROW)


func _draw_tiles(top_left: Vector2, bottom_right: Vector2) -> void:
	var j0 := int(floor(top_left.y / ROW))
	var j1 := int(ceil(bottom_right.y / ROW))
	for j in range(j0, j1):
		var i0 := int(floor((top_left.x - j * SIDE * 0.5) / SIDE)) - 1
		var i1 := int(ceil((bottom_right.x - j * SIDE * 0.5) / SIDE)) + 1
		for i in range(i0, i1):
			for up in 2:
				var h := _hash(i, j, up)
				if h > TILE_CHANCE:
					continue
				var tint: Color = Palette.PLAYER if _hash(i, j, up + 7) < 0.6 else Palette.NOVA
				# HDR 2D blends in linear space, so tiny alphas already read clearly on the dark base.
				var alpha := 0.0015 + 0.004 * (0.5 + 0.5 * sin(_time * 1.3 + h * 90.0))
				var tri: PackedVector2Array
				if up == 0:
					tri = PackedVector2Array([_lattice_point(i, j), _lattice_point(i + 1, j), _lattice_point(i, j + 1)])
				else:
					tri = PackedVector2Array([_lattice_point(i + 1, j), _lattice_point(i + 1, j + 1), _lattice_point(i, j + 1)])
				draw_colored_polygon(tri, Color(tint.r, tint.g, tint.b, alpha))


func _draw_lattice(top_left: Vector2, bottom_right: Vector2) -> void:
	var segments := PackedVector2Array()
	var j0 := int(floor(top_left.y / ROW))
	var j1 := int(ceil(bottom_right.y / ROW))
	for j in range(j0, j1 + 1):
		segments.append(Vector2(top_left.x, j * ROW))
		segments.append(Vector2(bottom_right.x, j * ROW))
	var slope := SIDE * 0.5 / ROW
	for sign_value: float in [1.0, -1.0]:
		var c_top := top_left.x - sign_value * top_left.y * slope
		var c_bottom := top_left.x - sign_value * bottom_right.y * slope
		var c_min := minf(c_top, c_bottom)
		var c_max := maxf(c_top, c_bottom) + (bottom_right.x - top_left.x)
		var k := int(floor(c_min / SIDE))
		while k * SIDE <= c_max:
			var c := k * SIDE
			segments.append(Vector2(c + sign_value * top_left.y * slope, top_left.y))
			segments.append(Vector2(c + sign_value * bottom_right.y * slope, bottom_right.y))
			k += 1
	draw_multiline(segments, LINE_COLOR, 1.0)


func _draw_accents(top_left: Vector2, bottom_right: Vector2) -> void:
	var cx0 := int(floor(top_left.x / ACCENT_CELL)) - 1
	var cx1 := int(ceil(bottom_right.x / ACCENT_CELL)) + 1
	var cy0 := int(floor(top_left.y / ACCENT_CELL)) - 1
	var cy1 := int(ceil(bottom_right.y / ACCENT_CELL)) + 1
	for cx in range(cx0, cx1):
		for cy in range(cy0, cy1):
			var h := _hash(cx, cy, 31)
			if h > 0.55:
				continue
			var offset := Vector2(_hash(cx, cy, 41), _hash(cx, cy, 43)) * ACCENT_CELL
			var origin := Vector2(cx, cy) * ACCENT_CELL + offset
			var radius := 50.0 + _hash(cx, cy, 47) * 130.0
			# The backdrop stays on the player's side of the art rule: cool and even-sided.
			var sides := 4 + 2 * int(_hash(cx, cy, 53) * 2.0)
			var spin := (0.05 + h * 0.15) * (1.0 if _hash(cx, cy, 59) < 0.5 else -1.0)
			var tint: Color = Palette.PLAYER if _hash(cx, cy, 61) < 0.5 else Palette.NOVA
			var shape := Palette.regular_polygon(sides, radius, _time * spin)
			for i in shape.size():
				shape[i] += origin
			draw_polyline(Palette.closed(shape), Color(tint.r, tint.g, tint.b, 0.08), 1.5, true)
			var inner := Palette.regular_polygon(sides, radius * 0.62, -_time * spin * 1.4)
			for i in inner.size():
				inner[i] += origin
			draw_polyline(Palette.closed(inner), Color(tint.r, tint.g, tint.b, 0.045), 1.0, true)


func _hash(a: int, b: int, c: int) -> float:
	var n := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0xffff) / 65535.0
