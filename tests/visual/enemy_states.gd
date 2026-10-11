extends SceneTree

# Windowed capture of enemies held in each visual state, in rows by state and columns by kind:
# normal, hit flash, slowed, burning, charging (shooters glow, dashers show their lane), spawning in.
# Usage: godot --fixed-fps 60 --path <project> -s res://tests/visual/enemy_states.gd -- [prefix]
const KINDS := ["penta", "dart", "dasher", "shooter", "battery"]
const STATES := ["normal", "flash", "slow", "burn", "charge", "spawn"]

var game
var frame := 0
var shots := "user://ui_shots"
var prefix := "enemy_states"
var _cells: Array = []


func _initialize() -> void:
	seed(4)
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		prefix = args[0]
	load("res://scripts/score_store.gd").persist = false
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shots))


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 3:
		game._start_game()
		game.spawner.trickle_cd = 999.0
		game.spawner.ring_cd = 999.0
		game.hud_layer.visible = false
		game.player.visible = false
		var center: Vector2 = game.player.global_position
		for s in STATES.size():
			for k in KINDS.size():
				var at: Vector2 = center + Vector2(-440 + k * 110, -275 + s * 110)
				game.spawner.spawn_enemy(KINDS[k], at)
		var enemies: Array = game.get_tree().get_nodes_in_group("enemies")
		for i in enemies.size():
			_cells.append([enemies[i], STATES[i / KINDS.size()], enemies[i].global_position])
	if frame < 4:
		return false
	game.player.hp = game.player.max_hp
	for cell in _cells:
		_hold(cell[0], cell[1], cell[2])
	if frame == 40:
		var path := ProjectSettings.globalize_path("%s/%s.png" % [shots, prefix])
		root.get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ", path)
		return true
	return false


func _hold(enemy, state: String, at: Vector2) -> void:
	enemy.global_position = at
	enemy.speed = 0.0
	enemy.hp = 99999
	enemy._spin = 0.0
	enemy.rotation = 0.3
	enemy._action_cd = 999.0
	enemy._age = 0.15 if state == "spawn" else 1.0
	enemy._flash = 0.05 if state == "flash" else 0.0
	if state == "slow":
		enemy.apply_slow(0.5, 1.0)
	if state == "burn":
		enemy.apply_burn(0, 1.0)
	if state == "charge" and enemy.behavior != "":
		enemy._state = enemy.State.WINDUP
		enemy._state_time = 0.5 * (enemy.dash_windup if enemy.behavior == "dash" else enemy.Balance.SHOT_WINDUP)
		enemy._dash_dir = Vector2.RIGHT
		enemy._dash_start = at
		enemy._dash_length = 90.0
	else:
		enemy._state = enemy.State.CHASE
