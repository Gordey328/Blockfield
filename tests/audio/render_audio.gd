extends SceneTree
## Isolated post-mixer PCM proof. Never loads main or writes user preferences.
## Run with a real audio driver; --headless uses Dummy and is not listening proof.
const AUDIO = preload("res://audio/openspades_audio.gd")
const BUS := "OpenSpadesPCMProof"
const OUTPUT := "res://../.cache/previews/audio-pcm"
var checks := 0
var failures := 0
var host: Node3D
var audio: OpenSpadesAudio
var capture: AudioEffectCapture
var bus_index := -1
var master_was_muted := false
var output: String
var results: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("AUDIO_PCM: " + label)

func _run() -> void:
	var driver := AudioServer.get_driver_name()
	output = ProjectSettings.globalize_path(OUTPUT).path_join(driver.to_lower())
	DirAccess.make_dir_recursive_absolute(output)
	print("AUDIO PCM DRIVER: %s; mixer %.0f Hz; speaker mode %d" % [driver, AudioServer.get_mix_rate(), AudioServer.get_speaker_mode()])
	# Prevent brief initial Master-bus output while reassigning service-created
	# voices. The separate muted probe bus still runs its capture effect.
	master_was_muted = AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, true)
	AudioServer.add_bus()
	bus_index = AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(bus_index, BUS)
	AudioServer.set_bus_send(bus_index, "Master")
	capture = AudioEffectCapture.new()
	capture.buffer_length = 3.0
	AudioServer.add_bus_effect(bus_index, capture)
	AudioServer.set_bus_mute(bus_index, true)
	host = Node3D.new()
	root.add_child(host)
	var camera := Camera3D.new()
	host.add_child(camera)
	camera.current = true
	root.audio_listener_enable_3d = true
	audio = AUDIO.new()
	host.add_child(audio)
	audio.setup(null, camera)
	audio._random.seed = 328
	await create_timer(.15).timeout
	var quiet: Dictionary = await record("silence", func(): pass, .15, false)
	check(float(quiet.rms) < .0000001, "probe starts silent")
	for weapon in range(3):
		var name: String = ["rifle", "smg", "shotgun"][weapon]
		await record(name + "_first_person", func(): audio.weapon_fire(weapon, true, Vector3.ZERO, Vector3.ZERO), 1.5)
		await record(name + "_world", func(): audio.weapon_fire(weapon, false, Vector3.ZERO, Vector3(2, 0, -4)), 1.5)
	var head_full: Dictionary = await local_sound("head_feedback_gain_1", "Feedback/HeadshotFeedback", 1.0)
	var head_native: Dictionary = await local_sound("head_feedback_native_gain_02", "Feedback/HeadshotFeedback", .2)
	var gain_ratio := sqrt(float(head_native.energy) / maxf(.000000001, float(head_full.energy)))
	check(absf(gain_ratio - .2) < .012, "head feedback measured PCM amplitude ratio is .2 (+/-6%)")
	for entry: Array in [["chat", "Feedback/Chat"], ["menu_hover", "Feedback/Limbo/Hover"], ["menu_select", "Feedback/Limbo/Select"], ["alert", "Feedback/Alert"]]:
		await local_sound(str(entry[0]), str(entry[1]), 1.0)
	var mono: Dictionary = await record("mono_center", func(): audio.play_spatial("Weapons/DryFire", Vector3(0, 0, -3), 1.0, 3.0), .5)
	check(float(mono.difference_rms) < float(mono.rms) * .01, "centered mono has equal mixed stereo channels")
	var left: Dictionary = await record("mono_left", func(): audio.play_spatial("Weapons/DryFire", Vector3(-3, 0, -3), 1.0, 5.0), .5)
	var right: Dictionary = await record("mono_right", func(): audio.play_spatial("Weapons/DryFire", Vector3(3, 0, -3), 1.0, 5.0), .5)
	check(float(left.left_rms) > float(left.right_rms) * 1.25, "world mono left position changes actual channel balance")
	check(float(right.right_rms) > float(right.left_rms) * 1.25, "world mono right position changes actual channel balance")
	var left_balance := float(left.left_rms) / maxf(.000000001, float(left.right_rms))
	var right_balance := float(right.right_rms) / maxf(.000000001, float(right.left_rms))
	check(absf(left_balance / right_balance - 1.0) < .08, "opposite spatial positions produce mirrored balance (+/-8%)")
	var stereo: Dictionary = await local_sound("original_stereo_local", "Weapons/Rifle/FireStereo", 1.0)
	check(float(stereo.difference_rms) > float(stereo.rms) * .05, "original stereo retains distinct left/right PCM")
	var distance_near: Dictionary = await record("distance_near", func(): audio.play_spatial("Weapons/DryFire", Vector3(0, 0, -2), 1.0, 2.0), .5)
	var distance_far: Dictionary = await record("distance_far", func(): audio.play_spatial("Weapons/DryFire", Vector3(0, 0, -8), 1.0, 2.0), .5)
	var distance_ratio := sqrt(float(distance_far.energy) / maxf(.000000001, float(distance_near.energy)))
	check(absf(distance_ratio - .25) < .015, "actual world PCM at 8m/2m retains quarter amplitude (+/-6%)")
	var disabled: Dictionary = await record("muted_bus_capture_disabled", func():
		AudioServer.set_bus_effect_enabled(bus_index, 0, false)
		audio.play_local("Feedback/Chat"), .5, false)
	check(int(disabled.frames) == 0, "disabling capture yields no frames despite real playback")
	AudioServer.set_bus_effect_enabled(bus_index, 0, true)
	var report := {"engine": Engine.get_version_info().string, "driver": driver, "mix_rate": AudioServer.get_mix_rate(), "checks": checks, "failures": failures, "head_feedback_amplitude_ratio": gain_ratio, "distance_amplitude_ratio": distance_ratio, "results": results, "browser_listening_verified": false, "wav_format": "stereo signed PCM16; per-file scale is reported, raw metrics are unscaled"}
	var json := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	check(json != null, "PCM report can be saved")
	if json != null:
		report.checks = checks
		report.failures = failures
		json.store_string(JSON.stringify(report, "\t"))
		json.close()
	await finish()

