extends SceneTree

# Synthesizes every sound effect and music loop into res://assets/audio as WAV files.
# Output is deterministic, so regenerating without changes leaves the files identical.
# Usage: godot --headless --path <project> -s res://tools/audio/generate_audio.gd [-- only=<name,...>]

const Synth := preload("res://tools/audio/synth.gd")
const W := Synth.Wave

const SFX_DIR := "res://assets/audio/sfx/"
const BGM_DIR := "res://assets/audio/bgm/"
const SFX_RATE := 44100
const BGM_RATE := 22050

var s: Synth
var _only: Array[String] = []
var _written := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("only="):
			_only.assign(arg.trim_prefix("only=").split(","))
	s = Synth.new(SFX_RATE, 7)
	for method in get_method_list():
		var name: String = method["name"]
		if name.begins_with("sfx_"):
			_write_sfx(name.trim_prefix("sfx_"))
	s = Synth.new(BGM_RATE, 11)
	if _wanted("title"):
		_save(BGM_DIR + "title.wav", bgm_title(), BGM_RATE, true)
	if _wanted("game"):
		_save(BGM_DIR + "game.wav", bgm_game(), BGM_RATE, true)
	print("AUDIO wrote=%d" % _written)
	quit(0)


func _wanted(name: String) -> bool:
	return _only.is_empty() or _only.has(name)


func _write_sfx(name: String) -> void:
	if not _wanted(name):
		return
	s.rng.seed = hash(name)
	var buf: PackedFloat32Array = call("sfx_" + name)
	_save(SFX_DIR + name + ".wav", Synth.normalize(buf, 0.9), SFX_RATE, false)


func _save(path: String, buf: PackedFloat32Array, rate: int, loop: bool) -> void:
	var err := Synth.save_wav(ProjectSettings.globalize_path(path), buf, rate, loop)
	if err != OK:
		printerr("AUDIO FAIL: %s (%s)" % [path, error_string(err)])
		return
	_written += 1
	print("  %s  %.2fs" % [path, float(buf.size()) / rate])


# --- Weapons ---

func sfx_shot() -> PackedFloat32Array:
	var body := s.tone(W.SQUARE, 0.08, 1400.0, 520.0, {"duty": 0.25, "decay": 30.0})
	body = Synth.mixed(body, s.highpass(s.noise(0.04, {"decay": 80.0, "gain": 0.3}), 3000.0))
	return s.lowpass(body, 6000.0)


func sfx_missile() -> PackedFloat32Array:
	var hiss := s.lowpass(s.noise(0.22, {"attack": 0.02, "decay": 10.0}), 1500.0, 5000.0)
	return Synth.mixed(hiss, s.tone(W.SAW, 0.22, 180.0, 520.0, {"decay": 9.0, "gain": 0.35}))


func sfx_explode() -> PackedFloat32Array:
	var rumble := s.lowpass(s.tone(W.NOISE, 0.6, 9000.0, 1500.0, {"decay": 7.0}), 3500.0, 200.0)
	rumble = Synth.mixed(rumble, s.tone(W.SINE, 0.35, 110.0, 38.0, {"decay": 9.0, "gain": 1.2}))
	return Synth.soft_clip(rumble, 1.8)


func sfx_laser() -> PackedFloat32Array:
	var beam := s.tone(W.SAW, 0.26, 1800.0, 260.0, {"decay": 7.0, "vibrato_hz": 38.0, "vibrato": 0.8})
	beam = Synth.mixed(beam, s.tone(W.SQUARE, 0.26, 900.0, 130.0, {"decay": 7.0, "duty": 0.12, "gain": 0.4}))
	return s.lowpass(beam, 7000.0, 1800.0)


func sfx_zap() -> PackedFloat32Array:
	var parts := []
	for i in 6:
		var f := s.rng.randf_range(500.0, 2200.0)
		parts.append(s.tone(W.SQUARE, 0.025, f, f * 0.7, {"duty": 0.3, "gain": 1.0 - i * 0.12}))
	var zap := Synth.mixed(Synth.concat(parts), s.highpass(s.noise(0.15, {"decay": 25.0, "gain": 0.5}), 2500.0))
	return Synth.crush(zap, 6.0)


func sfx_nova() -> PackedFloat32Array:
	var wave := s.tone(W.SINE, 0.45, 180.0, 720.0, {"attack": 0.01, "decay": 6.0})
	wave = Synth.mixed(wave, s.tone(W.TRIANGLE, 0.45, 183.0, 735.0, {"attack": 0.01, "decay": 6.0, "gain": 0.6}))
	return Synth.mixed(wave, s.lowpass(s.noise(0.45, {"attack": 0.05, "decay": 8.0, "gain": 0.25}), 800.0, 4000.0))


