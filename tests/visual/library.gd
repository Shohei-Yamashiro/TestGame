extends SceneTree

# Windowed capture of the library: opened from the title, then from the pause screen on a passive.
var game
var frame := 0
var shots := "user://ui_shots"


func _initialize() -> void:
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
	if frame == 20:
		_shot("7_title_buttons.png")
		game._open_library()
		game.library_layer.show_item("wings", true)
	if frame == 30:
		_shot("8_library_weapon.png")
		game.library_layer.close()
		game._start_game()
	if frame == 60:
		game._pause()
	if frame == 70:
		_shot("9_pause.png")
		game._open_library()
		game.library_layer.show_item("armor", false)
	if frame == 80:
		_shot("10_library_passive.png")
		return true
	return false
