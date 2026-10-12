class_name OpenSpadesPostEffects
extends CanvasLayer
## Two optional bounded passes; HUD CanvasLayers stay above this layer.
const COLOR_SHADER = preload("res://presentation/post_color.gdshader")
const DEPTH_SHADER = preload("res://presentation/post_depth.gdshader")
const EXTENSIONS = preload("res://presentation/openspades_extensions.gd")
const IMAGES := "res://assets/openspades/images/"
const TEXTURES := {"lens_dust": "Textures/LensDustTexture.png", "flare_image": "Gfx/LensFlare/4.png", "flare_ghost": "Gfx/LensFlare/1.png", "hurt_sprite": "Gfx/HurtSprite.png", "hurt_ring": "Gfx/HurtRing2.png"}
const DEFAULTS := {"fxaa": true, "msaa": 0, "bloom": true, "lens": true,
	"lens_flare": true, "color_correction": true, "saturation": 1.0,
	"exposure": 0.0, "tone_map": false, "camera_blur": true, "dof": false,
	"dof_strength": 1.0, "manual_focus": false, "ssao": false, "ssao_strength": 1.0, "quality": 1,
	"ambient_energy": 0.55}
const RANGES := {"saturation": Vector2(0,2), "exposure": Vector2(-4,4),
	"dof_strength": Vector2(0,2), "ssao_strength": Vector2(0,2), "ambient_energy": Vector2(0,1.5)}
var camera: Camera3D
var environment: WorldEnvironment
var _options: Dictionary = DEFAULTS.duplicate()
var _color_rect: ColorRect
var _depth_quad: MeshInstance3D
var _color_material: ShaderMaterial
var _depth_material: ShaderMaterial
var _hurt_age := 10.0
var _health := 100.0
var _hurt_angle := 0.0
var _directional := false
var _hurt_overlay_enabled := false
var _hdr_active := false
var _correction_tint := Vector3.ONE
var _last_rotation := Vector3.ZERO
var _flare_sources: Array[Dictionary] = []

func setup(view_camera: Camera3D, world_environment: WorldEnvironment = null) -> void:
	camera = view_camera
	environment = world_environment
	layer = -5
	if _color_rect == null:
		_color_material = ShaderMaterial.new()
		_color_material.shader = COLOR_SHADER
		reload_resources()
		_color_rect = ColorRect.new()
		_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_color_rect.material = _color_material
		_color_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_color_rect)
		_depth_material = ShaderMaterial.new()
		_depth_material.shader = DEPTH_SHADER
		_depth_quad = MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(2,2)
		_depth_quad.mesh = mesh
		# This camera-space quad must never enter a water-reflection scene.
		_depth_quad.layers = 1 << 18
		_depth_quad.material_override = _depth_material
		_depth_quad.extra_cull_margin = 16384
		_depth_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The screen copy contains opaque geometry. Run before transparent sprites and
		# view equipment, otherwise a final quad would erase the depth-hacked weapon.
		_depth_material.render_priority = -128
		camera.add_child(_depth_quad)
		_depth_quad.position.z = -1
	_last_rotation = camera.global_rotation
	_apply_options()
	set_flare_sources([])

func _exit_tree() -> void:
	if is_instance_valid(_depth_quad):
		_depth_quad.queue_free()

func reload_resources() -> void:
	if _color_material != null:
		for binding in TEXTURES:
			_color_material.set_shader_parameter(binding, EXTENSIONS.texture(IMAGES + TEXTURES[binding]))

func get_options() -> Dictionary:
	return _options.duplicate(true)

func set_hdr_active(active: bool) -> void:
	_hdr_active=active
	if _color_material!=null:_apply_options()

func get_hdr_correction() -> Dictionary:
	var desaturate:=maxf(0.0,1.0-maxf(1.0-_hurt_age/0.2,0.0)*(0.5-_health/100.0*0.3)*4.0)
	return {"tint":_correction_tint,"exposure":pow(2.0,_options.exposure*0.5),"saturation":_options.saturation*(0.8 if _options.bloom else 0.9)*desaturate,"enhancement":0.1 if _options.bloom else 0.0,"correction_enabled":_options.color_correction,"aces_enabled":true}