func sfx_swoosh() -> PackedFloat32Array:
	var air := s.noise(0.3, {"attack": 0.08, "release": 0.15})
	return s.highpass(s.lowpass(air, 900.0, 5000.0), 400.0)


func sfx_launch() -> PackedFloat32Array:
	var rise := s.tone(W.TRIANGLE, 0.18, 260.0, 1100.0, {"decay": 8.0})
	return Synth.mixed(rise, s.tone(W.SQUARE, 0.18, 520.0, 2200.0, {"decay": 12.0, "duty": 0.2, "gain": 0.25}))


func sfx_drain() -> PackedFloat32Array:
	return s.tone(W.SINE, 0.24, 620.0, 240.0, {"attack": 0.02, "decay": 5.0, "vibrato_hz": 22.0, "vibrato": 1.5})


func sfx_place() -> PackedFloat32Array:
	return Synth.concat([
		s.tone(W.SQUARE, 0.03, 1500.0, 1500.0, {"duty": 0.25}),
		s.tone(W.SQUARE, 0.05, 750.0, 700.0, {"duty": 0.25, "decay": 30.0}),
	])


# --- Enemies ---

func sfx_hit() -> PackedFloat32Array:
	var tick := s.tone(W.SQUARE, 0.05, 420.0, 160.0, {"duty": 0.4, "decay": 50.0})
	return Synth.mixed(tick, s.tone(W.NOISE, 0.04, 6000.0, 2000.0, {"decay": 70.0, "gain": 0.6}))


func sfx_kill() -> PackedFloat32Array:
	var crunch := s.tone(W.NOISE, 0.16, 7000.0, 900.0, {"decay": 18.0})
	crunch = Synth.mixed(crunch, s.tone(W.SQUARE, 0.14, 700.0, 110.0, {"duty": 0.5, "decay": 16.0, "gain": 0.7}))
	return Synth.crush(s.lowpass(crunch, 8000.0, 2000.0), 10.0)


func sfx_enemy_shot() -> PackedFloat32Array:
	return s.tone(W.SQUARE, 0.1, 300.0, 600.0, {"duty": 0.5, "decay": 18.0, "vibrato_hz": 30.0, "vibrato": 2.0})


# --- Player and pickups ---

func sfx_gem() -> PackedFloat32Array:
	return Synth.concat([
		s.tone(W.TRIANGLE, 0.035, Synth.midi_hz(88), -1.0, {"release": 0.005}),
		s.tone(W.TRIANGLE, 0.09, Synth.midi_hz(95), -1.0, {"decay": 30.0}),
	])


func sfx_heal() -> PackedFloat32Array:
	var parts := []
	for note in [72, 76, 79, 84]:
		parts.append(s.tone(W.TRIANGLE, 0.07, Synth.midi_hz(note), -1.0, {"release": 0.01}))
	parts.append(s.tone(W.TRIANGLE, 0.25, Synth.midi_hz(88), -1.0, {"decay": 9.0, "vibrato_hz": 6.0, "vibrato": 0.2}))
	return s.echo(_tail(Synth.concat(parts), 0.3), 0.09, 0.3, 0.4)


func sfx_hurt() -> PackedFloat32Array:
	var hit := s.tone(W.SQUARE, 0.28, 260.0, 70.0, {"duty": 0.5, "decay": 9.0})
	hit = Synth.mixed(hit, s.lowpass(s.noise(0.2, {"decay": 14.0}), 2500.0, 400.0))
	return Synth.soft_clip(hit, 2.5)


func sfx_death() -> PackedFloat32Array:
	var fall := s.tone(W.SQUARE, 1.2, 520.0, 35.0, {"duty": 0.5, "decay": 2.5, "vibrato_hz": 9.0, "vibrato": 1.0})
	fall = Synth.mixed(fall, s.lowpass(s.tone(W.NOISE, 1.2, 8000.0, 300.0, {"decay": 3.0}), 6000.0, 200.0))
	return Synth.soft_clip(fall, 2.0)


# --- Progress and UI ---

func sfx_levelup() -> PackedFloat32Array:
	var parts := []
	for note in [72, 76, 79, 84, 88]:
		parts.append(_chip(note, 0.06, 0.25))
	parts.append(_chip(91, 0.32, 0.25))
	return s.echo(_tail(Synth.concat(parts), 0.4), 0.12, 0.3, 0.35)


func sfx_select() -> PackedFloat32Array:
	return Synth.concat([_chip(79, 0.05, 0.25), _chip(86, 0.14, 0.25)])


func sfx_ui() -> PackedFloat32Array:
	return s.tone(W.SQUARE, 0.045, 1320.0, 1100.0, {"duty": 0.25, "decay": 40.0})


