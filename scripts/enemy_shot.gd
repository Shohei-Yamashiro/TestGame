extends Node2D

const Palette := preload("res://scripts/palette.gd")
const Balance := preload("res://scripts/balance.gd")

const HIT_RADIUS := 6.0

var direction := Vector2.RIGHT
# Once reflected the shot belongs to the player: it hurts enemies instead.
var reflected := false
var _damage := Balance.SHOT_DAMAGE
var _speed := Balance.SHOT_SPEED
var _age := 0.0
var _player: Node2D
var _game: Node


func _ready() -> void:
	add_to_group("enemy_shots")
	z_index = 3
	_player = get_tree().get_first_node_in_group("player") as Node2D
	_game = get_tree().get_first_node_in_group("game")


func reflect(normal: Vector2, damage: int) -> void:
	reflected = true
	remove_from_group("enemy_shots")
	direction = (direction - 2.0 * direction.dot(normal) * normal).normalized()
	_speed *= Balance.REFLECT_SPEED
	_damage = damage
	_age = 0.0
	queue_redraw()


func cancel() -> void:
	var fx := get_tree().get_first_node_in_group("fx")
	if fx:
		fx.burst(global_position, Palette.hdr(Palette.ENEMY_SHOT, 1.2), 5, 120.0)
	queue_free()


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= Balance.SHOT_LIFETIME:
		queue_free()
		return
	global_position += direction * _speed * delta
	rotation += 6.0 * delta
	if reflected:
		_hit_enemies()
		return
	if _player == null or not bool(_player.get("alive")):
		return
	var reach: float = HIT_RADIUS + float(_player.get("hurt_radius"))
	if global_position.distance_squared_to(_player.global_position) <= reach * reach:
		_player.call("take_hit", _damage)
		var fx := get_tree().get_first_node_in_group("fx")
		if fx:
			fx.burst(global_position, Palette.hdr(Palette.ENEMY_SHOT, 1.3), 6, 160.0)
		queue_free()


func _hit_enemies() -> void:
	for node in _game.query_enemies(global_position, 40.0):
		if not is_instance_valid(node) or not node.alive:
			continue
		var reach: float = HIT_RADIUS + float(node.radius)
		if global_position.distance_squared_to(node.global_position) <= reach * reach:
			node.take_damage(_damage, direction)
			var fx := get_tree().get_first_node_in_group("fx")
			if fx:
				fx.hit_sparks(global_position, direction, Palette.hdr(Palette.ORBIT, 1.4))
			queue_free()
			return


func _draw() -> void:
	# Hostile shots are warm triangles; reflected ones switch to the player's cool, even-sided look.
	var color := Palette.ORBIT if reflected else Palette.ENEMY_SHOT
	var halo := Palette.hdr(color, 1.0)
	halo.a = 0.25
	draw_circle(Vector2.ZERO, HIT_RADIUS + 4.0, halo)
	var body := Palette.regular_polygon(4 if reflected else 3, HIT_RADIUS + 1.0, 0.0)
	draw_colored_polygon(body, Palette.hdr(color, 1.8))
