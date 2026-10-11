extends SceneTree

# Windowed capture of every particle kind (sparks, shards, rings, dots) at two moments of their life,
# with the world frozen so only the effects move. Use it to compare fx.gd changes before and after.
# Usage: godot --fixed-fps 60 --path <project> -s res://tests/visual/particles.gd -- [prefix]
const Palette := preload("res://scripts/palette.gd")

var game
var frame := 0
var shots := "user://ui_shots"
var prefix := "particles"


func _initialize() -> void:
	seed(3)
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
	if frame == 3:
		game._start_game()
		game.world.process_mode = Node.PROCESS_MODE_DISABLED
		game.hud_layer.visible = false
		for node in game.get_tree().get_nodes_in_group("enemies"):
			node.queue_free()
	if frame == 6:
		var fx = game.fx
		var c: Vector2 = game.player.global_position
		fx.shatter(c + Vector2(-380, -150), Palette.hdr(Palette.ENEMIES[0], 1.2), 1.0)
		fx.shatter(c + Vector2(-130, -150), Palette.hdr(Palette.ENEMIES[2], 1.2), 1.6)
		fx.shatter(c + Vector2(380, -150), Palette.hdr(Palette.PLAYER, 1.3), 2.2)
		fx.hit_sparks(c + Vector2(-380, 150), Vector2.RIGHT, Palette.hdr(Palette.BULLET, 1.2))
		fx.hit_sparks(c + Vector2(-250, 150), Vector2.UP, Palette.hdr(Palette.LASER, 1.3))
		fx.burst(c + Vector2(0, 150), Palette.hdr(Palette.GEM, 1.6), 18, 420.0)
		fx.ring(c + Vector2(250, 150), Palette.hdr(Palette.MINE, 1.6), 90.0, 0.5)
		fx.ring(c + Vector2(130, -150), Palette.hdr(Palette.HOMING, 1.4), 64.0, 0.25)
	if frame == 9:
		_shot("early")
	if frame == 20:
		_shot("late")
		return true
	return false
