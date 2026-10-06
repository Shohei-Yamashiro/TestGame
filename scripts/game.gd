extends Node2D

const PlayerScript := preload("res://scripts/player.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const GemScript := preload("res://scripts/gem.gd")
const BackgroundScript := preload("res://scripts/background.gd")
const FxScript := preload("res://scripts/fx.gd")
const TitleDecoScript := preload("res://scripts/title_deco.gd")
const ItemIconScript := preload("res://scripts/item_icon.gd")
const Palette := preload("res://scripts/palette.gd")
const Balance := preload("res://scripts/balance.gd")
const WEAPON_SCRIPTS := {
	"blaster": preload("res://scripts/weapons/blaster.gd"),
	"homing": preload("res://scripts/weapons/homing.gd"),
	"orbit": preload("res://scripts/weapons/orbit.gd"),
	"nova": preload("res://scripts/weapons/nova.gd"),
	"laser": preload("res://scripts/weapons/laser.gd"),
	"wings": preload("res://scripts/weapons/wings.gd"),
}

const UI_ACCENT := Color(0.35, 0.95, 1.0)
const UI_PANEL := Color(0.04, 0.06, 0.11, 0.94)
const GAME_OVER_DELAY := 0.7
const SAVE_PATH := "user://save.cfg"
const MAX_RECORDS := 10

const LOOK_AHEAD := Vector2(80.0, 80.0)
const LOOK_SMOOTH_MOVING := 0.7
const LOOK_SMOOTH_STOPPING := 0.4
const ENEMY_LEASH := 1000.0
const SEPARATION_CELL := 40.0
const SEPARATION_SPACING := 0.95
const SEPARATION_STRENGTH := 0.5
const SHAKE_MAX := 9.0
const SHAKE_DECAY := 2.2

enum Phase { TITLE, PLAYING, PAUSED, LEVEL_UP, GAME_OVER }

# Survives reload_current_scene so "retry" can skip the title screen.
static var skip_title := false
static var persist_scores := true

var phase := Phase.TITLE
var world: Node2D
var player
var camera: Camera2D
var fx: Node2D
var look_offset := Vector2.ZERO
var look_velocity := Vector2.ZERO
var elapsed := 0.0
var kills := 0
var level := 1
var xp := 0
var xp_to_next := Balance.xp_to_next(1)
var trickle_cd := 0.6
var ring_cd := 0.4
var _merge_cd := 0.0
var pending_levels := 0
# Owned items in pick order: weapon id -> weapon node, passive id -> stage (1..6).
var weapons := {}
var passives := {}
# Entries are "weapon:<id>" or "passive:<id>".
var level_choices: Array[String] = []
var trauma := 0.0
var enemy_grid := {}
var score := 0
var kill_score := 0
var overflow_score := 0
var best_score := 0
# Top runs, best first: {score, date, cleared, time}.
var records: Array = []
var ranking_root: Control
var ranking_rows: Control
var cleared := false
var hud_weapon_icons: Array = []
var hud_passive_icons: Array = []
var score_label: Label
var ui_font: Font

var hp_label: Label
var level_label: Label
var time_label: Label
var hp_fill: Panel
var xp_fill: Panel

var upgrade_layer: CanvasLayer
var choice_buttons: Array[Button] = []

var game_over_layer: CanvasLayer
var go_title: Label
var go_stats: Label
var go_score: Label
var go_best: Label
var btn_restart: Button
var btn_go_title: Button

var hud_layer: CanvasLayer
var title_layer: CanvasLayer
var title_deco: Node2D
var btn_start: Button
var btn_quit: Button
var pause_layer: CanvasLayer
var btn_resume: Button
var btn_pause_title: Button


func _ready() -> void:
	# Runs after the player's physics step so the camera never lags a tick behind.
	process_physics_priority = 10
	add_to_group("game")
	_load_best()
	ui_font = _make_font()
	_build_environment()
	_build_world()
	_build_hud()
	_build_upgrade_ui()
	_build_game_over_ui()
	_build_pause_ui()
	_build_title_ui()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	player.visible = false
	if skip_title:
		skip_title = false
		_start_game()


func _physics_process(delta: float) -> void:
	_update_shake(delta)
	if phase != Phase.PLAYING:
		return
	_update_camera(delta)
	_separate_enemies()
	_leash_enemies()
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


func add_trauma(amount: float) -> void:
	trauma = minf(1.0, trauma + amount)


func _update_shake(delta: float) -> void:
	trauma = maxf(0.0, trauma - SHAKE_DECAY * delta)
	var strength := trauma * trauma * SHAKE_MAX
	camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match phase:
		Phase.TITLE:
			if ranking_root.visible:
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
		var spurt := Balance.LAST_SPURT_SPAWN if _remaining() <= Balance.LAST_SPURT else 1.0
		trickle_cd -= delta
		if trickle_cd <= 0.0:
			trickle_cd = Balance.trickle_interval(elapsed) * spurt
			_spawn_pack()
		ring_cd -= delta
		if ring_cd <= 0.0:
			ring_cd = Balance.ring_interval(elapsed) * spurt
			_spawn_ring()
		if pending_levels > 0:
			_open_level_up()
	_update_hud()


func _update_camera(delta: float) -> void:
	var move_ratio: Vector2 = player.velocity / maxf(1.0, float(player.move_speed))
	# Standing still keeps the current lead: drifting back to centre on its own
	# scrolls the world forward and reads as the ship backing up.
	if move_ratio == Vector2.ZERO:
		_smooth_damp_look(look_offset, LOOK_SMOOTH_STOPPING, delta)
	else:
		_smooth_damp_look(move_ratio * LOOK_AHEAD, LOOK_SMOOTH_MOVING, delta)
	camera.global_position = player.global_position + look_offset


# Critically damped spring, so the camera eases in and out without overshoot.
func _smooth_damp_look(target: Vector2, smooth_time: float, delta: float) -> void:
	var omega := 2.0 / smooth_time
	var x := omega * delta
	var decay := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := look_offset - target
	var temp := (look_velocity + omega * change) * delta
	look_velocity = (look_velocity - omega * temp) * decay
	look_offset = target + (change + temp) * decay


func _view_rect() -> Rect2:
	var size := get_viewport_rect().size
	return Rect2(camera.get_screen_center_position() - size * 0.5, size)


func _edge_spawn_position() -> Vector2:
	var view := _view_rect()
	var margin := 40.0
	match randi() % 4:
		0:
			return Vector2(randf_range(view.position.x, view.end.x), view.position.y - margin)
		1:
			return Vector2(view.end.x + margin, randf_range(view.position.y, view.end.y))
		2:
			return Vector2(randf_range(view.position.x, view.end.x), view.end.y + margin)
		_:
			return Vector2(view.position.x - margin, randf_range(view.position.y, view.end.y))


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


# Stragglers reappear on the edge the player is heading toward, so outrunning the horde doesn't thin it out.
func _leash_enemies() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node2D
		if enemy != null and enemy.global_position.distance_to(player.global_position) > ENEMY_LEASH:
			enemy.global_position = _edge_position_toward(player.velocity)


func _edge_position_toward(dir: Vector2) -> Vector2:
	if dir.length_squared() < 1.0:
		return _edge_spawn_position()
	var view := _view_rect()
	var center := view.get_center()
	var ray := dir.normalized().rotated(randf_range(-0.9, 0.9))
	var half := view.size * 0.5 + Vector2(40, 40)
	var t := minf(half.x / maxf(absf(ray.x), 0.001), half.y / maxf(absf(ray.y), 0.001))
	return center + ray * t


func _enemy_count() -> int:
	return get_tree().get_nodes_in_group("enemies").size()


func _spawn_enemy(kind: String, at: Vector2) -> void:
	if _enemy_count() >= Balance.ENEMY_CAP:
		return
	if kind == "shooter" and get_tree().get_nodes_in_group("shooters").size() >= Balance.SHOOTER_MAX:
		kind = "penta"
	var enemy := EnemyScript.new()
	enemy.setup(kind, elapsed)
	enemy.died.connect(_on_enemy_died)
	world.add_child(enemy)
	enemy.global_position = at


# A small clump entering from one point on the screen edge.
func _spawn_pack() -> void:
	var origin := _edge_spawn_position()
	var kind := Balance.pick_enemy_kind(elapsed)
	var count := Balance.trickle_pack(elapsed)
	if Balance.ENEMY_KINDS[kind].has("behavior"):
		count = mini(count, 3)
	for i in count:
		_spawn_enemy(kind, origin + Vector2(randf_range(-28, 28), randf_range(-28, 28)))


# A full ring just outside the screen so enemies close in from every direction.
func _spawn_ring() -> void:
	var count := Balance.ring_count(elapsed)
	var center := camera.get_screen_center_position()
	var radius := get_viewport_rect().size.length() * 0.5 + 50.0
	var offset := randf() * TAU
	for i in count:
		var angle := offset + TAU * float(i) / float(count)
		var jitter := Vector2(randf_range(-20, 20), randf_range(-20, 20))
		_spawn_enemy(Balance.pick_enemy_kind(elapsed, false), center + Vector2.from_angle(angle) * radius + jitter)


func _remaining() -> float:
	return maxf(0.0, Balance.TIME_LIMIT - elapsed)


func _on_enemy_died(at: Vector2, value: int, points: int) -> void:
	kills += 1
	kill_score += points
	score += points
	add_trauma(0.06)
	var gem := GemScript.new()
	gem.value = value
	gem.collected.connect(_on_gem_collected)
	world.add_child(gem)
	gem.global_position = at


func _on_player_hurt(_amount: int) -> void:
	add_trauma(0.45)


func _on_gem_collected(value: int) -> void:
	if phase == Phase.GAME_OVER:
		return
	xp += value
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
		add_trauma(0.5)
	var rank := _record_score()
	go_title.text = "タイムアップ！" if survived else "ゲームオーバー"
	go_title.add_theme_color_override("font_color", Palette.GEM if survived else Palette.HURT)
	var lines: Array[String] = ["撃破 %d体  %d" % [kills, kill_score]]
	if overflow_score > 0:
		lines.append("強化ボーナス  %d" % overflow_score)
	if survived:
		lines.append("クリア  %d    残りHP  %d" % [clear_bonus, hp_bonus])
	else:
		lines.append("生存 %s / %s" % [_format_time(elapsed), _format_time(Balance.TIME_LIMIT)])
	go_stats.text = "\n".join(lines)
	go_score.text = "%d" % score
	if rank == 0:
		go_best.text = "NEW RECORD!"
	elif rank > 0:
		go_best.text = "ランクイン  %d位      BEST  %d" % [rank + 1, best_score]
	else:
		go_best.text = "BEST  %d" % best_score
	go_best.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35) if rank >= 0 else Color(0.75, 0.88, 0.95))
	await get_tree().create_timer(GAME_OVER_DELAY).timeout
	game_over_layer.visible = true


