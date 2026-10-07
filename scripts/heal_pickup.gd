extends Node2D

# A small repair kit dropped by enemies: walk over it to recover a little HP. Like gems it stays until taken
# and the magnet pulls it in.

const Palette := preload("res://scripts/palette.gd")
const Balance := preload("res://scripts/balance.gd")
const GemScript := preload("res://scripts/gem.gd")

signal collected(amount: int)

const PICKUP_RADIUS := 22.0
const SIZE := 7.0

var _age := 0.0
var _pull_speed := 0.0
var _attracted := false
var _player: Node2D


func _ready() -> void:
	add_to_group("heals")
	z_index = 0
	_player = get_tree().get_first_node_in_group("player") as Node2D


func _physics_process(delta: float) -> void:
	_age += delta
	queue_redraw()
	if _player == null or not bool(_player.get("alive")):
		return
	var dist := global_position.distance_to(_player.global_position)
	if dist <= float(_player.get("magnet_radius")):
		_attracted = true
	if _attracted:
		_pull_speed = minf(GemScript.MAGNET_MAX_SPEED, _pull_speed + GemScript.MAGNET_ACCEL * delta)
		global_position += (_player.global_position - global_position).normalized() * minf(dist, _pull_speed * delta)
		dist = global_position.distance_to(_player.global_position)
	if dist <= PICKUP_RADIUS:
		var fx := get_tree().get_first_node_in_group("fx")
		if fx:
			fx.ring(global_position, Palette.hdr(Palette.HEAL, 1.8), 28.0, 0.3)
			fx.burst(global_position, Palette.hdr(Palette.HEAL, 1.5), 8, 180.0)
		collected.emit(Balance.HEAL_PICKUP)
		remove_from_group("heals")
		queue_free()


func _draw() -> void:
	var bob := sin(_age * 3.0) * 1.5
	var center := Vector2(0, bob)
	var halo := Palette.HEAL
	halo.a = 0.14 + 0.06 * sin(_age * 5.0)
	draw_circle(center, SIZE * 1.8, halo)
	# A hexagon (friendly, even-sided) holding a plus sign.
	var hex := Palette.regular_polygon(6, SIZE, PI / 6.0)
	for i in hex.size():
		hex[i] += center
	draw_colored_polygon(hex, Color(Palette.HEAL.r * 0.15, Palette.HEAL.g * 0.3, Palette.HEAL.b * 0.25, 0.9))
	draw_polyline(Palette.closed(hex), Palette.hdr(Palette.HEAL, 1.7), 1.5, true)
	var arm := SIZE * 0.6
	var half := SIZE * 0.2
	draw_rect(Rect2(center + Vector2(-half, -arm), Vector2(half * 2.0, arm * 2.0)), Palette.hdr(Palette.HEAL, 2.0))
	draw_rect(Rect2(center + Vector2(-arm, -half), Vector2(arm * 2.0, half * 2.0)), Palette.hdr(Palette.HEAL, 2.0))
