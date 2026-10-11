extends SceneTree
## Imported native PCM bytes and the public resource-pack lookup contract.
const EXTENSIONS = preload("res://presentation/openspades_extensions.gd")
const AUDIO = preload("res://audio/openspades_audio.gd")
const ROOT := "res://assets/openspades/"
const TARGET := "Sounds/Weapons/SMG/V2Local1.opus"
const ALIAS := ROOT + "sounds/Weapons/SMG/V2Local1.ogg"
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _run() -> void:
	EXTENSIONS.clear()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXTENSIONS.IMPACT_PCM_MANIFEST))
	check(parsed is Dictionary and parsed.get("files") is Dictionary, "generated native PCM manifest is available")
	if not parsed is Dictionary or not parsed.get("files") is Dictionary:
		_finish()
		return
	var manifest: Dictionary = parsed
	var legacy_manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "manifest.json"))
	var originals: Dictionary = {}
	var original_sounds: int = 0
	for row: Dictionary in legacy_manifest.assets:
		originals[row.virtual_path] = row
		if str(row.output).begins_with("sounds/"):
			original_sounds += 1
	check(original_sounds == 146, "full146-entry original Vorbis catalog remains available")
	check(manifest.files.size() == 49, "curated49 original weapon, impact and block sounds are present")
	check(EXTENSIONS._validate_impact_pcm_manifest(manifest).size() == manifest.files.size(), "generated manifest satisfies the bounded runtime contract")
	var total_pcm: int = 0
	for canonical: String in manifest.files:
		var entry: Dictionary = manifest.files[canonical]
		var stream: AudioStreamWAV = EXTENSIONS.sound(canonical) as AudioStreamWAV
		check(stream != null, "canonical bundled sound resolves to PCM: " + canonical)
		if stream == null:
			continue
		var pcm: PackedByteArray = stream.data
		var channels: int = int(entry.channels)
		var frames: int = int(entry.frames)
		total_pcm += pcm.size()
		check(stream.format == AudioStreamWAV.FORMAT_16_BITS, "import preserves PCM16 without QOA/ADPCM: " + canonical)
		check(stream.mix_rate == 48000 and stream.stereo == (channels == 2), "native rate and channel layout: " + canonical)
		check(pcm.size() == frames * channels * 2 and is_equal_approx(stream.get_length(), float(frames) / 48000.0), "exact native frame count and duration: " + canonical)
		check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "one-shot stream does not gain an import loop: " + canonical)
		check(EXTENSIONS._sha256(pcm) == entry.pcm_sha256, "imported sample bytes equal native-floor manifest SHA256: " + canonical)
		check(EXTENSIONS._sha256(FileAccess.get_file_as_bytes(ROOT + entry.output)) == entry.output_sha256, "generated WAV container SHA256: " + canonical)
		check(originals.has(canonical) and originals[canonical].source_sha256 == entry.source_sha256, "PCM provenance equals original package catalog: " + canonical)
		if originals.has(canonical):
			check(EXTENSIONS.sound(ROOT + originals[canonical].output) == stream, "existing .ogg alias shares the canonical PCM resource: " + canonical)
		check(AUDIO.is_stereo(stream) == (channels == 2), "audio routing reads preserved channel layout: " + canonical)
	check(total_pcm == 7442462 and total_pcm <= EXTENSIONS.MAX_IMPACT_PCM, "all imported PCM occupies the measured7,442,462-byte budget")
	check(EXTENSIONS._impact_pcm_streams.size() == manifest.files.size(), "only the curated successfully loaded streams are retained")
	_check_override_precedence()
	_check_legacy_fallback(manifest)
	EXTENSIONS.clear()
	check(EXTENSIONS._impact_pcm_streams.is_empty() and EXTENSIONS._impact_pcm_files.is_empty(), "explicit clear releases PCM resources and manifest state")
	check(EXTENSIONS.sound(TARGET) is AudioStreamWAV, "clear reloads the bundled resource on the next lookup")
	EXTENSIONS.clear()
	_finish()