func set_options(values: Dictionary) -> Dictionary:
	var proposed := _options.duplicate()
	for key: String in values:
		if not DEFAULTS.has(key):
			return {"ok": false, "error": "Unknown graphics option: " + key}
		var value = values[key]
		if key in RANGES:
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
				return {"ok": false, "error": "Expected finite number: " + key}
			proposed[key] = clampf(float(value), RANGES[key].x, RANGES[key].y)
		elif key in ["msaa", "quality"]:
			if typeof(value) != TYPE_INT or (key == "msaa" and value not in [0,2,4]) or (key == "quality" and value not in [0,1,2]):
				return {"ok": false, "error": "Invalid graphics enum: " + key}
			proposed[key] = value
		elif typeof(value) != TYPE_BOOL:
			return {"ok": false, "error": "Expected boolean: " + key}
		else:
			proposed[key] = value
	_options = proposed
	if _color_material != null:
		_apply_options()
	return {"ok": true, "options": get_options()}

func preset(name: String) -> Dictionary:
	if name not in ["low", "medium", "high"]:
		return {"ok": false, "error": "Unknown graphics preset: " + name}
	var values := DEFAULTS.duplicate()
	if name == "low":
		for key in ["fxaa", "bloom", "lens", "lens_flare", "camera_blur"]:
			values[key] = false
		values.quality = 0
	elif name == "high":
		values.merge({"msaa": 4, "ssao": true, "dof": true, "quality": 2}, true)
	return set_options(values)

func _apply_options() -> void:
	for key in ["fxaa", "bloom", "lens"]:
		_color_material.set_shader_parameter(key + "_enabled", _options[key] and not (_hdr_active and key=="bloom"))
	_color_material.set_shader_parameter("flare_enabled", _options.lens_flare)
	_color_material.set_shader_parameter("correction_enabled", _options.color_correction and not _hdr_active)
	_color_material.set_shader_parameter("tone_map_enabled", _options.tone_map and not _hdr_active)
	_color_material.set_shader_parameter("exposure", pow(2.0, _options.exposure * 0.5))
	_color_material.set_shader_parameter("quality", _options.quality)
	_color_material.set_shader_parameter("enhancement", (0.1 if _options.bloom else 0.0) if _options.tone_map else (0.7 if _options.bloom else 0.3))
	_depth_material.set_shader_parameter("ssao_enabled", _options.ssao)
	_depth_material.set_shader_parameter("dof_enabled", _options.dof)
	_depth_material.set_shader_parameter("ssao_strength", _options.ssao_strength)
	_depth_material.set_shader_parameter("dof_strength", _options.dof_strength)
	_depth_material.set_shader_parameter("manual_focus_enabled",_options.manual_focus)
	_depth_material.set_shader_parameter("quality", _options.quality)
	_depth_quad.visible = _options.ssao or _options.dof
	if is_instance_valid(camera):
		camera.get_viewport().msaa_3d = Viewport.MSAA_DISABLED if _options.msaa == 0 else (Viewport.MSAA_2X if _options.msaa == 2 else Viewport.MSAA_4X)
	if is_instance_valid(environment) and environment.environment != null:
		environment.environment.ambient_light_energy = _options.ambient_energy
		var fog_color := environment.environment.fog_light_color
		var tint := Color(1.0 / (fog_color.r+0.5), 1.0 / (fog_color.g+0.5), 1.0 / (fog_color.b+0.5)).lerp(Color.WHITE,0.2)
		var minimum := minf(tint.r,minf(tint.g,tint.b))
		_correction_tint=Vector3(tint.r,tint.g,tint.b)/maxf(minimum,0.001) if _options.color_correction else Vector3.ONE
		_color_material.set_shader_parameter("tint",_correction_tint)

func damage(_amount: float, direction_angle: float = INF) -> void:
	_hurt_age = 0.0
	_directional = is_finite(direction_angle)
	_hurt_angle = direction_angle if _directional else 0.0

