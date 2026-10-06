extends Node2D

const Palette := preload("res://scripts/palette.gd")
const Balance := preload("res://scripts/balance.gd")

var direction := Vector2.RIGHT
var speed := Balance.BULLET_SPEED
var damage := 10
var pierce := 1

const HIT_MARGIN := 7.0
const LIFETIME := 1.6

var _age := 0.0
var _hit: Array[Node] = []
var _game: Node


func _ready() -> void:
	z_index = 3
	rotation = direction.angle()
	_game = get_tree().get_first_node_in_group("game")


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	# The grid is one tick old, so search a little wider than the largest enemy reach.
	for node in _game.query_enemies(global_position, 40.0):
		if not is_instance_valid(node) or not node.alive or _hit.has(node):
			continue
		var enemy := node as Node2D
		var reach: float = float(enemy.get("radius")) + HIT_MARGIN
		if global_position.distance_squared_to(enemy.global_position) <= reach * reach:
			_hit.append(enemy)
			var fx := get_tree().get_first_node_in_group("fx")
			if fx:
				fx.hit_sparks(global_position, direction, Palette.hdr(Palette.BULLET, 1.2))
			enemy.call("take_damage", damage, direction)
			pierce -= 1
			if pierce <= 0:
				queue_free()
				return
	_age += delta
	if _age >= LIFETIME:
		queue_free()


func _draw() -> void:
	var trail := Palette.hdr(Palette.BULLET, 0.9)
	trail.a = 0.35
	draw_line(Vector2(-22, 0), Vector2(-4, 0), trail, 2.0, true)
	var tip := Palette.hdr(Palette.BULLET, 2.0)
	if pierce > 1:
		tip = Palette.hdr(Palette.BULLET_PIERCE, 2.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(9, 0),
		Vector2(0, 3.5),
		Vector2(-7, 0),
		Vector2(0, -3.5),
	]), tip)
