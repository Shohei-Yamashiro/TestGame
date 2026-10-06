extends "res://scripts/weapons/weapon.gd"

const BulletScript := preload("res://scripts/bullet.gd")

var _cd := 0.15


func _physics_process(delta: float) -> void:
	_cd -= delta
	if _cd > 0.0:
		return
	var locks := 3 if is_special() else (2 if is_milestone() else 1)
	var targets := _nearest_enemies(locks)
	if targets.is_empty():
		return
	_cd = cooldown_of(stat("interval"))
	var ratio := Balance.BLASTER_MULTI_RATIO if locks == 2 else 1.0
	for i in locks:
		# With fewer enemies than locks, the spare shots double up on the closest ones.
		var target: Node2D = targets[i % targets.size()]
		var dir := target.global_position - player.global_position
		dir = player.facing if dir.length_squared() < 1.0 else dir.normalized()
		_shoot(dir, ratio)


func _nearest_enemies(count: int) -> Array:
	var origin := player.global_position
	var best: Array = []
	var best_dist: Array[float] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var dist := origin.distance_squared_to((node as Node2D).global_position)
		if best.size() == count and dist >= best_dist[count - 1]:
			continue
		var at := best_dist.bsearch(dist)
		best.insert(at, node)
		best_dist.insert(at, dist)
		if best.size() > count:
			best.pop_back()
			best_dist.pop_back()
	return best


func _shoot(shot_dir: Vector2, ratio: float) -> void:
	var bullet := BulletScript.new()
	bullet.direction = shot_dir
	bullet.damage = maxi(1, int(round(float(damage_of(stat("damage"))) * ratio)))
	bullet.pierce = Balance.BLASTER_SPECIAL_PIERCE if is_special() else 1
	world().add_child(bullet)
	# Must stay within the bullet's hit reach so enemies overlapping the player still get hit.
	bullet.global_position = player.global_position + shot_dir * 6.0
