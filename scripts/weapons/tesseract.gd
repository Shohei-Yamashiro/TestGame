extends "res://scripts/weapons/weapon.gd"

enum Leg { OUT, BACK, ORBIT }

const KNOCK := 10.0
const RETURN_ACCEL := 1800.0
const CATCH_DIST := 24.0
const SPIN_XW := 2.6
const SPIN_YZ := 1.7
const SPIN_XY := 0.6
const EYE_4D := 3.0
const EYE_3D := 4.0
const TILT_X := 0.5
const TILT_Y := 0.6
const DRAW_SCALE := 1.8

var _cd := 0.5
var _time := 0.0
# Each cube: {"pos", "start", "dir", "t", "leg", "speed", "angle", "phase", "hit"}; "hit" resets on every leg.
var cubes: Array[Dictionary] = []
var _edges: Array[Vector2i] = []


func _ready() -> void:
	super._ready()
	top_level = true
	global_position = Vector2.ZERO
	z_index = 3
	# Hypercube corners are the 16 sign patterns of (x, y, z, w); edges join corners differing in one sign.
	for i in 16:
		for bit in 4:
			var j := i ^ (1 << bit)
			if j > i:
				_edges.append(Vector2i(i, j))


func _physics_process(delta: float) -> void:
	_time += delta
	_cd -= delta
	if _cd <= 0.0 and cubes.is_empty() and nearest_enemy(float(stat("range")) + 80.0) != null:
		_cd = cooldown_of(stat("interval"))
		throw()
	for i in range(cubes.size() - 1, -1, -1):
		if not _advance(cubes[i], delta):
			cubes.remove_at(i)
	queue_redraw()


func throw() -> void:
	var spreads := [-Balance.TESSERACT_SPREAD, Balance.TESSERACT_SPREAD] if is_milestone() else [0.0]
	for spread: float in spreads:
		cubes.append({
			"pos": player.global_position,
			"start": player.global_position,
			"dir": player.facing.rotated(spread),
			"t": 0.0,
			"leg": Leg.OUT,
			"speed": 0.0,
			"angle": 0.0,
			"phase": spread * 3.0,
			"hit": {},
		})


# Moves one cube and hits what it touches; returns false once the cube is gone.
func _advance(cube: Dictionary, delta: float) -> bool:
	var before: Vector2 = cube["pos"]
	match int(cube["leg"]):
		Leg.OUT:
			cube["t"] = float(cube["t"]) + delta
			var x := clampf(float(cube["t"]) / Balance.TESSERACT_OUT_TIME, 0.0, 1.0)
			cube["pos"] = (cube["start"] as Vector2) + (cube["dir"] as Vector2) * float(stat("range")) * (1.0 - (1.0 - x) * (1.0 - x))
			if x >= 1.0:
				cube["leg"] = Leg.BACK
				cube["hit"] = {}
		Leg.BACK:
			cube["speed"] = minf(Balance.TESSERACT_RETURN_SPEED, float(cube["speed"]) + RETURN_ACCEL * delta)
			var to_player := player.global_position - before
			if to_player.length() <= CATCH_DIST + float(cube["speed"]) * delta:
				if not is_special():
					return false
				cube["leg"] = Leg.ORBIT
				cube["t"] = 0.0
				cube["angle"] = (before - player.global_position).angle()
				cube["hit"] = {}
			else:
				cube["pos"] = before + to_player.normalized() * float(cube["speed"]) * delta
		Leg.ORBIT:
			cube["t"] = float(cube["t"]) + delta
			if float(cube["t"]) >= Balance.TESSERACT_ORBIT_TIME:
				return false
			cube["angle"] = float(cube["angle"]) + TAU / Balance.TESSERACT_ORBIT_TIME * delta
			cube["pos"] = player.global_position + Vector2.from_angle(float(cube["angle"])) * area_of(Balance.TESSERACT_ORBIT_RADIUS)
	_hit_around(cube, (cube["pos"] as Vector2) - before)
	return true


func _hit_around(cube: Dictionary, motion: Vector2) -> void:
	var at: Vector2 = cube["pos"]
	var hit: Dictionary = cube["hit"]
	var push := motion.normalized() if motion.length_squared() > 0.01 else Vector2.ZERO
	for enemy in enemies_in_circle(at, area_of(Balance.TESSERACT_HIT_RADIUS)):
		var key: int = enemy.get_instance_id()
		if hit.has(key):
			continue
		hit[key] = true
		if fx:
			fx.hit_sparks(enemy.global_position, push, Palette.hdr(Palette.TESSERACT, 1.3))
		enemy.take_damage(damage_of(stat("damage")), push, KNOCK)


# Rotates the hypercube in the XW and YZ planes and projects it to 2D; returns [points, depth 0..1 per corner].
func _project(t: float) -> Array:
	var points := PackedVector2Array()
	var depths := PackedFloat32Array()
	var a := t * SPIN_XW
	var b := t * SPIN_YZ
	var c := t * SPIN_XY
	for i in 16:
		var x := 1.0 if i & 1 else -1.0
		var y := 1.0 if i & 2 else -1.0
		var z := 1.0 if i & 4 else -1.0
		var w := 1.0 if i & 8 else -1.0
		var x2 := x * cos(a) - w * sin(a)
		var w2 := x * sin(a) + w * cos(a)
		var y2 := y * cos(b) - z * sin(b)
		var z2 := y * sin(b) + z * cos(b)
		var k := 1.0 / (EYE_4D - w2)
		var p := Vector3(x2, y2, z2) * k
		p = p.rotated(Vector3.UP, TILT_Y).rotated(Vector3.RIGHT, TILT_X)
		var k3 := EYE_3D / (EYE_3D - p.z)
		points.append(Vector2(p.x, p.y).rotated(c) * k3)
		depths.append(clampf((w2 + 1.5) / 3.0 * 0.6 + (p.z + 0.7) / 1.4 * 0.4, 0.0, 1.0))
	return [points, depths]


func _draw() -> void:
	var s := area_of(Balance.TESSERACT_HIT_RADIUS) * DRAW_SCALE
	for cube in cubes:
		var at: Vector2 = cube["pos"]
		var projected := _project(_time + float(cube["phase"]))
		var points: PackedVector2Array = projected[0]
		var depths: PackedFloat32Array = projected[1]
		draw_circle(at, s * 0.55, Color(Palette.TESSERACT.r, Palette.TESSERACT.g, Palette.TESSERACT.b, 0.08))
		for edge in _edges:
			var near := (depths[edge.x] + depths[edge.y]) * 0.5
			var color := Palette.hdr(Palette.TESSERACT, lerpf(0.9, 2.0, near))
			color.a = lerpf(0.45, 1.0, near)
			draw_line(at + points[edge.x] * s, at + points[edge.y] * s, color, lerpf(1.0, 2.2, near), true)
