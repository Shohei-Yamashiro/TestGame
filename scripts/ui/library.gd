extends CanvasLayer

# Reference screen: every weapon and passive with its description and per-level numbers.
signal closed

const Balance := preload("res://scripts/balance.gd")
const ItemIconScript := preload("res://scripts/item_icon.gd")

const TILE_SIZE := Vector2(64, 72)
const TILE_STEP := Vector2(72, 80)
const TILES_PER_ROW := 5
const BADGE_SIZE := 22.0
const ROW_HEIGHT := 28.0
const NAME_WIDTH := 190.0
const VALUE_WIDTH := 74.0
const STRIPE_COLOR := Color(0.35, 0.95, 1.0, 0.05)
const RULE_COLOR := Color(0.35, 0.95, 1.0, 0.25)
const SPECIAL_TINT := Color(1.0, 0.85, 0.35, 0.08)
const SPECIAL_COLOR := Color(1.0, 0.85, 0.35)
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
@onready var _milestone: Label = $Root/Detail/Body/Notes/Milestone
@onready var _special: Label = $Root/Detail/Body/Notes/Special

var _group := ButtonGroup.new()
var _tiles: Array[Button] = []
var selected := ""


func _ready() -> void:
	$Root/Back.pressed.connect(close)
	_add_tiles(_weapon_tiles, Balance.WEAPON_ORDER, true)
	_add_tiles(_passive_tiles, Balance.PASSIVE_ORDER, false)
	_table.draw.connect(_draw_table_rules)


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
	_fill_table(id, data, is_weapon)
	_milestone.get_parent().visible = is_weapon
	if is_weapon:
		_milestone.text = "Lv%d 強化：%s\n%s" % [Balance.MILESTONE_STAGE, data["milestone"], data["milestone_desc"]]
		_special.text = "Lv%d スペシャル：%s\n%s" % [Balance.SPECIAL_STAGE, data["special"], data["special_desc"]]


# Weapons get Lv1-5 plus the special (Lv6), then the fixed numbers a passive scales; passives get Lv1-5.
func _fill_table(id: String, data: Dictionary, is_weapon: bool) -> void:
	for child in _table.get_children():
		_table.remove_child(child)
		child.queue_free()
	var stages := Balance.SPECIAL_STAGE if is_weapon else Balance.MAX_STAGE
	_table.columns = stages + 1
	_table.add_child(_label("", LABEL_COLOR, 17, NAME_WIDTH))
	for lv in range(1, stages + 1):
		var head := _label("Lv%d" % lv, SPECIAL_COLOR if lv == Balance.SPECIAL_STAGE else LABEL_COLOR, 17, VALUE_WIDTH)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_table.add_child(head)
	for entry: Array in data["stats"]:
		var key: String = entry[0]
		var values: Array = data[key]
		# Weapon arrays start at Lv1; passive arrays carry the untaken value at index 0.
		var offset := 0 if is_weapon else 1
		var texts: Array[String] = []
		for lv in Balance.MAX_STAGE:
			var value := float(values[lv + offset])
			texts.append(format_value(key, true, value) if is_weapon else passive_text(key, value, float(values[0])))
		if is_weapon:
			texts.append(format_value(key, true, lv6_value(id, key, float(values[Balance.MAX_STAGE - 1]))))
		_add_row(entry[2], Balance.STAT_PASSIVES.get(key, "") if is_weapon else "", texts)
	if is_weapon:
		for entry: Array in Balance.WEAPON_EXTRAS[id]:
			_add_row(entry[1], entry[0], extra_texts(entry))
	_table.queue_redraw()


func _add_row(title: String, passive_id: String, texts: Array[String]) -> void:
	var name_cell := HBoxContainer.new()
	name_cell.custom_minimum_size = Vector2(NAME_WIDTH, ROW_HEIGHT)
	name_cell.add_theme_constant_override("separation", 6)
	name_cell.add_child(_badge(passive_id))
	name_cell.add_child(_label(title, LABEL_COLOR, 17))
	_table.add_child(name_cell)
	for text in texts:
		var cell := _label(text, VALUE_COLOR, 17, VALUE_WIDTH)
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_table.add_child(cell)


# Alternate row stripes, a rule under the header, and a gold tint behind the special column.
func _draw_table_rules() -> void:
	var cols := _table.columns
	var rows := _table.get_child_count() / cols
	if rows == 0:
		return
	var width := _table.size.x
	for r in range(1, rows):
		var cell := _table.get_child(r * cols) as Control
		if r % 2 == 0:
			_table.draw_rect(Rect2(0, cell.position.y, width, cell.size.y), STRIPE_COLOR)
	var first_row := _table.get_child(cols) as Control
	_table.draw_line(Vector2(0, first_row.position.y), Vector2(width, first_row.position.y), RULE_COLOR, 1.0)
	if cols == Balance.SPECIAL_STAGE + 1:
		var last := _table.get_child(cols - 1) as Control
		var gap := float(_table.get_theme_constant("h_separation")) * 0.5
		_table.draw_rect(Rect2(last.position.x - gap, 0, last.size.x + gap * 2.0, _table.size.y), SPECIAL_TINT)


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


# Every cell shares one height and centres its text, so names and numbers sit on the same line.
func _label(text: String, color: Color, font_size: int, width := 0.0) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, ROW_HEIGHT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


static func lv6_value(id: String, key: String, lv5: float) -> float:
	var change: Variant = (Balance.WEAPON_LV6.get(id, {}) as Dictionary).get(key)
	if change == null:
		return lv5
	if change is String and (change as String).begins_with("+"):
		return lv5 + float((change as String).substr(1))
	return _constant_or_number(change)


# Lv1-5 then Lv6 for a fixed row: "—" where the number isn't used yet.
static func extra_texts(entry: Array) -> Array[String]:
	var base: Variant = null if entry[2] is String and entry[2] == "" else _constant_or_number(entry[2])
	var special: Variant = base if entry[3] == null else _constant_or_number(entry[3])
	var texts: Array[String] = []
	for lv in Balance.MAX_STAGE:
		texts.append(_format_extra(entry[0], entry[4], base))
	texts.append(_format_extra(entry[0], entry[4], special))
	return texts


# Entries hold either a number or the name of a constant in balance.gd.
static func _constant_or_number(source: Variant) -> float:
	if source is String:
		return float((load("res://scripts/balance.gd") as GDScript).get_script_constant_map()[source])
	return float(source)


static func _format_extra(passive_id: String, format: String, value: Variant) -> String:
	if value == null:
		return "—"
	if format == "turns":
		return "%.2f" % (float(value) / TAU)
	match passive_id:
		"knock":
			for grade: Array in Balance.KNOCK_GRADES:
				if float(value) < float(grade[0]):
					return grade[1]
		"rate":
			return "%.2f" % (1.0 / float(value))
	return "%d" % roundi(float(value))


# Passives read as a multiplier on the untaken value, oriented so every upgrade raises the number
# (armor shows the damage still taken, which falls).
static func passive_text(key: String, value: float, base: float) -> String:
	match key:
		"cooldown":
			return "×%.2f" % (base / value)
		"armor":
			return "×%.2f" % (1.0 - value)
		"regen":
			return "%.1f%%" % (value * 100.0)
	return "×%.2f" % (value / base)


static func format_value(key: String, _is_weapon: bool, value: float) -> String:
	match key:
		"interval":
			return "%.2f" % (1.0 / value)
		"life":
			return "%.1f秒" % value
		"drain":
			return "%d%%" % roundi(value * 100.0)
		"max":
			return "%d個" % roundi(value)
	return "%d" % roundi(value)