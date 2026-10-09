extends "res://scripts/weapons/weapon.gd"

const SPIN_XW := 2.6
const SPIN_YZ := 1.7
const SPIN_XY := 0.6
const EYE_4D := 3.0
const EYE_3D := 4.0
const TILT_X := 0.5
const TILT_Y := 0.6
const DRAW_SCALE := 1.05
const FADE_TIME := 0.4
const SLIDE_SPIN := 3.0
const KNOCK := 6.0

var _cd := 0.5
var _time := 0.0
# Each cube: {"pos", "start", "dir", "age", "life", "phase", "touched"}; it slides while age < TESSERACT_SLIDE_TIME.
# "touched" maps an enemy's instance id to the time it may take damage again.
var cubes: Array[Dictionary] = []
var _edges: Array[Vector2i] = []


func _ready() -> void:
	super._ready()
	top_level = true
	global_position = Vector2.ZERO
	z_index = 2
	# Hypercube corners are the 16 sign patterns of (x, y, z, w); edges join corners differing in one sign.
	for i in 16:
		for bit in 4:
			var j := i ^ (1 << bit)
			if j > i:
				_edges.append(Vector2i(i, j))


func _physics_process(delta: float) -> void:
	_time += delta
	_cd -= delta
	if _cd <= 0.0 and nearest_enemy(Balance.TESSERACT_TRIGGER) != null:
		_cd = cooldown_of(stat("interval"))
		launch()
	for i in range(cubes.size() - 1, -1, -1):
		var cube := cubes[i]
		cube["age"] = float(cube["age"]) + delta
		if float(cube["age"]) >= float(cube["life"]):
			cubes.remove_at(i)
			continue
		_slide(cube)
		_hold(cube)
	_block_shots()
	queue_redraw()


func radius() -> float:
	return area_of(Balance.TESSERACT_RADIUS)


func is_sliding(cube: Dictionary) -> bool:
	return float(cube["age"]) < Balance.TESSERACT_SLIDE_TIME


func launch() -> void:
	Audio.sfx("launch")
	var spreads := [-Balance.TESSERACT_SPREAD, Balance.TESSERACT_SPREAD] if is_milestone() else [0.0]
	for spread: float in spreads:
		cubes.append({
			"pos": player.global_position,
			"start": player.global_position,
			"dir": player.facing.rotated(spread),
			"age": 0.0,
			"life": Balance.TESSERACT_SLIDE_TIME + float(stat("life")),
			"phase": randf() * TAU,
			"touched": {},
		})
	while cubes.size() > Balance.TESSERACT_MAX:
		cubes.pop_front()


# Eases out from the launch point and comes to rest at the full range.
func _slide(cube: Dictionary) -> void:
	var x := clampf(float(cube["age"]) / Balance.TESSERACT_SLIDE_TIME, 0.0, 1.0)
	var travel := area_of(Balance.TESSERACT_RANGE) * (1.0 - (1.0 - x) * (1.0 - x))
	cube["pos"] = (cube["start"] as Vector2) + (cube["dir"] as Vector2) * travel


# Pushes touching enemies out to the cube's edge. They take damage while it slides, and at rest only with the special.
func _hold(cube: Dictionary) -> void:
	var at: Vector2 = cube["pos"]
	var r := radius()
	var touched: Dictionary = cube["touched"]
	var sliding := is_sliding(cube)
	var hurts := sliding or is_special()
	for enemy in enemies_in_circle(at, r):
		var offset: Vector2 = enemy.global_position - at
		var out := offset.normalized() if offset.length_squared() > 0.01 else (cube["dir"] as Vector2)
		enemy.global_position = at + out * (r + float(enemy.radius))
		if not hurts:
			continue
		var key: int = enemy.get_instance_id()
		if float(touched.get(key, 0.0)) > _time:
			continue
		var damage := damage_of(stat("damage"))
		if sliding:
			touched[key] = _time + Balance.TESSERACT_HIT_TICK
		else:
			touched[key] = _time + Balance.TESSERACT_REST_TICK
			damage = maxi(1, int(round(float(damage) * Balance.TESSERACT_REST_RATIO)))
		if fx:
			fx.hit_sparks(at + out * r, out, Palette.hdr(Palette.TESSERACT, 1.3))
		enemy.take_damage(damage, out, KNOCK if sliding else 0.0)
	if touched.size() > 32:
		for key in touched.keys():
			if float(touched[key]) <= _time:
				touched.erase(key)


func _block_shots() -> void:
	if cubes.is_empty():
		return
	var r := radius()
	for shot in get_tree().get_nodes_in_group("enemy_shots"):
		for cube in cubes:
			var limit: float = r + shot.HIT_RADIUS
			if shot.global_position.distance_squared_to(cube["pos"]) <= limit * limit:
				shot.cancel()
				break


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
	var r := radius()
	var tint := Palette.TESSERACT
	for cube in cubes:
		var at: Vector2 = cube["pos"]
		var age: float = cube["age"]
		var fade := clampf((float(cube["life"]) - age) / FADE_TIME, 0.0, 1.0)
		var sliding := is_sliding(cube)
		var hot := sliding or is_special()
		var s := r * DRAW_SCALE
		draw_circle(at, r, Color(tint.r, tint.g, tint.b, (0.18 if hot else 0.08) * fade))
		draw_arc(at, r, 0.0, TAU, 32, Color(tint.r, tint.g, tint.b, (0.6 if hot else 0.3) * fade), 1.0, true)
		# Spins fast while sliding and slows to a calm turn once it rests.
		var slide_left := maxf(0.0, Balance.TESSERACT_SLIDE_TIME - age)
		var spin_t := _time + float(cube["phase"]) - slide_left * slide_left * SLIDE_SPIN
		var projected := _project(spin_t)
		var points: PackedVector2Array = projected[0]
		var depths: PackedFloat32Array = projected[1]
		var glow := 1.0 if hot else 0.75
		for edge in _edges:
			var near := (depths[edge.x] + depths[edge.y]) * 0.5
			var color := Palette.hdr(tint, lerpf(0.9, 2.0, near) * glow)
			color.a = lerpf(0.45, 1.0, near) * fade
			draw_line(at + points[edge.x] * s, at + points[edge.y] * s, color, lerpf(1.0, 2.2, near), true)
