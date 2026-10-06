extends CanvasLayer

signal restart_requested
signal title_requested

const Palette := preload("res://scripts/palette.gd")

@onready var _title: Label = $Root/Title
@onready var _score: Label = $Root/Score
@onready var _best: Label = $Root/Best
@onready var _stats: Label = $Root/Stats


func _ready() -> void:
	$Root/Restart.pressed.connect(restart_requested.emit)
	$Root/ToTitle.pressed.connect(title_requested.emit)


# rank is the 0-based ranking slot of this run, or -1 when it did not rank in.
func show_result(survived: bool, score: int, rank: int, best: int, lines: Array[String]) -> void:
	_title.text = "タイムアップ！" if survived else "ゲームオーバー"
	_title.add_theme_color_override("font_color", Palette.GEM if survived else Palette.HURT)
	_stats.text = "\n".join(lines)
	_score.text = "%d" % score
	if rank == 0:
		_best.text = "NEW RECORD!"
	elif rank > 0:
		_best.text = "ランクイン  %d位      BEST  %d" % [rank + 1, best]
	else:
		_best.text = "BEST  %d" % best
	_best.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35) if rank >= 0 else Color(0.75, 0.88, 0.95))
