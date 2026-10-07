extends "res://scripts/weapons/weapon.gd"

const KNOCK := 12.0
const MINE_SIZE := 9.0

var _cd := 0.3
var _time := 0.0
# {"pos", "age"}
var mines: Array[Dictionary] = []


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
	var trigger := trigger_radius()
	for i in range(mines.size() - 1, -1, -1):
		var mine := mines[i]
		mine["age"] = float(mine["age"]) + delta
		if float(mine["age"]) >= Balance.MINE_LIFETIME:
			mines.remove_at(i)
		elif float(mine["age"]) >= Balance.MINE_ARM_TIME and not enemies_in_circle(mine["pos"], trigger).is_empty():
			mines.remove_at(i)
			detonate(mine["pos"])
	queue_redraw()


func max_mines() -> int:
	return int(stat("max"))


# An enemy entering this circle sets the mine off; it grows with the area passive.
func trigger_radius() -> float:
	return area_of(Balance.MINE_TRIGGER)


func _spot_is_free(at: Vector2) -> bool:
	for mine in mines:
		if at.distance_squared_to(mine["pos"]) < Balance.MINE_SPACING * Balance.MINE_SPACING:
			return false
	return true


func place(at: Vector2) -> void:
	while mines.size() >= max_mines():
		mines.remove_at(0)
	mines.append({"pos": at, "age": 0.0})


func detonate(at: Vector2) -> void:
	var damage := damage_of(stat("damage"))
	var burn := maxi(1, int(round(float(damage) * Balance.MINE_BURN_RATIO)))
	var spread := area_of(Balance.MINE_SPREAD_RADIUS) if is_special() else 0.0
	for enemy in enemies_in_circle(at, _blast_radius()):
		if is_milestone():
			enemy.apply_burn(burn, Balance.MINE_BURN_TIME, spread)
		enemy.take_damage(damage, (enemy.global_position - at).normalized(), KNOCK)
	if fx:
		fx.ring(at, Palette.hdr(Palette.MINE, 1.6), _blast_radius(), 0.3)
		fx.burst(at, Palette.hdr(Palette.BURN if is_milestone() else Palette.MINE, 1.3), 12, 300.0)


func _blast_radius() -> float:
	return area_of(stat("radius"))


func _draw() -> void:
	var trigger := trigger_radius()
	for mine in mines:
		var armed := float(mine["age"]) >= Balance.MINE_ARM_TIME
		var pulse := 0.75 + 0.25 * sin(_time * 6.0 + float(mine["age"]))
		var pos: Vector2 = mine["pos"]
		# The trigger range as a faint dashed ring, only once the mine can go off.
		if armed:
			var ring := Palette.hdr(Palette.MINE, 1.0)
			ring.a = 0.35
			for k in 12:
				var a := TAU * float(k) / 12.0 + _time * 0.6
				draw_arc(pos, trigger, a, a + TAU / 24.0, 4, ring, 1.0, true)
		# A hexagonal casing (friendly, even-sided) with a fuse stud on each corner and a core that blinks once armed.
		var casing := Palette.regular_polygon(6, MINE_SIZE, PI / 6.0)
		var inner := Palette.regular_polygon(6, MINE_SIZE * 0.42, PI / 6.0)
		for i in 6:
			casing[i] += pos
			inner[i] += pos
		var core := Palette.hdr(Palette.MINE, 1.8 * pulse if armed else 0.7)
		draw_colored_polygon(casing, Color(Palette.MINE.r * 0.2, Palette.MINE.g * 0.15, Palette.MINE.b * 0.3, 0.9))
		draw_polyline(Palette.closed(casing), core, 1.5, true)
		draw_colored_polygon(inner, core)
		for p in casing:
			draw_circle(p, 1.6, core)
