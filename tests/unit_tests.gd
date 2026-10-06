extends SceneTree

# Logic regression tests: data tables, art rules, ranking, camera, spawning and gem merging.
# Every method named test_* runs; a failed check is reported and the process exits non-zero.
# Usage: godot --headless --path <project> -s res://tests/unit_tests.gd
const Balance := preload("res://scripts/balance.gd")
const Palette := preload("res://scripts/palette.gd")
const GameScript := preload("res://scripts/game.gd")
const GemScript := preload("res://scripts/gem.gd")
const ScoreStore := preload("res://scripts/score_store.gd")
const CameraRig := preload("res://scripts/camera_rig.gd")
const ItemIconScript := preload("res://scripts/item_icon.gd")

var _current := ""
var _failures: Array[String] = []
var _checks := 0


# Runs on the first frame rather than in _initialize: only then is the tree live,
# so nodes added by the tests get their _ready.
func _process(_delta: float) -> bool:
	_run_all()
	return false


func _run_all() -> void:
	seed(1)
	var tests := 0
	for method in get_method_list():
		var name: String = method["name"]
		if name.begins_with("test_"):
			_current = name
			tests += 1
			call(name)
	for failure in _failures:
		printerr("UNIT FAIL: " + failure)
	print("UNIT %s tests=%d checks=%d failed=%d" % [
		"OK" if _failures.is_empty() else "FAIL", tests, _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append("%s: %s" % [_current, message])


# --- Data tables ---

func test_weapon_table() -> void:
	check(Balance.WEAPON_ORDER.has(Balance.STARTING_WEAPON), "starting weapon is not in WEAPON_ORDER")
	for id in Balance.WEAPON_ORDER:
		check(Balance.WEAPONS.has(id), "%s missing from WEAPONS" % id)
		check(GameScript.WEAPON_SCRIPTS.has(id), "%s missing from WEAPON_SCRIPTS" % id)
		if not Balance.WEAPONS.has(id):
			continue
		var entry: Dictionary = Balance.WEAPONS[id]
		for key in ["name", "desc", "milestone", "milestone_desc", "special", "special_desc"]:
			check(str(entry.get(key, "")) != "", "%s has no %s" % [id, key])
		for pair in entry["stats"]:
			var stat: String = pair[0]
			var values: Array = entry.get(stat, [])
			check(values.size() == Balance.MAX_STAGE, "%s.%s needs %d values" % [id, stat, Balance.MAX_STAGE])
			for i in range(1, values.size()):
				# Upgrades never make a weapon worse: intervals shrink, everything else grows.
				if stat == "interval":
					check(values[i] <= values[i - 1], "%s.interval rises at Lv%d" % [id, i + 1])
				else:
					check(values[i] >= values[i - 1], "%s.%s drops at Lv%d" % [id, stat, i + 1])


func test_passive_table() -> void:
	for id in Balance.PASSIVE_ORDER:
		check(Balance.PASSIVES.has(id), "%s missing from PASSIVES" % id)
		var entry: Dictionary = Balance.PASSIVES.get(id, {})
		for pair in entry.get("stats", []):
			var values: Array = entry.get(pair[0], [])
			check(values.size() == Balance.MAX_STAGE + 1, "%s.%s needs %d values" % [id, pair[0], Balance.MAX_STAGE + 1])
		check(str(entry.get("name", "")) != "", "%s has no name" % id)
		check(ItemIconScript.COLORS.has(id), "%s has no icon color" % id)


func test_stats_have_library_labels() -> void:
	var tables := []
	for id in Balance.WEAPON_ORDER:
		tables.append([id, Balance.WEAPONS[id]])
	for id in Balance.PASSIVE_ORDER:
		tables.append([id, Balance.PASSIVES[id]])
	for pair in tables:
		for entry in pair[1]["stats"]:
			check(entry.size() == 3 and str(entry[2]) != "", "%s.%s needs a short library label" % [pair[0], entry[0]])


func test_library_lists_every_item() -> void:
	var library = (load("res://scenes/ui/library.tscn") as PackedScene).instantiate()
	root.add_child(library)
	library.open()
	check(library.visible, "library should open")
	check(library._tiles.size() == Balance.WEAPON_ORDER.size() + Balance.PASSIVE_ORDER.size(), "one tile per weapon and passive")
	for id in Balance.WEAPON_ORDER:
		library.show_item(id, true)
		var rows: int = 1 + Balance.WEAPONS[id]["stats"].size()
		check(library._table.get_child_count() == rows * (Balance.MAX_STAGE + 1), "%s table has the wrong cell count" % id)
		check(library._special.visible, "%s should show its special" % id)
	for id in Balance.PASSIVE_ORDER:
		library.show_item(id, false)
		check(not library._special.visible, "%s is a passive and has no special" % id)
		var pressed = library._group.get_pressed_button()
		check(pressed != null and pressed.get_meta("item") == id, "the %s tile should be highlighted" % id)
	library.close()
	check(not library.visible, "library should close")
	library.free()


func test_library_value_format() -> void:
	var Library := load("res://scripts/ui/library.gd")
	check(Library.format_value("interval", true, 0.3) == "0.30秒", "interval format")
	check(Library.format_value("armor", false, 0.06) == "-6%", "armor format")
	check(Library.format_value("damage", true, 25.0) == "25", "weapon damage format")
	check(Library.format_value("damage", false, 1.2) == "×1.20", "passive damage format")
	check(Library.format_value("radius", true, 110.0) == "110", "plain number format")


func test_enemy_table() -> void:
	for kind in Balance.ENEMY_KINDS:
		var entry: Dictionary = Balance.ENEMY_KINDS[kind]
		for key in ["sides", "radius", "hp", "speed", "damage", "xp", "score", "color"]:
			check(entry.has(key), "%s has no %s" % [kind, key])
		check(int(entry.get("color", -1)) >= 0 and int(entry.get("color", -1)) < Palette.ENEMIES.size(),
			"%s color index out of range" % kind)
		check(str(entry.get("behavior", "chase")) in ["chase", "dash", "shoot"], "%s has an unknown behavior" % kind)


func test_xp_curve_grows() -> void:
	for level in range(1, 80):
		check(Balance.xp_to_next(level + 1) > Balance.xp_to_next(level), "xp_to_next does not grow at Lv%d" % level)


# --- Art rules: hostile = warm and odd-sided, friendly = cool and even-sided ---

func test_art_rule_enemies() -> void:
	for kind in Balance.ENEMY_KINDS:
		check(int(Balance.ENEMY_KINDS[kind]["sides"]) % 2 == 1, "%s must have an odd number of sides" % kind)
	for color in Palette.ENEMIES:
		check(color.r > color.b, "enemy color %s is not warm" % color)
	check(Palette.ENEMY_SHOT.r > Palette.ENEMY_SHOT.b, "enemy shot color is not warm")


func test_art_rule_friendly() -> void:
	for look in GemScript.LOOKS:
		check(int(look["sides"]) % 2 == 0, "gem look with %d sides must be even" % look["sides"])
	var friendly := [Palette.PLAYER, Palette.BULLET, Palette.BULLET_PIERCE, Palette.GEM, Palette.HOMING,
		Palette.ORBIT, Palette.NOVA, Palette.LASER, Palette.WINGS, Palette.ELECTRIC]
	friendly.append_array(Palette.GEM_TIERS)
	friendly.append_array(ItemIconScript.COLORS.values())
	for color in friendly:
		check(color.b > color.r, "friendly color %s is not cool" % color)


# --- Spawning ---

func test_spawn_kinds() -> void:
	var seen := {}
	for i in 4000:
		var t := fmod(float(i) * 0.37, Balance.TIME_LIMIT)
		var kind := Balance.pick_enemy_kind(t)
		seen[kind] = true
		check(Balance.ENEMY_KINDS.has(kind), "unknown kind %s" % kind)
	for kind in Balance.ENEMY_KINDS:
		check(seen.has(kind), "%s never spawns within a round" % kind)


func test_spawn_opening_is_triangles() -> void:
	for i in 500:
		check(Balance.pick_enemy_kind(0.0) == "tri", "something other than tri spawns at t=0")


func test_rings_skip_special_behaviors() -> void:
	for i in 3000:
		var kind := Balance.pick_enemy_kind(fmod(float(i) * 0.37, Balance.TIME_LIMIT), false)
		check(not Balance.ENEMY_KINDS[kind].has("behavior"), "ring spawned %s" % kind)


# Kind weights are consumed in order, so once they pass 1.0 the later kinds silently lose share.
func test_spawn_weights_leave_room_for_triangles() -> void:
	var tri := 0
	for i in 4000:
		if Balance.pick_enemy_kind(Balance.TIME_LIMIT) == "tri":
			tri += 1
	check(tri > 0, "kind weights sum to 1 or more by the end of a round")


# --- Ranking ---

func test_ranking_order_and_cap() -> void:
	ScoreStore.persist = false
	var store := ScoreStore.new()
	for value in [300, 100, 200]:
		store.record(value, false, 60.0)
	check(_scores(store) == [300, 200, 100], "ranking is not sorted best first: %s" % [_scores(store)])
	check(store.best == 300, "best does not follow the top record")
	for i in ScoreStore.MAX_RECORDS:
		store.record(1000 + i, true, 180.0)
	check(store.records.size() == ScoreStore.MAX_RECORDS, "ranking is not capped at %d" % ScoreStore.MAX_RECORDS)
	check(store.record(1, false, 10.0) == -1, "a score below the list should not rank")
	check(store.record(2000, true, 180.0) == 0, "a new best should rank first")


func test_ranking_tie_keeps_older_first() -> void:
	ScoreStore.persist = false
	var store := ScoreStore.new()
	store.record(500, false, 60.0)
	check(store.record(500, true, 180.0) == 1, "an equal score should rank below the existing one")


func test_ranking_saves_and_loads() -> void:
	var path := "user://test_save.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	ScoreStore.persist = true
	var store := ScoreStore.new()
	store.path = path
	store.record(4200, true, 180.0)
	store.record(1300, false, 95.5)
	var loaded := ScoreStore.new()
	loaded.path = path
	loaded.load_saved()
	ScoreStore.persist = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(_scores(loaded) == [4200, 1300], "saved ranking did not load back: %s" % [_scores(loaded)])
	check(loaded.best == 4200, "loaded best is wrong")
	check(bool(loaded.records[0]["cleared"]) and is_equal_approx(float(loaded.records[1]["time"]), 95.5),
		"record fields did not survive the round trip")


func test_ranking_migrates_legacy_best() -> void:
	var path := "user://test_legacy.cfg"
	var cfg := ConfigFile.new()
	cfg.set_value("score", "best", 777)
	cfg.save(path)
	ScoreStore.persist = true
	var store := ScoreStore.new()
	store.path = path
	store.load_saved()
	ScoreStore.persist = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(_scores(store) == [777], "a save with only a best score should become a single record")


func _scores(store) -> Array:
	var result := []
	for record in store.records:
		result.append(int(record["score"]))
	return result


# --- Camera ---

func test_camera_trauma_caps_and_decays() -> void:
	var camera := CameraRig.new()
	root.add_child(camera)
	camera.add_trauma(0.7)
	camera.add_trauma(0.7)
	check(is_equal_approx(camera.trauma, 1.0), "trauma should cap at 1.0")
	for i in 120:
		camera.update_shake(1.0 / 60.0)
	check(camera.trauma == 0.0 and camera.offset == Vector2.ZERO, "shake should settle to zero")
	camera.free()


func test_camera_leads_and_holds_when_stopped() -> void:
	var camera := CameraRig.new()
	var target := Node2D.new()
	root.add_child(camera)
	root.add_child(target)
	for i in 120:
		camera.follow(target, Vector2(200, 0), 200.0, 1.0 / 60.0)
	check(camera.look_offset.x > CameraRig.LOOK_AHEAD.x * 0.9, "camera should lead toward the direction of travel")
	var lead := camera.look_offset
	for i in 120:
		camera.follow(target, Vector2.ZERO, 200.0, 1.0 / 60.0)
	# Drifting back to centre on its own reads as the ship backing up.
	check(camera.look_offset.distance_to(lead) < 2.0, "camera should hold its lead while the player stands still")
	camera.free()
	target.free()


# --- Spawning (with a live game) ---

func _new_game():
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	game._start_game()
	game.elapsed = 120.0
	return game


func test_spawner_caps_shooters() -> void:
	var game = _new_game()
	for i in Balance.SHOOTER_MAX + 3:
		game.spawner.spawn_enemy("shooter", Vector2(500, float(i) * 30.0))
	var shooters: int = game.get_tree().get_nodes_in_group("shooters").size()
	var pentas := 0
	for enemy in game.get_tree().get_nodes_in_group("enemies"):
		if enemy.kind == "penta":
			pentas += 1
	check(shooters == Balance.SHOOTER_MAX, "shooters should stop at %d, got %d" % [Balance.SHOOTER_MAX, shooters])
	check(pentas == 3, "extra shooters should become pentas, got %d" % pentas)
	game.free()


func test_spawner_respects_enemy_cap() -> void:
	var game = _new_game()
	for i in Balance.ENEMY_CAP + 20:
		game.spawner.spawn_enemy("tri", Vector2(600, float(i)))
	check(game._enemy_count() == Balance.ENEMY_CAP, "enemy count should stop at the cap, got %d" % game._enemy_count())
	game.free()


# --- New weapons (with a live game) ---

func _sturdy_enemy(game, at: Vector2):
	game.spawner.spawn_enemy("tri", at)
	var enemies: Array = game.get_tree().get_nodes_in_group("enemies")
	var enemy = enemies[enemies.size() - 1]
	enemy.hp = 100000
	return enemy


func test_chain_hits_up_to_its_target_count() -> void:
	var game = _new_game()
	var first = null
	for i in 5:
		var enemy = _sturdy_enemy(game, Vector2(200 + i * 100, 0))
		if i == 0:
			first = enemy
	game._separate_enemies()
	game._add_weapon("chain")
	var chain = game.weapons["chain"]
	check(chain.strike(first) == 3, "Lv1 chain should hit 3 enemies")
	chain.level = Balance.MILESTONE_STAGE
	check(chain.max_targets() == int(chain.stat("jumps")) + Balance.CHAIN_MILESTONE_JUMPS, "milestone adds jumps")
	check(chain.strike(first) == 5, "milestone chain should reach all 5 enemies in range")
	game.free()


func test_chain_stops_at_jump_range() -> void:
	var game = _new_game()
	var first = _sturdy_enemy(game, Vector2(200, 0))
	_sturdy_enemy(game, Vector2(200 + Balance.CHAIN_JUMP * 2.0, 0))
	game._separate_enemies()
	game._add_weapon("chain")
	check(game.weapons["chain"].strike(first) == 1, "an enemy beyond the jump range must not be reached")
	game.free()


func test_tesseract_blocks_enemies_and_shots() -> void:
	var game = _new_game()
	game._add_weapon("tesseract")
	var tesseract = game.weapons["tesseract"]
	tesseract._cd = 999.0
	game.player.facing = Vector2.RIGHT
	var origin: Vector2 = game.player.global_position
	var enemy = _sturdy_enemy(game, origin + Vector2(Balance.TESSERACT_RANGE * 0.5, 0))
	var start_hp: int = enemy.hp
	tesseract.launch()
	for i in int(Balance.TESSERACT_SLIDE_TIME * 60.0) + 1:
		game._separate_enemies()
		tesseract._physics_process(1.0 / 60.0)
	var at: Vector2 = tesseract.cubes[0]["pos"]
	check(not tesseract.is_sliding(tesseract.cubes[0]), "the cube should be at rest after its slide")
	check(at.distance_to(origin + Vector2(Balance.TESSERACT_RANGE, 0)) < 1.0, "the cube should rest at its full range")
	check(enemy.hp < start_hp, "a sliding cube should hurt the enemy it pushes")
	check(enemy.global_position.x > origin.x + Balance.TESSERACT_RANGE * 0.5 + 20.0, "the enemy should be shoved forward")
	var resting = _sturdy_enemy(game, at + Vector2(0, 5))
	var shot = load("res://scripts/enemy_shot.gd").new()
	game.world.add_child(shot)
	shot.global_position = at + Vector2(4, 0)
	var resting_hp: int = resting.hp
	game._separate_enemies()
	tesseract._physics_process(1.0 / 60.0)
	var gap: float = resting.global_position.distance_to(at)
	check(gap >= tesseract.radius() + resting.radius - 0.01, "a resting cube should still push enemies out, gap %.1f" % gap)
	check(resting.hp == resting_hp, "a resting cube should not hurt without the special")
	check(shot.is_queued_for_deletion(), "an enemy shot inside the cube should be cancelled")
	tesseract.cubes[0]["age"] = 999.0
	tesseract._physics_process(1.0 / 60.0)
	check(tesseract.cubes.is_empty(), "the cube should vanish after its life")
	game.free()


func test_tesseract_special_hurts_at_rest() -> void:
	var game = _new_game()
	game._add_weapon("tesseract")
	var tesseract = game.weapons["tesseract"]
	tesseract._cd = 999.0
	tesseract.level = Balance.SPECIAL_STAGE
	game.player.facing = Vector2.RIGHT
	tesseract.launch()
	check(tesseract.cubes.size() == 2, "the milestone should launch two cubes")
	var dirs: Array = [tesseract.cubes[0]["dir"], tesseract.cubes[1]["dir"]]
	check(absf((dirs[0] as Vector2).angle_to(dirs[1])) < PI / 2.0, "the two cubes should fan out at an acute angle")
	for cube in tesseract.cubes:
		cube["age"] = Balance.TESSERACT_SLIDE_TIME + 0.1
	tesseract._physics_process(1.0 / 60.0)
	var at: Vector2 = tesseract.cubes[0]["pos"]
	var enemy = _sturdy_enemy(game, at + Vector2(0, -5).rotated((tesseract.cubes[0]["dir"] as Vector2).angle()))
	var start_hp: int = enemy.hp
	game._separate_enemies()
	tesseract._physics_process(1.0 / 60.0)
	check(enemy.hp < start_hp, "with the special a resting cube should hurt enemies it touches")
	game.free()


func test_mine_detonates_and_caps() -> void:
	var game = _new_game()
	game._add_weapon("mine")
	var mine = game.weapons["mine"]
	mine._cd = 999.0
	for i in Balance.MINE_MAX + 3:
		mine.place(Vector2(400 + i * 50, 300))
	check(mine.mines.size() == Balance.MINE_MAX, "mines should cap at %d" % Balance.MINE_MAX)
	mine.mines.clear()
	mine.place(Vector2(300, 0))
	var enemy = _sturdy_enemy(game, Vector2(300, 0))
	var start_hp: int = enemy.hp
	game._separate_enemies()
	mine._physics_process(Balance.MINE_ARM_TIME + 0.01)
	check(mine.mines.is_empty(), "an armed mine touched by an enemy should detonate")
	check(enemy.hp < start_hp, "the blast should damage the enemy")
	game.free()


func test_drain_costs_hp_and_heals() -> void:
	var game = _new_game()
	game._add_weapon("drain")
	var drain = game.weapons["drain"]
	var p = game.player
	p.hp = 60
	var enemy = _sturdy_enemy(game, p.global_position + Vector2(120, 0))
	var start_hp: int = enemy.hp
	game._separate_enemies()
	drain._cd = 0.0
	drain._physics_process(1.0 / 60.0)
	check(drain.links.size() == 1, "drain should link to the nearest enemy")
	check(p.hp == 60 - Balance.DRAIN_COST, "linking should cost %d hp, hp %d" % [Balance.DRAIN_COST, p.hp])
	check(enemy.hp < start_hp, "the link should hurt right away")
	for i in int(Balance.DRAIN_TIME * 60.0):
		game._separate_enemies()
		drain._physics_process(1.0 / 60.0)
	check(drain.links.is_empty(), "the link should end after its time")
	var dealt: int = start_hp - enemy.hp
	var expected := int(float(dealt) * float(drain.stat("drain")))
	check(absi(p.hp - (60 - Balance.DRAIN_COST + expected)) <= 1, "drain should heal about %d of %d dealt, hp %d" % [expected, dealt, p.hp])
	check(expected > 0, "the test should drain enough to heal")
	game.free()


func test_drain_holds_fire_at_low_hp() -> void:
	var game = _new_game()
	game._add_weapon("drain")
	var drain = game.weapons["drain"]
	game.player.hp = Balance.DRAIN_MIN_HP
	_sturdy_enemy(game, game.player.global_position + Vector2(100, 0))
	game._separate_enemies()
	drain._cd = 0.0
	drain._physics_process(1.0 / 60.0)
	check(drain.links.is_empty(), "drain must not fire at or below the hp floor")
	check(game.player.hp == Balance.DRAIN_MIN_HP, "no hp should be spent")
	game.free()


func test_drain_special_jumps_on_kill() -> void:
	var game = _new_game()
	game._add_weapon("drain")
	var drain = game.weapons["drain"]
	drain.level = Balance.SPECIAL_STAGE
	var p = game.player
	p.hp = 60
	var origin: Vector2 = p.global_position
	# The second enemy is out of linking range from the player but within jump range of the first.
	game.spawner.spawn_enemy("tri", origin + Vector2(200, 0))
	var weak = game.get_tree().get_nodes_in_group("enemies")[0]
	weak.hp = 1
	var next = _sturdy_enemy(game, origin + Vector2(330, 0))
	game._separate_enemies()
	drain._cd = 0.0
	drain._physics_process(1.0 / 60.0)
	check(not weak.alive, "the weak enemy should die on the first tick")
	check(drain.links.size() == 1 and drain.links[0]["target"] == next, "the link should jump to the nearby enemy")
	check(p.hp > 60 - Balance.DRAIN_COST, "a kill should heal, hp %d" % p.hp)
	game.free()


# --- Passives (with a live game) ---

func test_passives_reach_the_player() -> void:
	var game = _new_game()
	for id in Balance.PASSIVE_ORDER:
		game.passives[id] = Balance.MAX_STAGE
	game._apply_stats()
	var p = game.player
	check(is_equal_approx(p.magnet_radius, Balance.PASSIVES["magnet"]["magnet"][Balance.MAX_STAGE]), "magnet not applied")
	check(is_equal_approx(p.move_speed, Balance.PASSIVES["move"]["speed"][Balance.MAX_STAGE]), "move speed not applied")
	check(is_equal_approx(p.area_mult, Balance.PASSIVES["area"]["area"][Balance.MAX_STAGE]), "area_mult not applied")
	check(is_equal_approx(p.knock_mult, Balance.PASSIVES["knock"]["knock"][Balance.MAX_STAGE]), "knock_mult not applied")
	check(is_equal_approx(p.xp_mult, Balance.PASSIVES["growth"]["xp"][Balance.MAX_STAGE]), "xp_mult not applied")
	check(is_equal_approx(p.armor, Balance.PASSIVES["armor"]["armor"][Balance.MAX_STAGE]), "armor not applied")
	check(is_equal_approx(p.regen, Balance.PASSIVES["regen"]["regen"][Balance.MAX_STAGE]), "regen not applied")
	check(p.max_hp == Balance.PASSIVES["max_hp"]["max_hp"][Balance.MAX_STAGE], "max_hp not applied")
	game.free()


func test_move_and_magnet_are_separate() -> void:
	var game = _new_game()
	game.passives["move"] = Balance.MAX_STAGE
	game._apply_stats()
	check(is_equal_approx(game.player.magnet_radius, Balance.BASE_MAGNET), "move speed alone must not widen the magnet")
	game.passives.erase("move")
	game.passives["magnet"] = Balance.MAX_STAGE
	game._apply_stats()
	check(is_equal_approx(game.player.move_speed, Balance.PASSIVES["move"]["speed"][0]), "magnet alone must not speed the player up")
	game.free()


func test_max_hp_heals_by_the_increase() -> void:
	var game = _new_game()
	game.player.hp = 60
	game.passives["max_hp"] = 1
	game._apply_stats()
	var gain: int = Balance.PASSIVES["max_hp"]["max_hp"][1] - Balance.PLAYER_MAX_HP
	check(game.player.hp == 60 + gain, "hp should rise by the max_hp gain, got %d" % game.player.hp)
	game._apply_stats()
	check(game.player.hp == 60 + gain, "re-applying the same stage must not heal again")
	game.free()


func test_armor_reduces_damage_but_not_below_one() -> void:
	var game = _new_game()
	var p = game.player
	p.armor = 0.3
	p.hp = 100
	p.take_hit(10)
	check(p.hp == 93, "armor 0.3 should turn 10 damage into 7, hp=%d" % p.hp)
	p._hurt_cd = 0.0
	p.take_hit(1)
	check(p.hp == 92, "a hit always deals at least 1, hp=%d" % p.hp)
	game.free()


func test_regen_banks_fractions() -> void:
	var game = _new_game()
	var p = game.player
	p.regen = 0.5
	p.hp = 50
	for i in 60:
		p._regenerate(1.0 / 60.0)
	check(p.hp == 50, "0.5 HP/s should not heal a whole point in 1 s, hp=%d" % p.hp)
	for i in 66:
		p._regenerate(1.0 / 60.0)
	check(p.hp == 51, "0.5 HP/s should heal 1 point in about 2 s, hp=%d" % p.hp)
	p.hp = p.max_hp
	p._regenerate(10.0)
	check(p.hp == p.max_hp, "regen must not exceed max hp")
	game.free()


func test_growth_banks_fractional_xp() -> void:
	var game = _new_game()
	game.xp_to_next = 1000
	game.player.xp_mult = 1.5
	game._on_gem_collected(1)
	check(game.xp == 1, "1 xp at x1.5 gives 1 now, got %d" % game.xp)
	game._on_gem_collected(1)
	check(game.xp == 3, "the banked half should pay out on the next gem, got %d" % game.xp)
	game.free()


func test_knock_scales_enemy_push() -> void:
	var game = _new_game()
	game.spawner.spawn_enemy("tri", Vector2(300, 0))
	var enemy = game.get_tree().get_nodes_in_group("enemies")[0]
	enemy.hp = 1000
	game.player.knock_mult = 2.0
	var before: Vector2 = enemy.global_position
	enemy.take_damage(1, Vector2.RIGHT, 10.0)
	check(is_equal_approx(enemy.global_position.x - before.x, 20.0), "knock x2 should push 20, got %.2f" % (enemy.global_position.x - before.x))
	game.free()


func test_area_scales_weapon_reach() -> void:
	var game = _new_game()
	game._add_weapon("nova")
	game._add_weapon("laser")
	game.player.area_mult = 1.5
	var nova = game.weapons["nova"]
	nova._emit_wave()
	var wave: Dictionary = nova._waves[nova._waves.size() - 1]
	check(is_equal_approx(float(wave["radius"]), float(nova.stat("radius")) * 1.5), "nova radius should scale with area")
	var laser = game.weapons["laser"]
	check(is_equal_approx(laser.area_of(laser.stat("width")), float(laser.stat("width")) * 1.5), "laser width should scale with area")
	game.free()


func test_spawner_edges_are_off_screen() -> void:
	var game = _new_game()
	var view: Rect2 = game.camera.view_rect()
	for i in 200:
		var at: Vector2 = game.spawner.edge_spawn_position()
		check(not view.has_point(at), "edge spawn %s landed on screen" % at)
		var ahead: Vector2 = game.spawner.edge_position_toward(Vector2.from_angle(float(i)) * 100.0)
		check(not view.grow(-1.0).has_point(ahead), "leash position %s landed on screen" % ahead)
	game.free()


# --- Gems ---

func test_gem_merge_sums_value_and_tier() -> void:
	var a = GemScript.new()
	var b = GemScript.new()
	a.value = 1
	b.value = 2
	root.add_child(a)
	root.add_child(b)
	a.global_position = Vector2.ZERO
	b.global_position = Vector2(30, 0)
	a.absorb(b)
	check(a.value == 3, "merged value should be 3, got %d" % a.value)
	check(a.tier == 1, "value 3 should be tier 1, got %d" % a.tier)
	check(a.global_position.is_equal_approx(Vector2(20, 0)), "merged position should be value-weighted, got %s" % a.global_position)
	check(b.is_queued_for_deletion(), "absorbed gem should be freed")
	a.free()


func test_gem_tiers_are_ascending() -> void:
	check(Balance.GEM_TIERS.size() == GemScript.LOOKS.size(), "GEM_TIERS and LOOKS sizes differ")
	check(Balance.GEM_TIERS.size() == Palette.GEM_TIERS.size(), "GEM_TIERS and palette sizes differ")
	for i in range(1, Balance.GEM_TIERS.size()):
		check(Balance.GEM_TIERS[i] > Balance.GEM_TIERS[i - 1], "GEM_TIERS not ascending at %d" % i)
