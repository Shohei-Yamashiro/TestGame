extends "res://scripts/weapons/weapon.gd"

const KNOCK := 6.0

var _cd := 0.8
var _beams: Array[Dictionary] = []


func _ready() -> void:
	super._ready()
	# Beams are drawn where they were fired, in world space.
	top_level = true
	global_position = Vector2.ZERO
	z_index = 3


func _physics_process(delta: float) -> void:
	_cd -= delta
	if _cd <= 0.0:
		var target := nearest_enemy(Balance.LASER_LENGTH)
		if target != null:
			_cd = cooldown_of(stat("interval"))
			_fire((target.global_position - player.global_position).normalized())
	for i in range(_beams.size() - 1, -1, -1):
		_beams[i]["age"] = float(_beams[i]["age"]) + delta
		if float(_beams[i]["age"]) >= Balance.LASER_SHOW:
			_beams.remove_at(i)
	if not _beams.is_empty():
		queue_redraw()


func _fire(aim: Vector2) -> void:
	var count := 4 if is_special() else (2 if is_milestone() else 1)
	var origin := player.global_position
	var width := area_of(stat("width"))
	var damage := damage_of(stat("damage"))
	var enemies := get_tree().get_nodes_in_group("enemies")
	for i in count:
		var dir := aim.rotated(TAU * float(i) / float(count))
		var end := origin + dir * Balance.LASER_LENGTH
		for node in enemies:
			if not is_instance_valid(node) or not node.alive:
				continue
			var p: Vector2 = node.global_position
			var closest := Geometry2D.get_closest_point_to_segment(p, origin, end)
			var reach: float = width * 0.5 + float(node.radius)
			if p.distance_squared_to(closest) <= reach * reach:
				node.take_damage(damage, dir, KNOCK)
				if fx:
					fx.hit_sparks(p, dir, Palette.hdr(Palette.LASER, 1.3))
		_beams.append({"from": origin, "to": end, "width": width, "age": 0.0})
	queue_redraw()


func _draw() -> void:
	for beam in _beams:
		var t := float(beam["age"]) / Balance.LASER_SHOW
		var fade := 1.0 - t * t
		var width := float(beam["width"]) * (0.6 + 0.4 * fade)
		var to: Vector2 = beam["to"]
		# The tail retracts from the muzzle toward the far end.
		var from: Vector2 = (beam["from"] as Vector2).lerp(to, ease(t, 1.6))
		var glow := Palette.hdr(Palette.LASER, 1.0)
		glow.a = 0.35 * fade
		draw_line(from, to, glow, width * 2.2, true)
		var core := Palette.hdr(Palette.LASER, 2.2)
		core.a = fade
		draw_line(from, to, core, width * 0.6, true)
