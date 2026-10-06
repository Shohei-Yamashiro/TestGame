extends Control

# Symbol-only badge for a weapon or passive: a framed glyph with level pips underneath.

const Palette := preload("res://scripts/palette.gd")
const Balance := preload("res://scripts/balance.gd")

const COLORS := {
	"blaster": Palette.BULLET,
	"homing": Palette.HOMING,
	"orbit": Palette.ORBIT,
	"nova": Palette.NOVA,
	"laser": Palette.LASER,
	"wings": Palette.WINGS,
	"chain": Palette.CHAIN,
	"tesseract": Palette.TESSERACT,
	"mine": Palette.MINE,
	"drain": Palette.DRAIN,
	"attack": Color(0.9, 0.5, 1.0),
	"rate": Color(0.5, 0.85, 1.0),
	"move": Color(0.45, 1.0, 0.65),
	"magnet": Color(0.8, 0.65, 1.0),
	"max_hp": Color(0.55, 0.6, 1.0),
	"regen": Color(0.3, 1.0, 0.85),
	"area": Color(0.25, 0.65, 1.0),
	"armor": Color(0.75, 0.85, 1.0),
	"growth": Color(0.35, 0.95, 1.0),
	"knock": Color(0.45, 0.45, 1.0),
}
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
	var frame := _octagon(c, s * 0.5)
	draw_colored_polygon(frame, Color(color.r * 0.1, color.g * 0.12, color.b * 0.18, 0.9 if filled else 0.35))
	var border := color if filled else Color(0.5, 0.6, 0.7, 0.35)
	if special:
		var gold := Color(1.0, 0.85, 0.35)
		draw_colored_polygon(frame, Color(gold.r, gold.g, gold.b, 0.1))
		draw_polyline(Palette.closed(frame), gold, 2.0, true)
		draw_polyline(Palette.closed(_octagon(c, s * 0.5 - 4.0)), Color(gold.r, gold.g, gold.b, 0.75), 1.0, true)
	else:
		draw_polyline(Palette.closed(frame), border, 1.5, true)
	if not filled:
		return
	_draw_symbol(c, s * 0.36, color)
	_draw_pips(Vector2(s * 0.5, s + 8.0), color)


func _octagon(c: Vector2, r: float) -> PackedVector2Array:
	var k := r * 0.42
	return PackedVector2Array([
		c + Vector2(-r + k, -r), c + Vector2(r - k, -r), c + Vector2(r, -r + k), c + Vector2(r, r - k),
		c + Vector2(r - k, r), c + Vector2(-r + k, r), c + Vector2(-r, r - k), c + Vector2(-r, -r + k),
	])


const SEG_WIDTH := 5.0
const SEG_SPECIAL_WIDTH := 8.0
const SEG_POINT := 3.0
const SEG_HEIGHT := 8.0
const SEG_GAP := 1.0


# A row of interlocking right-pointing hexagons, one per stage, reading like a single arrow gauge.
func _draw_pips(center: Vector2, color: Color) -> void:
	var count := Balance.MAX_STAGE + (1 if is_weapon else 0)
	var total := SEG_POINT - SEG_GAP
	for i in count:
		total += (SEG_SPECIAL_WIDTH if i + 1 == Balance.SPECIAL_STAGE else SEG_WIDTH) + SEG_GAP
	var x := center.x - total * 0.5
	for i in count:
		var stage := i + 1
		var width := SEG_SPECIAL_WIDTH if stage == Balance.SPECIAL_STAGE else SEG_WIDTH
		var owned := stage <= level and not (preview and stage == level)
		var next := preview and stage == level
		var tint := Color(1.0, 0.85, 0.35) if stage == Balance.SPECIAL_STAGE else color
		var seg := _arrow_hexagon(x, center.y, width)
		if owned:
			draw_colored_polygon(seg, tint)
		elif next:
			draw_colored_polygon(seg, Color.WHITE)
		else:
			draw_polyline(Palette.closed(seg), Color(tint.r, tint.g, tint.b, 0.4), 1.0, true)
		x += width + SEG_GAP


