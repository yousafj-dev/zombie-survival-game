class_name SfxGen
extends RefCounted

## Procedural sound effects, generated in code at runtime — there are no
## audio files in the project. Each stream is built once and cached.
## All clips are short, modest-volume 16-bit mono WAVs; the players that
## use them route to the "SFX" bus, and the menu's Sound toggle mutes the
## Master bus, so every one of these obeys the toggle for real.

const MIX_RATE := 22050

static var _gunshot: AudioStreamWAV
static var _reload_click: AudioStreamWAV
static var _zombie_hit: AudioStreamWAV
static var _ui_click: AudioStreamWAV
static var _pickup: AudioStreamWAV

static func gunshot() -> AudioStreamWAV:
	if _gunshot == null:
		_gunshot = _make(_render_gunshot())
	return _gunshot

static func reload_click() -> AudioStreamWAV:
	if _reload_click == null:
		_reload_click = _make(_render_reload_click())
	return _reload_click

static func zombie_hit() -> AudioStreamWAV:
	if _zombie_hit == null:
		_zombie_hit = _make(_render_zombie_hit())
	return _zombie_hit

static func ui_click() -> AudioStreamWAV:
	if _ui_click == null:
		_ui_click = _make(_render_ui_click())
	return _ui_click

static func pickup() -> AudioStreamWAV:
	if _pickup == null:
		_pickup = _make(_render_pickup())
	return _pickup

# --- rendering -----------------------------------------------------------

static func _render_gunshot() -> PackedByteArray:
	var count := int(MIX_RATE * 0.22)
	var samples: Array = []
	samples.resize(count)
	for i in count:
		var t := float(i) / MIX_RATE
		var noise := randf() * 2.0 - 1.0
		var crack := noise * 0.7 * exp(-t * 30.0)
		var thump := sin(TAU * 72.0 * t) * 0.8 * exp(-t * 16.0)
		samples[i] = (crack + thump) * 0.5
	return _pack(samples)

static func _render_reload_click() -> PackedByteArray:
	var count := int(MIX_RATE * 0.1)
	var samples: Array = []
	samples.resize(count)
	for i in count:
		var t := float(i) / MIX_RATE
		var s := 0.0
		for start in [0.0, 0.05]:
			var dt: float = t - start
			if dt >= 0.0 and dt < 0.02:
				s += (randf() * 2.0 - 1.0) * exp(-dt * 240.0) * 0.45
				s += sin(TAU * 2300.0 * t) * exp(-dt * 240.0) * 0.2
		samples[i] = s
	return _pack(samples)

static func _render_zombie_hit() -> PackedByteArray:
	var count := int(MIX_RATE * 0.14)
	var samples: Array = []
	samples.resize(count)
	for i in count:
		var t := float(i) / MIX_RATE
		var thud := sin(TAU * 95.0 * t) * exp(-t * 22.0) * 0.75
		var mush := (randf() * 2.0 - 1.0) * exp(-t * 45.0) * 0.22
		samples[i] = (thud + mush) * 0.6
	return _pack(samples)

static func _render_ui_click() -> PackedByteArray:
	var count := int(MIX_RATE * 0.05)
	var samples: Array = []
	samples.resize(count)
	for i in count:
		var t := float(i) / MIX_RATE
		samples[i] = sin(TAU * 1350.0 * t) * exp(-t * 95.0) * 0.32
	return _pack(samples)

static func _render_pickup() -> PackedByteArray:
	var count := int(MIX_RATE * 0.16)
	var samples: Array = []
	samples.resize(count)
	for i in count:
		var t := float(i) / MIX_RATE
		var freq := 880.0 if t < 0.07 else 1318.0
		samples[i] = sin(TAU * freq * t) * exp(-t * 14.0) * 0.4
	return _pack(samples)

static func _pack(samples: Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(float(samples[i]), -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	return bytes

static func _make(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
