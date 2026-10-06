extends CanvasLayer

signal resume_requested
signal title_requested


func _ready() -> void:
	$Root/Resume.pressed.connect(resume_requested.emit)
	$Root/ToTitle.pressed.connect(title_requested.emit)
