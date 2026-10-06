extends SceneTree

# Windowed capture of the title logo and the high score table.
var game
var frame := 0
var shots := "user://ui_shots"


func _initialize() -> void:
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
	if frame == 100:
		_shot("4_title.png")
		for i in 7:
			game.score = 52000 - i * 6100
			game.cleared = i % 3 != 2
			game.elapsed = 180.0 if game.cleared else 95.0 + i * 7.0
			game._record_score()
		game._show_ranking(true)
	if frame == 110:
		_shot("5_ranking.png")
		return true
	return false
