extends RefCounted

# Top runs, best first, kept in user://save.cfg.
const SAVE_PATH := "user://save.cfg"
const MAX_RECORDS := 10
# Where saves lived while the project was called "TestGame" (relative to OS.get_data_dir()).
const LEGACY_PATH := "Godot/app_userdata/TestGame/save.cfg"

# Automated runs turn this off (or pass "nosave") so they never touch the player's record.
static var persist := true

# Each entry is {score, date, cleared, time}.
var records: Array = []
var best := 0
var path := SAVE_PATH
var legacy_path := OS.get_data_dir().path_join(LEGACY_PATH)


func load_saved() -> void:
	if OS.get_cmdline_user_args().has("nosave"):
		persist = false
	if not persist:
		return
	# Copied rather than moved, so the old file stays as a backup.
	if not FileAccess.file_exists(path) and FileAccess.file_exists(legacy_path):
		DirAccess.copy_absolute(legacy_path, ProjectSettings.globalize_path(path))
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	records = cfg.get_value("score", "records", [])
	var legacy := int(cfg.get_value("score", "best", 0))
	if records.is_empty() and legacy > 0:
		records = [{"score": legacy, "date": "", "cleared": false, "time": 0.0}]
	if not records.is_empty():
		best = int(records[0]["score"])


func save() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("score", "best", best)
	cfg.set_value("score", "records", records)
	cfg.save(path)


# Inserts a run into the ranking and returns its 0-based rank, or -1 if it missed the list.
func record(score: int, cleared: bool, time: float) -> int:
	var rank := records.size()
	for i in records.size():
		if score > int(records[i]["score"]):
			rank = i
			break
	if rank >= MAX_RECORDS:
		return -1
	var date := Time.get_datetime_string_from_system(false, true).substr(0, 16)
	records.insert(rank, {"score": score, "date": date, "cleared": cleared, "time": time})
	records.resize(mini(records.size(), MAX_RECORDS))
	best = int(records[0]["score"])
	save()
	return rank
