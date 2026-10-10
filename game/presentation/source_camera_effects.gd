class_name SourceCameraEffects
extends RefCounted
## Native camera presentation: Client_Scene.cpp:111..119,201..247,384..440.
## Sampling changes no gameplay/view target state. Input grenade intensities are
## already decayed by the owner; dt is accepted for the shared per-frame contract.

const NOISE_SIZE: int = 1024
const NOISE_MASK: int = NOISE_SIZE - 1
const SPADE_TOOL: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _values: Array[PackedFloat32Array] = []
var _derivatives: Array[PackedFloat32Array] = []

func _init(seed_value: int = 7341) -> void:
	reset_noise(seed_value)

func reset_noise(seed_value: int) -> void:
	# This private stream cannot change gameplay pellet/grenade randomness.
	_rng.seed = seed_value
	_values.clear()
	_derivatives.clear()
	for axis: int in range(3):
		var values: PackedFloat32Array = PackedFloat32Array()
		var derivatives: PackedFloat32Array = PackedFloat32Array()
		values.resize(NOISE_SIZE)
		derivatives.resize(NOISE_SIZE)
		# C++ constructs its gradient member before filling value samples.
		for index: int in range(NOISE_SIZE):
			derivatives[index] = (_rng.randf() - _rng.randf()) * 4.0
		for index: int in range(NOISE_SIZE):
			values[index] = _rng.randf() - _rng.randf()
		_values.append(values)
		_derivatives.append(derivatives)

func set_noise_tables(axis: int, values: PackedFloat32Array, derivatives: PackedFloat32Array) -> bool:
	# Deterministic fixtures may supply the actual native table contents.
	if axis < 0 or axis >= 3 or values.size() != NOISE_SIZE or derivatives.size() != NOISE_SIZE:
		return false
	_values[axis] = values.duplicate()
	_derivatives[axis] = derivatives.duplicate()
	return true

func sample_noise(axis: int, coordinate: float) -> float:
	# NoiseSampler.cpp:38..83: smooth value interpolation + cubic gradient.
	if axis < 0 or axis >= 3 or not is_finite(coordinate):
		return 0.0
	var wrapped: float = coordinate / float(NOISE_SIZE)
	wrapped = (wrapped - floorf(wrapped)) * float(NOISE_SIZE)
	var integer: int = floori(wrapped)
	var fraction: float = wrapped - floorf(wrapped)
	var next: int = (integer + 1) & NOISE_MASK
	integer &= NOISE_MASK
	var smooth: float = fraction * fraction * (3.0 - 2.0 * fraction)
	var value: float = lerpf(_values[axis][integer], _values[axis][next], smooth)
	var gradient: float = (_derivatives[axis][integer] * (1.0 - fraction) - _derivatives[axis][next] * fraction) * fraction * (1.0 - fraction)
	return value + gradient

func _random_at(values: Variant, index: int) -> float:
	if values != null and index < values.size():
		return float(values[index])
	return _rng.randf()

