class_name PlanarWaterReflection
extends Node
## Reflection-only render proxies share mesh resources, never voxel nodes.
## Native source: GLRenderer mirrored view around z=63 and Water2.fs mirrorTexture.
const WATER_LAYER := 1 << 19
const VIEW_LAYER := 1 << 18
const STANDARD_SHADER = preload("res://world/reflection_standard.gdshader")
const MAX_SCAN_NODES := 4096
const MAX_LIGHTS := 16
var enabled := false
var source_camera: Camera3D
var plane_level := 1.0
var distance_limit := 64.0
var resolution_limit := Vector2i(320, 240)
var updates_per_second := 20.0
var geometry_limit := 768
var viewport: SubViewport
var mirror_camera: Camera3D
var _water_material: ShaderMaterial
var _proxies: Dictionary = {}
var _lights: Dictionary = {}
var _materials: Dictionary = {}
var _custom_shaders: Dictionary = {}
var _standard_shaders: Dictionary = {}
var _default_material := StandardMaterial3D.new()
var _source_nodes: Dictionary = {}
var _tree: SceneTree
var _source_viewport: Viewport
var _source_world: World3D
var _registry_scan_count := 0
var _registry_budget_reached := false
var _light_properties: Dictionary = {}
var _elapsed := 1.0
var _ready_texture := false
var _stats := {"requested_frames": 0, "geometry": 0, "lights": 0, "scanned_nodes": 0,
	"clipped_below": 0, "budget_omitted": 0, "unsupported": 0, "last_prepare_usec": 0, "max_prepare_usec": 0}

func setup(camera: Camera3D, water_material: ShaderMaterial, level: float, draw_distance: float) -> void:
	var camera_changed := camera != source_camera
	source_camera = camera
	_water_material = water_material
	plane_level = level
	distance_limit = draw_distance
	if viewport == null:
		viewport = SubViewport.new()
		viewport.name = "BoundedWaterMirror"
		# Use one explicit World3D; own_world_3d additionally duplicates that resource
		# internally, which would put raw RenderingServer proxies in the wrong RID.
		viewport.own_world_3d = false
		viewport.world_3d = World3D.new()
		viewport.size = Vector2i(320, 240)
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		viewport.msaa_3d = Viewport.MSAA_DISABLED
		add_child(viewport)
		mirror_camera = Camera3D.new()
		mirror_camera.name = "MirroredCamera"
		mirror_camera.current = true
		mirror_camera.cull_mask = ((1 << 20) - 1) & ~(WATER_LAYER | VIEW_LAYER)
		viewport.add_child(mirror_camera)
	_water_material.set_shader_parameter("reflection_texture", viewport.get_texture())
	_water_material.set_shader_parameter("reflection_enabled", false)
	if is_instance_valid(camera) and camera.is_inside_tree() and (_tree == null or camera_changed):
		_source_viewport = camera.get_viewport()
		_source_world = camera.get_world_3d()
		_tree = get_tree()
		if not _tree.node_added.is_connected(_register_node):
			_tree.node_added.connect(_register_node)
			_tree.node_removed.connect(_unregister_node)
		_scan_registry()
	_elapsed = 1.0
	set_process(enabled)

func set_enabled(value: bool) -> void:
	enabled = value
	_elapsed = 1.0
	set_process(value and viewport != null)
	if viewport != null and not value:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _water_material != null:
		_water_material.set_shader_parameter("reflection_enabled", value and _ready_texture)

func set_budget(size_limit: Vector2i, frequency: float, instances: int) -> void:
	resolution_limit = Vector2i(clampi(size_limit.x, 32, 512), clampi(size_limit.y, 32, 512))
	updates_per_second = clampf(frequency, 1.0, 30.0)
	geometry_limit = clampi(instances, 8, 1024)
	_elapsed = 1.0

static func mirrored_transform(original: Transform3D, level: float) -> Transform3D:
	var reflection := Basis(Vector3.RIGHT, Vector3.DOWN, Vector3.BACK)
	# Negate local X as well: Godot cameras require a proper (positive determinant)
	# basis. The shader projects into this camera, including its horizontal reversal.
	var reflected_basis := Basis(-(reflection * original.basis.x), reflection * original.basis.y, reflection * original.basis.z)
	var eye := original.origin
	eye.y = level * 2.0 - eye.y
	return Transform3D(reflected_basis.orthonormalized(), eye)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 1.0 / updates_per_second:
		return
	_elapsed = fmod(_elapsed, 1.0 / updates_per_second)
	update_now()

