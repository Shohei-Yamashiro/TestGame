extends SceneTree

# Usage: godot --headless --fixed-fps 60 --path <project> -s res://tests/bot.gd -- <policy> <seed> <max_seconds> nosave
#   policy: casual (short-sighted human-ish) | kite (flee enemies, chase gems) | idle (never move)

var game
var frame := 0
var policy := "kite"
var max_seconds := 300.0
var next_report := 10.0
var held := {}
var level_log: Array[String] = []
var peak_physics_ms := 0.0
var peak_process_ms := 0.0
var peak_enemies := 0
var first_hurt := -1.0
var last_hp := 100


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		policy = args[0]
	if args.size() > 1:
		seed(int(args[1]))
	if args.size() > 2:
		max_seconds = float(args[2])
	load("res://scripts/game.gd").persist_scores = false
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 2:
		game._start_game()
		return false
	if frame < 3:
		return false
	_track()
	if game.phase == game.Phase.LEVEL_UP:
		_choose()
	elif game.phase == game.Phase.PLAYING:
		_steer()
	if game.elapsed >= next_report:
		_report()
		next_report += 10.0
	if game.phase == game.Phase.GAME_OVER or game.elapsed >= max_seconds:
		_final()
		return true
	return false


var sum_frame_ms := 0.0
var frames_tracked := 0
var heavy_frame_ms := 0.0
var heavy_frames := 0


func _track() -> void:
	var phys := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var proc := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	peak_physics_ms = maxf(peak_physics_ms, phys)
	peak_process_ms = maxf(peak_process_ms, proc)
	sum_frame_ms += phys + proc
	frames_tracked += 1
	if game._enemy_count() >= 100:
		heavy_frame_ms += phys + proc
		heavy_frames += 1
	peak_enemies = maxi(peak_enemies, game._enemy_count())
	var hp: int = game.player.hp
	if hp < last_hp and first_hurt < 0.0:
		first_hurt = game.elapsed
	last_hp = hp


func _choose() -> void:
	var picks: Array = game.level_choices
	# Fill weapon slots first, then raise whichever offered item is lowest; heal when low.
	var best := 0
	var best_score := -1
	for i in picks.size():
		var id: String = picks[i]
		var score: int = 10 - game.item_level(id) + (3 if id.begins_with("weapon:") else 0)
		if score > best_score:
			best_score = score
			best = i
	var chosen: String = picks[best]
	var label := "%s%d" % [chosen.get_slice(":", 1), game.item_level(chosen) + 1]
	level_log.append("%5.1fs L%d:%s" % [game.elapsed, game.level, label])
	game._on_choice_pressed(best)


var _casual_dir := Vector2.ZERO
var _casual_cd := 0.0


func _steer() -> void:
	var dir := Vector2.ZERO
	if policy == "casual":
		# Human-ish: short awareness, decisions every 0.25s, and keeps drifting when nothing is close.
		_casual_cd -= 1.0 / 60.0
		if _casual_cd <= 0.0:
			_casual_cd = 0.25
			var me: Vector2 = game.player.global_position
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
		var me: Vector2 = game.player.global_position
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
		# Gentle orbit so the bot doesn't sit still in a calm moment.
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


func _stages() -> String:
	var items: Array[String] = []
	for id in game.weapons:
		items.append("%s%d" % [id, game.weapons[id].level])
	for id in game.passives:
		items.append("%s%d" % [id, game.passives[id]])
	return " ".join(items)


func _report() -> void:
	print("t=%3ds hp=%3d lv=%2d kills=%4d enemies=%3d %s  kills/s=%.1f" % [
		int(game.elapsed), game.player.hp, game.level, game.kills, game._enemy_count(), _stages(),
		float(game.kills) / maxf(1.0, game.elapsed)])


func _final() -> void:
	var outcome := "CLEARED" if game.cleared else ("DIED" if game.phase == game.Phase.GAME_OVER else "RUNNING")
	print("RESULT policy=%s %s at t=%.1fs score=%d (kill %d overflow %d) hp=%d level=%d kills=%d %s first_hurt=%.1fs" % [
		policy, outcome, game.elapsed, game.score, game.kill_score, game.overflow_score, game.player.hp, game.level, game.kills, _stages(), first_hurt])
	print("PERF peak_enemies=%d avg_frame=%.2fms avg_frame_100plus=%.2fms peak_physics=%.2fms peak_process=%.2fms (scripts only, headless)" % [
		peak_enemies, sum_frame_ms / maxf(1.0, frames_tracked), heavy_frame_ms / maxf(1.0, heavy_frames), peak_physics_ms, peak_process_ms])
	print("LEVELS " + ", ".join(level_log))
