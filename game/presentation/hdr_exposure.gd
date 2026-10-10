class_name HdrExposure
extends Node
## Source GLAutoExposureFilter + AutoExposure{Preprocess,}.fs, v0.1.3.
## True floating-point textures required. No LDR metering is labelled HDR.

const REDUCE = preload("res://presentation/hdr_reduce.gdshader")
const GAIN = preload("res://presentation/hdr_gain.gdshader")
const PRESENT = preload("res://presentation/hdr_present.gdshader")
const BLOOM = preload("res://presentation/hdr_bloom.gd")
const NORMALIZE = preload("res://presentation/hdr_normalize.gdshader")
const DEFAULTS: Dictionary = {"min_ev":-1.5,"max_ev":0.5,"speed":1.0,"gamma":2.2,"bloom":true}
var enabled: bool = false
var automatic_update: bool = true
var max_meter_size: Vector2i = Vector2i(128,128)
var _options: Dictionary = DEFAULTS.duplicate()
var _source: Texture2D
var _raw_source: Texture2D
var _compatibility_encoded: bool = false
var _normalization: SubViewport
var _normalization_material: ShaderMaterial
var _normalization_bytes: int = 0
var _levels: Array[SubViewport] = []
var _logical_levels: Array[Vector2i] = []
var _gains: Array[SubViewport] = []
var _gain_materials: Array[ShaderMaterial] = []
var _present: ShaderMaterial
var _bloom: Node
var _bloom_dust: Texture2D
var _one: Texture2D
var _gain_texture: Texture2D
var _gain_index: int = 0
var _updates: int = 0
var _estimated_bytes: int = 0

func _init() -> void:
	var image: Image = Image.create(1,1,false,Image.FORMAT_RGBAF)
	image.fill(Color.WHITE)
	_one = ImageTexture.create_from_image(image)
	_gain_texture = _one
	_present = ShaderMaterial.new()
	_present.shader = PRESENT
	_present.set_shader_parameter("gain_texture",_one)
	_present.set_shader_parameter("hdr_enabled",false)
	var dust_image: Image = Image.create(1,1,false,Image.FORMAT_RGBA8)
	dust_image.fill(Color(0.35,0.35,0.35))
	_bloom_dust = ImageTexture.create_from_image(dust_image)
	if ResourceLoader.exists("res://assets/openspades/images/Textures/LensDustTexture.png"):
		_bloom_dust = load("res://assets/openspades/images/Textures/LensDustTexture.png")

func _process(dt: float) -> void:
	if automatic_update and enabled:
		advance(dt)

func setup(source_texture: Texture2D, compatibility_encoded: bool = false) -> void:
	_raw_source = source_texture
	_compatibility_encoded = compatibility_encoded
	_prepare_linear_source()
	_present.set_shader_parameter("scene_texture",_source)
	_build_levels()

func set_source_texture(source_texture: Texture2D, compatibility_encoded: bool = false) -> void:
	setup(source_texture,compatibility_encoded)

func _prepare_linear_source() -> void:
	_normalization_bytes = 0
	_source = _raw_source
	if not _compatibility_encoded or _raw_source == null:
		if _normalization != null:
			remove_child(_normalization)
			_normalization.queue_free()
			_normalization = null
			_normalization_material = null
		return
	if _normalization == null:
		_normalization = SubViewport.new()
		_normalization.disable_3d = true
		_normalization.use_hdr_2d = true
		_normalization.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(_normalization)
		_normalization_material = ShaderMaterial.new()
		_normalization_material.shader = NORMALIZE
		var rect := ColorRect.new()
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.material = _normalization_material
		_normalization.add_child(rect)
	_normalization.size = Vector2i(maxi(2,_raw_source.get_width()),maxi(2,_raw_source.get_height()))
	_normalization.get_child(0).size = Vector2(_normalization.size)
	_normalization_material.set_shader_parameter("source_texture",_raw_source)
	_normalization_bytes = _normalization.size.x*_normalization.size.y*8
	_source = _normalization.get_texture()

func get_linear_texture() -> Texture2D:
	## Shared pre-filter radiance; already-linear inputs are returned unchanged.
	return _source

