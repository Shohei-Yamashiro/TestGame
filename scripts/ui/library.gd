extends CanvasLayer

# Reference screen: every weapon and passive with its description and per-level numbers.
signal closed

const Balance := preload("res://scripts/balance.gd")
const ItemIconScript := preload("res://scripts/item_icon.gd")

const TILE_SIZE := Vector2(64, 72)
const TILE_STEP := Vector2(72, 80)
const TILES_PER_ROW := 5
const BOOST_SIZE := 34.0
const BOOST_STEP := 40.0
const LABEL_COLOR := Color(0.6, 0.75, 0.85)
const VALUE_COLOR := Color(0.96, 0.97, 0.98)

@export var tile_style: StyleBox
@export var tile_hover_style: StyleBox
@export var tile_selected_style: StyleBox

@onready var _weapon_tiles: Control = $Root/WeaponTiles
@onready var _passive_tiles: Control = $Root/PassiveTiles
@onready var _icon = $Root/Detail/Icon
@onready var _name: Label = $Root/Detail/Name
@onready var _kind: Label = $Root/Detail/Kind
@onready var _desc: Label = $Root/Detail/Desc
@onready var _table: GridContainer = $Root/Detail/Table
@onready var _milestone: Label = $Root/Detail/Milestone
@onready var _special: Label = $Root/Detail/Special
@onready var _boost_caption: Label = $Root/Detail/BoostCaption
@onready var _boosts: Control = $Root/Detail/Boosts

var _group := ButtonGroup.new()
var _tiles: Array[Button] = []
var selected := ""


func _ready() -> void:
	$Root/Back.pressed.connect(close)
	_add_tiles(_weapon_tiles, Balance.WEAPON_ORDER, true)
	_add_tiles(_passive_tiles, Balance.PASSIVE_ORDER, false)


func _add_tiles(parent: Control, ids: Array, is_weapon: bool) -> void:
	for i in ids.size():
		var tile := Button.new()
		tile.toggle_mode = true
		tile.button_group = _group
		tile.focus_mode = Control.FOCUS_NONE
		tile.position = Vector2(i % TILES_PER_ROW, i / TILES_PER_ROW) * TILE_STEP
		tile.size = TILE_SIZE
		tile.custom_minimum_size = TILE_SIZE
		tile.add_theme_stylebox_override("normal", tile_style)
		tile.add_theme_stylebox_override("hover", tile_hover_style)
		tile.add_theme_stylebox_override("pressed", tile_selected_style)
		tile.add_theme_stylebox_override("hover_pressed", tile_selected_style)
		var icon := ItemIconScript.new()
		icon.icon_size = 44.0
		icon.position = Vector2(10, 6)
		tile.add_child(icon)
		icon.configure(ids[i], is_weapon, 0)
		tile.pressed.connect(show_item.bind(ids[i], is_weapon))
		tile.set_meta("item", ids[i])
		parent.add_child(tile)
		_tiles.append(tile)


func open() -> void:
	visible = true
	show_item(Balance.WEAPON_ORDER[0], true)


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func show_item(id: String, is_weapon: bool) -> void:
	selected = id
	for tile in _tiles:
		tile.set_pressed_no_signal(tile.get_meta("item") == id)
	var data: Dictionary = Balance.WEAPONS[id] if is_weapon else Balance.PASSIVES[id]
	_icon.configure(id, is_weapon, Balance.SPECIAL_STAGE if is_weapon else Balance.MAX_STAGE)
	_name.text = data["name"]
	_kind.text = "武器" if is_weapon else "パッシブ"
	var effects: Array[String] = []
	for entry: Array in data["stats"]:
		effects.append(entry[1])
	_desc.text = data["desc"] if is_weapon else "・".join(effects)
	_fill_table(data, is_weapon)
	_fill_boosts(Balance.WEAPON_PASSIVES[id] if is_weapon else [])
	_milestone.visible = is_weapon
	_special.visible = is_weapon
	if is_weapon:
		_milestone.text = "Lv%d 強化：%s\n%s" % [Balance.MILESTONE_STAGE, data["milestone"], data["milestone_desc"]]
		_special.text = "Lv%d スペシャル：%s\n%s" % [Balance.SPECIAL_STAGE, data["special"], data["special_desc"]]


# Badges for the passives that strengthen this weapon, right-aligned; clicking one opens that passive.
func _fill_boosts(passive_ids: Array) -> void:
	for child in _boosts.get_children():
		_boosts.remove_child(child)
		child.queue_free()
	_boost_caption.visible = not passive_ids.is_empty()
	var right := _boosts.size.x
	for i in passive_ids.size():
		var pid: String = passive_ids[i]
		var data: Dictionary = Balance.PASSIVES[pid]
		var badge := Button.new()
		badge.flat = true
		badge.focus_mode = Control.FOCUS_NONE
		badge.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		badge.tooltip_text = "%s：%s" % [data["name"], data["stats"][0][1]]
		badge.size = Vector2(BOOST_SIZE, BOOST_SIZE)
		badge.position = Vector2(right - BOOST_SIZE - float(passive_ids.size() - 1 - i) * BOOST_STEP, 0)
		var icon := ItemIconScript.new()
		icon.icon_size = BOOST_SIZE
		icon.show_pips = false
		badge.add_child(icon)
		icon.configure(pid, false, 0)
		badge.pressed.connect(show_item.bind(pid, false))
		badge.set_meta("item", pid)
		_boosts.add_child(badge)


func _fill_table(data: Dictionary, is_weapon: bool) -> void:
	for child in _table.get_children():
		_table.remove_child(child)
		child.queue_free()
	_cell("", LABEL_COLOR, 170.0)
	for lv in range(1, Balance.MAX_STAGE + 1):
		_cell("Lv%d" % lv, LABEL_COLOR, 96.0, HORIZONTAL_ALIGNMENT_RIGHT)
	for entry: Array in data["stats"]:
		var key: String = entry[0]
		var values: Array = data[key]
		_cell(entry[2], LABEL_COLOR, 170.0)
		# Weapon arrays start at Lv1; passive arrays carry the untaken value at index 0.
		var offset := 0 if is_weapon else 1
		for lv in Balance.MAX_STAGE:
			_cell(format_value(key, is_weapon, float(values[lv + offset])), VALUE_COLOR, 96.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _cell(text: String, color: Color, width: float, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 30)
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", color)
	_table.add_child(label)


static func format_value(key: String, is_weapon: bool, value: float) -> String:
	match key:
		"interval":
			return "%.2f秒" % value
		"life":
			return "%.1f秒" % value
		"drain":
			return "%d%%" % roundi(value * 100.0)
		"max":
			return "%d個" % roundi(value)
		"armor":
			return "-%d%%" % roundi(value * 100.0)
		"regen":
			return "%.1f" % value
		"cooldown", "area", "xp", "knock":
			return "×%.2f" % value
		"damage":
			return ("%d" % roundi(value)) if is_weapon else ("×%.2f" % value)
	return "%d" % roundi(value)
