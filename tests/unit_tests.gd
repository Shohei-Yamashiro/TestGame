extends SceneTree

# Logic regression tests: data tables, art rules, ranking and gem merging.
# Every method named test_* runs; a failed check is reported and the process exits non-zero.
# Usage: godot --headless --path <project> -s res://tests/unit_tests.gd
const Balance := preload("res://scripts/balance.gd")
const Palette := preload("res://scripts/palette.gd")
const GameScript := preload("res://scripts/game.gd")
const GemScript := preload("res://scripts/gem.gd")

var _current := ""
var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
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
	GameScript.persist_scores = false
	var game = GameScript.new()
	for value in [300, 100, 200]:
		game.score = value
		game._record_score()
	check(_scores(game) == [300, 200, 100], "ranking is not sorted best first: %s" % [_scores(game)])
	check(game.best_score == 300, "best_score does not follow the top record")
	for i in GameScript.MAX_RECORDS:
		game.score = 1000 + i
		game._record_score()
	check(game.records.size() == GameScript.MAX_RECORDS, "ranking is not capped at %d" % GameScript.MAX_RECORDS)
	game.score = 1
	check(game._record_score() == -1, "a score below the list should not rank")
	game.score = 2000
	check(game._record_score() == 0, "a new best should rank first")
	game.free()


func test_ranking_tie_keeps_older_first() -> void:
	GameScript.persist_scores = false
	var game = GameScript.new()
	game.score = 500
	game._record_score()
	game.score = 500
	check(game._record_score() == 1, "an equal score should rank below the existing one")
	game.free()


func _scores(game) -> Array:
	var result := []
	for record in game.records:
		result.append(int(record["score"]))
	return result


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