func update_now() -> bool:
	if not enabled or not is_instance_valid(source_camera) or not source_camera.is_inside_tree() or viewport == null:
		return false
	# Source players keep their eyes above the water. A submerged camera needs a
	# different two-sided water model; suspend this surface-only reflection there.
	if source_camera.global_position.y <= plane_level + 0.05 or -source_camera.global_basis.z.y > 0.15:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_water_material.set_shader_parameter("reflection_enabled", false)
		return false
	var started := Time.get_ticks_usec()
	if source_camera.get_world_3d() != _source_world:
		_source_world = source_camera.get_world_3d()
		_source_viewport = source_camera.get_viewport()
		_scan_registry()
	_sync_camera()
	_sync_scene()
	var projection_view := mirror_camera.get_camera_projection() * Projection(mirror_camera.global_transform.affine_inverse())
	_water_material.set_shader_parameter("reflection_projection_view", projection_view)
	_water_material.set_shader_parameter("reflection_texel_size", Vector2.ONE / Vector2(viewport.size))
	_water_material.set_shader_parameter("reflection_enabled", true)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_ready_texture = true
	_stats.requested_frames += 1
	_stats.last_prepare_usec = Time.get_ticks_usec() - started
	_stats.max_prepare_usec = maxi(_stats.max_prepare_usec, _stats.last_prepare_usec)
	return true

func _sync_camera() -> void:
	var size := source_camera.get_viewport().get_visible_rect().size
	var aspect := maxf(size.x, 1.0) / maxf(size.y, 1.0)
	var width := mini(resolution_limit.x, floori(resolution_limit.y * aspect))
	viewport.size = Vector2i(maxi(1, width), maxi(1, roundi(width / aspect)))
	mirror_camera.keep_aspect = source_camera.keep_aspect
	mirror_camera.projection = source_camera.projection
	mirror_camera.fov = source_camera.fov
	mirror_camera.size = source_camera.size
	mirror_camera.frustum_offset = source_camera.frustum_offset
	# get_camera_transform() below already includes the source camera offsets.
	mirror_camera.h_offset = 0.0
	mirror_camera.v_offset = 0.0
	mirror_camera.near = source_camera.near
	mirror_camera.far = minf(source_camera.far, distance_limit + 16.0)
	mirror_camera.global_transform = mirrored_transform(source_camera.get_camera_transform(), plane_level)
	mirror_camera.environment = source_camera.environment
	viewport.world_3d.environment = source_camera.get_world_3d().environment

func _sync_scene() -> void:
	var candidates: Array[Dictionary] = []
	var light_candidates: Array[Dictionary] = []
	var scanned := 0
	var clipped := 0
	var unsupported := 0
	var allowed_layers := source_camera.cull_mask & ~(WATER_LAYER | VIEW_LAYER)
	for node: Node3D in _source_nodes.values():
		scanned += 1
		if not is_instance_valid(node) or not node.is_inside_tree() or not node.is_visible_in_tree():
			continue
		if node is Light3D:
			var light := node as Light3D
			var distance := source_camera.global_position.distance_squared_to(light.global_position)
			if light is DirectionalLight3D or distance < pow(distance_limit + _light_range(light), 2.0):
				light_candidates.append({"node": light, "distance": -1.0 if light is DirectionalLight3D else distance})
		elif node is GeometryInstance3D:
			var geometry := node as GeometryInstance3D
			if geometry.layers & allowed_layers == 0:
				continue
			if (geometry is MeshInstance3D and geometry.mesh == null) or (geometry is MultiMeshInstance3D and geometry.multimesh == null):
				continue
			if not (geometry is MeshInstance3D or geometry is MultiMeshInstance3D or geometry is Sprite3D):
				unsupported += 1
				continue
			var bounds := geometry.global_transform * geometry.get_aabb()
			if bounds.end.y < plane_level - 0.0001:
				clipped += 1
				continue
			var center: Vector3 = bounds.get_center()
			var extent := bounds.size.length() * 0.5
			var distance := source_camera.global_position.distance_squared_to(center)
			if distance > pow(distance_limit + extent, 2.0):
				continue
			candidates.append({"node": geometry, "distance": distance})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)
	light_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)
	var used: Dictionary = {}
	var used_materials: Dictionary = {}
	for index in range(mini(candidates.size(), geometry_limit)):
		var node: GeometryInstance3D = candidates[index].node
		if _sync_geometry(node, used_materials):
			used[node.get_instance_id()] = true
		else:
			unsupported += 1
	for key in _proxies.keys():
		if not used.has(key):
			RenderingServer.free_rid(_proxies[key].rid)
			_proxies.erase(key)
	for key in _materials.keys():
		if not used_materials.has(key):
			_materials.erase(key)
	var used_lights: Dictionary = {}
	for index in range(mini(light_candidates.size(), MAX_LIGHTS)):
		_sync_light(light_candidates[index].node)
		used_lights[light_candidates[index].node.get_instance_id()] = true
	for key in _lights.keys():
		if not used_lights.has(key):
			_lights[key].queue_free()
			_lights.erase(key)
	_stats.geometry = _proxies.size()
	_stats.lights = _lights.size()
	_stats.scanned_nodes = scanned
	_stats.clipped_below = clipped
	_stats.unsupported = unsupported
	_stats.budget_omitted = maxi(0, candidates.size() - geometry_limit)
	_stats.scan_budget_reached = _registry_budget_reached
	_stats.registry_scan_nodes = _registry_scan_count

