extends Node2D

const Palette := preload("res://scripts/palette.gd")
const Balance := preload("res://scripts/balance.gd")
const EnemyShotScript := preload("res://scripts/enemy_shot.gd")
const Audio := preload("res://scripts/audio.gd")

signal died(at: Vector2, xp: int, points: int)

const SPAWN_IN := 0.3

enum State { CHASE, WINDUP, DASH }

var kind := "tri"
var radius := 11.0
var speed := 95.0
var hp := 10
var contact_damage := 5
var xp_value := 1
var points := 10
var alive := true
var sides := 3
var spiky := false
var behavior := ""
var knock_scale := 1.0
var color := Palette.ENEMIES[0]
var _flash := 0.0
var _age := 0.0
var _spin := 1.5
var _player: Node2D
var _state := State.CHASE
var _state_time := 0.0
var _action_cd := 0.0
var _dash_dir := Vector2.ZERO
var _dash_length := 0.0
var _dash_start := Vector2.ZERO
var _slow_time := 0.0
var _slow_factor := 1.0
# Per-kind attack tuning, read from the kind's table entry with the shared constants as defaults.
var dash_trigger := Balance.DASH_TRIGGER
var dash_windup := Balance.DASH_WINDUP
var dash_speed := Balance.DASH_SPEED
var dash_overshoot := Balance.DASH_OVERSHOOT
var dash_cooldown := Balance.DASH_COOLDOWN
var dash_lane := Balance.DASH_LANE_WIDTH
var shot_interval := Balance.SHOT_INTERVAL
var shot_damage := Balance.SHOT_DAMAGE
var shot_count := 1
var _flank := 0.0
var _burn_time := 0.0
var _burn_tick := 0.0
var _burn_damage := 0
# Above zero, the fire jumps this far to nearby enemies when this one dies burning.
var _burn_spread := 0.0
var _drawn_look := 0
# Created on the first burn; the flames flicker every frame while the body stays cached.
var _flames: Node2D


func setup(enemy_kind: String, t: float) -> void:
	kind = enemy_kind
	var data: Dictionary = Balance.ENEMY_KINDS[kind]
	sides = data["sides"]
	spiky = data.get("spiky", false)
	behavior = data.get("behavior", "")
	knock_scale = data.get("knock", 1.0)
	radius = data["radius"]
	hp = int(round(Balance.ENEMY_BASE_HP * float(data["hp"]) * Balance.enemy_hp_scale(t)))
	speed = Balance.enemy_speed(t) * float(data["speed"])
	contact_damage = int(round(float(int(data["damage"]) + int(t / 60.0) * 2) * Balance.ENEMY_DAMAGE_MULT))
	xp_value = data["xp"]
	points = data["score"]
	color = Palette.ENEMIES[data["color"]]
	dash_trigger = data.get("dash_trigger", Balance.DASH_TRIGGER)
	dash_windup = data.get("dash_windup", Balance.DASH_WINDUP)
	dash_speed = data.get("dash_speed", Balance.DASH_SPEED)
	dash_overshoot = data.get("dash_overshoot", Balance.DASH_OVERSHOOT)
	dash_cooldown = data.get("dash_cooldown", Balance.DASH_COOLDOWN)
	dash_lane = data.get("dash_lane", Balance.DASH_LANE_WIDTH)
	shot_interval = data.get("shot_interval", Balance.SHOT_INTERVAL)
	shot_damage = int(round(float(data.get("shot_damage", Balance.SHOT_DAMAGE)) * Balance.ENEMY_DAMAGE_MULT))
	shot_count = data.get("shot_count", 1)
	if randf() < Balance.FLANK_CHANCE:
		_flank = randf_range(-Balance.FLANK_ANGLE, Balance.FLANK_ANGLE)


func _ready() -> void:
	add_to_group("enemies")
	if behavior == "shoot":
		add_to_group("shooters")
	z_index = 1
	_spin = randf_range(1.0, 2.2) * (1.0 if randf() < 0.5 else -1.0)
	rotation = randf() * TAU
	_action_cd = randf_range(1.0, 2.5)
	_player = get_tree().get_first_node_in_group("player") as Node2D


func apply_slow(factor: float, duration: float) -> void:
	_slow_time = maxf(_slow_time, duration)
	_slow_factor = minf(factor, 1.0)


func apply_burn(damage: int, duration: float, spread := 0.0) -> void:
	if _burn_time <= 0.0:
		_burn_tick = Balance.MINE_BURN_TICK
	_burn_time = maxf(_burn_time, duration)
	_burn_damage = maxi(_burn_damage, damage)
	_burn_spread = maxf(_burn_spread, spread)


func is_burning() -> bool:
	return _burn_time > 0.0


func _update_burn(delta: float) -> void:
	_burn_time -= delta
	_burn_tick -= delta
	if _burn_tick <= 0.0:
		_burn_tick += Balance.MINE_BURN_TICK
		take_damage(_burn_damage, Vector2.ZERO, 0.0)


