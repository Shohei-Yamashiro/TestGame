extends Node2D

const Palette := preload("res://scripts/palette.gd")
const Balance := preload("res://scripts/balance.gd")

signal collected(value: int)

const PICKUP_RADIUS := 30.0
const MAGNET_ACCEL := 1800.0
const MAGNET_MAX_SPEED := 900.0
# Per tier: outline sides, size, and whether the outline is a star (even spike counts only).
const LOOKS := [
	{"sides": 4, "size": 7.0, "star": false},
	{"sides": 6, "size": 10.0, "star": false},
	{"sides": 8, "size": 12.5, "star": false},
	{"sides": 8, "size": 16.0, "star": true},
]

var value := 1
var tier := 0
var _taken := false
var _age := 0.0
var _pull_speed := 0.0
var _attracted := false
var _pop := 0.0
var _player: Node2D


func _ready() -> void:
	add_to_group("gems")
	z_index = 0
	_age = randf() * TAU
	_player = get_tree().get_first_node_in_group("player") as Node2D
	_update_tier()


# Only gems resting on the floor take part in merging; ones flying to the player are left alone.
func can_merge() -> bool:
	return not _taken and not _attracted


func absorb(other: Node2D) -> void:
	var total := value + int(other.value)
	global_position = global_position.lerp(other.global_position, float(other.value) / float(total))
	value = total
	other.queue_free()
	_pop = 1.0
	_update_tier()


func _update_tier() -> void:
	tier = 0
	for i in Balance.GEM_TIERS.size():
		if value >= int(Balance.GEM_TIERS[i]):
			tier = i
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _taken:
		return
	_age += delta
	_pop = maxf(0.0, _pop - delta * 4.0)
	rotation = _age * (1.5 - 0.25 * tier)
	scale = Vector2.ONE * (1.0 + sin(_age * 5.0) * 0.12 + 0.45 * _pop)
	var player := _player
	if player == null or not bool(player.get("alive")):
		return
	var dist := global_position.distance_to(player.global_position)
	if dist <= PICKUP_RADIUS:
		_taken = true
		var fx := get_tree().get_first_node_in_group("fx")
		if fx:
			fx.ring(global_position, Palette.hdr(Palette.GEM_TIERS[tier], 1.6), 18.0 + 6.0 * tier, 0.25)
		collected.emit(value)
		queue_free()
		return
	# Once caught by the magnet a gem keeps homing, so it never stalls at the edge of the radius.
	if dist <= float(player.get("magnet_radius")):
		_attracted = true
	if _attracted:
		_pull_speed = minf(MAGNET_MAX_SPEED, _pull_speed + MAGNET_ACCEL * delta)
		global_position += (player.global_position - global_position).normalized() * minf(dist, _pull_speed * delta)


func _outline(look: Dictionary, size: float) -> PackedVector2Array:
	var sides: int = look["sides"]
	if not look["star"]:
		return Palette.regular_polygon(sides, size, 0.0)
	var points := PackedVector2Array()
	for i in sides * 2:
		points.append(Vector2.from_angle(PI * float(i) / float(sides)) * (size if i % 2 == 0 else size * 0.55))
	return points


func _draw() -> void:
	var look: Dictionary = LOOKS[tier]
	var color: Color = Palette.GEM_TIERS[tier]
	var size: float = look["size"]
	if tier >= 2:
		var halo := color
		halo.a = 0.12
		draw_circle(Vector2.ZERO, size * 1.5, halo)
	var outer := _outline(look, size)
	draw_colored_polygon(outer, Color(color.r * 0.15, color.g * 0.25, color.b * 0.3, 0.85))
	draw_polyline(Palette.closed(outer), Palette.hdr(color, 1.7), 1.5, true)
	if tier >= 1:
		var inner_sides: int = 4 if tier == 1 else 6 if tier == 2 else 8
		var inner := Palette.regular_polygon(inner_sides, size * 0.5, PI / float(inner_sides))
		draw_polyline(Palette.closed(inner), Palette.hdr(color, 1.2), 1.0, true)
	draw_colored_polygon(Palette.regular_polygon(4, 2.0 + 1.0 * tier, 0.0), Palette.hdr(color.lerp(Color.WHITE, 0.3), 2.2))
	if tier == 3:
		# A four-ray glint marks the biggest crystals.
		var glint := Palette.hdr(Color.WHITE, 1.6)
		glint.a = 0.7
		for dir in [Vector2.RIGHT, Vector2.DOWN]:
			draw_line(-dir * size * 1.6, dir * size * 1.6, glint, 1.0, true)