func _load_best() -> void:
	# Automated runs pass "nosave" so they never touch the player's record.
	if OS.get_cmdline_user_args().has("nosave"):
		persist_scores = false
	if not persist_scores:
		return
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	records = cfg.get_value("score", "records", [])
	var legacy := int(cfg.get_value("score", "best", 0))
	if records.is_empty() and legacy > 0:
		records = [{"score": legacy, "date": "", "cleared": false, "time": 0.0}]
	if not records.is_empty():
		best_score = int(records[0]["score"])


func _save_scores() -> void:
	if not persist_scores:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("score", "best", best_score)
	cfg.set_value("score", "records", records)
	cfg.save(SAVE_PATH)


# Inserts this run into the ranking and returns its 0-based rank, or -1 if it missed the list.
func _record_score() -> int:
	var rank := records.size()
	for i in records.size():
		if score > int(records[i]["score"]):
			rank = i
			break
	if rank >= MAX_RECORDS:
		return -1
	var date := Time.get_datetime_string_from_system(false, true).substr(0, 16)
	records.insert(rank, {"score": score, "date": date, "cleared": cleared, "time": elapsed})
	records.resize(mini(records.size(), MAX_RECORDS))
	best_score = int(records[0]["score"])
	_save_scores()
	return rank


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
	_refresh_upgrade_buttons()
	upgrade_layer.visible = true


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
	player.magnet_radius = float(_passive_value("move", "magnet"))


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
	camera = Camera2D.new()
	camera.name = "Camera"
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	add_child(camera)
	camera.global_position = player.global_position
	camera.make_current()
	background.camera = camera
	title_deco = TitleDecoScript.new()
	title_deco.camera = camera
	title_deco.sub_font = ui_font
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


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	layer.layer = 10
	layer.visible = false
	add_child(layer)
	hud_layer = layer
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var view := get_viewport_rect().size
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.06, 0.72)
	shade.position = Vector2.ZERO
	shade.size = Vector2(view.x, 84)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var rule := ColorRect.new()
	rule.color = Color(UI_ACCENT.r, UI_ACCENT.g, UI_ACCENT.b, 0.45)
	rule.position = Vector2(0, 84)
	rule.size = Vector2(view.x, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(rule)
	var hp_back := Panel.new()
	hp_back.position = Vector2(30, 52)
	hp_back.size = Vector2(240, 14)
	hp_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_back.add_theme_stylebox_override("panel", _slanted_box(Color(0.3, 0.06, 0.1, 0.9), Color(1.0, 0.3, 0.35, 0.6), 1))
	root.add_child(hp_back)
	hp_fill = Panel.new()
	hp_fill.position = Vector2(30, 52)
	hp_fill.size = Vector2(240, 14)
	hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_fill.add_theme_stylebox_override("panel", _slanted_box(Color(1.0, 0.3, 0.38), Color(0, 0, 0, 0), 0))
	root.add_child(hp_fill)
	hp_label = _label(root, "HP  100 / 100", Vector2(28, 12), Vector2(250, 32), 22)
	level_label = _label(root, "レベル  1", Vector2(310, 12), Vector2(200, 32), 22)
	var xp_back := Panel.new()
	xp_back.position = Vector2(312, 52)
	xp_back.size = Vector2(180, 14)
	xp_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_back.add_theme_stylebox_override("panel", _slanted_box(Color(0.04, 0.2, 0.18, 0.9), Color(Palette.GEM.r, Palette.GEM.g, Palette.GEM.b, 0.6), 1))
	root.add_child(xp_back)
	xp_fill = Panel.new()
	xp_fill.position = xp_back.position
	xp_fill.size = xp_back.size
	xp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_fill.add_theme_stylebox_override("panel", _slanted_box(Palette.GEM, Color(0, 0, 0, 0), 0))
	root.add_child(xp_fill)
	time_label = _label(root, "3:00", Vector2(520, 8), Vector2(150, 44), 34)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var time_caption := _label(root, "残り時間", Vector2(520, 50), Vector2(150, 24), 15)
	time_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_caption.add_theme_color_override("font_color", Color(0.7, 0.85, 0.95, 0.75))
	score_label = _label(root, "0", Vector2(680, 8), Vector2(180, 44), 30)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	var score_caption := _label(root, "SCORE", Vector2(680, 50), Vector2(180, 24), 15)
	score_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_caption.add_theme_color_override("font_color", Color(0.7, 0.85, 0.95, 0.75))
	for i in Balance.MAX_WEAPONS:
		hud_weapon_icons.append(_make_icon(root, Vector2(890 + i * 50, 14), 40.0))
	for i in Balance.MAX_PASSIVES:
		hud_passive_icons.append(_make_icon(root, Vector2(1066 + i * 50, 14), 40.0))
	var divider := ColorRect.new()
	divider.color = Color(UI_ACCENT.r, UI_ACCENT.g, UI_ACCENT.b, 0.3)
	divider.position = Vector2(1048, 16)
	divider.size = Vector2(1, 52)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(divider)
	var hint := _label(root, "WASD / 方向キーで移動    武器は自動で攻撃    Esc でポーズ", Vector2(0, view.y - 36), Vector2(view.x, 28), 18)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.7, 0.85, 0.95, 0.75))