func sfx_start() -> PackedFloat32Array:
	var sweep := s.lowpass(s.tone(W.SAW, 0.5, 110.0, 880.0, {"attack": 0.05, "decay": 3.0}), 400.0, 6000.0)
	return Synth.mixed(sweep, _chord([69, 76, 81], 0.6), s.samples(0.3))


func sfx_clear() -> PackedFloat32Array:
	var parts := []
	for n in [[72, 0.12], [76, 0.12], [79, 0.12], [84, 0.24], [79, 0.12], [84, 0.6]]:
		parts.append(_chip(n[0], n[1], 0.5))
	var melody := Synth.mixed(Synth.concat(parts), _chord([60, 64, 67, 72], 0.9), s.samples(0.72), 0.5)
	return s.echo(_tail(melody, 0.4), 0.15, 0.25, 0.3)


func sfx_gameover() -> PackedFloat32Array:
	var parts := []
	for n in [[76, 0.22], [75, 0.22], [74, 0.22], [73, 0.9]]:
		var long: bool = n[1] > 0.5
		parts.append(s.tone(W.SQUARE, n[1], Synth.midi_hz(n[0]), -1.0,
			{"duty": 0.5, "release": 0.04, "decay": 1.5, "vibrato_hz": 5.0, "vibrato": 0.25 if long else 0.0}))
	var melody := s.lowpass(Synth.concat(parts), 2500.0)
	melody = Synth.mixed(melody, _chord([45, 52, 57], 1.4), s.samples(0.66), 0.4)
	return s.echo(_tail(melody, 0.5), 0.2, 0.3, 0.3)


func _chip(note: int, seconds: float, duty: float) -> PackedFloat32Array:
	return s.tone(W.SQUARE, seconds, Synth.midi_hz(note), -1.0, {"duty": duty, "release": 0.01, "decay": 4.0})


func _chord(notes: Array, seconds: float) -> PackedFloat32Array:
	var out := s.silence(seconds)
	for note in notes:
		var f := Synth.midi_hz(note)
		out = Synth.mixed(out, s.tone(W.SAW, seconds, f, -1.0, {"attack": 0.02, "release": seconds * 0.6}), 0, 0.3)
		out = Synth.mixed(out, s.tone(W.SAW, seconds, f * 1.006, -1.0, {"attack": 0.02, "release": seconds * 0.6}), 0, 0.3)
	return s.lowpass(out, 2500.0)


# Room for an echo to ring out after the dry sound ends.
func _tail(buf: PackedFloat32Array, seconds: float) -> PackedFloat32Array:
	return Synth.concat([buf, s.silence(seconds)])


# --- Music ---
# Chords are MIDI note lists, one per bar. Lead events are [start_16th, length_16ths, midi] within a bar.

const AM := [57, 60, 64]
const F := [53, 57, 60]
const C := [55, 60, 64]
const G := [55, 59, 62]
const DM := [57, 62, 65]
const E := [56, 59, 64]


func bgm_title() -> PackedFloat32Array:
	var chords := [AM, F, C, G, AM, F, DM, E]
	var step := 60.0 / 84.0 / 4.0
	var bar := s.samples(16.0 * step)
	var total := bar * chords.size()
	var pad := Synth.Track.new(total)
	var arp := Synth.Track.new(total)
	var bass := Synth.Track.new(total)
	for b in chords.size():
		var chord: Array = chords[b]
		var at := b * bar
		for note in chord:
			for detune in [0.997, 1.003]:
				pad.add(s.tone(W.SAW, 16.0 * step + 0.4, Synth.midi_hz(note + 12) * detune, -1.0, {"attack": 0.6, "release": 0.8}), at, 0.12)
		bass.add(s.tone(W.TRIANGLE, 16.0 * step, Synth.midi_hz(chord[0] - 24), -1.0, {"attack": 0.05, "release": 0.4}), at, 0.5)
		var pattern := [0, 1, 2, 1, 0, 1, 2, 3]
		for i in 8:
			var degree: int = pattern[i]
			var note: int = chord[degree % 3] + 24 + (12 if degree == 3 else 0)
			arp.add(s.tone(W.TRIANGLE, 2.0 * step, Synth.midi_hz(note), -1.0, {"decay": 3.0, "release": 0.05}), at + s.samples(i * 2.0 * step), 0.28)
	var out := Synth.Track.new(total)
	out.add(s.lowpass(pad.data, 1400.0))
	out.add(s.echo(arp.data, 3.0 * step, 0.4, 0.5, true))
	out.add(bass.data)
	return Synth.soft_clip(Synth.normalize(out.data, 0.8), 1.2)