# Notched on the left and pointed on the right, so each segment nests into the previous one.
func _arrow_hexagon(left: float, mid_y: float, width: float) -> PackedVector2Array:
	var top := mid_y - SEG_HEIGHT * 0.5
	var bottom := mid_y + SEG_HEIGHT * 0.5
	return PackedVector2Array([
		Vector2(left, top), Vector2(left + width, top), Vector2(left + width + SEG_POINT, mid_y),
		Vector2(left + width, bottom), Vector2(left, bottom), Vector2(left + SEG_POINT, mid_y),
	])


func _draw_symbol(c: Vector2, r: float, color: Color) -> void:
	match item_id:
		"blaster":
			draw_colored_polygon(PackedVector2Array([c + Vector2(r, 0), c + Vector2(0, r * 0.45), c + Vector2(-r * 0.4, 0), c + Vector2(0, -r * 0.45)]), color)
			draw_line(c + Vector2(-r * 1.1, -r * 0.35), c + Vector2(-r * 0.55, -r * 0.35), color, 2.0, true)
			draw_line(c + Vector2(-r * 1.1, r * 0.35), c + Vector2(-r * 0.55, r * 0.35), color, 2.0, true)
		"homing":
			# An S traced from the lower-left, ending in an arrowhead at the upper right.
			var bend := r * 0.5
			var stretch := Vector2(1.3, 1.0)
			var path := PackedVector2Array()
			for i in 13:
				var a := lerpf(PI * 0.8, -PI * 0.5, float(i) / 12.0)
				path.append(c + Vector2(0, bend) + Vector2.from_angle(a) * bend * stretch)
			for i in range(1, 13):
				var a := lerpf(PI * 0.5, PI * 1.72, float(i) / 12.0)
				path.append(c + Vector2(0, -bend) + Vector2.from_angle(a) * bend * stretch)
			draw_polyline(path, color, 2.5, true)
			var tip := path[path.size() - 1]
			var dir := (tip - path[path.size() - 2]).normalized()
			draw_colored_polygon(PackedVector2Array([tip + dir * r * 0.45, tip + dir.orthogonal() * r * 0.28, tip - dir.orthogonal() * r * 0.28]), color)
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
			# A zigzag bolt joining two nodes.
			var bolt := PackedVector2Array([
				c + Vector2(-r * 0.85, -r * 0.75), c + Vector2(-r * 0.05, -r * 0.2), c + Vector2(-r * 0.35, r * 0.15),
				c + Vector2(r * 0.85, r * 0.75),
			])
			draw_polyline(bolt, Color(color.r, color.g, color.b, 0.35), 6.0, true)
			draw_polyline(bolt, color, 2.0, true)
			for p in [bolt[0], bolt[3]]:
				var d := r * 0.24
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)]), color)
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
			var pts := PackedVector2Array()
			for i in 8:
				var radius := r * 1.05 if i % 2 == 0 else r * 0.32
				pts.append(c + Vector2.from_angle(-PI * 0.5 + PI * float(i) / 4.0) * radius)
			draw_colored_polygon(pts, color)
		"rate":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(r * 0.25, -r * 1.05), c + Vector2(-r * 0.55, r * 0.15), c + Vector2(-r * 0.05, r * 0.15),
				c + Vector2(-r * 0.3, r * 1.05), c + Vector2(r * 0.55, -r * 0.2), c + Vector2(r * 0.05, -r * 0.2),
			]), color)
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
			draw_colored_polygon(_cross(c, r * 0.95, r * 0.34), color)
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


# A plus sign as a single 12-point outline.
func _cross(c: Vector2, arm: float, half: float) -> PackedVector2Array:
	return PackedVector2Array([
		c + Vector2(-half, -arm), c + Vector2(half, -arm), c + Vector2(half, -half), c + Vector2(arm, -half),
		c + Vector2(arm, half), c + Vector2(half, half), c + Vector2(half, arm), c + Vector2(-half, arm),
		c + Vector2(-half, half), c + Vector2(-arm, half), c + Vector2(-arm, -half), c + Vector2(-half, -half),
	])
