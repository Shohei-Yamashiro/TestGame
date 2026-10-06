extends "res://scripts/weapons/weapon.gd"

const KNOCK := 0.0
const LINK_BEADS := 10
const FLOW_BEADS := 4
const FLOW_SPEED := 1.6

var _cd := 0.6
var _time := 0.0
# Each link: {"target": enemy, "age", "tick_cd", "end": last known target position}.
var links: Array[Dictionary] = []


func _ready() -> void:
	super._ready()
	top_level = true
	global_position = Vector2.ZERO
	z_index = 3


func _physics_process(delta: float) -> void:
	_time += delta
	_cd -= delta
	if _cd <= 0.0 and links.is_empty() and player.hp > Balance.DRAIN_MIN_HP:
		var targets := _nearest_enemies(player.global_position, area_of(Balance.DRAIN_RANGE), 2 if is_milestone() else 1, {})
		if not targets.is_empty() and player.spend_hp(Balance.DRAIN_COST):
			_cd = cooldown_of(stat("interval"))
			for target in targets:
				links.append({"target": target, "age": 0.0, "tick_cd": 0.0, "end": target.global_position})
	for i in range(links.size() - 1, -1, -1):
		if not _update_link(links[i], delta):
			links.remove_at(i)
	queue_redraw()


# Drains on each tick; returns false once the link has run out or lost its target.
func _update_link(link: Dictionary, delta: float) -> bool:
	link["age"] = float(link["age"]) + delta
	if float(link["age"]) >= Balance.DRAIN_TIME:
		return false
	var target = link["target"]
	if not _alive(target):
		return false
	link["end"] = target.global_position
	if player.global_position.distance_to(target.global_position) > area_of(Balance.DRAIN_BREAK):
		return false
	link["tick_cd"] = float(link["tick_cd"]) - delta
	if float(link["tick_cd"]) > 0.0:
		return true
	link["tick_cd"] = Balance.DRAIN_TICK
	var damage := damage_of(stat("damage"))
	var away: Vector2 = (target.global_position - player.global_position).normalized()
	target.take_damage(damage, away, KNOCK)
	var healed := float(damage) * float(stat("drain"))
	if fx:
		fx.hit_sparks(target.global_position, -away, Palette.hdr(Palette.DRAIN, 1.4))
	if not target.alive:
		healed += Balance.DRAIN_KILL_HEAL
		if fx:
			fx.ring(player.global_position, Palette.hdr(Palette.DRAIN, 1.3), 30.0, 0.25)
		if is_special():
			var taken := {}
			for other in links:
				if _alive(other["target"]):
					taken[other["target"].get_instance_id()] = true
			var next := _nearest_enemies(target.global_position, area_of(Balance.DRAIN_JUMP), 1, taken)
			if not next.is_empty():
				link["target"] = next[0]
				link["end"] = next[0].global_position
				link["tick_cd"] = 0.0
				player.heal(healed)
				return true
		player.heal(healed)
		return false
	player.heal(healed)
	return true


func _alive(target) -> bool:
	return target != null and is_instance_valid(target) and target.alive


func _nearest_enemies(from: Vector2, reach: float, count: int, skip: Dictionary) -> Array:
	var found: Array = []
	for node in game.query_enemies(from, reach):
		if not _alive(node) or skip.has(node.get_instance_id()):
			continue
		var dist := from.distance_squared_to(node.global_position)
		if dist <= reach * reach:
			found.append([dist, node])
	found.sort_custom(func(a, b): return a[0] < b[0])
	var result: Array = []
	for i in mini(count, found.size()):
		result.append(found[i][1])
	return result


func _diamond(at: Vector2, size: float, turn: float) -> PackedVector2Array:
	var shape := PackedVector2Array()
	for k in 4:
		shape.append(at + Vector2.from_angle(turn + PI * 0.5 * float(k)) * size)
	return shape


func _draw() -> void:
	var from := player.global_position
	for link in links:
		var to: Vector2 = link["end"]
		var fade := clampf((Balance.DRAIN_TIME - float(link["age"])) / 0.2, 0.0, 1.0)
		var along := to - from
		var turn := along.angle()
		var glow := Palette.hdr(Palette.DRAIN, 1.0)
		glow.a = 0.3 * fade
		draw_line(from, to, glow, 6.0, true)
		var beam := Palette.hdr(Palette.DRAIN, 1.8)
		beam.a = 0.8 * fade
		draw_line(from, to, beam, 1.2, true)
		# A string of thin diamonds stretched along the link, pulsing outward.
		for k in LINK_BEADS:
			var t := (float(k) + 0.5) / float(LINK_BEADS)
			var pulse := 0.6 + 0.4 * sin(_time * 12.0 - t * 8.0)
			var bead := _diamond(from + along * t, 3.0 * pulse, turn)
			draw_polyline(Palette.closed(bead), beam, 1.0, true)
		# Bright motes flow back from the target to feed the player.
		var mote := Palette.hdr(Palette.DRAIN.lerp(Color.WHITE, 0.4), 2.4)
		mote.a = fade
		for k in FLOW_BEADS:
			var t := fposmod(_time * FLOW_SPEED + float(k) / float(FLOW_BEADS), 1.0)
			draw_colored_polygon(_diamond(to - along * t, 3.5, turn + PI * 0.25), mote)
		var ring := Palette.hdr(Palette.DRAIN, 1.6)
		ring.a = 0.7 * fade
		draw_polyline(Palette.closed(_diamond(to, 14.0, _time * 3.0)), ring, 1.5, true)