func _scan_registry() -> void:
	_source_nodes.clear()
	var stack: Array[Node] = [_source_viewport]
	var scanned := 0
	while not stack.is_empty() and scanned < MAX_SCAN_NODES:
		var node: Node = stack.pop_back()
		scanned += 1
		if node != _source_viewport and (node is Viewport or node is CanvasLayer or node is Control):
			continue
		_register_node(node)
		for child in node.get_children():
			stack.append(child)
	_registry_scan_count = scanned
	_registry_budget_reached = not stack.is_empty()

func _register_node(node: Node) -> void:
	if (node is GeometryInstance3D or node is Light3D) and node.is_inside_tree() and node.get_world_3d() == _source_world:
		if _source_nodes.size() < MAX_SCAN_NODES:
			_source_nodes[node.get_instance_id()] = node
		else:
			_registry_budget_reached = true

func _unregister_node(node: Node) -> void:
	_source_nodes.erase(node.get_instance_id())

func _sync_geometry(node: GeometryInstance3D, used_materials: Dictionary) -> bool:
	var mesh: Mesh
	var base: Resource
	var material: Material = node.material_override
	var sprite := node as Sprite3D
	var key := node.get_instance_id()
	if node is MeshInstance3D:
		mesh = node.mesh
		base = mesh
	elif node is MultiMeshInstance3D:
		base = node.multimesh
		mesh = node.multimesh.mesh if node.multimesh != null else null
	elif sprite != null and sprite.texture != null:
		mesh = _proxies[key].base if _proxies.has(key) else QuadMesh.new()
		(mesh as QuadMesh).size = sprite.texture.get_size() * sprite.pixel_size
		base = mesh
	if base == null or mesh == null:
		return false
	var entry: Dictionary
	if not _proxies.has(key):
		var rid := RenderingServer.instance_create()
		RenderingServer.instance_set_scenario(rid, viewport.world_3d.scenario)
		RenderingServer.instance_set_layer_mask(rid, 1)
		RenderingServer.instance_geometry_set_cast_shadows_setting(rid, RenderingServer.SHADOW_CASTING_SETTING_OFF)
		entry = {"rid": rid, "base": null, "materials": [], "transform": Transform3D.IDENTITY, "layers": 1, "visibility_range": Vector4.ZERO, "material_rids": []}
		_proxies[key] = entry
	else:
		entry = _proxies[key]
	if entry.base != base:
		entry.base = base
		entry.material_rids = []
		RenderingServer.instance_set_base(entry.rid, base.get_rid())
	if entry.transform != node.global_transform:
		entry.transform = node.global_transform
		RenderingServer.instance_set_transform(entry.rid, entry.transform)
	var layers := node.layers & ~(WATER_LAYER | VIEW_LAYER)
	if entry.layers != layers:
		entry.layers = layers
		RenderingServer.instance_set_layer_mask(entry.rid, layers)
	var visibility := Vector4(node.visibility_range_begin, node.visibility_range_end, node.visibility_range_begin_margin, node.visibility_range_end_margin)
	if entry.visibility_range != visibility:
		entry.visibility_range = visibility
		RenderingServer.instance_geometry_set_visibility_range(entry.rid, visibility.x, visibility.y, visibility.z, visibility.w, RenderingServer.VISIBILITY_RANGE_FADE_DISABLED)
	var retained: Array[Material] = []
	var material_rids: Array[RID] = []
	if sprite != null:
		var proxy_material: ShaderMaterial = entry.get("sprite_material")
		if proxy_material == null:
			proxy_material = ShaderMaterial.new()
			proxy_material.shader = _standard_shader(false, true, true)
			entry.sprite_material = proxy_material
		proxy_material.set_shader_parameter("reflection_clip_level", plane_level)
		proxy_material.set_shader_parameter("albedo_texture", sprite.texture)
		proxy_material.set_shader_parameter("texture_enabled", true)
		proxy_material.set_shader_parameter("albedo_color", sprite.modulate)
		proxy_material.set_shader_parameter("billboard_enabled", sprite.billboard != BaseMaterial3D.BILLBOARD_DISABLED)
		material_rids.append(proxy_material.get_rid())
		if entry.material_rids != material_rids:
			RenderingServer.instance_geometry_set_material_override(entry.rid, proxy_material.get_rid())
		retained.append(proxy_material)
	elif material != null:
		var proxy_material := _mirror_material(material, used_materials)
		if proxy_material == null:
			return false
		material_rids.append(proxy_material.get_rid())
		if entry.material_rids != material_rids:
			RenderingServer.instance_geometry_set_material_override(entry.rid, proxy_material.get_rid())
		retained.append(proxy_material)
	else:
		for surface in range(mesh.get_surface_count()):
			var original: Material = mesh.surface_get_material(surface)
			if node is MeshInstance3D and node.get_surface_override_material(surface) != null:
				original = node.get_surface_override_material(surface)
			var proxy_material := _mirror_material(original, used_materials)
			if proxy_material == null:
				return false
			material_rids.append(proxy_material.get_rid())
			retained.append(proxy_material)
		if entry.material_rids != material_rids:
			RenderingServer.instance_geometry_set_material_override(entry.rid, RID())
			for surface in range(material_rids.size()):
				if node is MultiMeshInstance3D:
					# Current original fragment/smoke MultiMeshes have one surface.
					RenderingServer.instance_geometry_set_material_override(entry.rid, material_rids[surface])
				else:
					RenderingServer.instance_set_surface_override_material(entry.rid, surface, material_rids[surface])
	entry.materials = retained
	entry.material_rids = material_rids
	return true

