extends Node2D

const Palette := preload("res://scripts/palette.gd")
const Balance := preload("res://scripts/balance.gd")
const PlayerScript := preload("res://scripts/player.gd")

var id := ""
var level := 1
var player: PlayerScript
var game: Node
var fx: Node


func setup(weapon_id: String, owner_player: PlayerScript) -> void:
	id = weapon_id
	player = owner_player


func _ready() -> void:
	game = get_tree().get_first_node_in_group("game")
	fx = get_tree().get_first_node_in_group("fx")


func is_special() -> bool:
	return level >= Balance.SPECIAL_STAGE


func is_milestone() -> bool:
	return level >= Balance.MILESTONE_STAGE


func stat(key: String) -> Variant:
	var values: Array = Balance.WEAPONS[id][key]
	return values[clampi(level, 1, Balance.MAX_STAGE) - 1]


func damage_of(base: Variant) -> int:
	return maxi(1, int(round(float(base) * float(player.damage_mult))))


func cooldown_of(base: Variant) -> float:
	return float(base) * float(player.cooldown_mult)


func area_of(base: Variant) -> float:
	return float(base) * float(player.area_mult)


func world() -> Node2D:
	return player.world


func nearest_enemy(max_dist: float = INF) -> Node2D:
	var best: Node2D = null
	var best_dist := max_dist * max_dist
	var origin := player.global_position
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node2D
		var dist := origin.distance_squared_to(enemy.global_position)
		if dist < best_dist:
			best_dist = dist
			best = enemy
	return best


func enemies_in_circle(at: Vector2, radius: float) -> Array:
	var result: Array = []
	for node in game.query_enemies(at, radius + 20.0):
		if not is_instance_valid(node) or not node.alive:
			continue
		var reach: float = radius + float(node.radius)
		if at.distance_squared_to(node.global_position) <= reach * reach:
			result.append(node)
	return result
