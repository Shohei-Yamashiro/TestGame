extends Node2D

const PlayerScript := preload("res://scripts/player.gd")
const GemScript := preload("res://scripts/gem.gd")
const BackgroundScript := preload("res://scripts/background.gd")
const FxScript := preload("res://scripts/fx.gd")
const TitleDecoScript := preload("res://scripts/title_deco.gd")
const Palette := preload("res://scripts/palette.gd")
const Balance := preload("res://scripts/balance.gd")
const ScoreStore := preload("res://scripts/score_store.gd")
const Spawner := preload("res://scripts/spawner.gd")
const CameraRig := preload("res://scripts/camera_rig.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")
const UI_THEME := preload("res://scenes/ui/ui_theme.tres")
const Hud := preload("res://scripts/ui/hud.gd")
const LevelUp := preload("res://scripts/ui/level_up.gd")
const GameOver := preload("res://scripts/ui/game_over.gd")
const PauseMenu := preload("res://scripts/ui/pause_menu.gd")
const TitleMenu := preload("res://scripts/ui/title_menu.gd")
const HudScene := preload("res://scenes/ui/hud.tscn")
const LevelUpScene := preload("res://scenes/ui/level_up.tscn")
const GameOverScene := preload("res://scenes/ui/game_over.tscn")
const PauseScene := preload("res://scenes/ui/pause_menu.tscn")
const TitleScene := preload("res://scenes/ui/title_menu.tscn")
const LibraryScene := preload("res://scenes/ui/library.tscn")
const Library := preload("res://scripts/ui/library.gd")
const WEAPON_SCRIPTS := {
	"blaster": preload("res://scripts/weapons/blaster.gd"),
	"homing": preload("res://scripts/weapons/homing.gd"),
	"orbit": preload("res://scripts/weapons/orbit.gd"),
	"nova": preload("res://scripts/weapons/nova.gd"),
	"laser": preload("res://scripts/weapons/laser.gd"),
	"wings": preload("res://scripts/weapons/wings.gd"),
	"chain": preload("res://scripts/weapons/chain.gd"),
	"tesseract": preload("res://scripts/weapons/tesseract.gd"),
	"drain": preload("res://scripts/weapons/drain.gd"),
	"mine": preload("res://scripts/weapons/mine.gd"),
}

const UI_ACCENT := Color(0.35, 0.95, 1.0)
const GAME_OVER_DELAY := 0.7
const SEPARATION_CELL := 40.0
const SEPARATION_SPACING := 0.95
const SEPARATION_STRENGTH := 0.5

enum Phase { TITLE, PLAYING, PAUSED, LEVEL_UP, GAME_OVER }

# Survives reload_current_scene so "retry" can skip the title screen.
static var skip_title := false

var phase := Phase.TITLE
var world: Node2D
var player
var camera: CameraRig
var fx: Node2D
var scores := ScoreStore.new()
var spawner := Spawner.new(self)
var elapsed := 0.0
var kills := 0
var level := 1
var xp := 0
var xp_to_next := Balance.xp_to_next(1)
var _merge_cd := 0.0
var _xp_carry := 0.0
var pending_levels := 0
# Owned items in pick order: weapon id -> weapon node, passive id -> stage (1..6).
var weapons := {}
var passives := {}
# Entries are "weapon:<id>" or "passive:<id>".
var level_choices: Array[String] = []
var enemy_grid := {}
var score := 0
var kill_score := 0
var overflow_score := 0
var cleared := false

var hud_layer: Hud
var upgrade_layer: LevelUp
var game_over_layer: GameOver
var pause_layer: PauseMenu
var title_layer: TitleMenu
var library_layer: Library
var title_deco: Node2D


func _ready() -> void:
	# Runs after the player's physics step so the camera never lags a tick behind.
	process_physics_priority = 10
	add_to_group("game")
	scores.load_saved()
	_build_environment()
	_build_world()
	_build_ui()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	player.visible = false
	if skip_title:
		skip_title = false
		_start_game()


