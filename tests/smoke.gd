extends SceneTree

# Smoke/stress test: every weapon and passive at its special, invincible player, 60 s of game time.
# Exits non-zero if the run stalls or ends early; script errors are caught by the runner's log scan.
# Usage: godot --headless --fixed-fps 60 --path <project> -s res://tests/smoke.gd -- nosave
const DURATION := 60.0
const MAX_FRAMES := 60 * 90

var game
var frame := 0
var peak_ms := 0.0
var sum_ms := 0.0
var samples := 0


func _initialize() -> void:
	seed(7)
	load("res://scripts/score_store.gd").persist = false
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 2:
		game._start_game()
		for id in ["homing", "orbit", "nova", "laser", "wings"]:
			game._add_weapon(id)
		for id in game.weapons:
			game.weapons[id].level = 6
		for id in ["attack", "rate", "move"]:
			game.passives[id] = 5
		game._apply_stats()
		return false
	if frame < 3:
		return false
	game.player.hp = game.player.max_hp
	game.pending_levels = 0
	if game.phase == game.Phase.LEVEL_UP:
		game._on_choice_pressed(0)
	var ms: float = (Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) + Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	if game.elapsed > 5.0:
		peak_ms = maxf(peak_ms, ms)
		sum_ms += ms
		samples += 1
	if game.phase == game.Phase.GAME_OVER:
		printerr("SMOKE FAIL: run ended early at t=%.1fs" % game.elapsed)
		quit(1)
		return false
	if game.elapsed >= DURATION:
		if game.kills <= 0:
			printerr("SMOKE FAIL: no kills in %ds" % int(DURATION))
			quit(1)
			return false
		print("SMOKE OK kills=%d avg_frame=%.2fms peak_frame=%.2fms" % [game.kills, sum_ms / maxf(1, samples), peak_ms])
		return true
	if frame > MAX_FRAMES:
		printerr("SMOKE FAIL: stalled at t=%.1fs" % game.elapsed)
		quit(1)
	return false
