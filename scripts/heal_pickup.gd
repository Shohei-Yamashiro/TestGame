extends Node2D

# A repair kit dropped by enemies: walk over it to recover HP. The magnet does not pull it in,
# so grabbing one means a short detour; it blinks before it fades away.

const Palette := preload("res://scripts/palette.gd")
const Balance := preload("res://scripts/balance.gd")

signal collected(amount: int)

const PICKUP_RADIUS := 26.0
const SIZE := 11.0
const BLINK_TIME := 5.0

var _age := 0.0
var _player: Node2D


func _ready() -> void:
	add_to_group("heals")
	z_index = 0
	_player = get_tree().get_first_node_in_group("player") as Node2D


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= Balance.HEAL_LIFETIME:
		queue_free()
		return
	queue_redraw()
	if _player == null or not bool(_player.get("alive")):
		return
	if global_position.distance_squared_to(_player.global_position) <= PICKUP_RADIUS * PICKUP_RADIUS:
		var fx := get_tree().get_first_node_in_group("fx")
		if fx:
			fx.ring(global_position, Palette.hdr(Palette.HEAL, 1.8), 40.0, 0.35)
			fx.burst(global_position, Palette.hdr(Palette.HEAL, 1.5), 12, 220.0)
		collected.emit(Balance.HEAL_PICKUP)
		remove_from_group("heals")
		queue_free()


func _draw() -> void:
	var left := Balance.HEAL_LIFETIME - _age
	if left < BLINK_TIME and fmod(_age, 0.3) < 0.12:
		return
	var bob := sin(_age * 3.0) * 2.0
	var center := Vector2(0, bob)
	var halo := Palette.HEAL
	halo.a = 0.14 + 0.06 * sin(_age * 5.0)
	draw_circle(center, SIZE * 1.9, halo)
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