func _build_upgrade_ui() -> void:
	upgrade_layer = CanvasLayer.new()
	upgrade_layer.name = "Upgrade"
	upgrade_layer.layer = 20
	upgrade_layer.visible = false
	add_child(upgrade_layer)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	upgrade_layer.add_child(root)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_overlay())
	root.add_child(_panel(Vector2(290, 115), Vector2(700, 490)))
	var title := _label(root, "レベルアップ", Vector2(290, 138), Vector2(700, 52), 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Palette.GEM)
	var hint := _label(root, "1つ選んでください（武器・パッシブ各3枠 / 武器はLv5の次にスペシャル）", Vector2(290, 192), Vector2(700, 32), 19)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.75, 0.88, 0.95))
	for i in 3:
		var button := _choice_button(root, "", Vector2(350, 245 + i * 112))
		button.size = Vector2(580, 92)
		button.custom_minimum_size = button.size
		var icon := _make_icon(button, Vector2(30, 13), 50.0)
		var heading := _label(button, "", Vector2(100, 10), Vector2(460, 36), 23)
		var detail := _label(button, "", Vector2(100, 50), Vector2(460, 30), 16)
		detail.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
		button.set_meta("icon", icon)
		button.set_meta("heading", heading)
		button.set_meta("detail", detail)
		button.pressed.connect(_on_choice_pressed.bind(i))
		choice_buttons.append(button)


