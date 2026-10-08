extends SceneTree

# Logic regression tests: data tables, art rules, ranking, camera, spawning and gem merging.
# Every method named test_* runs; a failed check is reported and the process exits non-zero.
# Usage: godot --headless --path <project> -s res://tests/unit_tests.gd
const Balance := preload("res://scripts/balance.gd")
const Library := preload("res://scripts/ui/library.gd")
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


# The library's passive rows must mirror what each weapon script actually scales.
func test_weapon_passive_rows_match_the_weapon_scripts() -> void:
	var consts := (load("res://scripts/balance.gd") as GDScript).get_script_constant_map()
	var call := RegEx.create_from_string("(area_of|cooldown_of)\\((.*)")
	var named := RegEx.create_from_string("Balance\\.([A-Z_]+)")
	var stat_key := RegEx.create_from_string("stat\\(\"([a-z_]+)\"\\)")
	for id: String in Balance.WEAPON_ORDER:
		check(Balance.WEAPON_EXTRAS.has(id), "%s needs its fixed passive rows listed" % id)
		var listed := {}
		for entry: Array in Balance.WEAPON_EXTRAS.get(id, []):
			check(entry.size() == 5, "%s row %s should have 5 fields" % [id, entry[1]])
			check(Balance.PASSIVES.has(entry[0]), "%s lists unknown passive %s" % [id, entry[0]])
			for source in [entry[2], entry[3]]:
				if source is String and source != "":
					check(consts.has(source), "%s names unknown constant %s" % [id, source])
					listed[source] = entry[0]
		for key: String in (Balance.WEAPON_LV6.get(id, {}) as Dictionary):
			var change: Variant = Balance.WEAPON_LV6[id][key]
			check(Balance.WEAPONS[id].has(key), "%s Lv6 override names unknown stat %s" % [id, key])
			if change is String and not (change as String).begins_with("+"):
				check(consts.has(change), "%s Lv6 override names unknown constant %s" % [id, change])
				listed[change] = Balance.STAT_PASSIVES.get(key, "")
		var script := load("res://scripts/weapons/%s.gd" % id) as GDScript
		var used := {}
		for line in script.source_code.split("\n"):
			if line.strip_edges().begins_with("func "):
				continue
			# Speeds divide by the rate multiplier directly rather than going through cooldown_of.
			var passive := ""
			var scaled := ""
			var m := call.search(line)
			if m != null:
				passive = "area" if m.get_string(1) == "area_of" else "rate"
				scaled = m.get_string(2)
			elif line.contains("cooldown_mult"):
				passive = "rate"
				scaled = line
			if passive == "":
				continue
			for c in named.search_all(scaled):
				var name := c.get_string(1)
				used[name] = true
				check(listed.get(name, "") == passive, "%s scales %s by %s but the library does not list it" % [id, name, passive])
			for k in stat_key.search_all(scaled):
				check(Balance.STAT_PASSIVES.get(k.get_string(1), "") == passive, "%s: stat %s should be marked as %s" % [id, k.get_string(1), passive])
		for name in listed:
			check(used.has(name), "%s lists %s but never scales it" % [id, name])
		var knock_rows := (Balance.WEAPON_EXTRAS.get(id, []) as Array).filter(func(e): return e[0] == "knock")
		var push: float = float(script.get_script_constant_map().get("KNOCK", Balance.KNOCKBACK))
		if push <= 0.0:
			check(knock_rows.is_empty(), "%s never pushes, so it should not list knockback" % id)
		else:
			check(knock_rows.size() == 1 and is_equal_approx(float(knock_rows[0][2]), push), "%s knockback row should read %.0f" % [id, push])
	var orbit_knock: Array = Balance.WEAPON_EXTRAS["orbit"].filter(func(e): return e[0] == "knock")[0]
	var orbit_script := load("res://scripts/weapons/orbit.gd") as GDScript
	check(is_equal_approx(float(orbit_knock[3]), float(orbit_script.get_script_constant_map()["SPECIAL_KNOCKBACK"])), "orbit special knockback row is stale")
	var wings_script := load("res://scripts/weapons/wings.gd") as GDScript
	check(int(Balance.WEAPON_LV6["wings"]["feathers"]) == (wings_script.get_script_constant_map()["WING_ANGLES"] as Array).size(), "wings Lv6 feather count is stale")


