extends Node
## Sfx (autoload)
##
## Every sound in the game is synthesised here rather than loaded from audio
## files - the project ships no .wav/.ogg assets, and generating them keeps it
## that way while still giving each weapon a distinct voice.
##
## Each sound is built from a handful of primitives (noise bursts, pitch sweeps,
## FM tones, decaying thumps) rendered into a 16-bit AudioStreamWAV once, then
## reused. Variation comes at PLAYBACK time instead of from multiple takes:
## play_3d() jitters pitch and volume per shot, so a full-auto slug launcher
## never sounds like the same click stamped out forty times.
##
## Positional sounds go through AudioStreamPlayer3D, which gives distance
## attenuation and stereo panning for free against whichever Camera3D is current
## (that camera is the audio listener).
##
## Synthesis is LAZY - each entry is built the first time it's actually played,
## not up front. A prior version of this file built the whole library (plus a
## much larger ambience/announcer system since dropped entirely) inside
## `_ready()`, synchronously, before the first frame could be drawn; on top of
## the ambience beds that cost Arena load 2+ extra seconds. This library alone
## is far smaller, but there's no reason to pay any of it on the startup path
## when spreading it across first-use moments is free.

const SAMPLE_RATE: int = 22050
## Concurrent 3D voices. Past this the oldest is recycled, so a chaotic firefight
## degrades gracefully instead of allocating players without bound.
const MAX_VOICES: int = 32

var _library: Dictionary = {}
var _voices: Array[AudioStreamPlayer3D] = []
var _next_voice: int = 0
var _ui_player: AudioStreamPlayer = null
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	for i in range(MAX_VOICES):
		var voice := AudioStreamPlayer3D.new()
		voice.max_distance = 220.0
		voice.unit_size = 12.0
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(voice)
		_voices.append(voice)
	_ui_player = AudioStreamPlayer.new()
	add_child(_ui_player)

## Fires a one-shot at a world position. `pitch` and `volume_db` are the centre
## values; the jitter around them is what stops repeats sounding mechanical.
func play_3d(sound: String, position: Vector3, pitch: float = 1.0, volume_db: float = 0.0,
		pitch_jitter: float = 0.12) -> void:
	var stream: AudioStream = _get_stream(sound)
	if stream == null:
		return
	var voice: AudioStreamPlayer3D = _take_voice()
	voice.stream = stream
	voice.global_position = position
	voice.pitch_scale = maxf(0.05, pitch + _rng.randf_range(-pitch_jitter, pitch_jitter))
	voice.volume_db = volume_db + _rng.randf_range(-1.5, 1.5)
	voice.play()

func play_ui(sound: String, pitch: float = 1.0, volume_db: float = -4.0) -> void:
	var stream: AudioStream = _get_stream(sound)
	if stream == null:
		return
	_ui_player.stream = stream
	_ui_player.pitch_scale = pitch
	_ui_player.volume_db = volume_db
	_ui_player.play()

## Synthesises `sound` on first request and caches it; every later play of the
## same sound is a free dictionary lookup.
func _get_stream(sound: String) -> AudioStream:
	if _library.has(sound):
		return _library[sound]
	var stream: AudioStreamWAV = _synthesize(sound)
	_library[sound] = stream
	return stream

## Round-robin rather than "find a free one": under sustained fire every voice is
## busy, and stealing the oldest is better than dropping the newest sound.
func _take_voice() -> AudioStreamPlayer3D:
	var voice: AudioStreamPlayer3D = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	return voice

## ---- Synthesis -------------------------------------------------------------

