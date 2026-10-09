extends "res://scripts/weapons/weapon.gd"

# Feather angles away from straight back, and their relative lengths, from the inner pair outward.
const WING_ANGLES := [0.42, 0.66, 0.9, 1.12]
const WING_LENGTHS := [1.0, 0.92, 0.8, 0.64]
const FLARE_TIME := 0.45
const KNOCK := 18.0
# The deployed wings swing around the sides to the front, hold, then swing back behind.
const SWEEP_TIME := 0.5
const SWEEP_OUT := 0.16
const SWEEP_HOLD := 0.24
const SWEEP_HIT_AT := 0.11
# The wings cross over each other in front, so dead ahead is struck a second time.
const SWEEP_CROSS_AT := 0.16
const SWEEP_CROSS_CONE := 0.45
const SWEEP_KNOCK := 30.0
# Feather angles away from straight ahead once the wings have closed in front;
# negative means the inner feathers cross past the centre line.
const SWEEP_FRONT := -0.14
const SWEEP_FRONT_STEP := 0.14

var _cd := 0.8
var _flare := 0.0
var _deploy := 0.0
var _time := 0.0
var _tick_cd := 0.0
var _mote_cd := 0.0
var _wing_dir := Vector2.DOWN
var _sweep_delay := 0.0
var _sweep_t := -1.0


func _ready() -> void:
	super._ready()
	# Drawn in world space, underneath the player.
	top_level = true
	global_position = Vector2.ZERO
	z_as_relative = false
	z_index = 1


func _physics_process(delta: float) -> void:
	_time += delta
	# Locked to the ship's nose so the wings never drift from it.
	_wing_dir = -player.facing
	if is_special():
		_deploy = move_toward(_deploy, 1.0, delta * 4.0)
		_tick_cd -= delta
		if _tick_cd <= 0.0 and _sweep_amount() < 0.3:
			_tick_cd = cooldown_of(Balance.WINGS_SPECIAL_TICK)
			var damage := maxi(1, int(round(float(damage_of(stat("damage"))) * Balance.WINGS_SPECIAL_RATIO)))
			_hit_cone(damage, Balance.AURA_KNOCKBACK, _wing_dir, _reach())
		_cd -= delta
		if _cd <= 0.0:
			_cd = cooldown_of(stat("interval"))
			_start_sweep()
	else:
		_cd -= delta
		if _cd <= 0.0:
			_cd = cooldown_of(stat("interval"))
			_flare = FLARE_TIME
			_hit_cone(damage_of(stat("damage")), KNOCK, _wing_dir, _reach())
			if is_milestone():
				_sweep_delay = Balance.ECHO_DELAY
		if _sweep_delay > 0.0:
			_sweep_delay -= delta
			if _sweep_delay <= 0.0:
				_start_sweep()
		_flare = maxf(0.0, _flare - delta)
		# Snap open on the beat, then fold back slowly.
		var open := _flare > 0.0 or _sweep_delay > 0.0 or _sweep_t >= 0.0
		_deploy = move_toward(_deploy, 1.0 if open else 0.0, delta * (10.0 if open else 2.5))
	_update_sweep(delta)
	if _deploy > 0.0:
		Audio.loop("wings_hum", _deploy)
	if _deploy > 0.3:
		_mote_cd -= delta
		if _mote_cd <= 0.0 and fx:
			_mote_cd = 0.04
			var feathers := _feathers()
			var tip: Vector2 = feathers[randi() % feathers.size()][2]
			fx.burst(tip, Palette.hdr(Palette.NOVA, 1.4), 1, 50.0)
	if _deploy > 0.0 or _sweep_t >= 0.0:
		queue_redraw()


func _start_sweep() -> void:
	Audio.sfx("swoosh")
	_sweep_t = 0.0


func _update_sweep(delta: float) -> void:
	if _sweep_t < 0.0:
		return
	var before := _sweep_t
	_sweep_t += delta
	var damage := int(round(float(damage_of(stat("damage"))) * Balance.WINGS_SWEEP_RATIO))
	var reach := _reach() * Balance.WINGS_SWEEP_REACH
	if before < SWEEP_HIT_AT and _sweep_t >= SWEEP_HIT_AT:
		_hit_cone(damage, SWEEP_KNOCK, -_wing_dir, reach)
	if before < SWEEP_CROSS_AT and _sweep_t >= SWEEP_CROSS_AT:
		var cross := maxi(1, int(round(float(damage) * Balance.WINGS_CROSS_RATIO)))
		_hit_cone(cross, SWEEP_KNOCK * 0.5, -_wing_dir, reach, SWEEP_CROSS_CONE)
	if _sweep_t >= SWEEP_TIME:
		_sweep_t = -1.0