func test_library_marks_rows_with_passives() -> void:
	var library = (load("res://scenes/ui/library.tscn") as PackedScene).instantiate()
	root.add_child(library)
	library.open()
	library.show_item("orbit", true)
	check(library._table.columns == Balance.SPECIAL_STAGE + 1, "weapon tables should run through the special stage")
	var damage_row: Control = library._table.get_child(library._table.columns)
	var badge: Button = damage_row.get_child(0)
	badge.pressed.emit()
	check(library.selected == "attack", "clicking the damage row's badge should open the attack passive")
	check(library._table.columns == Balance.MAX_STAGE + 1, "passive tables stop at their last level")
	check(Library.lv6_value("orbit", "count", 4.0) == 5.0, "the special's extra blade should show in Lv6")
	check(Library.lv6_value("wings", "reach", 190.0) == Balance.WINGS_SPECIAL_REACH, "deployed wings reach should show in Lv6")
	check(Library.lv6_value("blaster", "damage", 25.0) == 25.0, "unchanged stats carry Lv5 into Lv6")
	var radius := Library.extra_texts(["area", "", "ORBIT_RADIUS", "ORBIT_SPECIAL_RADIUS", ""])
	check(radius[0] == "78" and radius[Balance.MAX_STAGE] == "112", "fixed rows should switch to the special value in Lv6: %s" % [radius])
	var blast := Library.extra_texts(["area", "", "", "MISSILE_BLAST_RADIUS", ""])
	check(blast[0] == "—" and blast[Balance.MAX_STAGE] == "64", "special-only rows should be blank before Lv6: %s" % [blast])
	var push := Library.extra_texts(["knock", "", 14.0, 26.0, ""])
	check(push[0] == "中" and push[Balance.MAX_STAGE] == "強", "knockback should read as grades: %s" % [push])
	check(Library.extra_texts(["knock", "", 6.0, null, ""])[Balance.MAX_STAGE] == "弱", "a null Lv6 keeps the earlier value")
	check(Library.extra_texts(["rate", "", "ORBIT_HIT_COOLDOWN", null, ""])[0] == "0.50秒", "rate rows should read as seconds")
	check(Library.extra_texts(["rate", "", "ORBIT_SPEED", null, "turns"])[0] == "%.2f" % (Balance.ORBIT_SPEED / TAU), "spin rows should read as turns per second")
	library.free()


func test_library_lists_every_item() -> void:
	var library = (load("res://scenes/ui/library.tscn") as PackedScene).instantiate()
	root.add_child(library)
	library.open()
	check(library.visible, "library should open")
	check(library._tiles.size() == Balance.WEAPON_ORDER.size() + Balance.PASSIVE_ORDER.size(), "one tile per weapon and passive")
	for id in Balance.WEAPON_ORDER:
		library.show_item(id, true)
		var rows: int = 1 + Balance.WEAPONS[id]["stats"].size() + Balance.WEAPON_EXTRAS[id].size()
		check(library._table.get_child_count() == rows * (Balance.SPECIAL_STAGE + 1), "%s table has the wrong cell count" % id)
		check(library._special.is_visible_in_tree(), "%s should show its special" % id)
	for id in Balance.PASSIVE_ORDER:
		library.show_item(id, false)
		var rows: int = 1 + Balance.PASSIVES[id]["stats"].size()
		check(library._table.get_child_count() == rows * (Balance.MAX_STAGE + 1), "%s table has the wrong cell count" % id)
		check(not library._special.is_visible_in_tree(), "%s is a passive and has no special" % id)
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
		Palette.ORBIT, Palette.NOVA, Palette.LASER, Palette.WINGS, Palette.ELECTRIC, Palette.BURN]
	friendly.append_array(Palette.GEM_TIERS)
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


