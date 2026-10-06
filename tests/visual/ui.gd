extends SceneTree

# Windowed UI capture: HUD icons, level-up cards, then the time-up result screen.
var game
var frame := 0
var shots := "user://ui_shots"
var stage := 0
var wait := 0


func _initialize() -> void:
	seed(3)
	load("res://scripts/game.gd").persist_scores = false
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shots))


func _shot(name: String) -> void:
	var path := ProjectSettings.globalize_path(shots + "/" + name)
	root.get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 5:
		game._start_game()
		game._add_weapon("wings")
		game._add_weapon("homing")
		game.weapons["blaster"].level = 6
		game.weapons["wings"].level = 3
		game.weapons["homing"].level = 4
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_D
		ev.keycode = KEY_D
		ev.pressed = true
		Input.parse_input_event(ev)
		game.passives["attack"] = 2
		game.passives["move"] = 5
		game._apply_stats()
		game.elapsed = 160.0
	if frame < 6:
		return false
	game.player.hp = maxi(game.player.hp, 40)
	if game.phase == game.Phase.PAUSED:
		game._resume()
	match stage:
		0:
			if game.phase == game.Phase.LEVEL_UP:
				game._on_choice_pressed(0)
			var wings = game.weapons["wings"]
			if wings.level < 6 and game.elapsed > 162.0 and wings._sweep_t > 0.17 and wings._sweep_t < 0.22:
				_shot("0_wings_normal.png")
				wings.level = 6
			if game.elapsed > 166.0 and wings.level == 6:
				_shot("1_hud_lastspurt.png")
				game.pending_levels = 1
				stage = 1
		1:
			if game.phase == game.Phase.LEVEL_UP:
				wait += 1
				if wait == 20:
					_shot("2_levelup.png")
					game._on_choice_pressed(0)
					stage = 2
		2:
			if game.phase == game.Phase.LEVEL_UP:
				game._on_choice_pressed(0)
			if game.phase == game.Phase.GAME_OVER and game.game_over_layer.visible:
				wait += 1
				if wait == 60:
					_shot("3_result.png")
					return true
	return false
