extends SceneTree

# Windowed capture of chain lightning, boomerang and mines in action (milestone, then special).
var game
var frame := 0
var shots := "user://ui_shots"


func _initialize() -> void:
	seed(5)
	load("res://scripts/score_store.gd").persist = false
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
		game.weapons["blaster"].queue_free()
		game.weapons.erase("blaster")
		for id in ["chain", "boomerang", "mine"]:
			game._add_weapon(id)
			game.weapons[id].level = 3
		game.elapsed = 90.0
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_D
		ev.keycode = KEY_D
		ev.pressed = true
		Input.parse_input_event(ev)
	if frame < 6:
		return false
	game.player.hp = game.player.max_hp
	game.pending_levels = 0
	if game.phase == game.Phase.PAUSED:
		game._resume()
	if game.phase == game.Phase.LEVEL_UP:
		game._on_choice_pressed(0)
	if frame == 150:
		_shot("11_weapons_milestone.png")
		for id in ["chain", "boomerang", "mine"]:
			game.weapons[id].level = 6
	if frame == 300:
		_shot("12_weapons_special.png")
		return true
	return false