# 0 = wings behind, 1 = wings closed in front.
func _sweep_amount() -> float:
	if _sweep_t < 0.0:
		return 0.0
	if _sweep_t < SWEEP_OUT:
		return ease(_sweep_t / SWEEP_OUT, 0.5)
	if _sweep_t < SWEEP_HOLD:
		return 1.0
	return 1.0 - smoothstep(SWEEP_HOLD, SWEEP_TIME, _sweep_t)


func _reach() -> float:
	return area_of(Balance.WINGS_SPECIAL_REACH if is_special() else stat("reach"))


func _feather_count() -> int:
	return WING_ANGLES.size() if is_special() else int(stat("feathers"))


# The hit area is the fan the wings cover, so it follows the drawing closely.
func _hit_cone(damage: int, knock: float, axis: Vector2, reach: float, cone := Balance.WINGS_CONE) -> void:
	var center := player.global_position
	for enemy in enemies_in_circle(center, reach):
		var offset: Vector2 = enemy.global_position - center
		if offset.length_squared() > 1.0 and absf(axis.angle_to(offset)) > cone:
			continue
		enemy.take_damage(damage, offset.normalized(), knock)
		if fx:
			fx.hit_sparks(enemy.global_position, offset.normalized(), Palette.hdr(Palette.NOVA, 1.3))


# A feather is [base_a, side_a, tip, side_b, base_b] in world space.
func _feather(dir: Vector2, reach: float, index: int) -> Array:
	var normal := dir.orthogonal()
	var base := player.global_position + dir * 14.0
	var spread := 16.0 - float(index) * 2.0
	return [
		base + normal * 3.0,
		base + dir * reach * 0.6 + normal * spread,
		base + dir * reach,
		base + dir * reach * 0.6 - normal * spread * 0.6,
		base - normal * 3.0,
	]


func _feathers() -> Array:
	var result: Array = []
	var swing := _sweep_amount()
	var length := _reach() * 1.08 * _deploy * lerpf(1.0, Balance.WINGS_SWEEP_REACH, swing)
	var open := lerpf(0.35, 1.0, _deploy)
	for side in [-1.0, 1.0]:
		for i in _feather_count():
			var behind: float = WING_ANGLES[i] * open + 0.06 * sin(_time * 5.0 + float(i) * 1.3)
			var ahead := PI - (SWEEP_FRONT + SWEEP_FRONT_STEP * float(i))
			var angle: float = _wing_dir.angle() + side * lerpf(behind, ahead, swing)
			var reach: float = length * WING_LENGTHS[i] * (1.0 + 0.07 * sin(_time * 7.0 + float(i) * 1.7 + side))
			result.append(_feather(Vector2.from_angle(angle), reach, i))
	return result


func _draw() -> void:
	var pulse := 0.85 + 0.15 * sin(_time * 4.0)
	# Nearly folded feathers collapse into slivers that fail to triangulate.
	if _deploy >= 0.08:
		var glow := 1.0 + 0.8 * _sweep_amount()
		_draw_feathers(_feathers(), _deploy * pulse * glow, _deploy * glow)
	if _sweep_t >= SWEEP_HIT_AT:
		var fade := 1.0 - smoothstep(SWEEP_HIT_AT, SWEEP_TIME, _sweep_t)
		# A crescent left in front where the wings closed.
		var center := player.global_position
		var arc := Palette.hdr(Color(0.75, 1.0, 0.95), 1.6)
		arc.a = 0.6 * fade
		var r := _reach() * Balance.WINGS_SWEEP_REACH * 0.92
		var a := (-_wing_dir).angle()
		draw_arc(center, r, a - Balance.WINGS_CONE, a + Balance.WINGS_CONE, 32, arc, 6.0 * fade + 1.0, true)


func _draw_feathers(feathers: Array, mid_alpha: float, root_alpha: float) -> void:
	var root := Palette.hdr(Palette.NOVA, 1.3)
	root.a = 0.55 * root_alpha
	var mid := Palette.hdr(Color(0.6, 0.85, 1.0), 1.2)
	mid.a = 0.32 * mid_alpha
	var tip := Palette.hdr(Color(0.75, 1.0, 0.95), 1.0)
	tip.a = 0.0
	for feather in feathers:
		draw_polygon(PackedVector2Array(feather), PackedColorArray([root, mid, tip, mid, root]))
