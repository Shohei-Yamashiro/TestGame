extends SceneTree

# Loads every script and scene in the project and fails if any of them is broken.
# Usage: godot --headless --path <project> -s res://tests/check_scripts.gd
const ROOTS := ["res://scripts", "res://scenes", "res://tests", "res://tools"]

var failures: Array[String] = []
var checked := 0


func _initialize() -> void:
	for dir in ROOTS:
		_scan(dir)
	for failure in failures:
		printerr("CHECK FAIL: " + failure)
	print("CHECK %s checked=%d failed=%d" % ["OK" if failures.is_empty() else "FAIL", checked, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _scan(dir: String) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(sub))
	for file in DirAccess.get_files_at(dir):
		var path := dir.path_join(file)
		if file.ends_with(".gd"):
			checked += 1
			var script := load(path) as GDScript
			if script == null or not script.can_instantiate():
				failures.append(path)
		elif file.ends_with(".tscn"):
			checked += 1
			var scene := load(path) as PackedScene
			if scene == null or not scene.can_instantiate():
				failures.append(path)