func test_spawner_caps_every_shooting_kind() -> void:
	var game = _new_game()
	var kinds := ["turret", "shooter", "battery"]
	for i in Balance.SHOOTER_MAX + 3:
		game.spawner.spawn_enemy(kinds[i % kinds.size()], Vector2(500, float(i) * 30.0))
	var shooters: int = game.get_tree().get_nodes_in_group("shooters").size()
	check(shooters == Balance.SHOOTER_MAX, "turrets and batteries should share the shooter cap, got %d" % shooters)
	game.free()


func test_enemy_kinds_have_light_and_heavy_variants() -> void:
	for group in [["dart", "dasher", "lancer"], ["turret", "shooter", "battery"]]:
		for i in range(1, group.size()):
			var lighter: Dictionary = Balance.ENEMY_KINDS[group[i - 1]]
			var heavier: Dictionary = Balance.ENEMY_KINDS[group[i]]
			check(float(heavier.hp) > float(lighter.hp), "%s should be tougher than %s" % [group[i], group[i - 1]])
			check(int(heavier.xp) > int(lighter.xp), "%s should be worth more than %s" % [group[i], group[i - 1]])


func test_sparse_edge_fills_the_emptiest_sector() -> void:
	var game = _new_game()
	var center: Vector2 = game.player.global_position
	for i in 20:
		var counts: Array[int] = [5, 5, 5, 0, 5, 5, 5, 5]
		var at: Vector2 = game.spawner.sparse_edge_position(counts)
		check(game.spawner.sector_of(at - center) == 3, "arrival should land in the empty sector, got %d" % game.spawner.sector_of(at - center))
		check(counts[3] == 1, "the chosen sector should count the arrival")
	game.free()


func test_leashed_enemies_return_where_the_horde_is_thin() -> void:
	var game = _new_game()
	var center: Vector2 = game.player.global_position
	for s in 7:
		game.spawner.spawn_enemy("tri", center + Vector2.from_angle((float(s) + 0.5) * TAU / 8.0) * 200.0)
	game.spawner.spawn_enemy("tri", center + Vector2(game.spawner.LEASH + 300.0, 0))
	var enemies: Array = game.get_tree().get_nodes_in_group("enemies")
	var straggler = enemies[enemies.size() - 1]
	game.spawner.leash_enemies()
	var offset: Vector2 = straggler.global_position - center
	check(offset.length() < game.spawner.LEASH, "the straggler should be pulled back within the leash")
	check(game.spawner.sector_of(offset) == 7, "the straggler should reappear in the only empty sector, got %d" % game.spawner.sector_of(offset))
	game.free()


func test_flankers_swing_wide_only_from_afar() -> void:
	var game = _new_game()
	game.player.velocity = Vector2.ZERO
	game.spawner.spawn_enemy("tri", Vector2(900, 0))
	var enemy = game.get_tree().get_nodes_in_group("enemies")[0]
	enemy._flank = Balance.FLANK_ANGLE
	var near: Vector2 = enemy.chase_direction(Vector2(Balance.FLANK_NEAR * 0.5, 0))
	var far: Vector2 = enemy.chase_direction(Vector2(Balance.FLANK_FAR * 2.0, 0))
	check(absf(near.angle()) < 0.01, "close enemies should head straight in, got %.2f" % near.angle())
	check(is_equal_approx(far.angle(), Balance.FLANK_ANGLE), "distant flankers should swing wide, got %.2f" % far.angle())
	game.free()


