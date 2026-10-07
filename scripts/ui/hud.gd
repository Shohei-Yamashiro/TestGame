extends CanvasLayer

const Balance := preload("res://scripts/balance.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")
const StatusPanel := preload("res://scripts/ui/status_panel.gd")

const TEXT_COLOR := Color(0.96, 0.97, 0.98)

@onready var _status: StatusPanel = $Root/Status
@onready var _time_label: Label = $Root/TimeLabel
@onready var _score_label: Label = $Root/ScoreLabel
@onready var _weapon_icons: Array[Node] = $Root/WeaponIcons.get_children()
@onready var _passive_icons: Array[Node] = $Root/PassiveIcons.get_children()


func refresh(game) -> void:
	var xp_ratio := float(game.xp) / float(maxi(1, game.xp_to_next))
	_status.set_values(game.level, xp_ratio, int(game.player.hp), int(game.player.max_hp), game.elapsed)
	var remaining: float = game._remaining()
	_time_label.text = UiText.format_time(ceilf(remaining))
	if remaining <= Balance.LAST_SPURT and game.phase != game.Phase.GAME_OVER:
		var pulse := 0.75 + 0.25 * sin(game.elapsed * 8.0)
		_time_label.add_theme_color_override("font_color", Color(1.0, 0.35 * pulse + 0.1, 0.35 * pulse + 0.1))
	else:
		_time_label.add_theme_color_override("font_color", TEXT_COLOR)
	_score_label.text = "%d" % game.score
	var weapon_ids: Array = game.weapons.keys()
	for i in _weapon_icons.size():
		if i < weapon_ids.size():
			_weapon_icons[i].configure(weapon_ids[i], true, game.weapons[weapon_ids[i]].level)
		else:
			_weapon_icons[i].configure("", true, 0)
	var passive_ids: Array = game.passives.keys()
	for i in _passive_icons.size():
		if i < passive_ids.size():
			_passive_icons[i].configure(passive_ids[i], false, int(game.passives[passive_ids[i]]))
		else:
			_passive_icons[i].configure("", false, 0)
