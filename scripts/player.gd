extends Node2D

const Palette := preload("res://scripts/palette.gd")
const Balance := preload("res://scripts/balance.gd")

signal died
signal hurt(amount: int)

const RADIUS := 16.0
const TURN_RATE := 12.0

var world: Node2D
var max_hp := Balance.PLAYER_MAX_HP
var hp := Balance.PLAYER_MAX_HP
var move_speed: float = Balance.PASSIVES["move"]["speed"][0]
var damage_mult: float = Balance.PASSIVES["attack"]["damage"][0]
var cooldown_mult: float = Balance.PASSIVES["rate"]["cooldown"][0]
var area_mult: float = Balance.PASSIVES["area"]["area"][0]
var knock_mult: float = Balance.PASSIVES["knock"]["knock"][0]
var xp_mult: float = Balance.PASSIVES["growth"]["xp"][0]
var armor: float = Balance.PASSIVES["armor"]["armor"][0]
var regen: float = Balance.PASSIVES["regen"]["regen"][0]
var hurt_interval := Balance.HURT_INTERVAL
var hurt_radius := 14.0
var magnet_radius := Balance.BASE_MAGNET

var alive := true
var facing := Vector2.RIGHT
var velocity := Vector2.ZERO

var _hurt_cd := 0.0
var _regen_carry := 0.0
var _flash := 0.0
var _time := 0.0


func _ready() -> void:
	add_to_group("player")
	z_index = 2


func _physics_process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		queue_redraw()
	if not alive:
		velocity = Vector2.ZERO
		return
	_move(delta)
	_regenerate(delta)
	_contact_damage(delta)


# hp is whole numbers, so fractional healing is banked until it adds up to a point.
func _regenerate(delta: float) -> void:
	if regen <= 0.0 or hp >= max_hp:
		_regen_carry = 0.0
		return
	_regen_carry += regen * delta
	if _regen_carry >= 1.0:
		var amount := int(_regen_carry)
		_regen_carry -= float(amount)
		hp = mini(max_hp, hp + amount)


func _move(delta: float) -> void:
	var dir := _input_dir()
	if dir != Vector2.ZERO:
		# Turns smoothly instead of snapping between the eight input directions.
		facing = Vector2.from_angle(lerp_angle(facing.angle(), dir.angle(), 1.0 - exp(-TURN_RATE * delta)))
		queue_redraw()
	velocity = dir * move_speed
	global_position += velocity * delta


func _input_dir() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1.0
	return dir.normalized()


func _contact_damage(delta: float) -> void:
	_hurt_cd = maxf(0.0, _hurt_cd - delta)
	if _hurt_cd > 0.0:
		return
	var touching: Array[int] = []
	var game := get_tree().get_first_node_in_group("game")
	for node in game.query_enemies(global_position, 60.0):
		if not is_instance_valid(node) or not node.alive:
			continue
		var enemy := node as Node2D
		var reach: float = hurt_radius + float(enemy.get("radius"))
		if global_position.distance_squared_to(enemy.global_position) <= reach * reach:
			touching.append(int(enemy.get("contact_damage")))
	if touching.is_empty():
		return
	# Being swarmed hurts more than one bump, but only the strongest few count.
	touching.sort()
	touching.reverse()
	var damage := 0
	for i in mini(Balance.CONTACT_STACK, touching.size()):
		damage += touching[i]
	take_hit(damage)


# Shared by contact and enemy shots; returns false while the post-hit invulnerability is running.
func take_hit(damage: int) -> bool:
	if not alive or _hurt_cd > 0.0:
		return false
	_hurt_cd = hurt_interval
	damage = maxi(1, int(round(float(damage) * (1.0 - armor))))
	hp = maxi(0, hp - damage)
	hurt.emit(damage)
	_flash = 0.12
	queue_redraw()
	var fx := get_tree().get_first_node_in_group("fx")
	if fx:
		fx.burst(global_position, Palette.hdr(Palette.HURT, 1.2), 10, 300.0)
		fx.ring(global_position, Palette.hdr(Palette.HURT, 1.1), 46.0, 0.3)
	if hp <= 0 and alive:
		alive = false
		if fx:
			fx.shatter(global_position, Palette.hdr(Palette.PLAYER, 1.3), 2.2)
		visible = false
		died.emit()
	return true


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var color := Palette.PLAYER
	if not alive:
		color = Color(0.45, 0.5, 0.58)
	elif _flash > 0.0:
		color = Color(1.0, 1.0, 1.0)
	var glow := Palette.hdr(color, 1.8 if alive else 1.0)
	var hex := Palette.regular_polygon(6, RADIUS, _time * 0.6)
	draw_colored_polygon(hex, Color(color.r * 0.12, color.g * 0.18, color.b * 0.25, 0.92))
	draw_polyline(Palette.closed(hex), glow, 2.0, true)
	var inner := Palette.regular_polygon(6, RADIUS * 0.55, -_time * 1.1)
	draw_polyline(Palette.closed(inner), Palette.hdr(color, 0.9), 1.0, true)
	for i in 3:
		var start := _time * 1.6 + TAU * float(i) / 3.0
		draw_arc(Vector2.ZERO, RADIUS + 9.0, start, start + 1.1, 12, Palette.hdr(color, 1.2), 1.5, true)
	var tip := facing * (RADIUS + 10.0)
	draw_colored_polygon(PackedVector2Array([
		tip,
		facing * (RADIUS + 1.0) + facing.orthogonal() * 6.0,
		facing * (RADIUS + 1.0) - facing.orthogonal() * 6.0,
	]), glow)