func local_sound(name: String, path: String, gain: float) -> Dictionary:
	var stream := OpenSpadesExtensions.sound("res://assets/openspades/sounds/" + path + ".ogg")
	check(stream != null, name + " original imported resource loads")
	var duration := maxf(.5, stream.get_length() + .2) if stream != null else .5
	return await record(name, func(): audio.play_local(path, gain), duration)

func record(name: String, play: Callable, seconds: float, expect_sound: bool = true) -> Dictionary:
	audio.stop()
	await create_timer(.15).timeout
	capture.clear_buffer()
	var discarded_before := capture.get_discarded_frames()
	play.call()
	# These are the real service's voices, not a copied routing implementation.
	# Replay after selecting the bus so initial mixer scheduling cannot lose the
	# attack. Master and probe remain muted: this acceptance process is silent.
	for voice: Node in audio._voices:
		voice.stop()
		voice.bus = BUS
		voice.play()
	var frames := PackedVector2Array()
	var end_time := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end_time:
		await create_timer(.02).timeout
		var count := capture.get_frames_available()
		if count > 0:
			frames.append_array(capture.get_buffer(count))
	var remaining := capture.get_frames_available()
	if remaining > 0:
		frames.append_array(capture.get_buffer(remaining))
	var metrics := measure(frames)
	metrics.name = name
	metrics.window_seconds = seconds
	metrics.discarded_frames = capture.get_discarded_frames() - discarded_before
	if expect_sound:
		check(frames.size() > int(AudioServer.get_mix_rate() * seconds * .6), name + " captured live mixer frames")
		check(bool(metrics.finite), name + " all mixed samples are finite")
		check(float(metrics.rms) > .00001 and int(metrics.nonzero_frames) > 64, name + " mixed PCM contains audible energy")
		check(float(metrics.left_rms) > .00001 and float(metrics.right_rms) > .00001, name + " both output channels contain signal")
		check(int(metrics.discarded_frames) == 0, name + " capture ring buffer does not overflow")
	var scale := .95 / maxf(1.0, float(metrics.peak))
	metrics.wav_scale = scale
	if not frames.is_empty():
		check(write_wav(output.path_join(name + ".wav"), frames, scale), name + " review WAV is saved")
	results.append(metrics)
	print("PCM %s: frames=%d rms=%.7f L=%.7f R=%.7f peak=%.5f scale=%.5f" % [name, frames.size(), metrics.rms, metrics.left_rms, metrics.right_rms, metrics.peak, scale])
	return metrics

func measure(frames: PackedVector2Array) -> Dictionary:
	var left := 0.0
	var right := 0.0
	var difference := 0.0
	var peak := 0.0
	var nonzero := 0
	var finite := true
	for sample: Vector2 in frames:
		if not is_finite(sample.x) or not is_finite(sample.y):
			finite = false
			continue
		left += float(sample.x) * sample.x
		right += float(sample.y) * sample.y
		difference += float(sample.x - sample.y) * (sample.x - sample.y)
		peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
		if absf(sample.x) > .0000001 or absf(sample.y) > .0000001:
			nonzero += 1
	var count := maxf(1.0, frames.size())
	return {"frames": frames.size(), "nonzero_frames": nonzero, "finite": finite, "energy": left + right, "left_rms": sqrt(left / count), "right_rms": sqrt(right / count), "rms": sqrt((left + right) / (2.0 * count)), "difference_rms": sqrt(difference / count), "peak": peak}

func write_wav(path: String, frames: PackedVector2Array, scale: float) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	var rate := int(AudioServer.get_mix_rate())
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36 + frames.size() * 4)
	file.store_buffer("WAVEfmt ".to_ascii_buffer())
	file.store_32(16)
	file.store_16(1) # PCM
	file.store_16(2) # Stereo
	file.store_32(rate)
	file.store_32(rate * 4)
	file.store_16(4)
	file.store_16(16)
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(frames.size() * 4)
	for sample: Vector2 in frames:
		file.store_16(int(round(clampf(sample.x * scale, -1, 1) * 32767)) & 0xffff)
		file.store_16(int(round(clampf(sample.y * scale, -1, 1) * 32767)) & 0xffff)
	file.close()
	return true

func finish() -> void:
	audio.stop()
	host.queue_free()
	await process_frame
	await process_frame
	await create_timer(.2).timeout
	AudioServer.remove_bus_effect(bus_index, 0)
	AudioServer.remove_bus(bus_index)
	capture = null
	AudioServer.set_bus_mute(0, master_was_muted)
	print("AUDIO PCM: %d checks, %d failures; artifacts %s" % [checks, failures, output])
	quit(1 if failures else 0)
