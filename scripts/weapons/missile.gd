extends Node2D

const Palette := preload("res://scripts/palette.gd")
const Balance := preload("res://scripts/balance.gd")
const EnemyScript := preload("res://scripts/enemy.gd")

const LIFETIME := 3.0
const HIT_MARGIN := 6.0
const TRAIL_POINTS := 24

var direction := Vector2.RIGHT
var damage := 12
var pierce := 1
var explosive := false
var target: EnemyScript

var _age := 0.0
var _hit: Array[Node] = []
var _trail := PackedVector2Array()
var _game: Node
var _fx: Node


func _ready() -> void:
	z_index = 3
	_game = get_tree().get_first_node_in_group("game")
	_fx = get_tree().get_first_node_in_group("fx")


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	if target == null or not is_instance_valid(target) or not target.alive or _hit.has(target):
		target = _random_target()
	if target != null:
		# Loose steering right after launch, tightening up so the path bends in a wide arc.
		var turn_rate := lerpf(Balance.MISSILE_TURN_START, Balance.MISSILE_TURN, clampf(_age / 0.6, 0.0, 1.0))
		var want := (target.global_position - global_position).normalized()
		direction = direction.rotated(clampf(direction.angle_to(want), -turn_rate * delta, turn_rate * delta))
	var speed := Balance.MISSILE_SPEED * clampf(0.5 + _age * 2.0, 0.5, 1.0)
	global_position += direction * speed * delta
	_trail.append(global_position)
	if _trail.size() > TRAIL_POINTS:
		_trail.remove_at(0)
	queue_redraw()
	for node in _game.query_enemies(global_position, 40.0):
		if not is_instance_valid(node) or not node.alive or _hit.has(node):
			continue
		var reach: float = float(node.radius) + HIT_MARGIN
		if global_position.distance_squared_to(node.global_position) > reach * reach:
			continue
		_hit.append(node)
		if _fx:
			_fx.hit_sparks(global_position, direction, Palette.hdr(Palette.HOMING, 1.3))
		node.take_damage(damage, direction)
		if explosive:
			_explode()
		pierce -= 1
		if pierce <= 0:
			queue_free()
			return


func _random_target() -> EnemyScript:
	var candidates: Array = []
	var range_sq := Balance.HOMING_RANGE * Balance.HOMING_RANGE
	for node in get_tree().get_nodes_in_group("enemies"):
		if not _hit.has(node) and global_position.distance_squared_to(node.global_position) <= range_sq:
			candidates.append(node)
	return null if candidates.is_empty() else candidates.pick_random()


func _explode() -> void:
	var blast := int(round(float(damage) * Balance.MISSILE_BLAST_RATIO))
	for node in _game.query_enemies(global_position, Balance.MISSILE_BLAST_RADIUS + 20.0):
		if not is_instance_valid(node) or not node.alive or _hit.has(node):
			continue
		var d: Vector2 = node.global_position - global_position
		var reach: float = Balance.MISSILE_BLAST_RADIUS + float(node.radius)
		if d.length_squared() <= reach * reach:
			node.take_damage(blast, d.normalized())
	if _fx:
		_fx.ring(global_position, Palette.hdr(Palette.HOMING, 1.4), Balance.MISSILE_BLAST_RADIUS, 0.25)
		_fx.burst(global_position, Palette.hdr(Palette.HOMING, 1.2), 10, 260.0)


func _draw() -> void:
	# The node never rotates, so trail points only need the position offset removed.
	var count := _trail.size()
	if count >= 2:
		var points := PackedVector2Array()
		var colors := PackedColorArray()
		for i in count:
			points.append(_trail[i] - global_position)
			var c := Palette.hdr(Palette.HOMING, 1.3)
			c.a = pow(float(i + 1) / float(count), 1.6) * 0.8
			colors.append(c)
		draw_polyline_colors(points, colors, 2.5, true)
	var body := Palette.hdr(Palette.HOMING, 2.0)
	var side := direction.orthogonal()
	draw_colored_polygon(PackedVector2Array([
		direction * 8.0, -direction * 3.0 + side * 4.5, -direction * 1.0, -direction * 3.0 - side * 4.5,
	]), body)
