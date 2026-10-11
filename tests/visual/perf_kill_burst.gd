extends SceneTree

# Windowed frame-time breakdown for the late game: every weapon at its special, lots of enemies and kills.
# Unlike smoke.gd this renders, so it reports the real frame time with render CPU/GPU time.
# Usage: godot --fixed-fps 60 --path <project> -s res://tests/visual/perf_kill_burst.gd -- [mid] [nofx] [nofxsim] [noglow] [nobg]
#   mid      four weapons at Lv4 instead of everything maxed, so the field fills up
#   nofx     hides the particle layer (still simulated)   nofxsim  also stops simulating it
#   noglow   turns the glow pass off                       nobg     hides the background
#   breakdown  once a second, times every world node's process step grouped by script
const START_AT := 120.0
const WARMUP := 3.0
const DURATION := 30.0

var game
var frame := 0
var _last_usec := 0
var _rows: Array[Dictionary] = []
var _flags: Array[String] = []


func _initialize() -> void:
	seed(7)
	_flags.assign(OS.get_cmdline_user_args())
	load("res://scripts/score_store.gd").persist = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)


func _process(_delta: float) -> bool:
	frame += 1
	if _flags.has("title"):
		return _title_frame()
	if frame == 3:
		_setup()
		return false
	if frame < 4:
		return false
	game.player.hp = game.player.max_hp
	game.pending_levels = 0
	if game.phase == game.Phase.PAUSED:
		game._resume()
	if game.phase == game.Phase.LEVEL_UP:
		game._on_choice_pressed(0)
	for group in ["enemies", "gems", "enemy_shots"]:
		if _flags.has("hide_" + group):
			for node in game.get_tree().get_nodes_in_group(group):
				node.visible = false
	var now := Time.get_ticks_usec()
	var wall := float(now - _last_usec) / 1000.0
	_last_usec = now
	if game.elapsed > START_AT + WARMUP:
		var rid := root.get_viewport_rid()
		_rows.append({
			"wall": wall,
			"render_cpu": RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu(),
			"gpu": RenderingServer.viewport_get_measured_render_time_gpu(rid),
			"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"particles": game.fx.live_count(),
			"enemies": game.get_tree().get_nodes_in_group("enemies").size(),
			"redrawing": _redrawing(),
		})
		if _flags.has("breakdown") and frame % 60 == 0:
			_time_scripts()
	if game.elapsed >= START_AT + WARMUP + DURATION or game.phase == game.Phase.GAME_OVER:
		_report()
		return true
	return false


# Times one extra process step of every node in the world, grouped by script. The extra step
# nudges the run off its normal course, which is why it only happens with the "breakdown" flag.
var _passes := 0
var _cost := {}


func _time_scripts() -> void:
	_passes += 1
	var step := 1.0 / 60.0
	var start := Time.get_ticks_usec()
	game._physics_process(step)
	_add_cost("game.gd (separation, leash, gem merge)", Time.get_ticks_usec() - start, 1)
	var nodes: Array[Node] = []
	_collect(game.world, nodes)
	for node in nodes:
		var script: Script = node.get_script()
		if script == null or not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var t0 := Time.get_ticks_usec()
		if node.has_method("_physics_process"):
			node._physics_process(step)
		if node.has_method("_process") and node != game:
			node._process(step)
		_add_cost(script.resource_path.get_file(), Time.get_ticks_usec() - t0, 1)


# Enemies whose body is redrawn this frame because something on it is animating.
func _redrawing() -> int:
	var count := 0
	for enemy in game.get_tree().get_nodes_in_group("enemies"):
		if enemy.needs_redraw():
			count += 1
	return count


func _collect(node: Node, out: Array[Node]) -> void:
	for child in node.get_children():
		out.append(child)
		_collect(child, out)


func _add_cost(key: String, usec: int, count: int) -> void:
	var entry: Array = _cost.get(key, [0, 0])
	entry[0] += usec
	entry[1] += count
	_cost[key] = entry


# Baseline: the idle title screen, to tell engine and window overhead apart from the game's own cost.
func _title_frame() -> bool:
	var now := Time.get_ticks_usec()
	if frame > 60:
		var rid := root.get_viewport_rid()
		_rows.append({
			"wall": float(now - _last_usec) / 1000.0,
			"render_cpu": RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu(),
			"gpu": RenderingServer.viewport_get_measured_render_time_gpu(rid),
			"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"particles": 0,
			"enemies": 0,
		})
	_last_usec = now
	if frame > 660:
		_report()
		return true
	return false


func _setup() -> void:
	game._start_game()
	# "mid" is a typical four-weapon build, weak enough to let the field fill up.
	var ids: Array = ["blaster", "nova", "chain", "mine"] if _flags.has("mid") else game.Balance.WEAPON_ORDER
	for id in ids:
		if not game.weapons.has(id):
			game._add_weapon(id)
	for id in game.weapons:
		game.weapons[id].level = 4 if _flags.has("mid") else 6
	for id in game.Balance.PASSIVE_ORDER:
		game.passives[id] = 5
	game._apply_stats()
	game.elapsed = START_AT
	if _flags.has("nofx"):
		game.fx.visible = false
	if _flags.has("nofxsim"):
		game.fx.visible = false
		game.fx.process_mode = Node.PROCESS_MODE_DISABLED
	if _flags.has("nohud"):
		game.hud_layer.visible = false
	if _flags.has("nobg"):
		game.get_node("Background").visible = false
	if _flags.has("noglow"):
		for node in game.get_children():
			if node is WorldEnvironment:
				node.environment.glow_enabled = false


func _report() -> void:
	var label := " ".join(_flags) if not _flags.is_empty() else "default"
	print("PERF [%s] frames=%d" % [label, _rows.size()])
	for key in ["wall", "render_cpu", "gpu", "draws", "particles", "enemies", "redrawing"]:
		var values: Array[float] = []
		for row in _rows:
			values.append(float(row[key]))
		values.sort()
		var total := 0.0
		for v in values:
			total += v
		var n := maxi(1, values.size())
		print("  %-10s avg=%8.2f  p95=%8.2f  max=%8.2f" % [key, total / n, values[int(n * 0.95) - 1] if values.size() > 1 else 0.0, values[-1] if not values.is_empty() else 0.0])
	# Frame cost against particle count, to see whether kill bursts are what drives it.
	var buckets := {}
	for row in _rows:
		var b := int(row["particles"]) / 250 * 250
		if not buckets.has(b):
			buckets[b] = [0, 0.0, 0.0, 0.0]
		buckets[b][0] += 1
		buckets[b][1] += row["wall"]
		buckets[b][2] += row["render_cpu"]
		buckets[b][3] += row["gpu"]
	var keys := buckets.keys()
	keys.sort()
	for b in keys:
		var e: Array = buckets[b]
		print("  particles %4d-%4d  frames=%5d  wall=%6.2f  render_cpu=%6.2f  gpu=%6.2f" % [
			b, b + 249, e[0], e[1] / e[0], e[2] / e[0], e[3] / e[0]])
	if _passes > 0:
		var names := _cost.keys()
		names.sort_custom(func(a, b): return _cost[a][0] > _cost[b][0])
		print("  script cost per frame (avg of %d samples):" % _passes)
		for name in names:
			var e: Array = _cost[name]
			print("    %-42s %6.2fms  nodes=%6.1f" % [name, float(e[0]) / 1000.0 / _passes, float(e[1]) / _passes])
