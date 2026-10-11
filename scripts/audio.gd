extends Node

# Plays the generated sounds in res://assets/audio (see tools/audio/generate_audio.gd).
# Gameplay code calls the static sfx(), which plays through the Audio node in the tree and is
# a no-op when there is none, so tests that build nodes on their own stay silent.

const SFX_DIR := "res://assets/audio/sfx/"
const BGM_DIR := "res://assets/audio/bgm/"
const MUSIC := ["title", "game"]
const MUSIC_DB := -9.0
const MUSIC_DIM_DB := -10.0
const SILENT_DB := -60.0
const POLYPHONY := 48
const GEM_COMBO_GAP := 0.5
const GEM_COMBO_STEPS := 12

# name: [volume_db, min_gap_sec, max_voices, pitch_jitter]
# A new play is dropped while the last one is younger than min_gap or max_voices are still sounding.
const SOUNDS := {
	"shot": [-19.0, 0.04, 3, 0.05],
	"missile": [-13.0, 0.03, 4, 0.06],
	"explode": [-12.0, 0.05, 4, 0.08],
	"laser": [-13.0, 0.08, 2, 0.03],
	"zap": [-15.0, 0.05, 3, 0.08],
	"nova": [-11.0, 0.1, 2, 0.0],
	"swoosh": [-9.0, 0.08, 2, 0.05],
	"launch": [-15.0, 0.06, 3, 0.05],
	"drain": [-19.0, 0.12, 2, 0.05],
	"place": [-17.0, 0.06, 2, 0.03],
	"hit": [-21.0, 0.03, 4, 0.12],
	"kill": [-15.0, 0.03, 5, 0.1],
	"enemy_shot": [-19.0, 0.08, 3, 0.06],
	"gem": [-17.0, 0.03, 4, 0.0],
	"heal": [-9.0, 0.1, 1, 0.0],
	"hurt": [-11.0, 0.1, 1, 0.03],
	"death": [-5.0, 0.5, 1, 0.0],
	"levelup": [-8.0, 0.2, 1, 0.0],
	"select": [-9.0, 0.05, 1, 0.0],
	"ui": [-11.0, 0.03, 2, 0.0],
	"start": [-7.0, 0.3, 1, 0.0],
	"clear": [-5.0, 0.5, 1, 0.0],
	"gameover": [-5.0, 0.5, 1, 0.0],
}
# Looping beds that follow a 0..1 level, e.g. how far the wings are open. name: volume_db at full level.
const LOOPS := {
	"wings_hum": -21.0,
}
# A loop fades out once nothing has held it for this long (paused or frozen world included).
const LOOP_HOLD := 0.15
const LOOP_FADE := 3.0

var _streams := {}
var _last := {}
var _voices := {}
var _rng := RandomNumberGenerator.new()
var _sfx: AudioStreamPlayer
var _playback: AudioStreamPlaybackPolyphonic
var _music: AudioStreamPlayer
var _music_name := ""
var _music_tween: Tween
var _dimmed := false
var _silent := false
var _loops := {}
var _gem_combo := 0
var _gem_last := -1000.0


static var _current = null


static func sfx(sound: String, pitch: float = 1.0) -> void:
	if _current != null:
		_current.play(sound, pitch)


# Call every frame while the loop should sound; it fades out by itself once the calls stop.
static func loop(sound: String, level: float) -> void:
	if _current != null:
		_current.hold_loop(sound, level)


func _enter_tree() -> void:
	_current = self