func _build_game_over_ui() -> void:
	game_over_layer = CanvasLayer.new()
	game_over_layer.name = "GameOver"
	game_over_layer.layer = 30
	game_over_layer.visible = false
	add_child(game_over_layer)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_over_layer.add_child(root)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_overlay())
	root.add_child(_panel(Vector2(350, 110), Vector2(580, 500)))
	go_title = _label(root, "", Vector2(350, 138), Vector2(580, 56), 40)
	go_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go_score = _label(root, "0", Vector2(350, 190), Vector2(580, 80), 64)
	go_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go_score.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	go_best = _label(root, "", Vector2(350, 268), Vector2(580, 32), 22)
	go_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go_stats = _label(root, "", Vector2(350, 308), Vector2(580, 90), 19)
	go_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go_stats.add_theme_color_override("font_color", Color(0.75, 0.88, 0.95))
	btn_restart = _choice_button(root, "もう一度（Enter）", Vector2(410, 420))
	btn_restart.pressed.connect(_restart)
	btn_go_title = _choice_button(root, "タイトルへ", Vector2(410, 492))
	btn_go_title.pressed.connect(_back_to_title)


func _build_pause_ui() -> void:
	pause_layer = CanvasLayer.new()
	pause_layer.name = "Pause"
	pause_layer.layer = 25
	pause_layer.visible = false
	add_child(pause_layer)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_layer.add_child(root)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_overlay())
	root.add_child(_panel(Vector2(390, 185), Vector2(500, 350)))
	var title := _label(root, "ポーズ", Vector2(390, 215), Vector2(500, 60), 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", UI_ACCENT)
	var hint := _label(root, "Esc / P で再開", Vector2(390, 280), Vector2(500, 30), 18)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.75, 0.88, 0.95))
	btn_resume = _choice_button(root, "再開", Vector2(410, 335))
	btn_resume.pressed.connect(_resume)
	btn_pause_title = _choice_button(root, "タイトルへ", Vector2(410, 407))
	btn_pause_title.pressed.connect(_back_to_title)