func _physics_process(delta: float) -> void:
	camera.update_shake(delta)
	if phase != Phase.PLAYING:
		return
	camera.follow(player, player.velocity, float(player.move_speed), delta)
	_separate_enemies()
	spawner.leash_enemies()
	_merge_cd -= delta
	if _merge_cd <= 0.0:
		_merge_cd = Balance.GEM_MERGE_INTERVAL
		_merge_gems()


# Resting gems that share a grid cell fuse into one, keeping the gem count (and draw cost) down.
func _merge_gems() -> void:
	var gems := get_tree().get_nodes_in_group("gems")
	if gems.size() < 2:
		return
	var cell := Balance.GEM_MERGE_CELL_CROWDED if gems.size() > Balance.GEM_CROWDED else Balance.GEM_MERGE_CELL
	var keepers := {}
	for gem in gems:
		if gem.is_queued_for_deletion() or not gem.can_merge():
			continue
		var key := Vector2i((gem.global_position / cell).floor())
		var keeper = keepers.get(key)
		if keeper == null:
			keepers[key] = gem
		else:
			gem.remove_from_group("gems")
			keeper.absorb(gem)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if library_layer.visible:
		if key.keycode in [KEY_ESCAPE, KEY_BACKSPACE, KEY_P]:
			library_layer.close()
		return
	match phase:
		Phase.TITLE:
			if title_layer.is_ranking_open():
				if key.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_BACKSPACE]:
					_show_ranking(false)
			elif key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
				_start_game()
		Phase.PLAYING:
			if key.keycode in [KEY_ESCAPE, KEY_P]:
				_pause()
		Phase.PAUSED:
			if key.keycode in [KEY_ESCAPE, KEY_P]:
				_resume()
		Phase.GAME_OVER:
			if game_over_layer.visible and key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_R]:
				_restart()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and phase == Phase.PLAYING:
		_pause()


func _start_game() -> void:
	if phase != Phase.TITLE:
		return
	phase = Phase.PLAYING
	world.process_mode = Node.PROCESS_MODE_INHERIT
	player.visible = true
	hud_layer.visible = true
	title_deco.visible = false
	title_layer.visible = false
	fx.ring(player.global_position, Palette.hdr(Palette.PLAYER, 1.6), 160.0, 0.6)
	fx.burst(player.global_position, Palette.hdr(Palette.PLAYER, 1.4), 24, 520.0)


func _pause() -> void:
	if phase != Phase.PLAYING:
		return
	phase = Phase.PAUSED
	world.process_mode = Node.PROCESS_MODE_DISABLED
	pause_layer.visible = true


func _resume() -> void:
	if phase != Phase.PAUSED:
		return
	pause_layer.visible = false
	phase = Phase.PLAYING
	world.process_mode = Node.PROCESS_MODE_INHERIT


func _back_to_title() -> void:
	if phase != Phase.PAUSED and phase != Phase.GAME_OVER:
		return
	skip_title = false
	get_tree().reload_current_scene()


func _quit() -> void:
	get_tree().quit()


func _process(delta: float) -> void:
	if phase == Phase.PLAYING:
		elapsed = minf(elapsed + delta, Balance.TIME_LIMIT)
		if elapsed >= Balance.TIME_LIMIT:
			_finish(true)
			_update_hud()
			return
		spawner.update(delta)
		if pending_levels > 0:
			_open_level_up()
	_update_hud()


# Enemies whose grid cell overlaps the circle; built once per physics tick by _separate_enemies.
func query_enemies(at: Vector2, radius: float) -> Array:
	var result: Array = []
	var x0 := floori((at.x - radius) / SEPARATION_CELL)
	var x1 := floori((at.x + radius) / SEPARATION_CELL)
	var y0 := floori((at.y - radius) / SEPARATION_CELL)
	var y1 := floori((at.y + radius) / SEPARATION_CELL)
	for cx in range(x0, x1 + 1):
		for cy in range(y0, y1 + 1):
			var bucket = enemy_grid.get(Vector2i(cx, cy))
			if bucket != null:
				result.append_array(bucket)
	return result


