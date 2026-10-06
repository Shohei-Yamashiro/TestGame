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
