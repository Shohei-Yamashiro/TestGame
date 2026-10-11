extends CanvasLayer

signal start_requested
signal quit_requested
signal ranking_requested(open: bool)
signal library_requested
signal licenses_requested

const Palette := preload("res://scripts/palette.gd")
const ScoreStore := preload("res://scripts/score_store.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")

const MEDAL_COLORS: Array[Color] = [Color(1.0, 0.85, 0.35), Color(0.85, 0.9, 0.98), Color(1.0, 0.65, 0.4)]

@onready var _hi_score: Label = $Root/HiScore
@onready var _ranking: Control = $Root/Ranking
@onready var _rows: Control = $Root/Ranking/Rows


func _ready() -> void:
	$Root/Start.pressed.connect(start_requested.emit)
	$Root/RankingButton.pressed.connect(ranking_requested.emit.bind(true))
	$Root/LibraryButton.pressed.connect(library_requested.emit)
	$Root/LicensesButton.pressed.connect(licenses_requested.emit)
	$Root/Quit.pressed.connect(quit_requested.emit)
	$Root/Ranking/Back.pressed.connect(ranking_requested.emit.bind(false))
	$Root/Ranking/Heading.text = "HIGH SCORE  TOP %d" % ScoreStore.MAX_RECORDS


func is_ranking_open() -> bool:
	return _ranking.visible


func set_best(best: int) -> void:
	_hi_score.visible = best > 0
	_hi_score.text = "HI-SCORE  %d" % best


func show_ranking(open: bool, records: Array) -> void:
	_ranking.visible = open
	if not open:
		return
	for child in _rows.get_children():
		child.queue_free()
	if records.is_empty():
		var empty := _cell("まだ記録がありません", Vector2(290, 300), Vector2(700, 32), 22, Color(0.6, 0.7, 0.8))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return
	for i in records.size():
		var entry: Dictionary = records[i]
		var y := 166.0 + float(i) * 40.0
		var color: Color = MEDAL_COLORS[i] if i < MEDAL_COLORS.size() else Color(0.92, 0.95, 0.98)
		var cleared_run := bool(entry.get("cleared", false))
		var cells := [
			["%d" % (i + 1), 330.0, 70.0, HORIZONTAL_ALIGNMENT_CENTER, color],
			["%d" % int(entry["score"]), 410.0, 190.0, HORIZONTAL_ALIGNMENT_RIGHT, color],
			["CLEAR" if cleared_run else UiText.format_time(float(entry.get("time", 0.0))), 630.0, 100.0, HORIZONTAL_ALIGNMENT_CENTER,
				Palette.GEM if cleared_run else Color(0.7, 0.75, 0.85)],
			[str(entry.get("date", "")).replace("-", "/"), 750.0, 200.0, HORIZONTAL_ALIGNMENT_LEFT, Color(0.7, 0.8, 0.9)],
		]
		for cell in cells:
			var label := _cell(cell[0], Vector2(cell[1], y), Vector2(cell[2], 34), 22 if i < 3 else 20, cell[4])
			label.horizontal_alignment = cell[3]


func _cell(text: String, pos: Vector2, size: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	_rows.add_child(label)
	return label