func set_options(values: Dictionary) -> Dictionary:
	var proposed: Dictionary = _options.duplicate()
	for key: String in values:
		if not DEFAULTS.has(key):
			return {"ok":false,"error":"Unknown HDR option: "+key}
		if key == "bloom":
			if typeof(values[key]) != TYPE_BOOL:
				return {"ok":false,"error":"Expected HDR bloom boolean"}
			proposed[key] = values[key]
			continue
		if typeof(values[key]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(values[key])):
			return {"ok":false,"error":"Expected a finite HDR option: "+key}
		proposed[key] = float(values[key])
	proposed.min_ev = clampf(proposed.min_ev,-10.0,10.0)
	proposed.max_ev = clampf(proposed.max_ev,proposed.min_ev,10.0)
	proposed.speed = maxf(proposed.speed,0.0)
	proposed.gamma = clampf(proposed.gamma,0.1,8.0)
	_options = proposed
	_present.set_shader_parameter("hdr_gamma",_options.gamma)
	_configure_bloom()
	return {"ok":true,"options":_options.duplicate()}

func set_bloom_dust_texture(texture: Texture2D) -> void:
	if texture != null:
		_bloom_dust = texture
		_configure_bloom()

func set_bloom_budget(size: Vector2i, levels: int = 6) -> void:
	if _bloom != null:
		_bloom.set_budget(size,levels)
		_configure_bloom()

func _configure_bloom() -> void:
	if _bloom == null or _source == null:
		return
	_bloom.set_enabled(enabled and _options.bloom)
	var materials: Array[ShaderMaterial] = [_present]
	if not _levels.is_empty():
		materials.append(_levels[0].get_child(0).material)
	for material: ShaderMaterial in materials:
		material.set_shader_parameter("bloom_enabled",enabled and _options.bloom)
		material.set_shader_parameter("bloom_texture",_bloom.get_blur_texture())
		material.set_shader_parameter("bloom_dust_texture",_bloom_dust)
		material.set_shader_parameter("bloom_source_size",Vector2(_source.get_size()))

func set_meter_budget(size: Vector2i) -> void:
	max_meter_size = Vector2i(clampi(size.x,16,512),clampi(size.y,16,512))
	_build_levels()

func _new_target(size: Vector2i, material: ShaderMaterial) -> SubViewport:
	var target: SubViewport = SubViewport.new()
	target.size = Vector2i(maxi(size.x,2),maxi(size.y,2))
	target.disable_3d = true
	target.use_hdr_2d = true
	target.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(target)
	var rect: ColorRect = ColorRect.new()
	rect.size = Vector2(target.size)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = material
	target.add_child(rect)
	_estimated_bytes += target.size.x*target.size.y*8
	return target

func _clear_levels() -> void:
	for target: SubViewport in _levels+_gains:
		remove_child(target)
		target.queue_free()
	_levels.clear()
	_logical_levels.clear()
	_gains.clear()
	_gain_materials.clear()
	_estimated_bytes = 0
	_gain_index = 0
	_gain_texture = _one
	_present.set_shader_parameter("gain_texture",_one)

func _build_levels() -> void:
	_clear_levels()
	if _source == null or _source.get_width() < 1 or _source.get_height() < 1:
		return
	if _bloom == null:
		_bloom = BLOOM.new()
		add_child(_bloom)
	_bloom.setup(_source)
	var previous: Texture2D = _source
	var size: Vector2i = Vector2i(maxi(1,(_source.get_width()+1)/2),maxi(1,(_source.get_height()+1)/2))
	var ratio: float = minf(1.0,minf(float(max_meter_size.x)/size.x,float(max_meter_size.y)/size.y))
	size = Vector2i(maxi(1,ceili(size.x*ratio)),maxi(1,ceili(size.y*ratio)))
	var first: bool = true
	while true:
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = REDUCE
		material.set_shader_parameter("source_texture",previous)
		material.set_shader_parameter("preprocess",first)
		material.set_shader_parameter("logical_size",Vector2(size))
		var target: SubViewport = _new_target(size,material)
		_levels.append(target)
		_logical_levels.append(size)
		previous = target.get_texture()
		if size == Vector2i.ONE:
			break
		size = Vector2i(maxi(1,(size.x+1)/2),maxi(1,(size.y+1)/2))
		first = false
	for index: int in range(2):
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = GAIN
		material.set_shader_parameter("brightness_texture",previous)
		material.set_shader_parameter("previous_gain",_one)
		_gain_materials.append(material)
		_gains.append(_new_target(Vector2i.ONE,material))
	set_enabled(enabled)

