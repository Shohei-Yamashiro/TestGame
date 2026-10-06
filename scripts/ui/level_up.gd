extends CanvasLayer

signal chosen(index: int)

const Palette := preload("res://scripts/palette.gd")
const Balance := preload("res://scripts/balance.gd")

@onready var _buttons: Array[Button] = [$Root/Choice0, $Root/Choice1, $Root/Choice2]


func _ready() -> void:
	for i in _buttons.size():
		_buttons[i].pressed.connect(chosen.emit.bind(i))


# choices are "weapon:<id>" / "passive:<id>"; level_of returns the owned stage of a choice.
func show_choices(choices: Array[String], level_of: Callable) -> void:
	for i in _buttons.size():
		var button := _buttons[i]
		button.visible = i < choices.size()
		if not button.visible:
			continue
		var icon = button.get_node("Icon")
		var heading: Label = button.get_node("Heading")
		var detail: Label = button.get_node("Detail")
		var id := choices[i]
		var parts := id.split(":")
		var is_weapon := parts[0] == "weapon"
		var data: Dictionary = Balance.WEAPONS[parts[1]] if is_weapon else Balance.PASSIVES[parts[1]]
		var stage: int = level_of.call(id)
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
			detail.text = data["desc"] if is_weapon else stats_detail(data, 0, 1)
			heading.add_theme_color_override("font_color", Palette.GEM)
		else:
			heading.text = data["name"]
			# Weapon stat arrays start at Lv1, passive arrays at stage 0.
			var offset := 1 if is_weapon else 0
			detail.text = stats_detail(data, stage - offset, stage + 1 - offset)
			heading.add_theme_color_override("font_color", Color(0.96, 0.97, 0.98))
	visible = true


# Names only the stats that change between the two indices.
static func stats_detail(data: Dictionary, before_index: int, after_index: int) -> String:
	var parts: Array[String] = []
	for entry: Array in data["stats"]:
		var values: Array = data[entry[0]]
		if values[before_index] != values[after_index]:
			parts.append(entry[1])
	return "・".join(parts)
