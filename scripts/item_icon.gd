extends Control

# Badge for a weapon or passive: a white glyph on a tile of the item's own colour, with level pips underneath.
# Weapons sit on rounded squares and passives on circles. Icons are exempt from the warm/cool art rule,
# so every item can have a hue of its own.

const Palette := preload("res://scripts/palette.gd")
const Balance := preload("res://scripts/balance.gd")

const COLORS := {
	"blaster": Color(0.2, 0.55, 1.0),
	"homing": Color(0.2, 0.78, 0.4),
	"orbit": Color(0.55, 0.38, 1.0),
	"nova": Color(1.0, 0.55, 0.15),
	"laser": Color(1.0, 0.25, 0.45),
	"wings": Color(0.15, 0.8, 0.9),
	"chain": Color(0.95, 0.8, 0.15),
	"tesseract": Color(0.1, 0.65, 0.6),
	"mine": Color(0.9, 0.3, 0.15),
	"drain": Color(0.8, 0.25, 0.85),
	"attack": Color(1.0, 0.3, 0.25),
	"rate": Color(1.0, 0.75, 0.15),
	"move": Color(0.35, 0.85, 0.3),
	"magnet": Color(0.95, 0.4, 0.75),
	"max_hp": Color(0.95, 0.35, 0.5),
	"regen": Color(0.2, 0.8, 0.6),
	"area": Color(1.0, 0.5, 0.2),
	"armor": Color(0.5, 0.6, 0.78),
	"growth": Color(0.3, 0.65, 1.0),
	"knock": Color(0.6, 0.45, 1.0),
}
const GLYPH := Color(1.0, 1.0, 1.0, 0.95)
const GOLD := Color(1.0, 0.85, 0.35)
var item_id := ""
var is_weapon := true
var level := 0
# Highlights the pip that the next pick would fill.
var preview := false
@export var icon_size := 44.0


func configure(id: String, weapon: bool, lv: int, show_preview: bool = false) -> void:
	item_id = id
	is_weapon = weapon
	level = lv
	preview = show_preview
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(icon_size, icon_size + 14.0)
	size = custom_minimum_size


func _draw() -> void:
	var s := icon_size
	var c := Vector2(s, s) * 0.5
	var color: Color = COLORS.get(item_id, Color(0.5, 0.6, 0.7))
	var filled := item_id != ""
	var special := is_weapon and level >= Balance.SPECIAL_STAGE
	var tile := _tile(c, s * 0.5)
	if not filled:
		draw_colored_polygon(tile, Color(0.05, 0.07, 0.1, 0.45))
		draw_polyline(Palette.closed(tile), Color(0.5, 0.6, 0.7, 0.3), 1.0, true)
		return
	draw_colored_polygon(tile, color.darkened(0.35))
	# A lighter cap over the upper half gives the tile a little depth.
	var cap := PackedVector2Array()
	for p in tile:
		cap.append(Vector2(p.x, minf(p.y, c.y)))
	draw_colored_polygon(cap, Color(color.r, color.g, color.b, 0.45))
	if special:
		draw_polyline(Palette.closed(_tile(c, s * 0.5 + 1.5)), GOLD, 3.0, true)
	else:
		draw_polyline(Palette.closed(tile), color.lightened(0.35), 1.5, true)
	_draw_symbol(c, s * 0.34, GLYPH)
	_draw_pips(Vector2(s * 0.5, s + 7.0 * _pip_scale()), color.lightened(0.2))


