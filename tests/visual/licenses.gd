extends SceneTree

# Windowed capture of the title screen's licenses button and the licenses screen, top and scrolled.
# Usage: godot --fixed-fps 60 --path <project> -s res://tests/visual/licenses.gd -- [prefix]
var game
var frame := 0
var shots := "user://ui_shots"
var prefix := "licenses"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		prefix = args[0]
	load("res://scripts/score_store.gd").persist = false
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shots))


func _shot(name: String) -> void:
	var path := ProjectSettings.globalize_path("%s/%s_%s.png" % [shots, prefix, name])
	root.get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 60:
		_shot("title")
		game.title_layer.licenses_requested.emit()
	if frame == 70:
		_shot("top")
		game.licenses_layer.get_node("Root/Body").scroll_to_line(120)
	if frame == 80:
		_shot("scrolled")
		return true
	return false