# Soft pairwise push using a uniform grid, so only nearby enemies are compared.
func _separate_enemies() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	var count := enemies.size()
	if count == 0:
		enemy_grid = {}
		return
	var positions := PackedVector2Array()
	positions.resize(count)
	var radii := PackedFloat32Array()
	radii.resize(count)
	var grid := {}
	for i in count:
		var enemy := enemies[i] as Node2D
		var p: Vector2 = enemy.global_position
		positions[i] = p
		radii[i] = float(enemy.get("radius"))
		var cell := Vector2i(floori(p.x / SEPARATION_CELL), floori(p.y / SEPARATION_CELL))
		if grid.has(cell):
			grid[cell].append(i)
		else:
			grid[cell] = [i]
	enemy_grid = {}
	for cell in grid:
		var nodes: Array = []
		for idx: int in grid[cell]:
			nodes.append(enemies[idx])
		enemy_grid[cell] = nodes
	var pushes := PackedVector2Array()
	pushes.resize(count)
	for i in count:
		var p := positions[i]
		var cx := floori(p.x / SEPARATION_CELL)
		var cy := floori(p.y / SEPARATION_CELL)
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var bucket = grid.get(Vector2i(cx + dx, cy + dy))
				if bucket == null:
					continue
				for j: int in bucket:
					if j <= i:
						continue
					var min_dist := (radii[i] + radii[j]) * SEPARATION_SPACING
					var d := positions[j] - p
					var dist_sq := d.length_squared()
					if dist_sq >= min_dist * min_dist:
						continue
					var dist := sqrt(dist_sq)
					var normal := d / dist if dist > 0.01 else Vector2.from_angle(float(i * 7 + j) * 1.3)
					var push := normal * (min_dist - dist) * 0.5 * SEPARATION_STRENGTH
					pushes[i] -= push
					pushes[j] += push
	for i in count:
		if pushes[i] != Vector2.ZERO:
			(enemies[i] as Node2D).global_position += pushes[i]


func _enemy_count() -> int:
	return get_tree().get_nodes_in_group("enemies").size()


func _remaining() -> float:
	return maxf(0.0, Balance.TIME_LIMIT - elapsed)


func _on_enemy_died(at: Vector2, value: int, points: int) -> void:
	kills += 1
	kill_score += points
	score += points
	camera.add_trauma(0.06)
	var gem := GemScript.new()
	gem.value = value
	gem.collected.connect(_on_gem_collected)
	world.add_child(gem)
	gem.global_position = at


func _on_player_hurt(_amount: int) -> void:
	camera.add_trauma(0.45)


func _on_gem_collected(value: int) -> void:
	if phase == Phase.GAME_OVER:
		return
	# Fractions from the growth passive are banked so small gems still add up.
	_xp_carry += float(value) * player.xp_mult
	var gained := int(_xp_carry)
	_xp_carry -= float(gained)
	xp += gained
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = Balance.xp_to_next(level)
		pending_levels += 1
		fx.ring(player.global_position, Palette.hdr(Palette.GEM, 1.8), 120.0, 0.5)
		fx.burst(player.global_position, Palette.hdr(Palette.GEM, 1.6), 18, 420.0)


func _on_player_died() -> void:
	_finish(false)


func _finish(survived: bool) -> void:
	if phase == Phase.GAME_OVER:
		return
	phase = Phase.GAME_OVER
	cleared = survived
	pending_levels = 0
	world.process_mode = Node.PROCESS_MODE_DISABLED
	upgrade_layer.visible = false
	pause_layer.visible = false
	var hp_bonus := 0
	var clear_bonus := 0
	if survived:
		clear_bonus = Balance.CLEAR_BONUS
		hp_bonus = int(player.hp) * Balance.HP_BONUS_PER_POINT
		score += clear_bonus + hp_bonus
		# Time-up wipes the field for a clean finish.
		for node in get_tree().get_nodes_in_group("enemies"):
			fx.shatter(node.global_position, Palette.hdr(node.color, 1.2), 1.0)
			node.queue_free()
		for shot in get_tree().get_nodes_in_group("enemy_shots"):
			shot.queue_free()
		fx.ring(player.global_position, Palette.hdr(Palette.PLAYER, 1.8), 600.0, 0.8)
		camera.add_trauma(0.5)
	var rank := scores.record(score, cleared, elapsed)
	var lines: Array[String] = ["撃破 %d体  %d" % [kills, kill_score]]
	if overflow_score > 0:
		lines.append("強化ボーナス  %d" % overflow_score)
	if survived:
		lines.append("クリア  %d    残りHP  %d" % [clear_bonus, hp_bonus])
	else:
		lines.append("生存 %s / %s" % [UiText.format_time(elapsed), UiText.format_time(Balance.TIME_LIMIT)])
	game_over_layer.show_result(survived, score, rank, scores.best, lines)
	await get_tree().create_timer(GAME_OVER_DELAY).timeout
	game_over_layer.visible = true


