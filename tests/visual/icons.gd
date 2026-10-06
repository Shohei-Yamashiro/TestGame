extends SceneTree

# Windowed capture of every weapon and passive icon, empty, mid-level and maxed.
const Balance := preload("res://scripts/balance.gd")
const ItemIconScript := preload("res://scripts/item_icon.gd")

var frame := 0
var shots := "user://ui_shots"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shots))
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.06, 0.11)
	bg.size = Vector2(1280, 720)
	root.add_child(bg)
	var rows := [Balance.WEAPON_ORDER, Balance.PASSIVE_ORDER]
	for row in rows.size():
		var ids: Array = rows[row]
		var is_weapon := row == 0
		for i in ids.size():
			for j in 3:
				var icon := ItemIconScript.new()
				icon.icon_size = 64.0
				icon.position = Vector2(60 + i * 115, 80 + row * 300 + j * 90)
				root.add_child(icon)
				var lv: int = [1, 3, Balance.SPECIAL_STAGE if is_weapon else Balance.MAX_STAGE][j]
				icon.configure(ids[i], is_weapon, lv)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 10:
		var path := ProjectSettings.globalize_path(shots + "/6_icons.png")
		root.get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ", path)
		return true
	return false
