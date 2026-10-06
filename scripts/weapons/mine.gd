extends "res://scripts/weapons/weapon.gd"

const KNOCK := 12.0
const MINE_SIZE := 9.0

var _cd := 0.3
var _time := 0.0
# {"pos", "age"}
var mines: Array[Dictionary] = []
# Delayed second blasts from the milestone: {"pos", "delay", "damage"}
var _echoes: Array[Dictionary] = []
# Lingering slow zones from the special: {"pos", "age", "tick"}
var fields: Array[Dictionary] = []


func _ready() -> void:
	super._ready()
	top_level = true
	global_position = Vector2.ZERO
	z_as_relative = false
	z_index = 0


func _physics_process(delta: float) -> void:
	_time += delta
	_cd -= delta
	if _cd <= 0.0 and _spot_is_free(player.global_position):
		_cd = cooldown_of(stat("interval"))
		place(player.global_position)
	for i in range(mines.size() - 1, -1, -1):
		var mine := mines[i]
		mine["age"] = float(mine["age"]) + delta
		if float(mine["age"]) >= Balance.MINE_LIFETIME:
			mines.remove_at(i)
		elif float(mine["age"]) >= Balance.MINE_ARM_TIME and not enemies_in_circle(mine["pos"], Balance.MINE_TRIGGER).is_empty():
			mines.remove_at(i)
			detonate(mine["pos"])
	for i in range(_echoes.size() - 1, -1, -1):
		_echoes[i]["delay"] = float(_echoes[i]["delay"]) - delta
		if float(_echoes[i]["delay"]) <= 0.0:
			_blast(_echoes[i]["pos"], int(_echoes[i]["damage"]))
			_echoes.remove_at(i)
	_update_fields(delta)
	queue_redraw()


func _spot_is_free(at: Vector2) -> bool:
	for mine in mines:
		if at.distance_squared_to(mine["pos"]) < Balance.MINE_SPACING * Balance.MINE_SPACING:
			return false
	return true


func place(at: Vector2) -> void:
	if mines.size() >= Balance.MINE_MAX:
		mines.remove_at(0)
	mines.append({"pos": at, "age": 0.0})


func detonate(at: Vector2) -> void:
	var damage := damage_of(stat("damage"))
	_blast(at, damage)
	if is_milestone():
		_echoes.append({"pos": at, "delay": Balance.MINE_ECHO_DELAY, "damage": maxi(1, int(round(float(damage) * Balance.MINE_ECHO_RATIO)))})
	if is_special():
		fields.append({"pos": at, "age": 0.0, "tick": 0.0})


func _blast_radius() -> float:
	return area_of(stat("radius"))


func _blast(at: Vector2, damage: int) -> void:
	for enemy in enemies_in_circle(at, _blast_radius()):
		enemy.take_damage(damage, (enemy.global_position - at).normalized(), KNOCK)
	if fx:
		fx.ring(at, Palette.hdr(Palette.MINE, 1.6), _blast_radius(), 0.3)
		fx.burst(at, Palette.hdr(Palette.MINE, 1.3), 12, 300.0)


func _update_fields(delta: float) -> void:
	var radius := _blast_radius() * 0.9
	var damage := maxi(1, int(round(float(damage_of(stat("damage"))) * Balance.MINE_FIELD_RATIO)))
	for i in range(fields.size() - 1, -1, -1):
		var field := fields[i]
		field["age"] = float(field["age"]) + delta
		if float(field["age"]) >= Balance.MINE_FIELD_TIME:
			fields.remove_at(i)
			continue
		field["tick"] = float(field["tick"]) - delta
		if float(field["tick"]) > 0.0:
			continue
		field["tick"] = Balance.MINE_FIELD_TICK
		for enemy in enemies_in_circle(field["pos"], radius):
			enemy.apply_slow(Balance.NOVA_SLOW_FACTOR, Balance.MINE_FIELD_TICK + 0.1)
			enemy.take_damage(damage, Vector2.ZERO, 0.0)


func _draw() -> void:
	var radius := _blast_radius() * 0.9
	for field in fields:
		var fade := 1.0 - float(field["age"]) / Balance.MINE_FIELD_TIME
		var fill := Palette.MINE
		fill.a = 0.08 * fade
		draw_circle(field["pos"], radius, fill)
		var rim := Palette.hdr(Palette.MINE, 1.0)
		rim.a = 0.4 * fade
		draw_arc(field["pos"], radius, 0.0, TAU, 48, rim, 1.5, true)
	for mine in mines:
		var armed := float(mine["age"]) >= Balance.MINE_ARM_TIME
		var pulse := 0.75 + 0.25 * sin(_time * 6.0 + float(mine["age"]))
		# An eight-point star: a friendly, even-sided shape.
		var star := PackedVector2Array()
		for k in 8:
			var r := MINE_SIZE if k % 2 == 0 else MINE_SIZE * 0.5
			star.append((mine["pos"] as Vector2) + Vector2.from_angle(PI * float(k) / 4.0) * r)
		var core := Palette.hdr(Palette.MINE, 1.8 * pulse if armed else 0.7)
		draw_colored_polygon(star, Color(Palette.MINE.r * 0.2, Palette.MINE.g * 0.15, Palette.MINE.b * 0.3, 0.9))
		draw_polyline(Palette.closed(star), core, 1.5, true)
