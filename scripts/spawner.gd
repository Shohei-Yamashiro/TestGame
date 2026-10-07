extends RefCounted

# Decides what enters the arena and where: packs from the screen edge, closing rings,
# and stragglers pulled back in ahead of the player.
const Balance := preload("res://scripts/balance.gd")
const EnemyScript := preload("res://scripts/enemy.gd")

const LEASH := 850.0
const EDGE_MARGIN := 40.0
# Directions around the player are split into sectors; most packs and every straggler enter where the horde is thinnest.
const SECTORS := 8
const PACK_SPARSE := 0.7
# Packs of enemies with a special behaviour stay small so they never arrive as a wall.
const BEHAVIOR_PACK_MAX := 3

# Untyped: the game script preloads this one, so a typed reference would be circular.
var game
var trickle_cd := 0.6
var ring_cd := 0.4


func _init(owner_game) -> void:
	game = owner_game


func update(delta: float) -> void:
	var spurt := Balance.LAST_SPURT_SPAWN if game._remaining() <= Balance.LAST_SPURT else 1.0
	trickle_cd -= delta
	if trickle_cd <= 0.0:
		trickle_cd = Balance.trickle_interval(game.elapsed) * spurt
		spawn_pack()
	ring_cd -= delta
	if ring_cd <= 0.0:
		ring_cd = Balance.ring_interval(game.elapsed) * spurt
		spawn_ring()


func spawn_enemy(kind: String, at: Vector2) -> void:
	if game._enemy_count() >= Balance.ENEMY_CAP:
		return
	if Balance.ENEMY_KINDS[kind].get("behavior", "") == "shoot" and game.get_tree().get_nodes_in_group("shooters").size() >= Balance.SHOOTER_MAX:
		kind = "penta"
	var enemy := EnemyScript.new()
	enemy.setup(kind, game.elapsed)
	enemy.died.connect(game._on_enemy_died)
	game.world.add_child(enemy)
	enemy.global_position = at


# A small clump entering from one point on the screen edge, usually on the side with the fewest enemies.
func spawn_pack() -> void:
	var origin := sparse_edge_position(sector_counts()) if randf() < PACK_SPARSE else edge_spawn_position()
	var kind := Balance.pick_enemy_kind(game.elapsed)
	var count := Balance.trickle_pack(game.elapsed)
	if Balance.ENEMY_KINDS[kind].has("behavior"):
		count = mini(count, BEHAVIOR_PACK_MAX)
	for i in count:
		spawn_enemy(kind, origin + Vector2(randf_range(-28, 28), randf_range(-28, 28)))


# A full ring just outside the screen so enemies close in from every direction.
func spawn_ring() -> void:
	var count := Balance.ring_count(game.elapsed)
	var center: Vector2 = game.camera.get_screen_center_position()
	var radius: float = game.get_viewport_rect().size.length() * 0.5 + 50.0
	var offset := randf() * TAU
	for i in count:
		var angle := offset + TAU * float(i) / float(count)
		var jitter := Vector2(randf_range(-20, 20), randf_range(-20, 20))
		spawn_enemy(Balance.pick_enemy_kind(game.elapsed, false), center + Vector2.from_angle(angle) * radius + jitter)


# Stragglers reappear on the thinnest edge, so outrunning the horde only closes the gap it left.
func leash_enemies() -> void:
	var origin: Vector2 = game.player.global_position
	var far: Array[Node2D] = []
	for node in game.get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node2D
		if enemy != null and enemy.global_position.distance_squared_to(origin) > LEASH * LEASH:
			far.append(enemy)
	if far.is_empty():
		return
	var counts := sector_counts()
	for enemy in far:
		enemy.global_position = sparse_edge_position(counts)


# Enemies within the leash per direction sector around the player.
func sector_counts() -> Array[int]:
	var counts: Array[int] = []
	counts.resize(SECTORS)
	counts.fill(0)
	var origin: Vector2 = game.player.global_position
	for node in game.get_tree().get_nodes_in_group("enemies"):
		var offset: Vector2 = (node as Node2D).global_position - origin
		if offset.length_squared() <= LEASH * LEASH:
			counts[sector_of(offset)] += 1
	return counts


static func sector_of(offset: Vector2) -> int:
	return posmod(int(floor(offset.angle() / TAU * SECTORS)), SECTORS)


# Picks one of the emptiest sectors and counts the arrival there, so a batch spreads across the gaps.
func sparse_edge_position(counts: Array[int]) -> Vector2:
	var fewest := counts[0]
	for c in counts:
		fewest = mini(fewest, c)
	var options: Array[int] = []
	for i in SECTORS:
		if counts[i] == fewest:
			options.append(i)
	var sector: int = options.pick_random()
	counts[sector] += 1
	var angle := (float(sector) + randf()) * TAU / SECTORS
	return edge_from(game.player.global_position, Vector2.from_angle(angle))


func edge_spawn_position() -> Vector2:
	var view: Rect2 = game.camera.view_rect()
	match randi() % 4:
		0:
			return Vector2(randf_range(view.position.x, view.end.x), view.position.y - EDGE_MARGIN)
		1:
			return Vector2(view.end.x + EDGE_MARGIN, randf_range(view.position.y, view.end.y))
		2:
			return Vector2(randf_range(view.position.x, view.end.x), view.end.y + EDGE_MARGIN)
		_:
			return Vector2(view.position.x - EDGE_MARGIN, randf_range(view.position.y, view.end.y))


func edge_position_toward(dir: Vector2, spread := 0.9) -> Vector2:
	if dir.length_squared() < 1.0:
		return edge_spawn_position()
	var center: Vector2 = game.camera.view_rect().get_center()
	return edge_from(center, dir.normalized().rotated(randf_range(-spread, spread)))


# Where a ray from a point inside the view leaves the screen, just past the margin.
func edge_from(origin: Vector2, ray: Vector2) -> Vector2:
	var view: Rect2 = game.camera.view_rect().grow(EDGE_MARGIN)
	var t := INF
	if absf(ray.x) > 0.001:
		t = minf(t, ((view.end.x if ray.x > 0.0 else view.position.x) - origin.x) / ray.x)
	if absf(ray.y) > 0.001:
		t = minf(t, ((view.end.y if ray.y > 0.0 else view.position.y) - origin.y) / ray.y)
	return origin + ray * maxf(t, 0.0)
