class_name HdrSceneViewport
extends Node
## Optional floating-point scene capture. Geometry stays in the source World3D.
## Call setup after adding this node to the source viewport's tree, then enable.

const EXPOSURE = preload("res://presentation/hdr_exposure.gd")
var enabled: bool = false
var available: bool = true
var exposure: Node
var scene_viewport: SubViewport
var scene_camera: Camera3D
var presentation: TextureRect
var _layer: CanvasLayer
var _source_camera: Camera3D
var _source_viewport: Viewport
var _previous_disable_3d: bool = false
var _previous_camera_current: bool = false
var _dimensions: Vector2i = Vector2i.ZERO

func setup(source_camera: Camera3D, source_viewport: Viewport = null) -> void:
	set_enabled(false)
	_source_camera = source_camera
	_source_viewport = source_viewport if source_viewport != null else source_camera.get_viewport()
	available = supports_float_target()
	if not available:
		return
	if scene_viewport == null:
		scene_viewport = SubViewport.new()
		scene_viewport.use_hdr_2d = true
		scene_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(scene_viewport)
		scene_camera = Camera3D.new()
		scene_viewport.add_child(scene_camera)
		exposure = EXPOSURE.new()
		add_child(exposure)
		_layer = CanvasLayer.new()
		_layer.layer = -10
		add_child(_layer)
		presentation = TextureRect.new()
		presentation.mouse_filter = Control.MOUSE_FILTER_IGNORE
		presentation.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		presentation.stretch_mode = TextureRect.STRETCH_SCALE
		_layer.add_child(presentation)
		presentation.hide()
	scene_viewport.world_3d = _source_viewport.world_3d
	synchronize()
	exposure.setup(scene_viewport.get_texture())
	presentation.texture = scene_viewport.get_texture()
	presentation.material = exposure.get_present_material()

func set_enabled(value: bool) -> void:
	if value == enabled:
		return
	if value and (not available or scene_viewport == null or not is_instance_valid(_source_camera) or not is_instance_valid(_source_viewport)):
		return
	enabled = value
	if enabled:
		_previous_disable_3d = _source_viewport.disable_3d
		_previous_camera_current = _source_camera.current
		_source_camera.current = false
		_source_viewport.disable_3d = true
		synchronize()
		scene_camera.current = true
		scene_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	else:
		if is_instance_valid(_source_viewport):
			_source_viewport.disable_3d = _previous_disable_3d
		if is_instance_valid(_source_camera):
			_source_camera.current = _previous_camera_current
		if scene_viewport != null:
			scene_camera.current = false
			scene_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if presentation != null:
		presentation.visible = enabled
	if exposure != null:
		exposure.set_enabled(enabled)

func set_options(values: Dictionary) -> Dictionary:
	return exposure.set_options(values) if exposure != null else {"ok":false,"error":"HDR scene is not set up"}

func _process(_dt: float) -> void:
	if enabled:
		synchronize()

func synchronize() -> void:
	if not is_instance_valid(_source_camera) or not is_instance_valid(_source_viewport) or scene_viewport == null:
		return
	var dimensions: Vector2i = Vector2i(_source_viewport.get_visible_rect().size)
	dimensions = Vector2i(maxi(1,dimensions.x),maxi(1,dimensions.y))
	if dimensions != _dimensions:
		_dimensions = dimensions
		scene_viewport.size = dimensions
		presentation.size = Vector2(dimensions)
		if exposure != null:
			exposure.setup(scene_viewport.get_texture())
	scene_camera.global_transform = _source_camera.global_transform
	scene_camera.projection = _source_camera.projection
	scene_camera.keep_aspect = _source_camera.keep_aspect
	scene_camera.fov = _source_camera.fov
	scene_camera.size = _source_camera.size
	scene_camera.near = _source_camera.near
	scene_camera.far = _source_camera.far
	scene_camera.h_offset = _source_camera.h_offset
	scene_camera.v_offset = _source_camera.v_offset
	scene_camera.frustum_offset = _source_camera.frustum_offset
	scene_camera.cull_mask = _source_camera.cull_mask
	scene_camera.environment = _source_camera.environment
	scene_camera.attributes = _source_camera.attributes
	scene_viewport.msaa_3d = _source_viewport.msaa_3d
	scene_viewport.screen_space_aa = _source_viewport.screen_space_aa
	scene_viewport.scaling_3d_scale = _source_viewport.scaling_3d_scale

func get_stats() -> Dictionary:
	var stats: Dictionary = exposure.get_stats() if exposure != null else {}
	stats.scene_size = _dimensions
	stats.available = available
	stats.scene_color_bytes = _dimensions.x*_dimensions.y*8
	stats.shared_world = scene_viewport != null and is_instance_valid(_source_viewport) and scene_viewport.world_3d == _source_viewport.world_3d
	return stats

static func supports_float_target() -> bool:
	if not OS.has_feature("web"):
		return true
	# The extension must be enabled on the engine's actual WebGL2 context.
	# Absence keeps the ordinary renderer active instead of making an invalid FBO.
	return bool(JavaScriptBridge.eval("(function(){var c=document.getElementById('canvas');var g=c?c.getContext('webgl2'):null;return !!(g&&g.getExtension('EXT_color_buffer_float'));})()",true))

func _exit_tree() -> void:
	set_enabled(false)