func _build_title_ui() -> void:
	title_layer = CanvasLayer.new()
	title_layer.name = "Title"
	title_layer.layer = 40
	add_child(title_layer)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_layer.add_child(root)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var view := get_viewport_rect().size
	# The logo itself is drawn by title_deco, in the world layer where glow applies.
	if best_score > 0:
		var hi := _label(root, "HI-SCORE  %d" % best_score, Vector2(0, 352), Vector2(view.x, 30), 20)
		hi.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hi.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	btn_start = _choice_button(root, "スタート", Vector2(410, 400))
	btn_start.pressed.connect(_start_game)
	var btn_ranking := _choice_button(root, "ハイスコア", Vector2(410, 470))
	btn_ranking.pressed.connect(_show_ranking.bind(true))
	btn_quit = _choice_button(root, "終了", Vector2(410, 540))
	btn_quit.pressed.connect(_quit)
	var controls := _label(root, "移動  WASD / 方向キー      攻撃  自動      ポーズ  Esc      Enter / Space でスタート", Vector2(0, view.y - 44), Vector2(view.x, 28), 17)
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.add_theme_color_override("font_color", Color(0.7, 0.85, 0.95, 0.8))
	_build_ranking_ui()


func _build_ranking_ui() -> void:
	ranking_root = Control.new()
	ranking_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ranking_root.visible = false
	title_layer.add_child(ranking_root)
	ranking_root.add_child(_overlay())
	ranking_root.add_child(_panel(Vector2(290, 50), Vector2(700, 620)))
	var heading := _label(ranking_root, "HIGH SCORE  TOP %d" % MAX_RECORDS, Vector2(290, 72), Vector2(700, 48), 32)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_color_override("font_color", UI_ACCENT)
	var header_color := Color(0.6, 0.75, 0.85)
	for column in [["順位", 330.0, 70.0, HORIZONTAL_ALIGNMENT_CENTER], ["スコア", 410.0, 190.0, HORIZONTAL_ALIGNMENT_RIGHT],
			["結果", 630.0, 100.0, HORIZONTAL_ALIGNMENT_CENTER], ["日時", 750.0, 200.0, HORIZONTAL_ALIGNMENT_LEFT]]:
		var label := _label(ranking_root, column[0], Vector2(column[1], 132), Vector2(column[2], 26), 16)
		label.horizontal_alignment = column[3]
		label.add_theme_color_override("font_color", header_color)
	ranking_rows = Control.new()
	ranking_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ranking_root.add_child(ranking_rows)
	var back := _choice_button(ranking_root, "戻る（Esc）", Vector2(410, 590))
	back.pressed.connect(_show_ranking.bind(false))