## One-of-a-kind recipe per sound name, built only when first requested (see
## _get_stream). Returns null for an unknown name rather than erroring, so a
## typo'd sound key just plays nothing instead of crashing the caller.
func _synthesize(sound: String) -> AudioStreamWAV:
	match sound:
		"rocket_fire":
			return _mix([
				_sweep(0.32, 620.0, 90.0, 0.35, 3.0),
				_noise(0.34, 0.55, 4.0, 0.25),
			])
		"explosion":
			return _mix([
				_noise(0.85, 0.9, 2.2, 0.9),
				_sweep(0.5, 150.0, 28.0, 0.7, 2.4),
			])
		"railgun_charge":
			return _sound(_sweep(0.9, 110.0, 900.0, 0.28, 0.6, true))
		"railgun_fire":
			return _mix([
				_sweep(0.45, 1800.0, 160.0, 0.5, 4.5),
				_noise(0.2, 0.35, 6.0, 0.1),
			])
		"slug_fire":
			return _mix([
				_sweep(0.16, 420.0, 130.0, 0.4, 5.0),
				_noise(0.12, 0.3, 9.0, 0.5),
			])
		"grapple_fire":
			return _mix([
				_noise(0.1, 0.4, 12.0, 0.2),
				_sweep(0.28, 240.0, 700.0, 0.22, 2.5),
			])
		"grapple_hit":
			return _mix([
				_noise(0.14, 0.5, 14.0, 0.15),
				_tone(0.2, 320.0, 0.3, 7.0),
			])
		"buster_fire":
			return _mix([
				_sweep(1.2, 80.0, 34.0, 0.8, 1.1),
				_noise(0.9, 0.5, 1.8, 0.7),
			])
		"planet_shatter":
			return _mix([
				_noise(2.4, 1.0, 0.9, 1.0),
				_sweep(1.8, 90.0, 16.0, 0.9, 0.8),
				_tone(1.4, 41.0, 0.7, 1.2),
			])
		"collapse":
			return _mix([
				_noise(1.5, 0.85, 1.5, 0.85),
				_sweep(1.0, 120.0, 30.0, 0.6, 1.4),
			])
		"slap":
			return _mix([
				_noise(0.13, 0.9, 16.0, 0.05),
				_sweep(0.18, 900.0, 180.0, 0.45, 6.0),
			])
		"jump":
			return _sound(_sweep(0.16, 260.0, 460.0, 0.25, 5.0))
		"land":
			return _mix([
				_noise(0.2, 0.4, 9.0, 0.6),
				_sweep(0.22, 190.0, 60.0, 0.35, 5.0),
			])
		"health":
			return _mix([
				_tone(0.28, 880.0, 0.22, 5.0),
				_tone(0.34, 1320.0, 0.16, 4.0),
			])
		"jump_pad":
			return _sound(_sweep(0.4, 200.0, 1100.0, 0.4, 2.2))
		"ui_click":
			return _sound(_tone(0.07, 1400.0, 0.25, 22.0))
		_:
			return null

## White noise shaped by an exponential decay. `tone` mixes in a low-passed
## (smoothed) copy, which is what turns a hiss into a rumble.
func _noise(duration: float, amplitude: float, decay: float, tone: float) -> PackedFloat32Array:
	var count: int = int(duration * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var smoothed: float = 0.0
	# Heavier smoothing for lower-pitched results.
	var alpha: float = clampf(1.0 - tone * 0.9, 0.02, 0.95)
	for i in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var white: float = _rng.randf_range(-1.0, 1.0)
		smoothed += (white - smoothed) * alpha
		var env: float = exp(-decay * t)
		out[i] = smoothed * env * amplitude
	return out

## A sine whose frequency glides from `from_hz` to `to_hz`. `exponential` sweeps
## in pitch-space, which is how a charging capacitor actually sounds.
func _sweep(duration: float, from_hz: float, to_hz: float, amplitude: float,
		decay: float, exponential: bool = false) -> PackedFloat32Array:
	var count: int = int(duration * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / maxf(duration, 0.0001)
		var freq: float = (from_hz * pow(to_hz / maxf(from_hz, 1.0), u)) if exponential else lerpf(from_hz, to_hz, u)
		phase += TAU * freq / float(SAMPLE_RATE)
		# A touch of second harmonic keeps it from sounding like a test tone.
		var wave: float = sin(phase) * 0.8 + sin(phase * 2.0) * 0.2
		out[i] = wave * exp(-decay * t) * amplitude
	return out

## Fixed-pitch FM tone - the metallic ring under impacts and pickups.
func _tone(duration: float, hz: float, amplitude: float, decay: float) -> PackedFloat32Array:
	var count: int = int(duration * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in range(count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var env: float = exp(-decay * t)
		var modulator: float = sin(TAU * hz * 1.5 * t) * 1.4 * env
		out[i] = sin(TAU * hz * t + modulator) * env * amplitude
	return out

## Sums layers (padding to the longest), soft-clips, applies a short fade-in and
## fade-out, and packs to 16-bit PCM. The fades matter: a buffer that starts or
## ends mid-waveform clicks audibly on every play.
func _mix(layers: Array) -> AudioStreamWAV:
	var longest: int = 0
	for layer in layers:
		longest = maxi(longest, (layer as PackedFloat32Array).size())
	var summed := PackedFloat32Array()
	summed.resize(longest)
	for layer in layers:
		var samples: PackedFloat32Array = layer
		for i in range(samples.size()):
			summed[i] += samples[i]
	return _pack(summed)

func _pack(samples: PackedFloat32Array) -> AudioStreamWAV:
	var count: int = samples.size()
	var data := PackedByteArray()
	data.resize(count * 2)
	var fade: int = mini(160, maxi(1, count / 8))
	for i in range(count):
		# tanh-style soft clip so summed layers saturate instead of wrapping.
		var v: float = samples[i]
		v = v / (1.0 + absf(v))
		if i < fade:
			v *= float(i) / float(fade)
		elif i > count - fade:
			v *= float(count - i) / float(fade)
		var s: int = clampi(int(v * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, s)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream

## Convenience for single-layer sounds so the library table stays readable.
func _sound(samples: PackedFloat32Array) -> AudioStreamWAV:
	return _pack(samples)
