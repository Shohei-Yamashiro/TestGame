extends "res://scripts/weapons/weapon.gd"

const KNOCK := 4.0
const BOLT_SEGMENTS := 6
const BOLT_JITTER := 10.0

var _cd := 0.6
# Each strike: {"points": PackedVector2Array of hit positions, "age": float, "bolts": Array[PackedVector2Array]}
var _strikes: Array[Dictionary] = []


func _ready() -> void:
	super._ready()
	top_level = true
	global_position = Vector2.ZERO
	z_index = 3


func _physics_process(delta: float) -> void:
	_cd -= delta
	if _cd <= 0.0:
		var first := nearest_enemy(Balance.CHAIN_RANGE)
		if first != null:
			_cd = cooldown_of(stat("interval"))
			strike(first)
	for i in range(_strikes.size() - 1, -1, -1):
		_strikes[i]["age"] = float(_strikes[i]["age"]) + delta
		if float(_strikes[i]["age"]) >= Balance.CHAIN_SHOW:
			_strikes.remove_at(i)
	if not _strikes.is_empty():
		queue_redraw()


func max_targets() -> int:
	return int(stat("jumps")) + (Balance.CHAIN_MILESTONE_JUMPS if is_milestone() else 0)


# Hits first, then hops to the nearest enemy not yet struck; returns how many enemies were hit.
func strike(first: Node2D) -> int:
	var hit := {}
	var points := PackedVector2Array([player.global_position])
	var damage := float(damage_of(stat("damage")))
	var current := first
	var jump := area_of(Balance.CHAIN_JUMP)
	while current != null and hit.size() < max_targets():
		var at: Vector2 = current.global_position
		hit[current.get_instance_id()] = true
		points.append(at)
		var away := (at - points[points.size() - 2]).normalized()
		current.take_damage(maxi(1, int(round(damage))), away, KNOCK)
		if is_special():
			_discharge(at, int(round(damage * Balance.CHAIN_DISCHARGE_RATIO)), hit)
		if fx:
			fx.hit_sparks(at, away, Palette.hdr(Palette.CHAIN, 1.4))
		damage *= Balance.CHAIN_FALLOFF
		current = _next_target(at, jump, hit)
	_strikes.append({"points": points, "age": 0.0, "bolts": _bolts_for(points)})
	queue_redraw()
	return hit.size()


func _next_target(from: Vector2, jump: float, hit: Dictionary) -> Node2D:
	var best: Node2D = null
	var best_dist := jump * jump
	for node in game.query_enemies(from, jump):
		if not is_instance_valid(node) or not node.alive or hit.has(node.get_instance_id()):
			continue
		var dist := from.distance_squared_to(node.global_position)
		if dist <= best_dist:
			best_dist = dist
			best = node
	return best


func _discharge(at: Vector2, damage: int, hit: Dictionary) -> void:
	for enemy in enemies_in_circle(at, area_of(Balance.CHAIN_DISCHARGE_RADIUS)):
		if hit.has(enemy.get_instance_id()):
			continue
		enemy.take_damage(maxi(1, damage), (enemy.global_position - at).normalized(), KNOCK)
	if fx:
		fx.ring(at, Palette.hdr(Palette.CHAIN, 1.2), area_of(Balance.CHAIN_DISCHARGE_RADIUS), 0.2)


func _bolts_for(points: PackedVector2Array) -> Array:
	var bolts := []
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var normal := (b - a).orthogonal().normalized()
		var bolt := PackedVector2Array([a])
		for j in range(1, BOLT_SEGMENTS):
			var t := float(j) / float(BOLT_SEGMENTS)
			bolt.append(a.lerp(b, t) + normal * randf_range(-BOLT_JITTER, BOLT_JITTER))
		bolt.append(b)
		bolts.append(bolt)
	return bolts


func _draw() -> void:
	for strike_data in _strikes:
		var fade := 1.0 - float(strike_data["age"]) / Balance.CHAIN_SHOW
		var glow := Palette.hdr(Palette.CHAIN, 1.0)
		glow.a = 0.35 * fade
		var core := Palette.hdr(Palette.CHAIN.lerp(Color.WHITE, 0.3), 2.2)
		core.a = fade
		for bolt: PackedVector2Array in strike_data["bolts"]:
			draw_polyline(bolt, glow, 6.0, true)
			draw_polyline(bolt, core, 1.8, true)
