extends "res://scripts/weapons/weapon.gd"

const KNOCK := 14.0
const BOLT_COUNT := 10
const BOLT_POINTS := 7
const BOLT_JITTER := 11.0
const BOLT_REFRESH := 0.05

var _cd := 1.0
var _waves: Array[Dictionary] = []
var _time := 0.0
var _tick_cd := 0.0
var _mote_cd := 0.0
var _bolt_cd := 0.0
var _bolts: Array[PackedVector2Array] = []


func _ready() -> void:
	super._ready()
	# Waves stay where they were fired instead of following the player.
	top_level = true
	global_position = Vector2.ZERO
	z_as_relative = false
	z_index = 1


func _physics_process(delta: float) -> void:
	_time += delta
	if is_special():
		_update_shield(delta)
	else:
		_cd -= delta
		if _cd <= 0.0:
			_cd = cooldown_of(stat("interval"))
			_emit_wave()
	for i in range(_waves.size() - 1, -1, -1):
		var wave := _waves[i]
		wave["age"] = float(wave["age"]) + delta
		var t := clampf(float(wave["age"]) / Balance.NOVA_EXPAND, 0.0, 1.0)
		var r: float = float(wave["radius"]) * (1.0 - pow(1.0 - t, 2.0))
		var hit: Dictionary = wave["hit"]
		var center: Vector2 = wave["center"]
		for enemy in enemies_in_circle(center, r):
			var key: int = enemy.get_instance_id()
			if hit.has(key):
				continue
			hit[key] = true
			var away: Vector2 = (enemy.global_position - center).normalized()
			if is_milestone():
				enemy.apply_slow(Balance.NOVA_SLOW_FACTOR, Balance.NOVA_SLOW_TIME)
			enemy.take_damage(int(wave["damage"]), away, KNOCK)
		if float(wave["age"]) >= Balance.NOVA_EXPAND + 0.15:
			_waves.remove_at(i)
	if not _waves.is_empty() or is_special():
		queue_redraw()


func _emit_wave() -> void:
	_waves.append({
		"center": player.global_position,
		"radius": float(stat("radius")),
		"damage": damage_of(stat("damage")),
		"age": 0.0,
		"hit": {},
	})
	queue_redraw()


# Special: a permanent electric shield. Everything inside the circle is hit on each tick.
func _update_shield(delta: float) -> void:
	_tick_cd -= delta
	if _tick_cd <= 0.0:
		_tick_cd = cooldown_of(Balance.AURA_TICK)
		var center := player.global_position
		var damage := maxi(1, int(round(float(damage_of(stat("damage"))) * Balance.AURA_DAMAGE_RATIO)))
		for enemy in enemies_in_circle(center, Balance.RING_RADIUS):
			var away: Vector2 = (enemy.global_position - center).normalized()
			enemy.apply_slow(Balance.NOVA_SLOW_FACTOR, Balance.NOVA_SLOW_TIME)
			enemy.take_damage(damage, away, Balance.AURA_KNOCKBACK)
	_bolt_cd -= delta
	if _bolt_cd <= 0.0:
		_bolt_cd = BOLT_REFRESH
		_roll_bolts()
	_mote_cd -= delta
	if _mote_cd <= 0.0 and fx:
		_mote_cd = 0.06
		var at := player.global_position + Vector2.from_angle(randf() * TAU) * Balance.RING_RADIUS
		fx.burst(at, Palette.hdr(Palette.ELECTRIC, 1.6), 1, 90.0)


func _draw() -> void:
	if is_special():
		_draw_shield()
	for wave in _waves:
		var age := float(wave["age"])
		var t := clampf(age / Balance.NOVA_EXPAND, 0.0, 1.0)
		var r: float = float(wave["radius"]) * (1.0 - pow(1.0 - t, 2.0))
		var fade := 1.0 - clampf((age - Balance.NOVA_EXPAND * 0.6) / (Balance.NOVA_EXPAND * 0.4 + 0.15), 0.0, 1.0)
		var edge := Palette.hdr(Palette.NOVA, 1.8)
		edge.a = fade
		var inner := Palette.hdr(Palette.NOVA, 0.8)
		inner.a = 0.12 * fade
		var center: Vector2 = wave["center"]
		draw_circle(center, r, inner)
		draw_arc(center, r, 0.0, TAU, 64, edge, 3.0, true)
		draw_arc(center, r * 0.82, 0.0, TAU, 64, Color(edge.r, edge.g, edge.b, 0.35 * fade), 1.0, true)


# Short jagged arcs hugging the rim, re-rolled every few frames so the edge crackles.
func _roll_bolts() -> void:
	_bolts.clear()
	var r := Balance.RING_RADIUS
	for i in BOLT_COUNT:
		var start := randf() * TAU
		var span := randf_range(0.2, 0.55)
		var bolt := PackedVector2Array()
		for j in BOLT_POINTS:
			var t := float(j) / float(BOLT_POINTS - 1)
			# Ends pinned to the rim, middle free to jump in and out.
			var jitter := randf_range(-BOLT_JITTER, BOLT_JITTER) * sin(t * PI)
			bolt.append(Vector2.from_angle(start + span * t) * (r + jitter))
		_bolts.append(bolt)


func _draw_shield() -> void:
	var center := player.global_position
	var r := Balance.RING_RADIUS
	var fill := Palette.ELECTRIC
	fill.a = 0.035
	draw_circle(center, r, fill)
	var rim := Palette.hdr(Palette.ELECTRIC, 1.0)
	rim.a = 0.3
	draw_arc(center, r, 0.0, TAU, 96, rim, 1.5, true)
	var glow := Palette.hdr(Palette.ELECTRIC, 1.0)
	glow.a = 0.18
	var core := Palette.hdr(Palette.ELECTRIC.lerp(Color.WHITE, 0.4), 2.0)
	for bolt in _bolts:
		var points := PackedVector2Array()
		for p in bolt:
			points.append(center + p)
		draw_polyline(points, glow, 5.0, true)
		draw_polyline(points, core, 1.5, true)
