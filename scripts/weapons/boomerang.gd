extends "res://scripts/weapons/weapon.gd"

enum Leg { OUT, BACK, ORBIT }

const KNOCK := 10.0
const RETURN_ACCEL := 1800.0
const CATCH_DIST := 24.0
const SPIN := 14.0

var _cd := 0.5
var _time := 0.0
# Each blade: {"pos", "start", "dir", "t", "leg", "speed", "angle", "hit"}; "hit" resets on every leg.
var blades: Array[Dictionary] = []


func _ready() -> void:
	super._ready()
	top_level = true
	global_position = Vector2.ZERO
	z_index = 3


func _physics_process(delta: float) -> void:
	_time += delta
	_cd -= delta
	if _cd <= 0.0 and blades.is_empty() and nearest_enemy(float(stat("range")) + 80.0) != null:
		_cd = cooldown_of(stat("interval"))
		throw()
	for i in range(blades.size() - 1, -1, -1):
		if not _advance(blades[i], delta):
			blades.remove_at(i)
	queue_redraw()


func throw() -> void:
	var spreads := [-Balance.BOOMERANG_SPREAD, Balance.BOOMERANG_SPREAD] if is_milestone() else [0.0]
	for spread: float in spreads:
		blades.append({
			"pos": player.global_position,
			"start": player.global_position,
			"dir": player.facing.rotated(spread),
			"t": 0.0,
			"leg": Leg.OUT,
			"speed": 0.0,
			"angle": 0.0,
			"hit": {},
		})


# Moves one blade and hits what it touches; returns false once the blade is gone.
func _advance(blade: Dictionary, delta: float) -> bool:
	var before: Vector2 = blade["pos"]
	match int(blade["leg"]):
		Leg.OUT:
			blade["t"] = float(blade["t"]) + delta
			var x := clampf(float(blade["t"]) / Balance.BOOMERANG_OUT_TIME, 0.0, 1.0)
			blade["pos"] = (blade["start"] as Vector2) + (blade["dir"] as Vector2) * float(stat("range")) * (1.0 - (1.0 - x) * (1.0 - x))
			if x >= 1.0:
				blade["leg"] = Leg.BACK
				blade["hit"] = {}
		Leg.BACK:
			blade["speed"] = minf(Balance.BOOMERANG_RETURN_SPEED, float(blade["speed"]) + RETURN_ACCEL * delta)
			var to_player := player.global_position - before
			if to_player.length() <= CATCH_DIST + float(blade["speed"]) * delta:
				if not is_special():
					return false
				blade["leg"] = Leg.ORBIT
				blade["t"] = 0.0
				blade["angle"] = (before - player.global_position).angle()
				blade["hit"] = {}
			else:
				blade["pos"] = before + to_player.normalized() * float(blade["speed"]) * delta
		Leg.ORBIT:
			blade["t"] = float(blade["t"]) + delta
			if float(blade["t"]) >= Balance.BOOMERANG_ORBIT_TIME:
				return false
			blade["angle"] = float(blade["angle"]) + TAU / Balance.BOOMERANG_ORBIT_TIME * delta
			blade["pos"] = player.global_position + Vector2.from_angle(float(blade["angle"])) * area_of(Balance.BOOMERANG_ORBIT_RADIUS)
	_hit_around(blade, (blade["pos"] as Vector2) - before)
	return true


func _hit_around(blade: Dictionary, motion: Vector2) -> void:
	var at: Vector2 = blade["pos"]
	var hit: Dictionary = blade["hit"]
	var push := motion.normalized() if motion.length_squared() > 0.01 else Vector2.ZERO
	for enemy in enemies_in_circle(at, area_of(Balance.BOOMERANG_HIT_RADIUS)):
		var key: int = enemy.get_instance_id()
		if hit.has(key):
			continue
		hit[key] = true
		if fx:
			fx.hit_sparks(enemy.global_position, push, Palette.hdr(Palette.BOOMERANG, 1.3))
		enemy.take_damage(damage_of(stat("damage")), push, KNOCK)


func _draw() -> void:
	var edge := Palette.hdr(Palette.BOOMERANG, 1.9)
	var fill := Color(Palette.BOOMERANG.r * 0.2, Palette.BOOMERANG.g * 0.3, Palette.BOOMERANG.b * 0.4, 0.85)
	var s := area_of(Balance.BOOMERANG_HIT_RADIUS)
	for blade in blades:
		var at: Vector2 = blade["pos"]
		var turn := _time * SPIN
		# A chevron with a notched inner edge: six points, like a thrown boomerang.
		var shape := PackedVector2Array()
		for p in [Vector2(-0.9, -0.7), Vector2(0.0, -0.2), Vector2(0.9, -0.7), Vector2(0.9, -0.3), Vector2(0.0, 0.5), Vector2(-0.9, -0.3)]:
			shape.append(at + (p as Vector2).rotated(turn) * s)
		draw_colored_polygon(shape, fill)
		draw_polyline(Palette.closed(shape), edge, 2.0, true)