func _show_ranking(open: bool) -> void:
	ranking_root.visible = open
	title_deco.visible = not open
	if not open:
		return
	for child in ranking_rows.get_children():
		child.queue_free()
	if records.is_empty():
		var empty := _label(ranking_rows, "まだ記録がありません", Vector2(290, 300), Vector2(700, 32), 22)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
		return
	var medal := [Color(1.0, 0.85, 0.35), Color(0.85, 0.9, 0.98), Color(1.0, 0.65, 0.4)]
	for i in records.size():
		var entry: Dictionary = records[i]
		var y := 166.0 + float(i) * 40.0
		var color: Color = medal[i] if i < medal.size() else Color(0.92, 0.95, 0.98)
		var cleared_run := bool(entry.get("cleared", false))
		var cells := [
			["%d" % (i + 1), 330.0, 70.0, HORIZONTAL_ALIGNMENT_CENTER, color],
			["%d" % int(entry["score"]), 410.0, 190.0, HORIZONTAL_ALIGNMENT_RIGHT, color],
			["CLEAR" if cleared_run else _format_time(float(entry.get("time", 0.0))), 630.0, 100.0, HORIZONTAL_ALIGNMENT_CENTER,
				Palette.GEM if cleared_run else Color(0.7, 0.75, 0.85)],
			[str(entry.get("date", "")).replace("-", "/"), 750.0, 200.0, HORIZONTAL_ALIGNMENT_LEFT, Color(0.7, 0.8, 0.9)],
		]
		for cell in cells:
			var label := _label(ranking_rows, cell[0], Vector2(cell[1], y), Vector2(cell[2], 34), 22 if i < 3 else 20)
			label.horizontal_alignment = cell[3]
			label.add_theme_color_override("font_color", cell[4])


func _refresh_upgrade_buttons() -> void:
	for i in choice_buttons.size():
		var button := choice_buttons[i]
		button.visible = i < level_choices.size()
		if not button.visible:
			continue
		var icon = button.get_meta("icon")
		var heading: Label = button.get_meta("heading")
		var detail: Label = button.get_meta("detail")
		var id := level_choices[i]
		var parts := id.split(":")
		var is_weapon := parts[0] == "weapon"
		var data: Dictionary = Balance.WEAPONS[parts[1]] if is_weapon else Balance.PASSIVES[parts[1]]
		var stage := item_level(id)
		icon.configure(parts[1], is_weapon, stage + 1, true)
		if is_weapon and stage == Balance.MAX_STAGE:
			heading.text = "★ %s  スペシャル：%s" % [data["name"], data["special"]]
			detail.text = data["special_desc"]
			heading.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		elif is_weapon and stage + 1 == Balance.MILESTONE_STAGE:
			heading.text = "◆ %s  強化：%s" % [data["name"], data["milestone"]]
			detail.text = data["milestone_desc"]
			heading.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
		elif stage == 0:
			heading.text = "%s   NEW" % data["name"]
			detail.text = data["desc"] if is_weapon else _stats_detail(data, 0, 1)
			heading.add_theme_color_override("font_color", Palette.GEM)
		else:
			heading.text = data["name"]
			# Weapon stat arrays start at Lv1, passive arrays at stage 0.
			var offset := 1 if is_weapon else 0
			detail.text = _stats_detail(data, stage - offset, stage + 1 - offset)
			heading.add_theme_color_override("font_color", Color(0.96, 0.97, 0.98))


# Names only the stats that change between the two indices.
func _stats_detail(data: Dictionary, before_index: int, after_index: int) -> String:
	var parts: Array[String] = []
	for entry: Array in data["stats"]:
		var values: Array = data[entry[0]]
		if values[before_index] != values[after_index]:
			parts.append(entry[1])
	return "・".join(parts)