func _spread_fire() -> void:
	var near: Array = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var other := node as Node2D
		if other != null and other.global_position.distance_squared_to(global_position) <= _burn_spread * _burn_spread:
			near.append(other)
	near.sort_custom(func(a, b): return a.global_position.distance_squared_to(global_position) < b.global_position.distance_squared_to(global_position))
	for other in near.slice(0, Balance.MINE_SPREAD_COUNT):
		other.apply_burn(_burn_damage, Balance.MINE_BURN_TIME, _burn_spread)
		var fx := get_tree().get_first_node_in_group("fx")
		if fx:
			fx.burst(other.global_position, Palette.hdr(Palette.BURN, 1.4), 5, 160.0)


# Rotation is a transform change, so the body keeps its cached drawing except while it animates.
func needs_redraw() -> bool:
	return _age < SPAWN_IN + 0.05 or _state != State.CHASE


# Looks that hold steady while they last; the body only redraws when one of them toggles.
func _look() -> int:
	return (1 if _flash > 0.0 else 0) | (2 if _slow_time > 0.0 else 0) | (4 if _state != State.CHASE else 0) | (8 if _age >= SPAWN_IN else 0)


func _physics_process(delta: float) -> void:
	if needs_redraw() or _look() != _drawn_look:
		queue_redraw()
	if _burn_time > 0.0 and alive:
		_update_burn(delta)
	_age += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
	var pace := 1.0
	if _slow_time > 0.0:
		_slow_time -= delta
		pace = _slow_factor
	rotation += _spin * delta * (3.0 if _state == State.WINDUP else 1.0) * pace
	_update_flames()
	if not alive or _player == null:
		return
	var to_player := _player.global_position - global_position
	_state_time += delta
	_action_cd -= delta * pace
	match behavior:
		"dash":
			_update_dash(delta, to_player, pace)
		"shoot":
			_update_shoot(to_player)
	if _state == State.CHASE and to_player.length_squared() >= 1.0:
		global_position += chase_direction(to_player) * speed * delta * pace


# Heads for where the player is about to be, swinging wide while still far off; straight in once close.
func chase_direction(to_player: Vector2) -> Vector2:
	var dist := to_player.length()
	var swing := _flank * clampf((dist - Balance.FLANK_NEAR) / (Balance.FLANK_FAR - Balance.FLANK_NEAR), 0.0, 1.0)
	return (to_player / maxf(dist, 0.001)).rotated(swing)


func _update_dash(delta: float, to_player: Vector2, pace: float) -> void:
	match _state:
		State.CHASE:
			if _action_cd <= 0.0 and to_player.length() < dash_trigger:
				_state = State.WINDUP
				_state_time = 0.0
				# The lane is fixed the moment it appears (aimed with a little lead), so the band never lies.
				var lead := _player.global_position + Vector2(_player.get("velocity")) * Balance.DASH_LEAD
				var aim := lead - global_position
				_dash_dir = aim.normalized()
				_dash_length = aim.length() + dash_overshoot
				_dash_start = global_position
		State.WINDUP:
			if _state_time >= dash_windup:
				_state = State.DASH
				_state_time = 0.0
				# Crowd separation may have nudged it; launch from where the band starts.
				global_position = _dash_start
		State.DASH:
			global_position += _dash_dir * dash_speed * delta * pace
			if global_position.distance_to(_dash_start) >= _dash_length:
				_state = State.CHASE
				_action_cd = dash_cooldown


func _update_shoot(to_player: Vector2) -> void:
	match _state:
		State.CHASE:
			if _action_cd <= 0.0 and to_player.length() < Balance.SHOT_RANGE:
				_state = State.WINDUP
				_state_time = 0.0
		State.WINDUP:
			if _state_time >= Balance.SHOT_WINDUP:
				_fire(to_player.normalized())
				_state = State.CHASE
				_action_cd = shot_interval


# Several shots spread evenly across a fan centred on the player.
func _fire(dir: Vector2) -> void:
	Audio.sfx("enemy_shot")
	for i in shot_count:
		var offset := (float(i) - float(shot_count - 1) * 0.5) * Balance.SHOT_FAN
		var shot := EnemyShotScript.new()
		shot.direction = dir.rotated(offset)
		shot.damage = shot_damage
		get_parent().add_child(shot)
		shot.global_position = global_position + shot.direction * radius


func take_damage(amount: int, from_dir: Vector2, knockback: float = Balance.KNOCKBACK) -> void:
	if not alive:
		return
	hp -= amount
	_flash = 0.08
	queue_redraw()
	if hp <= 0:
		alive = false
		remove_from_group("enemies")
		remove_from_group("shooters")
		var fx := get_tree().get_first_node_in_group("fx")
		if fx:
			fx.shatter(global_position, Palette.hdr(color, 1.2), clampf(radius / 12.0, 0.8, 1.6))
		Audio.sfx("kill", clampf(12.0 / radius, 0.6, 1.2))
		if _burn_time > 0.0 and _burn_spread > 0.0:
			_spread_fire()
		died.emit(global_position, xp_value, points)
		queue_free()
		return
	Audio.sfx("hit")
	if _state == State.CHASE:
		var boost: float = float(_player.get("knock_mult")) if _player != null else 1.0
		global_position += from_dir * knockback * knock_scale * boost


