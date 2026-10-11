extends SceneTree

# Writes THIRD-PARTY-NOTICES.txt, the licence file shipped next to the game's executable.
# Rerun after upgrading Godot or adding fonts or other third-party assets; a unit test flags a stale file.
# Usage: godot --headless --path <project> -s res://tools/licenses/generate_notices.gd
const Licenses := preload("res://scripts/licenses.gd")


func _initialize() -> void:
	var file := FileAccess.open(Licenses.NOTICE_PATH, FileAccess.WRITE)
	file.store_string(Licenses.notice_text())
	file.close()
	print("NOTICES ", ProjectSettings.globalize_path(Licenses.NOTICE_PATH))
	quit()