func set_hurt_overlay_enabled(enabled: bool) -> void:
	# Main HUD owns these overlays; this switch is for isolated renderer previews.
	_hurt_overlay_enabled = enabled

func reset() -> void:
	_hurt_age = 10.0
	_directional = false
	if is_instance_valid(camera):
		_last_rotation = camera.global_rotation
	update_state(0,100,10,false,0.0)

func update_state(delta: float, health: float, hurt_age: float = -1, _sprinting: bool = false, aiming: float = 0.0, focus_distance: float = 10.0, source_radial: float = 0.0) -> void:
	if _color_material == null:
		return
	_hurt_age = maxf(0.0,hurt_age) if hurt_age >= 0 else _hurt_age+maxf(delta,0.0)
	_health = clampf(health,0,100)
	var flash := minf(maxf(1.0-_hurt_age/0.35,0.0)*(0.3+(1.0-_health/100.0)*0.7),0.9)
	var desaturate := maxf(0.0,1.0-maxf(1.0-_hurt_age/0.2,0.0)*(0.5-_health/100.0*0.3)*4.0)
	_color_material.set_shader_parameter("hurt_flash",flash if _hurt_overlay_enabled else 0.0)
	_color_material.set_shader_parameter("hurt_edge",maxf(1.0-_hurt_age/1.5,0.0)*0.7 if _hurt_overlay_enabled else 0.0)
	_color_material.set_shader_parameter("hurt_angle",_hurt_angle)
	_color_material.set_shader_parameter("hurt_direction_fade",minf(maxf(3.0-_hurt_age,0.0)*2.0,1.0) if _hurt_overlay_enabled and _directional and health > 0 else 0.0)
	var source_saturation := (0.8 if _options.bloom else 0.9) if _options.tone_map else (0.85 if _options.bloom else 1.0)
	_color_material.set_shader_parameter("saturation",_options.saturation*source_saturation*desaturate)
	_color_material.set_shader_parameter("hurt_blur",maxf(1.0-_hurt_age/0.15,0.0)*(0.5-_health/100.0*0.3)*6.0 if _options.camera_blur else 0.0)
	_color_material.set_shader_parameter("radial_blur",clampf(source_radial,0.0,1.0) if _options.camera_blur else 0.0)
	var motion := Vector2.ZERO
	if is_instance_valid(camera):
		var rotation := camera.global_rotation
		if delta > 0 and _options.camera_blur:
			motion = Vector2(wrapf(rotation.y-_last_rotation.y,-PI,PI),wrapf(_last_rotation.x-rotation.x,-PI,PI)).limit_length(0.05)
		_last_rotation = rotation
	_color_material.set_shader_parameter("camera_motion",motion)
	_depth_material.set_shader_parameter("focus_distance",maxf(focus_distance,0.05))
	_depth_material.set_shader_parameter("focus_focal_length",0.054 + 13.0 * pow(clampf(aiming,0.0,1.0),3.0))
	if bool(_options.lens_flare) and not _flare_sources.is_empty(): _update_flares()

func set_flare_sources(sources: Array[Dictionary]) -> void:
	_flare_sources = sources.slice(0,4)
	if _color_material != null:
		_update_flares()

func _update_flares() -> void:
	var positions := PackedVector4Array()
	var colors := PackedColorArray()
	positions.resize(4)
	colors.resize(4)
	for index in range(_flare_sources.size()):
		var source: Dictionary = _flare_sources[index]
		if not source.get("visible",true) or not is_instance_valid(camera):
			continue
		var position: Vector3 = source.get("position",camera.global_position + source.get("direction",Vector3.FORWARD)*1000.0)
		if not position.is_finite() or camera.is_position_behind(position):
			continue
		var point := camera.unproject_position(position)/camera.get_viewport().get_visible_rect().size
		positions[index] = Vector4(point.x,point.y,clampf(source.get("radius",0.06),0.001,0.3),clampf(source.get("energy",1.0),0,4))
		colors[index] = source.get("color",Color.WHITE)
	_color_material.set_shader_parameter("flare_sources",positions)
	_color_material.set_shader_parameter("flare_colors",colors)