# Rounded square for weapons, circle for passives.
func _tile(c: Vector2, r: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	if not is_weapon:
		for k in 32:
			points.append(c + Vector2.from_angle(TAU * float(k) / 32.0) * r)
		return points
	var corner := r * 0.32
	var inner := r - corner
	for q in 4:
		var center := c + Vector2(inner if q == 0 or q == 3 else -inner, inner if q < 2 else -inner)
		for k in 5:
			points.append(center + Vector2.from_angle(PI * 0.5 * float(q) + PI * 0.125 * float(k)) * corner)
	return points


const SEG_WIDTH := 5.0
const SEG_SPECIAL_WIDTH := 8.0
const SEG_POINT := 3.0
const SEG_HEIGHT := 8.0
const SEG_GAP := 1.0


# Pips are sized for a 44px icon and shrink with smaller ones so the row never overruns its tile.
func _pip_scale() -> float:
	return minf(1.0, icon_size / 44.0)


# A row of interlocking right-pointing hexagons, one per stage, reading like a single arrow gauge.
func _draw_pips(center: Vector2, color: Color) -> void:
	var k := _pip_scale()
	var count := Balance.MAX_STAGE + (1 if is_weapon else 0)
	var total := (SEG_POINT - SEG_GAP) * k
	for i in count:
		total += ((SEG_SPECIAL_WIDTH if i + 1 == Balance.SPECIAL_STAGE else SEG_WIDTH) + SEG_GAP) * k
	var x := center.x - total * 0.5
	for i in count:
		var stage := i + 1
		var width := (SEG_SPECIAL_WIDTH if stage == Balance.SPECIAL_STAGE else SEG_WIDTH) * k
		var owned := stage <= level and not (preview and stage == level)
		var next := preview and stage == level
		var tint := GOLD if stage == Balance.SPECIAL_STAGE else color
		var seg := _arrow_hexagon(x, center.y, width, k)
		if owned:
			draw_colored_polygon(seg, tint)
		elif next:
			draw_colored_polygon(seg, Color.WHITE)
		else:
			draw_polyline(Palette.closed(seg), Color(tint.r, tint.g, tint.b, 0.4), 1.0, true)
		x += width + SEG_GAP * k


# Notched on the left and pointed on the right, so each segment nests into the previous one.
func _arrow_hexagon(left: float, mid_y: float, width: float, k: float) -> PackedVector2Array:
	var top := mid_y - SEG_HEIGHT * k * 0.5
	var bottom := mid_y + SEG_HEIGHT * k * 0.5
	var point := SEG_POINT * k
	return PackedVector2Array([
		Vector2(left, top), Vector2(left + width, top), Vector2(left + width + point, mid_y),
		Vector2(left + width, bottom), Vector2(left, bottom), Vector2(left + point, mid_y),
	])


func _draw_symbol(c: Vector2, r: float, color: Color) -> void:
	match item_id:
		"blaster":
			# A plasma dart flying to the upper right, trailing speed streaks.
			var dart := _along(c, r, -PI * 0.25, [
				Vector2(1.05, 0), Vector2(0.3, 0.36), Vector2(0.42, 0.12), Vector2(-0.3, 0.12),
				Vector2(-0.3, -0.12), Vector2(0.42, -0.12), Vector2(0.3, -0.36),
			])
			draw_colored_polygon(dart, color)
			var streaks := _along(c, r, -PI * 0.25, [
				Vector2(-0.5, 0), Vector2(-1.1, 0), Vector2(-0.45, 0.32), Vector2(-0.85, 0.32),
				Vector2(-0.45, -0.32), Vector2(-0.85, -0.32),
			])
			draw_line(streaks[0], streaks[1], color, 2.5, true)
			draw_line(streaks[2], streaks[3], Color(color.r, color.g, color.b, 0.6), 1.5, true)
			draw_line(streaks[4], streaks[5], Color(color.r, color.g, color.b, 0.6), 1.5, true)
		"homing":
			# A missile curving in on a reticle, its trail fading toward the launch point.
			var target := c + Vector2(r * 0.45, -r * 0.45)
			draw_arc(target, r * 0.4, 0.0, TAU, 20, color, 1.5, true)
			for k in 4:
				var d := Vector2.from_angle(PI * 0.5 * float(k))
				draw_line(target + d * r * 0.28, target + d * r * 0.58, color, 1.5, true)
			var start := c + Vector2(-r * 0.95, r * 0.8)
			var bend := c + Vector2(r * 0.5, r * 0.95)
			var head := c + Vector2(r * 0.12, -r * 0.05)
			var trail := PackedVector2Array()
			for i in 13:
				var t := float(i) / 12.0
				trail.append(start.lerp(bend, t).lerp(bend.lerp(head, t), t))
			for i in 12:
				draw_line(trail[i], trail[i + 1], Color(color.r, color.g, color.b, 0.2 + 0.8 * float(i) / 11.0), 2.5, true)
			var dir := (head - trail[11]).normalized()
			var side := dir.orthogonal() * r * 0.3
			draw_colored_polygon(PackedVector2Array([head + dir * r * 0.5, head + side, head - dir * r * 0.05, head - side]), color)
		"orbit":
			draw_arc(c, r * 0.9, 0.0, TAU, 24, Color(color.r, color.g, color.b, 0.6), 1.5, true)
			draw_circle(c, r * 0.18, color)
			for i in 4:
				var p := c + Vector2.from_angle(-PI * 0.5 + TAU * float(i) / 4.0) * r * 0.9
				var d := r * 0.26
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)]), color)
		"nova":
			draw_circle(c, r * 0.22, color)
			draw_arc(c, r * 0.6, 0.0, TAU, 24, color, 2.0, true)
			draw_arc(c, r * 1.0, 0.0, TAU, 28, Color(color.r, color.g, color.b, 0.5), 1.5, true)
		"laser":
			var a := c + Vector2(-r, r * 0.8)
			var b := c + Vector2(r, -r * 0.8)
			draw_line(a, b, Color(color.r, color.g, color.b, 0.35), 7.0, true)
			draw_line(a, b, color, 2.5, true)
			draw_circle(a, r * 0.22, color)
		"wings":
			for side in [-1.0, 1.0]:
				for i in 3:
					var dir := Vector2.from_angle(PI * 0.5 + side * (0.35 + 0.4 * float(i)))
					var base := c + Vector2(0, r * 0.8)
					var tip := base - dir * r * (1.75 - 0.25 * float(i))
					var normal := dir.orthogonal() * (r * 0.24)
					draw_colored_polygon(PackedVector2Array([base + normal * 0.3, (base + tip) * 0.5 + normal, tip, base - normal * 0.3]), Color(color.r, color.g, color.b, 1.0 - 0.22 * float(i)))
		"chain":
			# A glowing lightning bolt with two sparkles beside it.
			var bolt := PackedVector2Array([
				c + Vector2(r * 0.3, -r * 1.05), c + Vector2(-r * 0.5, r * 0.1), c + Vector2(-r * 0.02, r * 0.1),
				c + Vector2(-r * 0.32, r * 1.0), c + Vector2(r * 0.55, -r * 0.22), c + Vector2(r * 0.08, -r * 0.22),
			])
			draw_polyline(Palette.closed(bolt), Color(color.r, color.g, color.b, 0.25), 5.0, true)
			draw_colored_polygon(bolt, color)
			for p in [c + Vector2(-r * 0.75, -r * 0.55), c + Vector2(r * 0.8, r * 0.45)]:
				var d := r * 0.14
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -d * 1.6), p + Vector2(d, 0), p + Vector2(0, d * 1.6), p + Vector2(-d, 0)]), Color(color.r, color.g, color.b, 0.8))
		"tesseract":
			var outer := r * 0.85
			var inner := r * 0.4
			var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
			for k in 4:
				var p: Vector2 = corners[k]
				var q: Vector2 = corners[(k + 1) % 4]
				draw_line(c + p * outer, c + q * outer, color, 2.0, true)
				draw_line(c + p * inner, c + q * inner, color, 2.0, true)
				draw_line(c + p * outer, c + p * inner, Color(color.r, color.g, color.b, 0.6), 1.5, true)
		"mine":
			var star := PackedVector2Array()
			for k in 8:
				star.append(c + Vector2.from_angle(PI * float(k) / 4.0) * (r * 0.95 if k % 2 == 0 else r * 0.45))
			draw_polyline(Palette.closed(star), color, 2.0, true)
			draw_circle(c, r * 0.22, color)
		"drain":
			var a := c + Vector2(-r * 0.62, r * 0.62)
			var b := c + Vector2(r * 0.62, -r * 0.62)
			draw_line(a, b, Color(color.r, color.g, color.b, 0.6), 1.5, true)
			var big := r * 0.3
			var small := r * 0.16
			draw_colored_polygon(PackedVector2Array([a + Vector2(0, -big), a + Vector2(big, 0), a + Vector2(0, big), a + Vector2(-big, 0)]), color)
			draw_polyline(Palette.closed(PackedVector2Array([b + Vector2(0, -big), b + Vector2(big, 0), b + Vector2(0, big), b + Vector2(-big, 0)])), color, 2.0, true)
			for t in [0.35, 0.65]:
				var p := a.lerp(b, t)
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -small), p + Vector2(small, 0), p + Vector2(0, small), p + Vector2(-small, 0)]), color)
		"attack":
			# A sword pointing to the upper right.
			var angle := -PI * 0.25
			draw_colored_polygon(_along(c, r, angle, [
				Vector2(1.1, 0), Vector2(0.85, 0.15), Vector2(-0.3, 0.15), Vector2(-0.3, -0.15), Vector2(0.85, -0.15),
			]), color)
			var hilt := _along(c, r, angle, [Vector2(-0.35, 0.42), Vector2(-0.35, -0.42), Vector2(-0.38, 0), Vector2(-0.78, 0)])
			draw_line(hilt[0], hilt[1], color, 3.0, true)
			draw_line(hilt[2], hilt[3], color, 3.5, true)
			draw_circle(_along(c, r, angle, [Vector2(-0.88, 0)])[0], r * 0.13, color)
		"rate":
			# A clock whose hand has just swept a quarter turn.
			draw_colored_polygon(_sector(c, r * 0.8, -PI * 0.5, 0.0), Color(color.r, color.g, color.b, 0.3))
			draw_arc(c, r * 0.95, 0.0, TAU, 32, color, 2.0, true)
			for k in 4:
				var d := Vector2.from_angle(PI * 0.5 * float(k))
				draw_line(c + d * r * 0.72, c + d * r * 0.95, color, 2.0, true)
			draw_line(c, c + Vector2(r * 0.72, 0), color, 2.5, true)
			draw_line(c, c + Vector2.from_angle(-PI * 0.5 - 0.5) * r * 0.5, color, 2.5, true)
			draw_circle(c, r * 0.13, color)
		"move":
			for i in 2:
				var x := -r * 0.55 + float(i) * r * 0.65
				draw_polyline(PackedVector2Array([c + Vector2(x, -r * 0.7), c + Vector2(x + r * 0.55, 0), c + Vector2(x, r * 0.7)]), color, 3.0, true)
		"magnet":
			# A horseshoe magnet with a small gem being drawn in.
			draw_arc(c + Vector2(0, -r * 0.1), r * 0.6, 0.0, PI, 16, color, r * 0.32, true)
			for side in [-1.0, 1.0]:
				var x: float = side * r * 0.6
				draw_line(c + Vector2(x, -r * 0.1), c + Vector2(x, -r * 0.75), color, r * 0.32, true)
			var g := c + Vector2(0, -r * 0.55)
			var gs := r * 0.2
			draw_colored_polygon(PackedVector2Array([g + Vector2(0, -gs), g + Vector2(gs, 0), g + Vector2(0, gs), g + Vector2(-gs, 0)]), color)
		"max_hp":
			var heart := PackedVector2Array()
			for k in 40:
				var t := TAU * float(k) / 40.0
				var x := 16.0 * pow(sin(t), 3)
				var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
				heart.append(c + Vector2(x, -y - 2.0) * r / 16.0)
			draw_colored_polygon(heart, color)
		"regen":
			draw_colored_polygon(_cross(c, r * 0.5, r * 0.18), color)
			for side in [0.0, PI]:
				draw_arc(c, r * 0.9, side - 0.4, side + 1.3, 12, color, 2.0, true)
				var tip := c + Vector2.from_angle(side + 1.3) * r * 0.9
				var d := Vector2.from_angle(side + 1.3 + PI * 0.5) * r * 0.3
				draw_colored_polygon(PackedVector2Array([tip + d, tip + d.orthogonal() * 0.7, tip - d.orthogonal() * 0.7]), color)
		"area":
			for i in 3:
				var size := r * (0.35 + 0.33 * float(i))
				var diamond := PackedVector2Array([c + Vector2(0, -size), c + Vector2(size, 0), c + Vector2(0, size), c + Vector2(-size, 0)])
				if i == 0:
					draw_colored_polygon(diamond, color)
				else:
					draw_polyline(Palette.closed(diamond), Color(color.r, color.g, color.b, 1.0 - 0.3 * float(i)), 1.5, true)
		"armor":
			var shield := Palette.regular_polygon(6, r * 1.0, PI / 6.0)
			for i in shield.size():
				shield[i] += c
			draw_polyline(Palette.closed(shield), color, 2.0, true)
			var core := Palette.regular_polygon(6, r * 0.55, PI / 6.0)
			for i in core.size():
				core[i] += c
			draw_colored_polygon(core, color)
		"growth":
			for i in 2:
				var y := r * 0.55 - float(i) * r * 0.65
				draw_polyline(PackedVector2Array([c + Vector2(-r * 0.7, y), c + Vector2(0, y - r * 0.55), c + Vector2(r * 0.7, y)]), color, 3.0, true)
			draw_line(c + Vector2(-r * 0.7, r * 0.95), c + Vector2(r * 0.7, r * 0.95), color, 2.0, true)
		"knock":
			var s := r * 0.32
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s, -s), c + Vector2(s, -s), c + Vector2(s, s), c + Vector2(-s, s)]), color)
			for side in [-1.0, 1.0]:
				var x: float = side * r * 0.62
				draw_polyline(PackedVector2Array([c + Vector2(x, -r * 0.6), c + Vector2(x + side * r * 0.4, 0), c + Vector2(x, r * 0.6)]), color, 2.5, true)


# Points given as (along, across) in units of r, laid along the direction `angle` from c.
func _along(c: Vector2, r: float, angle: float, points: Array) -> PackedVector2Array:
	var dir := Vector2.from_angle(angle)
	var out := PackedVector2Array()
	for p: Vector2 in points:
		out.append(c + dir * p.x * r + dir.orthogonal() * p.y * r)
	return out


func _sector(c: Vector2, r: float, from: float, to: float) -> PackedVector2Array:
	var points := PackedVector2Array([c])
	for k in 9:
		points.append(c + Vector2.from_angle(lerpf(from, to, float(k) / 8.0)) * r)
	return points


# A plus sign as a single 12-point outline.
func _cross(c: Vector2, arm: float, half: float) -> PackedVector2Array:
	return PackedVector2Array([
		c + Vector2(-half, -arm), c + Vector2(half, -arm), c + Vector2(half, -half), c + Vector2(arm, -half),
		c + Vector2(arm, half), c + Vector2(half, half), c + Vector2(half, arm), c + Vector2(-half, arm),
		c + Vector2(-half, half), c + Vector2(-arm, half), c + Vector2(-arm, -half), c + Vector2(-half, -half),
	])