func set_enabled(value: bool) -> void:
	enabled = value
	_present.set_shader_parameter("hdr_enabled",enabled)
	# The visible disabled path remains an ordinary encoded scene copy.
	_present.set_shader_parameter("scene_texture",_source if enabled else _raw_source)
	if _normalization != null:
		_normalization.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED
	for target: SubViewport in _levels:
		target.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED
	for target: SubViewport in _gains:
		target.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if not enabled:
		_gain_texture = _one
		_present.set_shader_parameter("gain_texture",_one)
	_configure_bloom()

func advance(dt: float) -> void:
	if not enabled or _gains.is_empty():
		return
	# Remove the inactive pass's old feedback edge before swapping. Keeping
	# both bindings would create a circular viewport dependency in Godot.
	var next: int = 1-_gain_index
	_gains[_gain_index].render_target_update_mode = SubViewport.UPDATE_DISABLED
	_gain_materials[_gain_index].set_shader_parameter("previous_gain",_one)
	var material: ShaderMaterial = _gain_materials[next]
	material.set_shader_parameter("previous_gain",_gain_texture)
	material.set_shader_parameter("min_gain",pow(2.0,_options.min_ev))
	material.set_shader_parameter("max_gain",pow(2.0,_options.max_ev))
	material.set_shader_parameter("adaptation_rate",adaptation_rate(dt,_options.speed))
	_gains[next].render_target_update_mode = SubViewport.UPDATE_ONCE
	_gain_index = next
	_gain_texture = _gains[next].get_texture()
	_present.set_shader_parameter("gain_texture",_gain_texture)
	_updates += 1
	_present.set_shader_parameter("bloom_frame",float(_updates%1024))
	if not _levels.is_empty():
		_levels[0].get_child(0).material.set_shader_parameter("bloom_frame",float(_updates%1024))

func get_gain_texture() -> Texture2D:
	return _gain_texture

func get_present_material() -> ShaderMaterial:
	return _present

func get_stats() -> Dictionary:
	var sizes: Array[Vector2i] = []
	for target: SubViewport in _levels:
		sizes.append(target.size)
	return {"enabled":enabled,"levels":sizes,"logical_levels":_logical_levels.duplicate(),"gain_targets":_gains.size(),"updates":_updates,"color_texture_bytes":_estimated_bytes+_normalization_bytes,"normalization_color_bytes":_normalization_bytes,"normalization_size":_normalization.size if _normalization != null else Vector2i.ZERO,"input_encoding":"compatibility_encoded" if _compatibility_encoded else "linear","meter_budget":max_meter_size,"hdr_required":true,"options":_options.duplicate(),"bloom":_bloom.get_stats() if _bloom != null else {}}

static func preprocess_brightness(color: Color) -> float:
	var brightness: float = maxf(maxf(color.r,color.g),color.b)
	if not (brightness >= 0.0 and brightness <= 16.0):
		brightness = 0.05
	brightness = clampf(brightness,0.05,1.3)
	brightness *= brightness
	return brightness*brightness

static func target_gain(mean_power: float, min_ev: float = -1.5, max_ev: float = 0.5) -> float:
	min_ev = clampf(min_ev,-10.0,10.0)
	max_ev = clampf(max_ev,min_ev,10.0)
	return clampf(0.6/sqrt(sqrt(maxf(mean_power,0.0000001))),pow(2.0,min_ev),pow(2.0,max_ev))

static func adaptation_rate(dt: float, speed: float = 1.0) -> float:
	return 1.0-pow(0.01,maxf(dt,0.0)*maxf(speed,0.0))

static func present_color(color: Color, gain: float, gamma: float = 2.2) -> Color:
	var output: Color = Color.BLACK
	for channel: int in range(3):
		var device: float = pow(maxf(color[channel]*gain,0.0),1.0/gamma)
		var value: float = device*device*0.8
		output[channel] = sqrt(clampf((value*(2.51*value+0.03))/(value*(2.43*value+0.59)+0.14),0.0,1.0))
	return output
