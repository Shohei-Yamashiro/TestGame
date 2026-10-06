extends SceneTree

# Windowed capture of the laser retracting and a homing volley mid-launch.
var game
var frame := 0
var shots := "user://ui_shots"
var taken := 0


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
		game._add_weapon("homing")
		game._add_weapon("laser")
		game.weapons["laser"].level = 3
		game.weapons["homing"].level = 3
		game.elapsed = 40.0
	if frame < 6:
		return false
	game.player.hp = game.player.max_hp
	game.pending_levels = 0
	if game.phase == game.Phase.PAUSED:
		game._resume()
	if game.phase == game.Phase.LEVEL_UP:
		game._on_choice_pressed(0)
	if frame < 200:
		return false
	var laser = game.weapons["laser"]
	var homing = game.weapons["homing"]
	if taken == 0 and not laser._beams.is_empty() and float(laser._beams[0]["age"]) > 0.12:
		_shot("6_laser.png")
		taken = 1
	elif taken == 1 and homing._queue.size() == 1:
		_shot("7_homing.png")
		taken = 2
		return true
	return frame > 3000
