extends SceneTree

# Windowed capture of the HUD bar alone, over a flat backdrop, so its alignment can be checked by eye or by pixel.
var game
var frame := 0
var shots := "user://ui_shots"


func _initialize() -> void:
	seed(3)
	load("res://scripts/score_store.gd").persist = false
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shots))


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 5:
		game._start_game()
		for id in ["homing", "chain", "drain"]:
			game._add_weapon(id)
		game.weapons["blaster"].level = 6
		game.weapons["homing"].level = 3
		for id in ["attack", "rate", "max_hp", "regen"]:
			game.passives[id] = 2
		game._apply_stats()
		var cover := CanvasLayer.new()
		cover.layer = 5
		var backdrop := ColorRect.new()
		backdrop.color = Color(0.04, 0.06, 0.11)
		backdrop.size = Vector2(1280, 720)
		cover.add_child(backdrop)
		root.add_child(cover)
	if frame == 30:
		game.level = 12
		game.score = 12345
		game.kills = 678
		game.player.hp = 70
	if frame == 40:
		var path := ProjectSettings.globalize_path(shots + "/hud_only.png")
		root.get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ", path)
		return true
	return false