func test_heal_drops_are_capped_and_heal_on_pickup() -> void:
	var game = _new_game()
	for i in Balance.HEAL_MAX_ON_FIELD + 2:
		game.drop_heal(Vector2(400, float(i) * 50.0))
	var kits: Array = game.get_tree().get_nodes_in_group("heals")
	check(kits.size() == Balance.HEAL_MAX_ON_FIELD, "heal kits on the field should stop at %d, got %d" % [Balance.HEAL_MAX_ON_FIELD, kits.size()])
	game.player.hp = 10
	kits[0].global_position = game.player.global_position
	kits[0]._physics_process(0.016)
	check(game.heals_picked == 1, "walking over a kit should count as a pickup")
	check(game.player.hp == 10 + Balance.HEAL_PICKUP, "a kit should restore %d HP, got %d" % [Balance.HEAL_PICKUP, game.player.hp])
	game.player.hp = game.player.max_hp
	var before: int = game.score
	kits[1].global_position = game.player.global_position
	kits[1]._physics_process(0.016)
	check(game.score == before + Balance.HEAL_SCORE, "a kit at full HP should turn into %d points" % Balance.HEAL_SCORE)
	game.free()


func test_magnet_pulls_heal_kits() -> void:
	var game = _new_game()
	var at: Vector2 = game.player.global_position + Vector2(game.player.magnet_radius * 0.8, 0)
	game.drop_heal(at)
	var kit = game.get_tree().get_nodes_in_group("heals")[0]
	kit._physics_process(0.1)
	check(kit.global_position.x < at.x, "a kit inside the magnet radius should drift toward the player")
	game.free()


func test_heal_kits_stay_until_taken() -> void:
	var game = _new_game()
	game.drop_heal(Vector2(2000, 2000))
	var kit = game.get_tree().get_nodes_in_group("heals")[0]
	kit._physics_process(600.0)
	check(not kit.is_queued_for_deletion(), "an untouched kit should stay like a gem")
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
	var caps: Array = Balance.WEAPONS["mine"]["max"]
	for level in [1, Balance.MAX_STAGE]:
		mine.level = level
		mine.mines.clear()
		for i in 15:
			mine.place(Vector2(400 + i * 50, 300))
		check(mine.mines.size() == int(caps[level - 1]), "at Lv%d mines should cap at %d" % [level, caps[level - 1]])
	check(int(caps[Balance.MAX_STAGE - 1]) > int(caps[0]), "the mine cap should grow with level")
	mine.level = 1
	mine.mines.clear()
	mine.place(Vector2(300, 0))
	var enemy = _sturdy_enemy(game, Vector2(300, 0))
	var start_hp: int = enemy.hp
	game._separate_enemies()
	mine._physics_process(Balance.MINE_ARM_TIME + 0.01)
	check(mine.mines.is_empty(), "an armed mine touched by an enemy should detonate")
	check(enemy.hp < start_hp, "the blast should damage the enemy")
	game.free()


func test_mine_trigger_grows_with_area() -> void:
	var game = _new_game()
	game._add_weapon("mine")
	var mine = game.weapons["mine"]
	mine._cd = 999.0
	# The search counts the enemy's own radius, so stand it clear of that too.
	var gap := Balance.MINE_TRIGGER + 20.0
	mine.place(Vector2(300, 0))
	_sturdy_enemy(game, Vector2(300 + gap, 0))
	game._separate_enemies()
	mine._physics_process(Balance.MINE_ARM_TIME + 0.01)
	check(mine.mines.size() == 1, "an enemy just outside the trigger range should not set the mine off")
	game.passives["area"] = Balance.MAX_STAGE
	game._apply_stats()
	check(mine.trigger_radius() > Balance.MINE_TRIGGER, "the area passive should widen the trigger range")
	mine._physics_process(1.0 / 60.0)
	check(mine.mines.is_empty(), "with a wider trigger the same enemy should set the mine off")
	game.free()