func _exit_tree() -> void:
	if _current == self:
		_current = null
	# Voices still sounding at quit hold their streams in the audio server and leak at exit.
	for player in find_children("*", "AudioStreamPlayer", false, false):
		player.stop()
	_playback = null
	_voices.clear()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	for sound: String in SOUNDS:
		_streams[sound] = load(SFX_DIR + sound + ".wav")
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = POLYPHONY
	_sfx = AudioStreamPlayer.new()
	_sfx.name = "Sfx"
	_sfx.stream = poly
	add_child(_sfx)
	# The dummy driver (headless runs) never mixes, so voices would pile up and leak at exit.
	_silent = AudioServer.get_driver_name() == "Dummy"
	if not _silent:
		_sfx.play()
		_playback = _sfx.get_stream_playback() as AudioStreamPlaybackPolyphonic
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.volume_db = SILENT_DB
	add_child(_music)


func play(sound: String, pitch: float = 1.0) -> void:
	var spec: Array = SOUNDS.get(sound, [])
	if spec.is_empty():
		return
	var now := _now()
	if now - float(_last.get(sound, -1000.0)) < float(spec[1]):
		return
	_last[sound] = now
	if _playback == null:
		return
	var ids: Array = _voices.get(sound, []).filter(func(id: int) -> bool: return _playback.is_stream_playing(id))
	if ids.size() < int(spec[2]):
		var jitter := float(spec[3])
		var id := _playback.play_stream(_streams[sound], 0.0, float(spec[0]), pitch * (1.0 + _rng.randf_range(-jitter, jitter)))
		if id != AudioStreamPlaybackPolyphonic.INVALID_ID:
			ids.append(id)
	_voices[sound] = ids


func hold_loop(sound: String, level: float) -> void:
	if not LOOPS.has(sound):
		return
	var entry: Dictionary = _loops.get(sound, {})
	if entry.is_empty():
		var player := AudioStreamPlayer.new()
		player.name = "Loop_" + sound
		player.stream = load(SFX_DIR + sound + ".wav")
		player.volume_db = SILENT_DB
		add_child(player)
		entry = {"player": player, "level": 0.0, "target": 0.0, "seen": 0.0}
		_loops[sound] = entry
	entry["target"] = clampf(level, 0.0, 1.0)
	entry["seen"] = _now()


func loop_level(sound: String) -> float:
	return float(_loops.get(sound, {}).get("level", 0.0))


func _process(delta: float) -> void:
	var now := _now()
	for sound: String in _loops:
		var entry: Dictionary = _loops[sound]
		var target := float(entry["target"]) if now - float(entry["seen"]) < LOOP_HOLD else 0.0
		entry["level"] = move_toward(float(entry["level"]), target, delta * LOOP_FADE)
		var player: AudioStreamPlayer = entry["player"]
		if float(entry["level"]) <= 0.0:
			if player.playing:
				player.stop()
			continue
		player.volume_db = float(LOOPS[sound]) + linear_to_db(float(entry["level"]))
		if not player.playing and not _silent:
			player.play()


# Quick pickups climb a semitone each, up to an octave.
func gem() -> void:
	var now := _now()
	_gem_combo = mini(_gem_combo + 1, GEM_COMBO_STEPS) if now - _gem_last < GEM_COMBO_GAP else 0
	_gem_last = now
	play("gem", pow(2.0, float(_gem_combo) / 12.0))


func play_music(track: String) -> void:
	if track == _music_name or not MUSIC.has(track):
		return
	_music_name = track
	_music.stream = load(BGM_DIR + track + ".wav")
	_music.volume_db = SILENT_DB
	if not _silent:
		_music.play()
	_fade_music(_music_db(), 0.8)


func stop_music(seconds: float = 1.0) -> void:
	_music_name = ""
	_fade_music(SILENT_DB, seconds, true)


func dim_music(on: bool) -> void:
	_dimmed = on
	if _music_name != "":
		_fade_music(_music_db(), 0.25)


func music_track() -> String:
	return _music_name


func _music_db() -> float:
	return MUSIC_DB + (MUSIC_DIM_DB if _dimmed else 0.0)


func _fade_music(db: float, seconds: float, stop_after: bool = false) -> void:
	if _music_tween != null:
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", db, seconds)
	if stop_after:
		_music_tween.tween_callback(_music.stop)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