func _open_level_up() -> void:
	if phase != Phase.PLAYING:
		return
	pending_levels -= 1
	level_choices = _roll_choices()
	if level_choices.is_empty():
		_overflow_level()
		return
	phase = Phase.LEVEL_UP
	world.process_mode = Node.PROCESS_MODE_DISABLED
	upgrade_layer.show_choices(level_choices, item_level)


# Everything is maxed: no menu, just heal when hurt or bank points.
func _overflow_level() -> void:
	if player.hp < player.max_hp:
		player.hp = mini(player.max_hp, player.hp + Balance.HEAL_AMOUNT)
		fx.ring(player.global_position, Palette.hdr(Palette.HURT, 1.4), 90.0, 0.4)
		fx.burst(player.global_position, Palette.hdr(Palette.GEM, 1.4), 14, 300.0)
	else:
		score += Balance.OVERFLOW_SCORE
		overflow_score += Balance.OVERFLOW_SCORE
		fx.ring(player.global_position, Palette.hdr(Color(1.0, 0.85, 0.35), 1.6), 110.0, 0.45)
		fx.burst(player.global_position, Palette.hdr(Color(1.0, 0.85, 0.35), 1.4), 18, 380.0)


func _roll_choices() -> Array[String]:
	var available: Array[String] = []
	for id: String in Balance.WEAPON_ORDER:
		if weapons.has(id):
			if weapons[id].level < Balance.SPECIAL_STAGE:
				available.append("weapon:" + id)
		elif weapons.size() < Balance.MAX_WEAPONS:
			available.append("weapon:" + id)
	for id: String in Balance.PASSIVE_ORDER:
		if passives.has(id):
			if int(passives[id]) < Balance.MAX_STAGE:
				available.append("passive:" + id)
		elif passives.size() < Balance.MAX_PASSIVES:
			available.append("passive:" + id)
	available.shuffle()
	return available.slice(0, 3)


func _add_weapon(id: String) -> void:
	var weapon: Node2D = WEAPON_SCRIPTS[id].new()
	weapon.name = "Weapon_" + id
	weapon.setup(id, player)
	player.add_child(weapon)
	weapons[id] = weapon


func item_level(choice: String) -> int:
	var parts := choice.split(":")
	if parts[0] == "weapon":
		return weapons[parts[1]].level if weapons.has(parts[1]) else 0
	if parts[0] == "passive":
		return int(passives.get(parts[1], 0))
	return 0


func _on_choice_pressed(index: int) -> void:
	if phase != Phase.LEVEL_UP or index >= level_choices.size():
		return
	_apply_upgrade(level_choices[index])


func _apply_upgrade(id: String) -> void:
	if phase != Phase.LEVEL_UP:
		return
	var parts := id.split(":")
	if parts[0] == "weapon":
		if weapons.has(parts[1]):
			weapons[parts[1]].level += 1
		else:
			_add_weapon(parts[1])
	else:
		passives[parts[1]] = int(passives.get(parts[1], 0)) + 1
		_apply_stats()
	upgrade_layer.visible = false
	phase = Phase.PLAYING
	world.process_mode = Node.PROCESS_MODE_INHERIT
	fx.ring(player.global_position, Palette.hdr(UI_ACCENT, 1.6), 70.0, 0.35)


func _passive_value(id: String, key: String) -> Variant:
	var values: Array = Balance.PASSIVES[id][key]
	return values[mini(int(passives.get(id, 0)), Balance.MAX_STAGE)]


