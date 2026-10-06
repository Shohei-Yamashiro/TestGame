extends SceneTree

# Windowed capture: dasher lanes, shooter shots vs orbit special, electric shield, gem tiers.
var game
var frame := 0
var shots := "user://ui_shots"


func _initialize() -> void:
	seed(11)
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
	if frame == 5:
		game._start_game()
		game._add_weapon("nova")
		game._add_weapon("orbit")
		game.weapons["nova"].level = 6
		game.weapons["orbit"].level = 6
		game.weapons["blaster"].level = 3
		game.elapsed = 100.0
		var center: Vector2 = game.player.global_position
		var kinds := ["dasher", "dasher", "shooter", "shooter", "shooter", "hepta"]
		for i in kinds.size():
			game._spawn_enemy(kinds[i], center + Vector2.from_angle(TAU * float(i) / kinds.size()) * 300.0)
		# Gems of each tier in a row, plus a loose cluster to watch merging.
		var values := [1, 3, 8, 20]
		for i in values.size():
			var gem = game.GemScript.new()
			gem.value = values[i]
			game.world.add_child(gem)
			gem.global_position = center + Vector2(-90 + i * 60, 230)
		for i in 12:
			var gem = game.GemScript.new()
			game.world.add_child(gem)
			gem.global_position = center + Vector2(260 + randf() * 35, -200 + randf() * 35)
	if frame < 6:
		return false
	game.player.hp = game.player.max_hp
	game.pending_levels = 0
	game.trickle_cd = 999.0
	game.ring_cd = 999.0
	game.player.magnet_radius = 0.0
	if game.phase == game.Phase.PAUSED:
		game._resume()
	if game.phase == game.Phase.LEVEL_UP:
		game._on_choice_pressed(0)
	for enemy in game.get_tree().get_nodes_in_group("enemies"):
		if enemy.behavior == "dash" and enemy._state == enemy.State.WINDUP and enemy._state_time > 0.35 and frame > 30:
			_shot("8_dash_lane.png")
			frame = 1000
			break
	if frame > 1000 and frame == 1060:
		_shot("9_shield_gems.png")
		return true
	return frame > 1200 or (frame == 400 and _force())


func _force() -> bool:
	_shot("8_dash_lane.png")
	frame = 1000
	return false
