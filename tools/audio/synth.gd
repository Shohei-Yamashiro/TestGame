extends RefCounted

# Small offline synthesizer for generate_audio.gd. Buffers are mono float samples in -1..1.

enum Wave { SINE, SQUARE, SAW, TRIANGLE, NOISE }

var rate: int
var rng := RandomNumberGenerator.new()


func _init(sample_rate: int, seed_value: int) -> void:
	rate = sample_rate
	rng.seed = seed_value


static func midi_hz(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)


func samples(seconds: float) -> int:
	return maxi(1, int(round(seconds * float(rate))))


func silence(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(samples(seconds))
	return out


# One voice. The pitch glides exponentially from f0 to f1; NOISE holds each random value for 1/f seconds.
# opts: attack, release (seconds), decay (exponential rate per second), duty (SQUARE),
#       vibrato_hz, vibrato (semitones), gain.
func tone(wave: int, seconds: float, f0: float, f1: float = -1.0, opts: Dictionary = {}) -> PackedFloat32Array:
	var n := samples(seconds)
	var out := PackedFloat32Array()
	out.resize(n)
	if f1 <= 0.0:
		f1 = f0
	var attack := maxf(1.0, float(opts.get("attack", 0.003)) * rate)
	var release := maxf(1.0, float(opts.get("release", 0.02)) * rate)
	var decay := float(opts.get("decay", 0.0)) / float(rate)
	var duty := float(opts.get("duty", 0.5))
	var vib_rate := float(opts.get("vibrato_hz", 0.0)) / float(rate)
	var vib_depth := float(opts.get("vibrato", 0.0))
	var gain := float(opts.get("gain", 1.0))
	var ratio := f1 / f0
	var phase := 0.0
	var held := 0.0
	for i in n:
		var t := float(i) / float(n)
		var freq := f0 * pow(ratio, t)
		if vib_depth > 0.0:
			freq *= pow(2.0, vib_depth * sin(TAU * vib_rate * i) / 12.0)
		var before := phase
		phase += freq / float(rate)
		phase -= floorf(phase)
		var v := 0.0
		match wave:
			Wave.SINE:
				v = sin(TAU * phase)
			Wave.SQUARE:
				v = 1.0 if phase < duty else -1.0
			Wave.SAW:
				v = 2.0 * phase - 1.0
			Wave.TRIANGLE:
				v = 4.0 * absf(phase - 0.5) - 1.0
			Wave.NOISE:
				if phase < before or i == 0:
					held = rng.randf_range(-1.0, 1.0)
				v = held
		var env := minf(1.0, float(i) / attack) * minf(1.0, float(n - i) / release)
		if decay > 0.0:
			env *= exp(-decay * i)
		out[i] = v * env * gain
	return out


func noise(seconds: float, opts: Dictionary = {}) -> PackedFloat32Array:
	return tone(Wave.NOISE, seconds, float(rate), float(rate), opts)


# A fixed-length mix bus for music. Packed arrays are copied when passed around, so writes go
# through this object; with wrap, a note's tail continues from the start for a seamless loop.
class Track:
	var data := PackedFloat32Array()

	func _init(length: int) -> void:
		data.resize(length)

	func add(src: PackedFloat32Array, at: int = 0, gain: float = 1.0, wrap: bool = true) -> void:
		var n := data.size()
		for i in src.size():
			var j := at + i
			if j >= n:
				if not wrap:
					break
				j %= n
			data[j] += src[i] * gain


# Returns a + b * gain with b starting at sample `at`; the result is as long as needed.
static func mixed(a: PackedFloat32Array, b: PackedFloat32Array, at: int = 0, gain: float = 1.0) -> PackedFloat32Array:
	var out := a.duplicate()
	if out.size() < at + b.size():
		out.resize(at + b.size())
	for i in b.size():
		out[at + i] += b[i] * gain
	return out


static func concat(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for part: PackedFloat32Array in parts:
		out.append_array(part)
	return out


# One-pole low-pass whose cutoff glides from c0 to c1 Hz over the buffer.
func lowpass(buf: PackedFloat32Array, c0: float, c1: float = -1.0) -> PackedFloat32Array:
	if c1 <= 0.0:
		c1 = c0
	var out := PackedFloat32Array()
	out.resize(buf.size())
	var y := 0.0
	var n := float(maxi(1, buf.size() - 1))
	for i in buf.size():
		var cutoff := lerpf(c0, c1, float(i) / n)
		var a := 1.0 - exp(-TAU * cutoff / float(rate))
		y += a * (buf[i] - y)
		out[i] = y
	return out


func highpass(buf: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var low := lowpass(buf, cutoff)
	var out := PackedFloat32Array()
	out.resize(buf.size())
	for i in buf.size():
		out[i] = buf[i] - low[i]
	return out


# Feedback echo. With wrap, echoes that run past the end come back in at the start (for loops).
func echo(buf: PackedFloat32Array, seconds: float, feedback: float, wet: float, wrap: bool = false) -> PackedFloat32Array:
	var d := samples(seconds)
	var n := buf.size()
	var line := PackedFloat32Array()
	line.resize(n)
	# Two passes so a wrapped loop also hears the echoes of its own end.
	for pass_index in (2 if wrap else 1):
		for i in n:
			var j := i - d
			var back := 0.0
			if j >= 0:
				back = line[j]
			elif wrap and pass_index > 0:
				back = line[j + n]
			line[i] = buf[i] + back * feedback
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = buf[i] + (line[i] - buf[i]) * wet
	return out


static func scale(buf: PackedFloat32Array, gain: float) -> PackedFloat32Array:
	var out := buf.duplicate()
	for i in out.size():
		out[i] *= gain
	return out


static func normalize(buf: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var top := 0.0
	for v in buf:
		top = maxf(top, absf(v))
	return buf if top <= 0.0 else scale(buf, peak / top)


static func soft_clip(buf: PackedFloat32Array, drive: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(buf.size())
	var norm := tanh(drive)
	for i in buf.size():
		out[i] = tanh(buf[i] * drive) / norm
	return out


static func crush(buf: PackedFloat32Array, levels: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(buf.size())
	for i in buf.size():
		out[i] = round(buf[i] * levels) / levels
	return out


# 16-bit mono PCM. A looping file gets a "smpl" chunk, which Godot's importer reads as the loop range.
static func save_wav(path: String, buf: PackedFloat32Array, sample_rate: int, loop: bool) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(round(clampf(buf[i], -1.0, 1.0) * 32767.0)))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var smpl_size := 36 + 24 if loop else 0
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(4 + (8 + 16) + (8 + data.size()) + ((8 + smpl_size) if loop else 0))
	file.store_buffer("WAVE".to_ascii_buffer())
	file.store_buffer("fmt ".to_ascii_buffer())
	file.store_32(16)
	file.store_16(1)
	file.store_16(1)
	file.store_32(sample_rate)
	file.store_32(sample_rate * 2)
	file.store_16(2)
	file.store_16(16)
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(data.size())
	file.store_buffer(data)
	if loop:
		file.store_buffer("smpl".to_ascii_buffer())
		file.store_32(smpl_size)
		for value in [0, 0, int(1.0e9 / sample_rate), 60, 0, 0, 0, 1, 0]:
			file.store_32(value)
		for value in [0, 0, 0, buf.size() - 1, 0, 0]:
			file.store_32(value)
	file.close()
	return OK
