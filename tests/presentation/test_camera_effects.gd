extends SceneTree
## Numeric native fixtures; no upstream checkout or graphics context required.
const CAMERA = preload("res://presentation/source_camera_effects.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("SOURCE CAMERA: " + message)

func near(a: float, b: float, tolerance: float = 0.000001) -> bool:
	return absf(a - b) <= tolerance

func _run() -> void:
	var camera: RefCounted = CAMERA.new(7341)
	var neutral: Dictionary = camera.sample({}, 10.0, 0.016)
	check(neutral.basis_delta.is_equal_approx(Basis.IDENTITY) and neutral.rotation_delta.is_equal_approx(Vector3.ZERO), "idle native camera must remain unrotated")
	check(neutral.fov_scale == 1.0 and neutral.radial_blur_strength == 0.0, "idle native FOV/radial blur must remain unchanged")
	var fire_input: Dictionary = {"shake_level":1,"last_fire_time":9.95,"random_values":[0.8,0.2,0.5]}
	var fire: Dictionary = camera.sample(fire_input, 10.0, 0.016)
	check(near(fire.fire_vibration, 0.25), "100 ms linear fire envelope must be squared at50 ms")
	check(fire.native_angles.distance_to(Vector3(0.001875,0.001,0.0045)) < 0.000001, "source fire pitch/yaw/roll numeric golden")
	check(near(fire.fov_scale,1.005) and near(fire.radial_blur_strength,0.0125), "source fire random tangent-FOV and radial blur numeric golden")
	var expired: Dictionary = camera.sample(fire_input, 10.06)
	check(expired.fire_vibration == 0.0 and expired.radial_blur_strength == 0.0, "fire vibration ends after native100 ms window")
	var future: Dictionary = camera.sample({"last_fire_time":10.01,"random_values":[0.5,0.5,0.0]},10.0)
	check(near(future.fire_vibration,1.21) and future.native_angles.x < 0.0, "source fire envelope has only a lower clamp, including future timestamps")
	var spade: Dictionary = camera.sample({"shake_level":1,"last_fire_time":10.0,"tool":0,"random_values":[0.8,0.2,0.5]},10.0)
	check(near(spade.fire_vibration,0.4), "spade multiplies the already squared fire envelope by0.4")
	check(spade.native_angles.distance_to(Vector3(0.0024,0.0005877852522924732,0.0072)) < 0.000001, "source spade angular numeric golden")
	check(near(spade.fov_scale,1.008) and near(spade.radial_blur_strength,0.02), "spade FOV/radial numeric golden")
	var sprint_input: Dictionary = {"shake_level":1,"raw_sprint":0.4,"walk_phase":0.125,"random_values":[0.5,0.5,0.0]}
	var sprint: Dictionary = camera.sample(sprint_input,10.0)
	check(near(sprint.sprint_blend,0.352), "raw sprint uses native cubic SmoothStep exactly once")
	check(sprint.native_angles.distance_to(Vector3(0.00022,0.002489015869776647,-0.0012445079348883236)) < 0.000001, "level1 sprint uses sine yaw/roll and cos^8 pitch")
	check(sprint.fov_scale == 1.0, "level1 sprint must not widen FOV or add coherent noise")
	sprint_input.shake_level = 2
	sprint_input.sprint_noise = Vector3(0.2,-0.3,0.5)
	var sprint_high: Dictionary = camera.sample(sprint_input,10.0)
	check(sprint_high.native_angles.distance_to(Vector3(-0.000836,0.002841015869776647,0.0001634920651116764)) < 0.000001, "level2 native sprint coherent coefficient golden")
	check(near(sprint_high.fov_scale,1.0352), "level2 sprint widens tangent FOV by SmoothStep(sprint)*0.1")
	var combined_input: Dictionary = {
		"shake_level":2,"first_person":true,"raw_ads":1.0,"ads_zoom_scale":2.4,
		"raw_sprint":0.4,"walk_phase":0.125,"last_fire_time":9.95,"tool":2,
		"grenade_fast":0.04,"grenade_slow":0.1,
		"random_values":[0.8,0.2,0.5,0.9,0.1,0.7,0.4,0.6,0.2,0.1,0.9],
		"sprint_noise":Vector3(0.2,-0.3,0.5),"grenade_noise":Vector3(-0.25,0.5,-0.75)
	}
	var original_input: Dictionary = combined_input.duplicate(true)
	var combined: Dictionary = camera.sample(combined_input,10.0,0.9)
	check(combined_input == original_input, "sampling must not mutate authoritative/presentation input or decay intensities")
	var same_sample: Dictionary = camera.sample(combined_input,10.0,0.0)
	check(same_sample.basis_delta.is_equal_approx(combined.basis_delta) and same_sample.fov_scale == combined.fov_scale, "sample dt must not decay intensities a second time")
	check(combined.native_angles.distance_to(Vector3(0.021039,0.007841015869776646,0.06066349206511169)) < 0.000001, "combined native fire/sprint/fast/slow angle golden")
	check(near(combined.native_fov_scale,0.4654166666666667) and near(combined.fov_scale,1.117), "native ADS divide precedes fast grenade additive FOV")
	check(near(combined.radial_blur_strength,0.0525), "native fire plus fast grenade radial blur golden")
	check(near(combined.grenade_fast_scaled,0.4) and near(combined.grenade_slow_scaled,0.16), "grenade fast multiplies10 while slow multiplies4 then squares")
	# Independent native axis-update golden converted to Godot right/up/back.
	var golden_basis: Basis = Basis(
		Vector3(0.9981198500145344,-0.060789077527612076,0.007839200233786599),
		Vector3(0.06061287406840423,0.9979396300790087,0.02103744791887063),
		Vector3(-0.009101895633943605,-0.02052273790490422,0.9997479545989356))
	check(combined.basis_delta.is_equal_approx(golden_basis), "basis must preserve native roll→pitch→yaw composition and mapped signs")
	check(Basis.from_euler(combined.rotation_delta,EULER_ORDER_YXZ).is_equal_approx(golden_basis), "diagnostic Godot local Euler must reconstruct canonical basis")
	check(near(combined.basis_delta.determinant(),1.0), "shake basis remains a proper rotation with no scaling/reflection")
	var owner_basis: Basis = Basis.from_euler(Vector3(0.4,1.1,-0.2))
	check((owner_basis * combined.basis_delta).is_equal_approx(owner_basis * golden_basis), "local matrix application preserves an already yawed/pitched owner pose")
	var zoomed_fov: float = CAMERA.apply_fov_degrees(68.0,1.0/2.4)
	check(near(CAMERA.apply_fov_degrees(zoomed_fov,combined.fov_scale),34.85701534538887,0.00001), "native68-degree ADS+shake FOV numeric golden")
	check(near(CAMERA.apply_fov_degrees(68.0,combined.native_fov_scale),34.85701534538887,0.00001), "already zoomed and native complete tangent multipliers produce the same FOV")
	combined_input.raw_ads = 0.0
	var raw_ads_only: Dictionary = camera.sample(combined_input,10.0)
	check(raw_ads_only.basis_delta.is_equal_approx(combined.basis_delta) and near(raw_ads_only.fov_scale,combined.fov_scale), "raw ADS must not resmooth or duplicate owner-provided zoom")
	combined_input.shake_level = 0
	var disabled: Dictionary = camera.sample(combined_input,10.0)
	check(disabled.basis_delta.is_equal_approx(Basis.IDENTITY) and disabled.fov_scale == 1.0 and disabled.radial_blur_strength == 0.0, "native shake level0 disables all camera shake channels")
	combined_input.shake_level = 1
	combined_input.grenade_fast = 0.0
	var slow_low: Dictionary = camera.sample(combined_input,10.0)
	check(slow_low.grenade_slow_scaled == 0.0, "slow grenade coherence is restricted to level2")
	var third: Dictionary = camera.sample({"first_person":false,"shake_level":2,"last_fire_time":10.0,"raw_sprint":1.0},10.0)
	check(third.basis_delta.is_equal_approx(Basis.IDENTITY) and third.fov_scale == 1.0, "third/free cameras omit fire and sprint effects")
	var grenade: Dictionary = camera.sample({"first_person":false,"shake_level":1,"grenade_fast":0.4,"random_values":[0.9,0.1,0.7,0.4,0.6,0.2,0.1,0.9]},10.0)
	check(grenade.native_angles.distance_to(Vector3(0.03,0.04,0.16)) < 0.000001 and near(grenade.fov_scale,1.08) and near(grenade.radial_blur_strength,0.1), "fast grenade affects non-first-person cameras and clamps scaled intensity at1")
	var max_slow: Dictionary = camera.sample({"first_person":false,"shake_level":2,"grenade_slow":1.0,"grenade_noise":Vector3(-0.25,0.5,-0.75)},10.0)
	check(max_slow.native_angles.distance_to(Vector3(0.05,-0.075,-0.05)) < 0.000001 and max_slow.grenade_slow_scaled == 1.0, "source slow intensity upper clamp applies before squaring")
	check(max_slow.fov_scale == 1.0 and max_slow.radial_blur_strength == 0.0, "slow coherent grenade changes neither FOV nor radial blur")
	var decay_input: Dictionary = {"grenade_fast":0.04,"grenade_slow":0.4}
	var decayed: Dictionary = CAMERA.decay_intensities(decay_input,0.1)
	check(decayed.grenade_fast == 0.0 and near(decayed.grenade_slow,0.3), "native per-second intensity decay clamps only at zero")
	check(decay_input.grenade_fast == 0.04 and decay_input.grenade_slow == 0.4, "separate decay helper must not mutate its input")
	var values: PackedFloat32Array = PackedFloat32Array()
	var derivatives: PackedFloat32Array = PackedFloat32Array()
	values.resize(1024)
	derivatives.resize(1024)
	values[0] = 0.2
	values[1] = -0.4
	values[1023] = 0.5
	derivatives[0] = 1.2
	derivatives[1] = -0.8
	derivatives[1023] = -1.0
	check(camera.set_noise_tables(0,values,derivatives), "native1024-entry noise fixtures are accepted")
	check(near(camera.sample_noise(0,0.25),0.3125) and near(camera.sample_noise(0,0.75),-0.1375), "native value-plus-gradient cubic noise numeric goldens")
	check(near(camera.sample_noise(0,-0.75),0.25625) and near(camera.sample_noise(0,1024.25),0.3125), "native coherent noise wraps at1024 including negative coordinates")
	camera.set_noise_tables(1,values,derivatives)
	camera.set_noise_tables(2,values,derivatives)
	var native_noise: Dictionary = camera.sample({"first_person":false,"shake_level":2,"grenade_slow":0.1},0.03125)
	check(native_noise.native_angles.distance_to(Vector3(0.0041,0.00441171875,0.01)) < 0.000001, "runtime coherent grenade must sample native axis0/1/2 rates8/12/11")
	var runtime_sprint_input: Dictionary = {"shake_level":2,"raw_sprint":1.0,"walk_phase":0.1,"random_values":[0.5,0.5,0.0]}
	var runtime_sprint: Dictionary = camera.sample(runtime_sprint_input,10.0)
	runtime_sprint_input.sprint_noise = Vector3(0.3125,0.3125,0.3125)
	var expected_sprint: Dictionary = camera.sample(runtime_sprint_input,10.0)
	check(runtime_sprint.basis_delta.is_equal_approx(expected_sprint.basis_delta), "runtime coherent sprint must use walk phase*2.5 rather than world time")
	values[0] = 0.9
	check(near(camera.sample_noise(0,0.0),0.2), "injected noise table contents are copied rather than externally mutated")
	check(not camera.set_noise_tables(3,values,derivatives) and not camera.set_noise_tables(0,PackedFloat32Array([1]),derivatives), "invalid noise axis/table sizes are rejected")
	var same_seed_a: RefCounted = CAMERA.new(9273)
	var same_seed_b: RefCounted = CAMERA.new(9273)
	var random_input: Dictionary = {"last_fire_time":10.0,"shake_level":2,"raw_sprint":0.7,"walk_phase":0.41,"grenade_fast":0.08,"grenade_slow":0.1}
	var seeded_a: Dictionary = same_seed_a.sample(random_input,10.0)
	var seeded_b: Dictionary = same_seed_b.sample(random_input,10.0)
	check(seeded_a.basis_delta.is_equal_approx(seeded_b.basis_delta) and seeded_a.fov_scale == seeded_b.fov_scale, "private seeded native-shaped stochastic effects are reproducible")
	seed(9273)
	var global_expected: float = randf()
	seed(9273)
	same_seed_a.sample(random_input,10.0)
	check(randf() == global_expected, "camera sampling must not consume gameplay/global RNG")
	print("SOURCE CAMERA TESTS: %d assertions, %d failures" % [checks,failures])
	quit(1 if failures else 0)