func bgm_game() -> PackedFloat32Array:
	var chords := [AM, F, C, G, AM, F, C, G, F, G, AM, AM, F, G, E, E]
	var step := 60.0 / 132.0 / 4.0
	var bar := s.samples(16.0 * step)
	var total := bar * chords.size()
	var drums := Synth.Track.new(total)
	var bass := Synth.Track.new(total)
	var arp := Synth.Track.new(total)
	var pad := Synth.Track.new(total)
	var lead := Synth.Track.new(total)

	var kick := s.tone(W.SINE, 0.22, 150.0, 42.0, {"decay": 16.0})
	kick = Synth.mixed(kick, s.tone(W.NOISE, 0.01, 8000.0, 8000.0, {"gain": 0.3}))
	var snare := s.highpass(s.noise(0.18, {"decay": 20.0}), 1200.0)
	snare = Synth.mixed(snare, s.tone(W.TRIANGLE, 0.1, 210.0, 160.0, {"decay": 30.0, "gain": 0.7}))
	var hat := s.highpass(s.noise(0.04, {"decay": 90.0}), 6000.0)
	var open_hat := s.highpass(s.noise(0.2, {"decay": 18.0}), 6000.0)

	var melody := {
		8: [[0, 4, 81], [4, 4, 84], [8, 2, 81], [10, 2, 79], [12, 4, 77]],
		9: [[0, 6, 79], [6, 2, 74], [8, 4, 79], [12, 4, 83]],
		10: [[0, 4, 84], [4, 2, 83], [6, 2, 81], [8, 8, 76]],
		11: [[0, 2, 81], [2, 2, 83], [4, 4, 84], [8, 8, 88]],
		12: [[0, 4, 89], [4, 4, 88], [8, 4, 84], [12, 4, 81]],
		13: [[0, 4, 86], [4, 4, 83], [8, 8, 79]],
		14: [[0, 4, 80], [4, 4, 83], [8, 4, 88], [12, 4, 86]],
		15: [[0, 8, 83], [8, 4, 80], [12, 4, 76]],
	}

	for b in chords.size():
		var chord: Array = chords[b]
		var at := b * bar
		for beat in 4:
			drums.add(kick, at + s.samples(beat * 4.0 * step), 0.9)
			drums.add(hat, at + s.samples((beat * 4.0 + 2.0) * step), 0.35)
			if b >= 8:
				drums.add(hat, at + s.samples((beat * 4.0 + 3.0) * step), 0.2)
		drums.add(snare, at + s.samples(4.0 * step), 0.6)
		drums.add(snare, at + s.samples(12.0 * step), 0.6)
		if b % 4 == 3:
			drums.add(open_hat, at + s.samples(14.0 * step), 0.3)
			drums.add(snare, at + s.samples(15.0 * step), 0.35)

		var root: int = chord[0] - 24
		for i in 8:
			var note := root + (12 if i % 2 == 1 else 0)
			bass.add(s.tone(W.SAW, 1.8 * step, Synth.midi_hz(note), -1.0, {"decay": 6.0, "release": 0.02}), at + s.samples(i * 2.0 * step), 0.55)

		var order := [0, 1, 2, 3, 2, 1]
		for i in 16:
			var degree: int = order[i % order.size()]
			var note: int = chord[degree % 3] + 12 + (12 if degree == 3 else 0)
			arp.add(s.tone(W.SQUARE, step * 0.9, Synth.midi_hz(note), -1.0, {"duty": 0.125, "decay": 14.0, "release": 0.01}), at + s.samples(i * step), 0.16)

		for note in chord:
			pad.add(s.tone(W.SAW, 16.0 * step, Synth.midi_hz(note), -1.0, {"attack": 0.15, "release": 0.2}), at, 0.07)

		for ev in melody.get(b, []):
			var v := s.tone(W.SQUARE, ev[1] * step, Synth.midi_hz(ev[2]), -1.0,
				{"duty": 0.5, "attack": 0.01, "release": 0.04, "decay": 1.5, "vibrato_hz": 5.5, "vibrato": 0.15})
			lead.add(v, at + s.samples(ev[0] * step), 0.2)

	var out := Synth.Track.new(total)
	out.add(drums.data)
	out.add(s.lowpass(bass.data, 900.0))
	out.add(s.echo(s.lowpass(arp.data, 3500.0), 3.0 * step, 0.35, 0.4, true))
	out.add(s.lowpass(pad.data, 1200.0))
	out.add(s.echo(s.lowpass(lead.data, 3000.0), 3.0 * step, 0.3, 0.35, true))
	return Synth.soft_clip(Synth.normalize(out.data, 0.85), 1.3)
