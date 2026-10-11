extends CanvasLayer

# Scrollable list of the licence notices (see scripts/licenses.gd), opened from the title screen.
signal closed

const Licenses := preload("res://scripts/licenses.gd")

const HEADING_COLOR := Color(0.35, 0.95, 1.0)
const BODY_COLOR := Color(0.75, 0.82, 0.9)

@onready var _body: RichTextLabel = $Root/Body

var _filled := false


func _ready() -> void:
	$Root/Back.pressed.connect(close)
	var bar := _body.get_v_scroll_bar()
	bar.custom_minimum_size.x = 10.0
	bar.add_theme_stylebox_override("scroll", _bar_style(Color(0.35, 0.95, 1.0, 0.08)))
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(state, _bar_style(Color(0.35, 0.95, 1.0, 0.6 if state == "grabber" else 0.9)))


func _bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(5)
	return style


func open() -> void:
	visible = true
	if not _filled:
		_filled = true
		_fill()
	_body.scroll_to_line(0)


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


# Built on first open: the third-party texts run to about 100 KB.
func _fill() -> void:
	_body.clear()
	for section in Licenses.sections():
		_body.push_font_size(22)
		_body.push_color(HEADING_COLOR)
		_body.add_text(section[0])
		_body.pop()
		_body.pop()
		_body.add_text("\n")
		_body.push_color(BODY_COLOR)
		_body.add_text(section[1])
		_body.pop()
		_body.add_text("\n\n")