func test_mine_milestone_sets_enemies_burning() -> void:
	var game = _new_game()
	game._add_weapon("mine")
	var mine = game.weapons["mine"]
	mine.level = Balance.MILESTONE_STAGE - 1
	var cold = _sturdy_enemy(game, Vector2(300, 0))
	var enemy = _sturdy_enemy(game, Vector2(600, 0))
	game._separate_enemies()
	mine.detonate(Vector2(300, 0))
	check(not cold.is_burning(), "before the milestone the blast should not set enemies alight")
	mine.level = Balance.MILESTONE_STAGE
	mine.detonate(Vector2(600, 0))
	check(enemy.is_burning(), "after the milestone the blast should set enemies alight")
	var hp_after_blast: int = enemy.hp
	for i in int(Balance.MINE_BURN_TIME * 60.0) + 10:
		enemy._physics_process(1.0 / 60.0)
	check(enemy.hp < hp_after_blast, "a burning enemy should keep taking damage")
	check(not enemy.is_burning(), "the fire should go out after its duration")
	game.free()


func test_mine_special_spreads_fire_on_death() -> void:
	var game = _new_game()
	var first = _sturdy_enemy(game, Vector2(300, 0))
	var near = _sturdy_enemy(game, Vector2(340, 0))
	first.apply_burn(1, Balance.MINE_BURN_TIME)
	first.take_damage(first.hp, Vector2.ZERO, 0.0)
	check(not near.is_burning(), "without the special the fire should not spread")
	var second = _sturdy_enemy(game, Vector2(600, 0))
	var neighbour = _sturdy_enemy(game, Vector2(640, 0))
	var far = _sturdy_enemy(game, Vector2(600 + Balance.MINE_SPREAD_RADIUS * 3.0, 0))
	second.apply_burn(1, Balance.MINE_BURN_TIME, Balance.MINE_SPREAD_RADIUS)
	second.take_damage(second.hp, Vector2.ZERO, 0.0)
	check(neighbour.is_burning(), "with the special a burning enemy's death should set its neighbour alight")
	check(not far.is_burning(), "the fire should not jump beyond the spread radius")
	game.free()


# Lines a label needs for text, from its own font, size and width (wrapping can only add a little, hence the margin).
func _lines_needed(label: Label, text: String) -> int:
	var font := label.get_theme_font("font")
	var size := label.get_theme_font_size("font_size")
	var inner := label.size.x - label.get_theme_stylebox("normal").get_minimum_size().x
	var lines := 0
	for part in text.split("\n"):
		var width := font.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		lines += 1 if width <= inner else ceili(width / (inner * 0.95))
	return lines


func test_level_up_texts_fit_their_cards() -> void:
	var layer = (load("res://scenes/ui/level_up.tscn") as PackedScene).instantiate()
	root.add_child(layer)
	var heading: Label = layer.get_node("Root/Choice0/Heading")
	var detail: Label = layer.get_node("Root/Choice0/Detail")
	check(detail.autowrap_mode != TextServer.AUTOWRAP_OFF, "level-up detail should wrap onto a second line")
	var LevelUp = load("res://scripts/ui/level_up.gd")
	var headings: Array[String] = []
	var details: Array[String] = []
	for id in Balance.WEAPON_ORDER:
		var d: Dictionary = Balance.WEAPONS[id]
		headings.append_array(["%s   NEW" % d["name"], "◆ %s  強化：%s" % [d["name"], d["milestone"]], "★ %s  スペシャル：%s" % [d["name"], d["special"]]])
		details.append_array([d["desc"], d["milestone_desc"], d["special_desc"]])
		for i in Balance.MAX_STAGE - 1:
			details.append(LevelUp.stats_detail(d, i, i + 1))
	for id in Balance.PASSIVE_ORDER:
		headings.append("%s   NEW" % Balance.PASSIVES[id]["name"])
		for i in Balance.MAX_STAGE:
			details.append(LevelUp.stats_detail(Balance.PASSIVES[id], i, i + 1))
	for text in headings:
		check(_lines_needed(heading, text) == 1, "level-up heading must fit on one line: %s" % text)
	for text in details:
		check(_lines_needed(detail, text) <= 2, "level-up detail must fit in two lines: %s" % text)
	layer.free()