func _apply_stats() -> void:
	player.damage_mult = float(_passive_value("attack", "damage"))
	player.cooldown_mult = float(_passive_value("rate", "cooldown"))
	player.move_speed = float(_passive_value("move", "speed"))
	player.magnet_radius = float(_passive_value("magnet", "magnet"))
	player.area_mult = float(_passive_value("area", "area"))
	player.knock_mult = float(_passive_value("knock", "knock"))
	player.xp_mult = float(_passive_value("growth", "xp"))
	player.armor = float(_passive_value("armor", "armor"))
	player.regen = float(_passive_value("regen", "regen"))
	var new_max := int(_passive_value("max_hp", "max_hp"))
	if new_max > player.max_hp:
		player.hp += new_max - player.max_hp
	player.max_hp = new_max


func _restart() -> void:
	if phase != Phase.GAME_OVER:
		return
	skip_title = true
	get_tree().reload_current_scene()


func _build_world() -> void:
	var background := BackgroundScript.new()
	background.name = "Background"
	add_child(background)
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	player = PlayerScript.new()
	player.world = world
	player.died.connect(_on_player_died)
	player.hurt.connect(_on_player_hurt)
	world.add_child(player)
	player.global_position = Vector2.ZERO
	fx = FxScript.new()
	fx.name = "Fx"
	# Keeps bursts animating while the world is frozen for level-up and game over.
	fx.process_mode = Node.PROCESS_MODE_ALWAYS
	world.add_child(fx)
	_add_weapon(Balance.STARTING_WEAPON)
	camera = CameraRig.new()
	add_child(camera)
	camera.global_position = player.global_position
	camera.make_current()
	background.camera = camera
	title_deco = TitleDecoScript.new()
	title_deco.camera = camera
	title_deco.sub_font = UI_THEME.default_font
	add_child(title_deco)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.4)
	env.set_glow_level(4, 0.0)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var vignette_layer := CanvasLayer.new()
	vignette_layer.name = "Vignette"
	vignette_layer.layer = 5
	add_child(vignette_layer)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0))
	gradient.set_color(1, Color(0.0, 0.0, 0.02, 0.85))
	gradient.add_point(0.55, Color(0, 0, 0, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 256
	var vignette := TextureRect.new()
	vignette.texture = texture
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.position = Vector2(-0.1, -0.1) * get_viewport_rect().size
	vignette.size = get_viewport_rect().size * 1.2
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette_layer.add_child(vignette)


func _build_ui() -> void:
	hud_layer = HudScene.instantiate()
	add_child(hud_layer)
	upgrade_layer = LevelUpScene.instantiate()
	upgrade_layer.chosen.connect(_on_choice_pressed)
	add_child(upgrade_layer)
	game_over_layer = GameOverScene.instantiate()
	game_over_layer.restart_requested.connect(_restart)
	game_over_layer.title_requested.connect(_back_to_title)
	add_child(game_over_layer)
	pause_layer = PauseScene.instantiate()
	pause_layer.resume_requested.connect(_resume)
	pause_layer.library_requested.connect(_open_library)
	pause_layer.title_requested.connect(_back_to_title)
	add_child(pause_layer)
	title_layer = TitleScene.instantiate()
	title_layer.start_requested.connect(_start_game)
	title_layer.quit_requested.connect(_quit)
	title_layer.ranking_requested.connect(_show_ranking)
	title_layer.library_requested.connect(_open_library)
	add_child(title_layer)
	title_layer.set_best(scores.best)
	library_layer = LibraryScene.instantiate()
	library_layer.closed.connect(_on_library_closed)
	add_child(library_layer)


func _open_library() -> void:
	if phase != Phase.TITLE and phase != Phase.PAUSED:
		return
	title_deco.visible = false
	library_layer.open()


func _on_library_closed() -> void:
	title_deco.visible = phase == Phase.TITLE


func _show_ranking(open: bool) -> void:
	title_layer.show_ranking(open, scores.records)
	title_deco.visible = not open


func _update_hud() -> void:
	hud_layer.refresh(self)

