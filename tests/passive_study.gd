extends SceneTree

# Measures what one passive is worth with everything else held fixed.
# Usage: godot --headless --fixed-fps 60 --path <project> -s res://tests/passive_study.gd -- <passive|none> <policy> <seed>
#   Weapons follow a fixed plan; every third level-up goes to the passive under test ("none" wastes it).

const WEAPON_PLAN := ["blaster", "homing", "chain", "nova"]
const MAX_SECONDS := 185.0

var game
var frame := 0
var passive := "none"
var policy := "kite"
var level_ups := 0
var passive_picks := 0
var damage_taken := 0
var healed := 0
var last_hp := 0
var held := {}
var _casual_dir := Vector2.ZERO
var _casual_cd := 0.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	passive = args[0]
	policy = args[1]
	seed(int(args[2]))
	load("res://scripts/score_store.gd").persist = false
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 2:
		game._start_game()
		game.player.hurt.connect(func(amount: int) -> void: damage_taken += amount)
		last_hp = game.player.hp
		return false
	if frame < 3:
		return false
	var hp: int = game.player.hp
	if hp > last_hp:
		healed += hp - last_hp
	last_hp = hp
	if game.phase == game.Phase.LEVEL_UP:
		_level_up()
	elif game.phase == game.Phase.PLAYING:
		_steer()
	if game.phase == game.Phase.GAME_OVER or game.elapsed >= MAX_SECONDS:
		var outcome := "CLEARED" if game.cleared else ("DIED" if game.phase == game.Phase.GAME_OVER else "RUNNING")
		print("STUDY passive=%s policy=%s outcome=%s t=%.1f score=%d kills=%d level=%d taken=%d healed=%d hp=%d" % [
			passive, policy, outcome, game.elapsed, game.score, game.kills, game.level, damage_taken, healed, game.player.hp])
		return true
	return false


func _level_up() -> void:
	level_ups += 1
	var choice := ""
	# The same five picks go to the passive in every run; "none" throws exactly those away.
	if level_ups % 3 == 0 and passive_picks < 5:
		passive_picks += 1
		if passive != "none":
			choice = "passive:" + passive
	else:
		choice = _weapon_choice()
	if choice == "":
		# Wasted pick: close the menu without taking anything.
		game.upgrade_layer.visible = false
		game.phase = game.Phase.PLAYING
		game.world.process_mode = Node.PROCESS_MODE_INHERIT
		return
	game._apply_upgrade(choice)


func Balance():
	return load("res://scripts/balance.gd")


func _weapon_choice() -> String:
	for id: String in WEAPON_PLAN:
		if not game.weapons.has(id):
			return "weapon:" + id
	var best := ""
	var best_level := 99
	for id: String in WEAPON_PLAN:
		var lv: int = game.weapons[id].level
		if lv < Balance().SPECIAL_STAGE and lv < best_level:
			best_level = lv
			best = id
	return "" if best == "" else "weapon:" + best


func _steer() -> void:
	var dir := Vector2.ZERO
	var me: Vector2 = game.player.global_position
	if policy == "casual":
		_casual_cd -= 1.0 / 60.0
		if _casual_cd <= 0.0:
			_casual_cd = 0.25
			var flee := Vector2.ZERO
			for node in game.get_tree().get_nodes_in_group("enemies"):
				var d: Vector2 = me - node.global_position
				var dist := d.length()
				if dist < 170.0 and dist > 0.1:
					flee += d / dist * (170.0 - dist) / 170.0
			if flee.length() > 0.3:
				_casual_dir = flee.normalized()
			elif _casual_dir == Vector2.ZERO or randf() < 0.1:
				_casual_dir = Vector2.from_angle(randf() * TAU)
		dir = _casual_dir
	elif policy == "kite":
		for node in game.get_tree().get_nodes_in_group("enemies"):
			var d: Vector2 = me - node.global_position
			var dist := d.length()
			if dist < 300.0 and dist > 0.1:
				dir += d / dist * pow((300.0 - dist) / 300.0, 2.0) * 3.0
		var best_gem: Node2D = null
		var best_dist := 450.0
		for node in game.world.get_children():
			if node.get_script() == game.GemScript:
				var gd: float = me.distance_to(node.global_position)
				if gd < best_dist:
					best_dist = gd
					best_gem = node
		if best_gem != null:
			dir += (best_gem.global_position - me).normalized() * 1.2
		dir += Vector2.from_angle(game.elapsed * 0.4) * 0.3
	_press(KEY_D, dir.x > 0.35)
	_press(KEY_A, dir.x < -0.35)
	_press(KEY_S, dir.y > 0.35)
	_press(KEY_W, dir.y < -0.35)


func _press(key: Key, down: bool) -> void:
	if bool(held.get(key, false)) == down:
		return
	held[key] = down
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = down
	Input.parse_input_event(ev)