func sample(input: Dictionary, time: float, _dt: float = 0.0) -> Dictionary:
	var shake_level: int = clampi(int(input.get("shake_level", 1)), 0, 2)
	var first_person: bool = bool(input.get("first_person", true))
	var ads: float = clampf(float(input.get("raw_ads", 0.0)), 0.0, 1.0)
	var sprint: float = clampf(float(input.get("raw_sprint", 0.0)), 0.0, 1.0)
	var walk: float = float(input.get("walk_phase", 0.0))
	# Root owns local/follow ADS zoom. Effects scale is applied to its already
	# zoomed tangent, preserving native grenade addition AFTER the ADS divide.
	var ads_zoom: float = maxf(float(input.get("ads_zoom_scale", 1.0)), 0.000001)
	var random_values: Variant = input.get("random_values", null)
	var random_index: int = 0
	var pitch: float = 0.0
	var yaw: float = 0.0
	var roll: float = 0.0
	var before_ads_scale: float = 1.0
	var after_ads_delta: float = 0.0
	var radial_blur: float = 0.0
	var fire: float = 0.0
	var sprint_blend: float = 0.0
	var fast: float = 0.0
	var slow: float = 0.0
	if first_person and shake_level >= 1:
		# Source applies only a lower clamp. Future timestamps intentionally
		# retain the source's >1 result rather than silently changing the math.
		fire = maxf(0.0, 1.0 - (time - float(input.get("last_fire_time", -1.0e20))) / 0.1)
		fire *= fire
		if int(input.get("tool", 2)) == SPADE_TOOL:
			fire *= 0.4
		roll += (_random_at(random_values, random_index) - _random_at(random_values, random_index + 1)) * 0.03 * fire
		before_ads_scale += _random_at(random_values, random_index + 2) * 0.04 * fire
		random_index += 3
		pitch += fire * (1.0 - fire) * 0.01
		yaw += sin(fire * TAU) * 0.001
		radial_blur += fire * 0.05
		sprint_blend = sprint * sprint * (3.0 - 2.0 * sprint)
		var phase: float = walk * TAU
		yaw += sin(phase) * 0.01 * sprint_blend
		roll -= sin(phase) * 0.005 * sprint_blend
		# Repeated squaring reproduces source cos^8, not the separate cos^16 eye bob.
		var pulse: float = cos(phase)
		pulse *= pulse
		pulse *= pulse
		pulse *= pulse
		pitch += pulse * 0.01 * sprint_blend
		if shake_level >= 2:
			var sprint_noise: Vector3 = input.get("sprint_noise", Vector3(sample_noise(0, walk * 2.5), sample_noise(1, walk * 2.5), sample_noise(2, walk * 2.5)))
			yaw += sprint_noise.x * 0.005 * sprint_blend
			pitch += sprint_noise.y * 0.01 * sprint_blend
			roll += sprint_noise.z * 0.008 * sprint_blend
			before_ads_scale += sprint_blend * 0.1
	var grenade_fast: float = float(input.get("grenade_fast", 0.0))
	if grenade_fast > 0.0 and shake_level >= 1:
		fast = minf(grenade_fast * 10.0, 1.0)
		roll += (_random_at(random_values, random_index) - _random_at(random_values, random_index + 1)) * 0.2 * fast
		pitch += (_random_at(random_values, random_index + 2) - _random_at(random_values, random_index + 3)) * 0.1 * fast
		yaw += (_random_at(random_values, random_index + 4) - _random_at(random_values, random_index + 5)) * 0.1 * fast
		after_ads_delta -= (_random_at(random_values, random_index + 6) - _random_at(random_values, random_index + 7)) * 0.1 * fast
		radial_blur += fast * 0.1
	var grenade_slow: float = float(input.get("grenade_slow", 0.0))
	if grenade_slow > 0.0 and shake_level >= 2:
		slow = minf(grenade_slow * 4.0, 1.0)
		slow *= slow
		var grenade_noise: Vector3 = input.get("grenade_noise", Vector3(sample_noise(0, time * 8.0), sample_noise(1, time * 12.0), sample_noise(2, time * 11.0)))
		roll += grenade_noise.x * 0.2 * slow
		pitch += grenade_noise.y * 0.1 * slow
		yaw += grenade_noise.z * 0.1 * slow
	# Native right/up/forward updates are local roll, then pitch, then yaw.
	# Godot camera Z points backwards: source roll/yaw signs invert.
	var basis_delta: Basis = Basis(Vector3.BACK, -roll) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.UP, -yaw)
	var native_scale: float = before_ads_scale / ads_zoom + after_ads_delta
	return {
		"basis_delta": basis_delta,
		"rotation_delta": basis_delta.get_euler(EULER_ORDER_YXZ),
		"fov_scale": native_scale * ads_zoom,
		"radial_blur_strength": radial_blur,
		"native_angles": Vector3(pitch, yaw, roll),
		"native_fov_scale": native_scale,
		"fire_vibration": fire,
		"sprint_blend": sprint_blend,
		"grenade_fast_scaled": fast,
		"grenade_slow_scaled": slow,
		"raw_ads": ads,
		"ads_zoom_scale": ads_zoom
	}

static func decay_intensities(input: Dictionary, dt: float) -> Dictionary:
	# Client_Update.cpp:248..258. Call once in the owner BEFORE sample(), or
	# retain the existing effects manager's equivalent decay. Never call both.
	return {
		"grenade_fast": maxf(0.0, float(input.get("grenade_fast", 0.0)) - maxf(dt, 0.0)),
		"grenade_slow": maxf(0.0, float(input.get("grenade_slow", 0.0)) - maxf(dt, 0.0))
	}

static func apply_fov_degrees(zoomed_fov_degrees: float, fov_scale: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(zoomed_fov_degrees) * 0.5) * fov_scale))
