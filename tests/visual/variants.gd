extends SceneTree

# Windowed capture: every enemy kind side by side (frozen in place) plus a heal kit.
var game
var frame := 0
var shots := "user://ui_shots"


func _initialize() -> void:
	seed(5)
	load("res://scripts/score_store.gd").persist = false
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shots))


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 5:
		game._start_game()
		game.spawner.trickle_cd = 999.0
		game.spawner.ring_cd = 999.0
		var center: Vector2 = game.player.global_position
		var rows := [["tri", "penta", "hepta"], ["dart", "dasher", "lancer"], ["turret", "shooter", "battery"]]
		for r in rows.size():
			for c in rows[r].size():
				game.spawner.spawn_enemy(rows[r][c], center + Vector2(-260 + c * 110, -150 + r * 110))
		for enemy in game.get_tree().get_nodes_in_group("enemies"):
			enemy.speed = 0.0
			enemy.hp = 99999
			enemy.dash_trigger = 0.0
			enemy.shot_interval = 999.0
		game.drop_heal(center + Vector2(200, 0))
	if frame == 40:
		var path := ProjectSettings.globalize_path(shots + "/variants.png")
		root.get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ", path)
		return true
	return false
