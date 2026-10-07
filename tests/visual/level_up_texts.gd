extends SceneTree

# Windowed capture of level-up cards with the longest texts (new weapon descriptions and a special heading).
var layer
var frame := 0
var shots := "user://ui_shots"


func _initialize() -> void:
	layer = (load("res://scenes/ui/level_up.tscn") as PackedScene).instantiate()
	root.add_child(layer)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shots))


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 3:
		var stages := {"weapon:tesseract": 0, "weapon:drain": 0, "weapon:blaster": 5}
		var choices: Array[String] = ["weapon:tesseract", "weapon:drain", "weapon:blaster"]
		layer.show_choices(choices, func(id: String) -> int: return stages[id])
	if frame == 8:
		var path := ProjectSettings.globalize_path(shots + "/7_level_up_texts.png")
		root.get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ", path)
		return true
	return false
