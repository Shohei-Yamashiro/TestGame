extends SceneTree

# Windowed capture of the library: opened from the title (a few weapons with long tables), then from the pause screen on a passive.
const WEAPONS := ["wings", "orbit", "mine", "drain", "chain", "homing"]
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


# Reports when a weapon's detail runs past the bottom of its panel.
func _check_fit(id: String) -> void:
	var body: Control = game.library_layer.get_node("Root/Detail/Body")
	var needed := body.get_combined_minimum_size().y
	print("FIT %s %s needed=%.0f panel=%.0f" % [id, "OK" if needed <= body.size.y else "OVERFLOW", needed, body.size.y])


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 20:
		_shot("7_title_buttons.png")
		game._open_library()
	for i in WEAPONS.size():
		var at := 22 + i * 6
		if frame == at:
			game.library_layer.show_item(WEAPONS[i], true)
		if frame == at + 4:
			_check_fit(WEAPONS[i])
			_shot("8_library_%s.png" % WEAPONS[i])
	if frame == 60:
		game.library_layer.close()
		game._start_game()
	if frame == 90:
		game._pause()
	if frame == 100:
		_shot("9_pause.png")
		game._open_library()
		game.library_layer.show_item("armor", false)
	if frame == 110:
		_shot("10_library_passive.png")
		return true
	return false
