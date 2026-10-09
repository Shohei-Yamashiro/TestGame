extends "res://scripts/weapons/weapon.gd"

const MissileScript := preload("res://scripts/weapons/missile.gd")

var _cd := 0.4
# Targets still waiting to be launched in the current volley.
var _queue: Array = []
var _burst_cd := 0.0
var _side := 1.0


func _physics_process(delta: float) -> void:
	if not _queue.is_empty():
		_burst_cd -= delta
		if _burst_cd <= 0.0:
			_burst_cd = Balance.HOMING_BURST_GAP
			_launch(_queue.pop_front())
		return
	_cd -= delta
	if _cd > 0.0:
		return
	var candidates := _enemies_in_range()
	if candidates.is_empty():
		return
	_cd = cooldown_of(stat("interval"))
	candidates.shuffle()
	var count := int(stat("count")) + (1 if is_special() else 0)
	for i in count:
		_queue.append(candidates[i % candidates.size()])
	_side = 1.0 if randf() < 0.5 else -1.0
	_burst_cd = 0.0


# Untyped on purpose: queued targets may have been freed before their turn to launch.
func _launch(queued) -> void:
	var target: Node2D = queued if is_instance_valid(queued) and queued.alive else null
	Audio.sfx("missile")
	var aim := player.facing
	if target != null:
		aim = (target.global_position - player.global_position).normalized()
	# Alternate sides so the volley fans out into visible arcs.
	_side = -_side
	var missile := MissileScript.new()
	missile.direction = aim.rotated(_side * (PI * 0.5 + randf_range(0.0, 0.5)))
	missile.target = target
	missile.damage = damage_of(stat("damage"))
	missile.explosive = is_special()
	missile.blast_radius = area_of(Balance.MISSILE_BLAST_RADIUS)
	missile.pierce = 2 if is_milestone() else 1
	world().add_child(missile)
	missile.global_position = player.global_position


func _enemies_in_range() -> Array:
	var result: Array = []
	var origin := player.global_position
	var range_sq := Balance.HOMING_RANGE * Balance.HOMING_RANGE
	for node in get_tree().get_nodes_in_group("enemies"):
		if origin.distance_squared_to(node.global_position) <= range_sq:
			result.append(node)
	return result
