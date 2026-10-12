class_name ArsenalAudio
extends Node
## Original procedural PCM, shared immutable clips, four reusable Master voices.
## Playback completion belongs to AudioStreamPlayer; no simulation timer runs here.
const SAMPLE_RATE: int = 22050
const VOICE_CAP: int = 4
const MAX_CLIPS: int = 64
const PIANO_NOTES: Array[float] = [261.63, 329.63, 392.0, 523.25, 659.25]
static var _clips: Dictionary[String, AudioStreamWAV] = {}
var _voices: Array[AudioStreamPlayer] = []
var _priorities: Array[int] = []
var _orders: Array[int] = []
var _serial: int = 0
var _piano_note: int = 0
var _played: int = 0
var _last_key: String = ""

func _ready() -> void:
	_ensure_built()

func play(events: Array[Dictionary]) -> void:
	_ensure_built()
	var ordered: Array[Dictionary] = events.duplicate()
	ordered.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return _priority(str(first.get("type", ""))) > _priority(str(second.get("type", ""))))
	var batch_keys: Array[String] = []
	for event: Dictionary in ordered:
		var item: String = str(event.get("item", ""))
		if not _valid_item(item): continue
		var type: String = str(event.get("type", ""))
		var key: String = ""
		if type == "fired": key = item + ":fire"
		elif type == "warning":
			key = item + ":warning"
			if item == "x18": _piano_note = 0
		elif type == "explosion" or type == "shatter": key = item + ":boom"
		elif type == "piano":
			key = "x18:note%d" % _piano_note
			_piano_note = (_piano_note + 1) % PIANO_NOTES.size()
		elif type == "jet": key = "x20:fire"
		if key.is_empty() or key in batch_keys: continue
		batch_keys.append(key)
		var priority: int = _priority(type)
		var slot: int = _choose_voice(priority)
		if slot < 0: continue
		var clip: AudioStreamWAV = _clip(key)
		if clip == null: continue
		_serial += 1
		_priorities[slot] = priority
		_orders[slot] = _serial
		var voice: AudioStreamPlayer = _voices[slot]
		voice.stop()
		voice.stream = clip
		voice.pitch_scale = 1.0
		voice.volume_db = -15.0 if type == "warning" else (-14.0 if type in ["explosion", "shatter"] else -18.0)
		voice.play()
		_played += 1
		_last_key = key

func clear() -> void:
	for voice: AudioStreamPlayer in _voices:
		voice.stop()
		voice.stream = null
	_priorities.fill(0)
	_orders.fill(0)
	_piano_note = 0
	_last_key = ""

func get_display_state() -> Dictionary:
	var active: int = 0
	for voice: AudioStreamPlayer in _voices:
		if voice.playing: active += 1
	return {"voices": _voices.size(), "active": active, "cached_clips": _clips.size(),
		"played": _played, "last_key": _last_key, "sample_rate": SAMPLE_RATE}

func _ensure_built() -> void:
	if not _voices.is_empty(): return
	for index: int in VOICE_CAP:
		var voice: AudioStreamPlayer = AudioStreamPlayer.new()
		voice.name = "ArsenalVoice%d" % index
		voice.bus = &"Master"
		voice.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		voice.max_polyphony = 1
		add_child(voice)
		_voices.append(voice)
		_priorities.append(0)
		_orders.append(0)

func _choose_voice(priority: int) -> int:
	for index: int in VOICE_CAP:
		if not _voices[index].playing: return index
	var oldest: int = -1
	for index: int in VOICE_CAP:
		if _priorities[index] > priority: continue
		if oldest < 0 or _priorities[index] < _priorities[oldest] or (_priorities[index] == _priorities[oldest] and _orders[index] < _orders[oldest]): oldest = index
	return oldest

static func _priority(type: String) -> int:
	if type == "warning": return 3
	if type in ["explosion", "piano", "shatter"]: return 2
	return 1

static func _valid_item(item: String) -> bool:
	return item.length() == 3 and item.begins_with("x") and item.substr(1).is_valid_int() and int(item.substr(1)) in range(1, 21)

static func _clip(key: String) -> AudioStreamWAV:
	if _clips.has(key): return _clips[key]
	if _clips.size() >= MAX_CLIPS: return null
	var parts: PackedStringArray = key.split(":")
	if parts.size() != 2 or not _valid_item(parts[0]): return null
	var item: int = int(parts[0].substr(1))
	var type: String = parts[1]
	var duration: float = .24 + (item % 5) * .045
	if type == "warning": duration = .85
	elif type == "boom": duration = .65
	elif type.begins_with("note"): duration = .75
	var length: int = roundi(duration * SAMPLE_RATE)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(length * 2)
	var phase: float = 0.0
	for index: int in length:
		var at: float = float(index) / SAMPLE_RATE
		var progress: float = at / duration
		var envelope: float = minf(at / .008, 1.0) * pow(maxf(0, 1.0 - progress), 1.65)
		var sample: float = 0.0
		var noise: float = _noise(index, item)
		if type == "warning":
			var frequency: float = 360 + item * 9 + sin(at * TAU * 3) * 180
			phase += TAU * frequency / SAMPLE_RATE
			sample = sin(phase) * (.35 + .15 * sin(at * TAU * 7))
		elif type == "boom":
			phase += TAU * (100 + item * 2) * (1.0 - progress * .8) / SAMPLE_RATE
			sample = .28 * sin(phase) + .30 * noise * pow(1.0 - progress, 2)
		elif type.begins_with("note"):
			var note: int = clampi(int(type.trim_prefix("note")), 0, 4)
			phase += TAU * PIANO_NOTES[note] / SAMPLE_RATE
			sample = (.37 * sin(phase) + .12 * sin(phase * 2) + .05 * sin(phase * 3.99)) * exp(-at * 3.0)
		else:
			var frequency: float = 160.0 + item * 41
			match item:
				1: frequency = lerpf(260, 1250, progress)
				2, 10: frequency = lerpf(110 + item * 3, 40, progress)
				3: frequency = lerpf(1350, 450, progress)
				5: frequency = 1900 + sin(at * TAU * 50) * 300
				6: frequency = 320 + sin(at * TAU * 30) * 120
				7: frequency = 190 + sin(at * TAU * 90) * 25
				8, 13: frequency = lerpf(440 + item * 10, 90, progress)
				9: frequency = 520 + sin(at * TAU * 12) * 260
				14: frequency = 660 if fmod(at, .10) < .05 else 880
				15: frequency = lerpf(260, 780, progress)
				_: pass
			phase += TAU * frequency / SAMPLE_RATE
			sample = .33 * sin(phase) + .10 * sin(phase * (1.5 + item * .025))
			if item in [2, 4, 6, 10, 11, 12, 16, 20]: sample += noise * (.32 if item in [4, 20] else .15)
			if item == 7: sample *= .65 + .35 * sin(at * TAU * 110)
			if item == 9: sample *= .6 + .4 * sin(at * TAU * 18)
			if item == 12: sample *= maxf(0.0, sin(at * TAU * 28))
		bytes.encode_s16(index * 2, roundi(clampf(sample * envelope, -.75, .75) * 32767))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	_clips[key] = wav
	return wav

static func _noise(index: int, seed: int) -> float:
	# Deterministic local LCG; synthesis does not touch gameplay's random state.
	var value: int = ((index + seed * 8191) * 1103515245 + 12345) & 0x7fffffff
	return float(value % 65536) / 32768.0 - 1.0
