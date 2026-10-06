extends "res://scripts/weapons/weapon.gd"

const BLADE_REACH := 12.0
const SPECIAL_KNOCKBACK := 26.0

var _angle := 0.0
var _hit_until := {}
var _time := 0.0


func _physics_process(delta: float) -> void:
	_time += delta
	var speed := (Balance.ORBIT_SPECIAL_SPEED if is_special() else Balance.ORBIT_SPEED) / float(player.cooldown_mult)
	_angle = wrapf(_angle + speed * delta, 0.0, TAU)
	queue_redraw()
	var damage := damage_of(stat("damage"))
	var cooldown := cooldown_of(Balance.ORBIT_HIT_COOLDOWN)
	var knock := SPECIAL_KNOCKBACK if is_special() else Balance.KNOCKBACK
	var reach := BLADE_REACH * _blade_scale()
	for offset in _blade_offsets():
		var at := player.global_position + offset
		for enemy in enemies_in_circle(at, reach):
			var key: int = enemy.get_instance_id()
			if float(_hit_until.get(key, 0.0)) > _time:
				continue
			_hit_until[key] = _time + cooldown
			var away: Vector2 = (enemy.global_position - player.global_position).normalized()
			if fx:
				fx.hit_sparks(enemy.global_position, away, Palette.hdr(Palette.ORBIT, 1.3))
			enemy.take_damage(damage, away, knock)
	_guard_shots(reach)
	if _hit_until.size() > 400:
		for key in _hit_until.keys():
			if float(_hit_until[key]) < _time:
				_hit_until.erase(key)


# Blades erase enemy shots; the special bounces them back off the blade's outward face.
func _guard_shots(reach: float) -> void:
	var shots := get_tree().get_nodes_in_group("enemy_shots")
	if shots.is_empty():
		return
	var offsets := _blade_offsets()
	var center := player.global_position
	for shot in shots:
		for offset in offsets:
			var limit: float = reach + shot.HIT_RADIUS
			if shot.global_position.distance_squared_to(center + offset) > limit * limit:
				continue
			if is_special():
				var damage := int(round(float(damage_of(stat("damage"))) * Balance.REFLECT_DAMAGE_RATIO))
				shot.reflect(offset.normalized(), damage)
				if fx:
					fx.hit_sparks(shot.global_position, offset.normalized(), Palette.hdr(Palette.ORBIT, 1.5))
			else:
				shot.cancel()
			break


func _blade_scale() -> float:
	return Balance.ORBIT_MILESTONE_SCALE if is_milestone() else 1.0


func _blade_offsets() -> Array[Vector2]:
	var count := int(stat("count")) + (1 if is_special() else 0)
	var radius := _orbit_radius()
	var result: Array[Vector2] = []
	for i in count:
		result.append(Vector2.from_angle(_angle + TAU * float(i) / float(count)) * radius)
	return result


func _orbit_radius() -> float:
	return area_of(Balance.ORBIT_SPECIAL_RADIUS if is_special() else Balance.ORBIT_RADIUS)


func _draw() -> void:
	var radius := _orbit_radius()
	var faint := Palette.hdr(Palette.ORBIT, 0.8)
	faint.a = 0.12
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, faint, 1.0, true)
	var edge := Palette.hdr(Palette.ORBIT, 1.9)
	var fill := Color(Palette.ORBIT.r * 0.2, Palette.ORBIT.g * 0.3, Palette.ORBIT.b * 0.4, 0.85)
	var k := _blade_scale()
	for offset in _blade_offsets():
		var tangent := offset.normalized().orthogonal() * k
		var radial := offset.normalized() * k
		var blade := PackedVector2Array([
			offset + tangent * 13.0,
			offset + radial * 5.0,
			offset - tangent * 9.0,
			offset - radial * 5.0,
		])
		draw_colored_polygon(blade, fill)
		draw_polyline(Palette.closed(blade), edge, 1.5, true)