func test_library_texts_fit_their_boxes() -> void:
	var layer = (load("res://scenes/ui/library.tscn") as PackedScene).instantiate()
	root.add_child(layer)
	var desc: Label = layer.get_node("Root/Detail/Desc")
	var body: VBoxContainer = layer.get_node("Root/Detail/Body")
	var milestone: Label = body.get_node("Notes/Milestone")
	# The two boxes share the body width side by side; the container sets this at runtime.
	milestone.size = Vector2((body.size.x - 10.0) * 0.5, milestone.size.y)
	for id in Balance.WEAPON_ORDER:
		var d: Dictionary = Balance.WEAPONS[id]
		check(_lines_needed(desc, d["desc"]) <= 2, "library description must fit in two lines: %s" % d["desc"])
		for pair in [["強化", d["milestone"], d["milestone_desc"]], ["スペシャル", d["special"], d["special_desc"]]]:
			var text := "Lv6 %s：%s\n%s" % pair
			check(_lines_needed(milestone, text) <= 4, "library %s box must fit in four lines: %s" % [pair[0], pair[2]])
	layer.free()


func test_hud_groups_status_left_and_score_right_of_timer() -> void:
	var hud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	var time_label: Label = hud.get_node("Root/TimeLabel")
	var time_center := time_label.position.x + time_label.size.x * 0.5
	check(is_equal_approx(time_center, 640.0), "the timer should sit at the centre of the screen")
	var status: Control = hud.get_node("Root/Status")
	check(status.position.x + status.BAR_RIGHT + status.BAR_SKEW <= hud.get_node("Root/WeaponIcons").position.x,
		"the status bars must not run into the weapon icons")
	var last_passive: Control = hud.get_node("Root/PassiveIcons").get_children().back()
	var passives_right: float = hud.get_node("Root/PassiveIcons").position.x + last_passive.position.x + last_passive.icon_size
	check(passives_right < time_label.position.x, "the passive icons must stay left of the timer")
	for name in ["ScoreLabel", "KillsLabel"]:
		check(hud.get_node("Root/" + name).position.x > time_label.position.x + time_label.size.x, "%s should sit right of the timer" % name)
	hud.free()


func test_choices_respect_slot_limits() -> void:
	var game = _new_game()
	# The run starts with the blaster, so one weapon slot is already taken.
	for id: String in Balance.WEAPON_ORDER.slice(1, Balance.MAX_WEAPONS - 1):
		game._add_weapon(id)
	for id: String in Balance.PASSIVE_ORDER.slice(0, Balance.MAX_PASSIVES - 1):
		game.passives[id] = 1
	var offered := {}
	for i in 200:
		for choice: String in game._roll_choices():
			offered[choice] = true
	check(offered.has("weapon:" + Balance.WEAPON_ORDER[Balance.MAX_WEAPONS - 1]), "a free weapon slot should offer new weapons")
	check(offered.has("passive:" + Balance.PASSIVE_ORDER[Balance.MAX_PASSIVES - 1]), "a free passive slot should offer new passives")
	game._add_weapon(Balance.WEAPON_ORDER[Balance.MAX_WEAPONS - 1])
	game.passives[Balance.PASSIVE_ORDER[Balance.MAX_PASSIVES - 1]] = 1
	check(game.weapons.size() == Balance.MAX_WEAPONS and game.passives.size() == Balance.MAX_PASSIVES, "slots should now be full")
	for i in 200:
		for choice: String in game._roll_choices():
			var parts := choice.split(":")
			var owned: bool = game.weapons.has(parts[1]) if parts[0] == "weapon" else game.passives.has(parts[1])
			check(owned, "full slots must only offer owned items, got %s" % choice)
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