func _make_icon(parent: Node, pos: Vector2, icon_size: float) -> Control:
	var icon := ItemIconScript.new()
	icon.icon_size = icon_size
	icon.position = pos
	parent.add_child(icon)
	return icon


func _update_hud() -> void:
	var current := int(player.hp)
	var maximum := int(player.max_hp)
	hp_label.text = "HP  %d / %d" % [current, maximum]
	level_label.text = "レベル  %d" % level
	var xp_ratio := clampf(float(xp) / float(maxi(1, xp_to_next)), 0.0, 1.0)
	xp_fill.size.x = 180.0 * xp_ratio
	xp_fill.visible = xp_ratio > 0.0
	var remaining := _remaining()
	time_label.text = _format_time(ceilf(remaining))
	if remaining <= Balance.LAST_SPURT and phase != Phase.GAME_OVER:
		var pulse := 0.75 + 0.25 * sin(elapsed * 8.0)
		time_label.add_theme_color_override("font_color", Color(1.0, 0.35 * pulse + 0.1, 0.35 * pulse + 0.1))
	else:
		time_label.add_theme_color_override("font_color", Color(0.96, 0.97, 0.98))
	score_label.text = "%d" % score
	var weapon_ids := weapons.keys()
	for i in hud_weapon_icons.size():
		if i < weapon_ids.size():
			hud_weapon_icons[i].configure(weapon_ids[i], true, weapons[weapon_ids[i]].level)
		else:
			hud_weapon_icons[i].configure("", true, 0)
	var passive_ids := passives.keys()
	for i in hud_passive_icons.size():
		if i < passive_ids.size():
			hud_passive_icons[i].configure(passive_ids[i], false, int(passives[passive_ids[i]]))
		else:
			hud_passive_icons[i].configure("", false, 0)
	var ratio := 0.0 if maximum <= 0 else clampf(float(current) / float(maximum), 0.0, 1.0)
	hp_fill.size.x = 240.0 * ratio
	hp_fill.visible = ratio > 0.0
	hp_fill.modulate = Color.WHITE if ratio > 0.3 else Color(1.0, 1.8, 0.5)


func _format_time(t: float) -> String:
	var total := maxi(0, int(t))
	return "%d:%02d" % [total / 60, total % 60]


func _make_font() -> Font:
	var preferred := ["Yu Gothic UI", "Yu Gothic", "Meiryo UI", "Meiryo", "MS Gothic", "Segoe UI"]
	var font := SystemFont.new()
	for font_name in preferred:
		var path := OS.get_system_font_path(font_name)
		if path != "":
			font.font_names = PackedStringArray([font_name])
			return font
	return font


func _label(parent: Node, text: String, pos: Vector2, size: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", ui_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.96, 0.97, 0.98))
	parent.add_child(label)
	return label


func _overlay() -> ColorRect:
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.01, 0.04, 0.85)
	overlay.position = Vector2.ZERO
	overlay.size = get_viewport_rect().size
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	return overlay


func _panel(pos: Vector2, size: Vector2) -> Panel:
	var panel := Panel.new()
	panel.position = pos
	panel.size = size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = UI_PANEL
	style.border_color = UI_ACCENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(22)
	# A corner detail of 1 turns the rounded corners into straight chamfers.
	style.corner_detail = 1
	style.shadow_color = Color(UI_ACCENT.r, UI_ACCENT.g, UI_ACCENT.b, 0.18)
	style.shadow_size = 18
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _slanted_box(fill: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.skew = Vector2(0.35, 0.0)
	return style


func _choice_button(parent: Node, text: String, pos: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.position = pos
	button.size = Vector2(460, 58)
	button.custom_minimum_size = Vector2(460, 58)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", ui_font)
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color(0.95, 0.95, 0.95))
	var normal := _slanted_box(Color(0.06, 0.16, 0.24, 0.95), Color(UI_ACCENT.r, UI_ACCENT.g, UI_ACCENT.b, 0.7), 2)
	normal.skew = Vector2(0.25, 0.0)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.1, 0.32, 0.45, 0.98)
	hover.border_color = UI_ACCENT
	hover.shadow_color = Color(UI_ACCENT.r, UI_ACCENT.g, UI_ACCENT.b, 0.35)
	hover.shadow_size = 10
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.2, 0.55, 0.7)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	parent.add_child(button)
	return button
