class_name SpectralWaveField
extends Node
## Native FFTWaveTank spectrum/encoding, truncated to 32 strongest modes.
## GPU inverse sum avoids a per-frame CPU FFT in single-thread browser builds.
const SHADER = preload("res://world/spectral_wave.gdshader")
const SIZE := 128
const MODE_COUNT := 32
const TIME_SCALES := [1.0, 0.15704 / 0.08, 0.02344 / 0.08]
var elapsed := 0.0
var animated := true
var _frequencies: Array[PackedVector2Array] = []
var _matrices: Array[PackedVector4Array] = []
var _phases: Array[PackedFloat64Array] = []
var _viewports: Array[SubViewport] = []
var _materials: Array[ShaderMaterial] = []

static func magnitude(distance: float) -> float:
	if distance <= 0.0:
		return 0.0
	return 0.8 / (distance * distance * SIZE) * exp(-pow(distance / (SIZE * 0.5), 2.0) * 3.0)

static func angular_speed(distance: float) -> float:
	return TAU * distance * 1.0e9 * 128.0 / SIZE / 4294967296.0

func setup(layers: int = 1, seed_value: int = 1337) -> void:
	assert(_viewports.is_empty(), "Wave field setup must be called once")
	var candidates: Array[Vector2] = []
	for y in range(9):
		for x in range(-8, 9):
			if x != 0 or y != 0:
				candidates.append(Vector2(x, y))
	candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		if not is_equal_approx(a.length_squared(), b.length_squared()):
			return a.length_squared() < b.length_squared()
		return a.y < b.y if a.y != b.y else a.x < b.x)
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	for layer in range(clampi(layers, 1, 3)):
		var frequencies := PackedVector2Array()
		var matrices := PackedVector4Array()
		var phases := PackedFloat64Array()
		for index in range(MODE_COUNT):
			frequencies.append(candidates[index])
			matrices.append(Vector4(random.randf() - random.randf(), random.randf() - random.randf(), random.randf() - random.randf(), random.randf() - random.randf()))
			phases.append(random.randf() * TAU)
		_frequencies.append(frequencies)
		_matrices.append(matrices)
		_phases.append(phases)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(SIZE, SIZE)
		viewport.disable_3d = true
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var material := ShaderMaterial.new()
		material.shader = SHADER
		var rectangle := ColorRect.new()
		rectangle.size = Vector2(SIZE, SIZE)
		rectangle.material = material
		viewport.add_child(rectangle)
		add_child(viewport)
		_viewports.append(viewport)
		_materials.append(material)
	set_time(0.0)

func _process(delta: float) -> void:
	if animated:
		set_time(elapsed + delta)

func set_time(seconds: float) -> void:
	elapsed = seconds
	for layer in range(_materials.size()):
		_materials[layer].set_shader_parameter("modes", coefficients(layer, seconds))

func coefficients(layer: int, seconds: float) -> PackedVector4Array:
	var result := PackedVector4Array()
	for index in range(MODE_COUNT):
		var frequency := _frequencies[layer][index]
		var phase: float = _phases[layer][index] + angular_speed(frequency.length()) * seconds * TIME_SCALES[layer]
		# Original SinCosTable discards the low 16 bits of the uint32 phase.
		phase = floor(posmod(phase, TAU) / TAU * 65536.0) * TAU / 65536.0
		var c := cos(phase)
		var s := sin(phase)
		var matrix := _matrices[layer][index]
		var scale := magnitude(frequency.length()) * (2.0 if frequency.y > 0 else 1.0)
		result.append(Vector4(frequency.x, frequency.y, (c * matrix.x + s * matrix.y) * scale, (c * matrix.z + s * matrix.w) * scale))
	return result

func sample_cpu(uv: Vector2, seconds: float = 0.0, layer: int = 0) -> Vector3:
	var value := Vector3.ZERO
	for mode in coefficients(layer, seconds):
		var angle := TAU * Vector2(mode.x, mode.y).dot(uv)
		var c := cos(angle)
		var s := sin(angle)
		value.z += mode.z * c - mode.w * s
		value.x -= 2.0 * sin(TAU * mode.x / SIZE) * (mode.z * s + mode.w * c)
		value.y -= 2.0 * sin(TAU * mode.y / SIZE) * (mode.z * s + mode.w * c)
	return value

func get_texture(layer: int = 0) -> Texture2D:
	return _viewports[layer].get_texture()

func set_enabled(enabled: bool) -> void:
	set_process(enabled)
	for viewport in _viewports:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED

func get_stats() -> Dictionary:
	return {"layers": _viewports.size(), "modes_per_layer": MODE_COUNT, "texture_size": SIZE, "texture_bytes": SIZE * SIZE * 4 * _viewports.size(), "native_full_fft": false}