func _outline(r: float, turn: float) -> PackedVector2Array:
	if not spiky:
		return Palette.regular_polygon(sides, r, turn)
	# Spiky stars alternate long points and deep notches.
	var points_out := PackedVector2Array()
	for i in sides * 2:
		var reach := r if i % 2 == 0 else r * (0.3 if sides == 3 else 0.42)
		points_out.append(Vector2.from_angle(turn + PI * float(i) / float(sides)) * reach)
	return points_out


# The charge lane as a band: it fills up from the start while charging, then fades behind the dash.
func _draw_lane(charge: float) -> void:
	# Undo the body's spin so the band is laid out in world directions.
	draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
	var start := _dash_start - global_position
	var half := _dash_dir.orthogonal() * radius * dash_lane * 0.5
	var end := start + _dash_dir * _dash_length
	var band := PackedVector2Array([start + half, end + half, end - half, start - half])
	var fade := 1.0
	if _state == State.DASH:
		fade = 1.0 - clampf(global_position.distance_to(_dash_start) / maxf(1.0, _dash_length), 0.0, 1.0)
	var base := color
	base.a = 0.07 * fade
	draw_colored_polygon(band, base)
	var rim := Palette.hdr(color, 1.1)
	rim.a = 0.45 * fade
	draw_polyline(Palette.closed(band), rim, 1.0, true)
	var fill_end := start + _dash_dir * _dash_length * (1.0 if _state == State.DASH else charge)
	var fill := Palette.hdr(color, 1.1)
	fill.a = 0.3 * fade
	draw_colored_polygon(PackedVector2Array([start + half, fill_end + half, fill_end - half, start - half]), fill)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _spawn_scale() -> float:
	return 1.0 - pow(1.0 - clampf(_age / SPAWN_IN, 0.0, 1.0), 3.0)


func _update_flames() -> void:
	if _burn_time <= 0.0:
		if _flames != null:
			_flames.visible = false
		return
	if _flames == null:
		_flames = Node2D.new()
		_flames.draw.connect(_draw_flames)
		add_child(_flames)
	_flames.visible = true
	_flames.rotation = -rotation
	_flames.queue_redraw()


# Three flickering tongues of plasma rising above the body, upright whatever the spin.
func _draw_flames() -> void:
	var r := radius * _spawn_scale()
	for k in 3:
		var x := (float(k) - 1.0) * r * 0.55
		var height := r * (0.9 + 0.35 * sin(_age * 14.0 + float(k) * 2.1)) * (1.2 if k == 1 else 0.85)
		var base := Vector2(x, -r * 0.35)
		var tongue := PackedVector2Array([base + Vector2(-r * 0.28, 0), base + Vector2(0, -height), base + Vector2(r * 0.28, 0)])
		var flame := Palette.hdr(Palette.BURN, 1.6)
		flame.a = 0.75
		_flames.draw_colored_polygon(tongue, flame)


func _draw() -> void:
	_drawn_look = _look()
	var grow := clampf(_age / SPAWN_IN, 0.0, 1.0)
	var r := radius * _spawn_scale()
	if r <= 0.5:
		return
	var tint := color
	var charge := 0.0
	if _state == State.WINDUP:
		var windup := dash_windup if behavior == "dash" else Balance.SHOT_WINDUP
		charge = clampf(_state_time / windup, 0.0, 1.0)
		tint = color.lerp(Color.WHITE, 0.5 * charge)
	if behavior == "dash" and _state != State.CHASE:
		_draw_lane(charge)
	var edge := Palette.hdr(tint, 1.6 + charge)
	var fill := Color(tint.r * 0.18, tint.g * 0.12, tint.b * 0.2, 0.9)
	if _flash > 0.0:
		edge = Palette.hdr(Color.WHITE, 2.0)
		fill = Color(1.0, 1.0, 1.0, 0.7)
	var outer := _outline(r, 0.0)
	draw_colored_polygon(outer, fill)
	draw_polyline(Palette.closed(outer), edge, 2.0, true)
	var inner := Palette.regular_polygon(sides, r * (0.3 if spiky else 0.45), PI / float(sides))
	draw_polyline(Palette.closed(inner), Palette.hdr(tint, 1.0), 1.0, true)
	if _state == State.WINDUP and behavior == "shoot":
		var glow := Palette.hdr(Palette.ENEMY_SHOT, 1.6)
		glow.a = charge
		draw_circle(Vector2.ZERO, r * 0.25 + 3.0 * charge, glow)
	if _slow_time > 0.0:
		var frost := Palette.hdr(Palette.SLOW, 1.2)
		frost.a = 0.55
		draw_arc(Vector2.ZERO, radius + 4.0, 0.0, TAU, 20, frost, 1.5, true)
	if grow < 1.0:
		var ring := Palette.hdr(color, 1.2)
		ring.a = 1.0 - grow
		draw_arc(Vector2.ZERO, radius * (1.0 + 1.5 * (1.0 - grow)), 0.0, TAU, 24, ring, 1.5, true)