func _mirror_material(original: Material, used: Dictionary) -> ShaderMaterial:
	if original == null:
		original = _default_material
	var key := original.get_instance_id()
	if used.has(key):
		return _materials.get(key)
	used[key] = true
	var material: ShaderMaterial = _materials.get(key)
	if material == null:
		material = ShaderMaterial.new()
		_materials[key] = material
	if original is ShaderMaterial:
		var source_shader: Shader = original.shader
		if source_shader == null:
			return null
		var shader_key := source_shader.get_instance_id()
		if not _custom_shaders.has(shader_key):
			var expression := RegEx.new()
			expression.compile("void\\s+fragment\\s*\\(\\s*\\)\\s*\\{")
			var code := source_shader.code
			var found := expression.search(code)
			if found == null:
				_materials.erase(key)
				return null
			code = code.insert(found.get_end(), "\n if ((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y < reflection_clip_level - 0.0001) { discard; }\n")
			var type_end := code.find(";") + 1
			code = code.insert(type_end, "\nuniform float reflection_clip_level = 1.0;\n")
			var clipped_shader := Shader.new()
			clipped_shader.code = code
			_custom_shaders[shader_key] = clipped_shader
		material.shader = _custom_shaders[shader_key]
		for parameter in source_shader.get_shader_uniform_list():
			var value = original.get_shader_parameter(parameter.name)
			material.set_shader_parameter(parameter.name, value)
	elif original is BaseMaterial3D:
		var source := original as BaseMaterial3D
		material.shader = _standard_shader(source.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED, source.cull_mode == BaseMaterial3D.CULL_DISABLED, source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
		material.set_shader_parameter("albedo_color", source.albedo_color)
		material.set_shader_parameter("vertex_color_enabled", source.vertex_color_use_as_albedo)
		material.set_shader_parameter("albedo_texture", source.albedo_texture)
		material.set_shader_parameter("texture_enabled", source.albedo_texture != null)
		material.set_shader_parameter("roughness", source.roughness)
		material.set_shader_parameter("metallic", source.metallic)
		material.set_shader_parameter("specular", source.metallic_specular)
		material.set_shader_parameter("emission_color", source.emission if source.emission_enabled else Color.BLACK)
		material.set_shader_parameter("emission_energy", source.emission_energy_multiplier)
		material.set_shader_parameter("billboard_enabled", source.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED)
		material.set_shader_parameter("alpha_scissor", source.alpha_scissor_threshold if source.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else 0.0)
	else:
		return null
	material.set_shader_parameter("reflection_clip_level", plane_level)
	return material

func _standard_shader(shaded: bool, double_sided: bool, transparent: bool) -> Shader:
	var key := "%s:%s:%s" % [shaded, double_sided, transparent]
	if not _standard_shaders.has(key):
		var code := STANDARD_SHADER.code
		if not shaded:
			code = code.replace("render_mode diffuse_burley;", "render_mode unshaded;")
		if double_sided:
			code = code.replace("shader_type spatial;", "shader_type spatial;\nrender_mode cull_disabled;")
		if transparent:
			code = code.replace("// ALPHA_OUTPUT", "ALPHA = color.a; ALPHA_SCISSOR_THRESHOLD = alpha_scissor;")
		var shader := Shader.new()
		shader.code = code
		_standard_shaders[key] = shader
	return _standard_shaders[key]

static func _light_range(light: Light3D) -> float:
	return light.omni_range if light is OmniLight3D else (light.spot_range if light is SpotLight3D else 0.0)

func _sync_light(original: Light3D) -> void:
	var key := original.get_instance_id()
	var mirror: Light3D = _lights.get(key)
	if mirror == null:
		mirror = ClassDB.instantiate(original.get_class()) as Light3D
		viewport.add_child(mirror)
		_lights[key] = mirror
	var type := original.get_class()
	if not _light_properties.has(type):
		var names: Array[String] = []
		for property in original.get_property_list():
			var name: String = property.name
			if name.begins_with("light_") or name.begins_with("omni_") or name.begins_with("spot_") or name.begins_with("directional_") or name.begins_with("distance_fade_"):
				names.append(name)
		_light_properties[type] = names
	for name: String in _light_properties[type]:
		var value = original.get(name)
		if mirror.get(name) != value:
			mirror.set(name, value)
	if mirror.global_transform != original.global_transform:
		mirror.global_transform = original.global_transform
	# A second shadow atlas would exceed the intended browser work budget.
	mirror.shadow_enabled = false
	mirror.visible = true

func clear_cache() -> void:
	for entry in _proxies.values():
		RenderingServer.free_rid(entry.rid)
	_proxies.clear()
	_materials.clear()
	_custom_shaders.clear()
	_standard_shaders.clear()
	for light in _lights.values():
		light.queue_free()
	_lights.clear()
	_ready_texture = false
	if _water_material != null:
		_water_material.set_shader_parameter("reflection_enabled", false)

func get_stats() -> Dictionary:
	var result := _stats.duplicate()
	result.merge({"enabled": enabled, "texture_ready": _ready_texture, "resolution": viewport.size if viewport != null else Vector2i.ZERO,
		"updates_per_second": updates_per_second, "geometry_budget": geometry_limit, "light_budget": MAX_LIGHTS,
		"scan_node_budget": MAX_SCAN_NODES, "plane_level": plane_level, "shared_mesh_resources": true,
		"reflection_shadows": false, "native_depth_raymarch": false, "material_cache": _materials.size()}, true)
	if viewport != null:
		result.texture_and_depth_bytes = viewport.size.x * viewport.size.y * 8
		result.last_draw_calls = viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	return result

func _exit_tree() -> void:
	if _tree != null and _tree.node_added.is_connected(_register_node):
		_tree.node_added.disconnect(_register_node)
		_tree.node_removed.disconnect(_unregister_node)
	_source_nodes.clear()
	clear_cache()