func _check_override_precedence() -> void:
	var native: AudioStream = EXTENSIONS.sound(TARGET)
	var probe: WeakRef = weakref(native)
	native = null
	check(probe.get_ref() != null and EXTENSIONS.sound(ALIAS) == probe.get_ref(), "strong bounded cache survives release of the caller reference")
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(ROOT + "sounds/Feedback/Alert.ogg")
	var loaded: Dictionary = EXTENSIONS.load_pack_bytes(_pack("impact-pcm-first", bytes))
	check(loaded.ok, "valid uploaded Vorbis override targets the original Opus key")
	var first: AudioStream = EXTENSIONS.sound(ALIAS)
	check(first is AudioStreamOggVorbis and first != probe.get_ref(), "active ZIP override wins over an already cached PCM resource")
	check(EXTENSIONS.sound(TARGET) == first, "canonical and legacy alias resolve to the same override")
	loaded = EXTENSIONS.load_pack_bytes(_pack("impact-pcm-second", bytes))
	check(loaded.ok, "a second active sound override loads")
	var second: AudioStream = EXTENSIONS.sound(TARGET)
	check(second is AudioStreamOggVorbis and second != first, "newest active sound override wins")
	check(EXTENSIONS.remove_pack("impact-pcm-second") and EXTENSIONS.sound(ALIAS) == first, "removing newest pack restores the previous sound")
	check(EXTENSIONS.remove_pack("impact-pcm-first") and EXTENSIONS.sound(TARGET) == probe.get_ref(), "removing all overrides restores the cached native PCM")

func _check_legacy_fallback(manifest: Dictionary) -> void:
	var legacy: AudioStream = load(ALIAS) as AudioStream
	check(legacy is AudioStreamOggVorbis, "legacy catalog output remains independently loadable")
	var invalid: Array[Variant] = [null, {}, {"format":"wrong","files":manifest.files}, {"format":"blockfield-impact-pcm-v1","files":42}]
	for change: Dictionary in [{"output":"../outside.wav"}, {"output":"sounds/Feedback/Alert.ogg"}, {"channels":3}, {"mix_rate":44100}, {"frames":1.5}, {"frames":EXTENSIONS.MAX_IMPACT_PCM}, {"pcm_sha256":"invalid"}]:
		var malformed: Dictionary = manifest.duplicate(true)
		malformed.files[TARGET].merge(change, true)
		invalid.append(malformed)
	for index: int in range(invalid.size()):
		_use_manifest(invalid[index])
		check(EXTENSIONS._impact_pcm_files.is_empty() and EXTENSIONS.sound(TARGET) == legacy and EXTENSIONS.sound(ALIAS) == legacy, "malformed/missing PCM manifest falls back to the original catalog: %d" % index)
	var missing: Dictionary = manifest.duplicate(true)
	missing.files[TARGET].output = "impact_pcm/Weapons/SMG/missing-fixture.wav"
	_use_manifest(missing)
	check(EXTENSIONS.sound(ALIAS) == legacy and EXTENSIONS.sound(TARGET) == legacy, "missing listed WAV falls back for both public aliases")
	check(EXTENSIONS._impact_pcm_streams.has(TARGET) and EXTENSIONS._impact_pcm_streams[TARGET] == null, "failed listed resource is remembered without retaining decoded data")
	var mismatched: Dictionary = manifest.duplicate(true)
	mismatched.files[TARGET].frames += 1
	_use_manifest(mismatched)
	check(EXTENSIONS.sound(TARGET) == legacy, "imported frame-count disagreement falls back to legacy audio")
	_use_manifest(manifest)
	check(EXTENSIONS.sound("Sounds/Feedback/Alert.opus") is AudioStreamOggVorbis, "unlisted bundled audio keeps the original Vorbis path")
	check(EXTENSIONS.sound("Sounds/Unknown/Missing.opus") == null, "unknown virtual resources do not enter the PCM whitelist")

func _use_manifest(manifest: Variant) -> void:
	# Simulate a missing/malformed packaged manifest without changing asset files.
	EXTENSIONS._impact_pcm_files = EXTENSIONS._validate_impact_pcm_manifest(manifest)
	EXTENSIONS._impact_pcm_streams.clear()
	EXTENSIONS._impact_pcm_loaded = true

func _pack(id: String, payload: PackedByteArray) -> PackedByteArray:
	var path: String = "user://impact-pcm-fixture.zip"
	var manifest: Dictionary = {"version":1,"id":id,"title":"Original sound override fixture",
		"authors":["OpenSpades authors; see bundled licenses"],"license":"Original bundled licenses apply",
		"assets":{TARGET:{"file":"alert.ogg","type":"sound","sha256":EXTENSIONS._sha256(payload)}}}
	var writer: ZIPPacker = ZIPPacker.new()
	writer.open(path)
	writer.start_file("blockfield-pack.json")
	writer.write_file(JSON.stringify(manifest).to_utf8_buffer())
	writer.close_file()
	writer.start_file("alert.ogg")
	writer.write_file(payload)
	writer.close_file()
	writer.close()
	var result: PackedByteArray = FileAccess.get_file_as_bytes(path)
	DirAccess.remove_absolute(path)
	return result

func _finish() -> void:
	print("IMPACT PCM: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
