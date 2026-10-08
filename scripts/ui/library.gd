extends CanvasLayer

# Reference screen: every weapon and passive with its description and per-level numbers.
signal closed

const Balance := preload("res://scripts/balance.gd")
const ItemIconScript := preload("res://scripts/item_icon.gd")

const TILE_SIZE := Vector2(64, 72)
const TILE_STEP := Vector2(72, 80)
const TILES_PER_ROW := 5
const BADGE_SIZE := 22.0
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
@onready var _table: GridContainer = $Root/Detail/Body/Table
@onready var _milestone: Label = $Root/Detail/Body/Milestone
@onready var _special: Label = $Root/Detail/Body/Special
@onready var _extras: GridContainer = $Root/Detail/Body/Extras

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
	_fill_extras(Balance.WEAPON_EXTRAS[id] if is_weapon else [])
	_milestone.visible = is_weapon
	_special.visible = is_weapon
	if is_weapon:
		_milestone.text = "Lv%d 強化：%s\n%s" % [Balance.MILESTONE_STAGE, data["milestone"], data["milestone_desc"]]
		_special.text = "Lv%d スペシャル：%s\n%s" % [Balance.SPECIAL_STAGE, data["special"], data["special_desc"]]


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
		_row_label(entry[2], Balance.STAT_PASSIVES.get(key, "") if is_weapon else "")
		# Weapon arrays start at Lv1; passive arrays carry the untaken value at index 0.
		var offset := 0 if is_weapon else 1
		for lv in Balance.MAX_STAGE:
			_cell(format_value(key, is_weapon, float(values[lv + offset])), VALUE_COLOR, 96.0, HORIZONTAL_ALIGNMENT_RIGHT)


# Row name with the badge of the passive that scales it (blank space keeps the names lined up).
func _row_label(text: String, passive_id: String) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(170, 30)
	row.add_theme_constant_override("separation", 6)
	row.add_child(_badge(passive_id))
	row.add_child(_label(text, LABEL_COLOR, 18))
	_table.add_child(row)


# Numbers outside the level table that a passive still scales, two to a line.
func _fill_extras(rows: Array) -> void:
	for child in _extras.get_children():
		_extras.remove_child(child)
		child.queue_free()
	_extras.visible = not rows.is_empty()
	for entry: Array in rows:
		var cell := HBoxContainer.new()
		cell.custom_minimum_size = Vector2(336, 28)
		cell.add_theme_constant_override("separation", 6)
		cell.add_child(_badge(entry[0]))
		var name_label := _label(entry[1], LABEL_COLOR, 17)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(name_label)
		cell.add_child(_label(extra_text(entry), VALUE_COLOR, 17))
		_extras.add_child(cell)


# A small passive icon; hovering names the passive and clicking opens it. An empty id leaves a gap.
func _badge(passive_id: String) -> Control:
	if passive_id == "":
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(BADGE_SIZE, BADGE_SIZE)
		return gap
	var data: Dictionary = Balance.PASSIVES[passive_id]
	var badge := Button.new()
	badge.flat = true
	badge.focus_mode = Control.FOCUS_NONE
	badge.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	badge.tooltip_text = "%s：%s" % [data["name"], data["stats"][0][1]]
	badge.custom_minimum_size = Vector2(BADGE_SIZE, BADGE_SIZE)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon := ItemIconScript.new()
	icon.icon_size = BADGE_SIZE
	icon.show_pips = false
	badge.add_child(icon)
	icon.configure(passive_id, false, 0)
	badge.pressed.connect(show_item.bind(passive_id, false))
	badge.set_meta("item", passive_id)
	return badge


func _label(text: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


# "78", "Lv6: 215" or "78（Lv6: 112）"; knockback reads as a grade.
static func extra_text(entry: Array) -> String:
	var base: Variant = _extra_number(entry[2])
	var special: Variant = _extra_number(entry[3])
	var base_text := _format_extra(entry[0], base)
	var special_text := _format_extra(entry[0], special)
	if base == null:
		return "Lv%d: %s" % [Balance.SPECIAL_STAGE, special_text]
	if special == null or special_text == base_text:
		return base_text
	return "%s（Lv%d: %s）" % [base_text, Balance.SPECIAL_STAGE, special_text]


# Entries hold either a number or the name of a balance constant; "" and null mean "not at this stage".
static func _extra_number(source: Variant) -> Variant:
	if source == null or (source is String and source == ""):
		return null
	if source is String:
		return float((load("res://scripts/balance.gd") as GDScript).get_script_constant_map()[source])
	return float(source)


static func _format_extra(passive_id: String, value: Variant) -> String:
	if value == null:
		return ""
	match passive_id:
		"knock":
			for grade: Array in Balance.KNOCK_GRADES:
				if float(value) < float(grade[0]):
					return grade[1]
		"rate":
			return "%.2f秒" % float(value)
	return "%d" % roundi(float(value))


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
