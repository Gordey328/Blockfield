class_name HdrBloom
extends Node
## Bounded source GLLensDustFilter hierarchy, entirely floating-point on GPU.
const FILTER = preload("res://presentation/hdr_bloom.gdshader")
const GAUSS_OFFSETS: Array[float] = [-2.30654399138844,-0.629455560633963,0.629455560633963,2.30654399138844]
const GAUSS_WEIGHTS: Array[float] = [0.178704407070903,0.321295592929097,0.321295592929097,0.178704407070903]
var max_size: Vector2i = Vector2i(256,256)
var max_levels: int = 6
var enabled: bool = false
var _passes: Array[SubViewport] = []
var _level_sizes: Array[Vector2i] = []
var _output: Texture2D
var _source: Texture2D
var _bytes: int = 0

func setup(source: Texture2D) -> void:
	_source = source
	for viewport: SubViewport in _passes:
		remove_child(viewport)
		viewport.queue_free()
	_passes.clear()
	_level_sizes.clear()
	_output = source
	_bytes = 0
	if source == null or source.get_width() < 2 or source.get_height() < 2:
		return
	var original_size: Vector2i = Vector2i(source.get_width(),source.get_height())
	var native_half: Vector2i = Vector2i((original_size.x+1)/2,(original_size.y+1)/2)
	var ratio: float = minf(1.0,minf(float(max_size.x)/native_half.x,float(max_size.y)/native_half.y))
	var size: Vector2i = Vector2i(maxi(2,ceili(native_half.x*ratio)),maxi(2,ceili(native_half.y*ratio)))
	var current: Texture2D = _downsample(source,size,Vector2(native_half)*2.0/Vector2(original_size))
	current = _gaussian(current,size)
	var textures: Array[Texture2D] = []
	for index: int in range(max_levels):
		var next_size: Vector2i = Vector2i((size.x+1)/2,(size.y+1)/2)
		if next_size.x <= 1 or next_size.y <= 1:
			break
		current = _downsample(current,next_size,Vector2(next_size)*2.0/Vector2(size))
		current = _gaussian(current,next_size)
		size = next_size
		textures.append(current)
		_level_sizes.append(size)
	if not textures.is_empty():
		current = textures[-1]
		for index: int in range(textures.size()-2,-1,-1):
			var count: int = textures.size()-1-index
			var material: ShaderMaterial = ShaderMaterial.new()
			material.shader = FILTER
			material.set_shader_parameter("operation",2)
			material.set_shader_parameter("source_texture",textures[index])
			material.set_shader_parameter("coarse_texture",current)
			material.set_shader_parameter("coarse_weight",float(count)/float(count+1))
			current = _pass(_level_sizes[index],material)
	_output = current
	set_enabled(enabled)

func _pass(size: Vector2i, material: ShaderMaterial) -> Texture2D:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = size
	viewport.use_hdr_2d = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var rect: ColorRect = ColorRect.new()
	rect.size = Vector2(size)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = material
	viewport.add_child(rect)
	_passes.append(viewport)
	_bytes += size.x*size.y*8
	return viewport.get_texture()

func _downsample(source: Texture2D, size: Vector2i, range_scale: Vector2) -> Texture2D:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = FILTER
	material.set_shader_parameter("source_texture",source)
	material.set_shader_parameter("range_scale",range_scale)
	return _pass(size,material)

func _gaussian(source: Texture2D, size: Vector2i) -> Texture2D:
	for axis: int in range(2):
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = FILTER
		material.set_shader_parameter("operation",1)
		material.set_shader_parameter("source_texture",source)
		material.set_shader_parameter("unit_shift",Vector2(1.0/size.x,0) if axis == 0 else Vector2(0,1.0/size.y))
		source = _pass(size,material)
	return source

func set_enabled(value: bool) -> void:
	enabled = value
	for viewport: SubViewport in _passes:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED

func set_budget(size: Vector2i, levels: int = 6) -> void:
	max_size = Vector2i(clampi(size.x,16,512),clampi(size.y,16,512))
	max_levels = clampi(levels,1,10)
	setup(_source)

func get_blur_texture() -> Texture2D:
	return _output

func get_stats() -> Dictionary:
	return {"enabled":enabled,"passes":_passes.size(),"levels":_level_sizes.duplicate(),"color_texture_bytes":_bytes,"max_size":max_size,"max_levels":max_levels}

static func compose(original: Color, blurred: Color, dust: Color, grain: float = 0.0) -> Color:
	return Color(maxf(original.r*0.95+blurred.r*dust.r*dust.r*2.0+grain*0.003,0),maxf(original.g*0.95+blurred.g*dust.g*dust.g*2.0+grain*0.003,0),maxf(original.b*0.95+blurred.b*dust.b*dust.b*2.0+grain*0.003,0),1.0)
