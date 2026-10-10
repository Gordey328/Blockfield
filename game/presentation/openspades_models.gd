@static_unload
class_name OpenSpadesModels
extends RefCounted
## Original KV6 coordinates were reflected to (x,-z,-y) during GLB conversion.
## Conjugate source rotations rather than guessing each part's orientation.

const ASSET_ROOT := "res://assets/openspades/models/"
const EXTENSIONS = preload("res://presentation/openspades_extensions.gd")
const SOURCE_AXES := Basis(Vector3.RIGHT, Vector3(0, 0, -1), Vector3(0, -1, 0))
const TEAM_COLORS := [Color(0.18, 0.42, 0.86), Color(0.22, 0.66, 0.26)]
static var _scene_cache: Dictionary = {}
static var _material_cache: Dictionary = {}
static var _resource_generation := -1

static func clear_cache() -> void:
	# Call after presentation nodes leave the tree, for explicit test/session teardown.
	RenderingServer.force_sync()
	_material_cache.clear()
	_scene_cache.clear()
	_resource_generation = EXTENSIONS.get_generation()

static func source_vector(value: Vector3) -> Vector3:
	return SOURCE_AXES * value

static func source_rotation(axis: Vector3, angle: float) -> Basis:
	return Basis(source_vector(axis).normalized(), -angle)

static func source_basis(value: Basis) -> Basis:
	return SOURCE_AXES * value * SOURCE_AXES.inverse()

static func source_translation(value: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, source_vector(value))

static func create(relative_path: String, first_person: bool = false) -> Node3D:
	if _resource_generation != EXTENSIONS.get_generation():
		clear_cache()
	var scene := _scene_cache.get(relative_path) as PackedScene
	if scene == null:
		scene = EXTENSIONS.model_override(relative_path)
		if scene == null:
			scene = load(ASSET_ROOT + relative_path + ".glb") as PackedScene
		if scene != null:
			_scene_cache[relative_path] = scene
	if scene == null:
		push_error("Missing imported OpenSpades model: " + relative_path)
		return Node3D.new()
	var node := scene.instantiate() as Node3D
	_prepare(node, first_person)
	return node

static func _prepare(node: Node, first_person: bool) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if first_person:
			mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mesh_node.mesh != null:
			for surface in range(mesh_node.mesh.get_surface_count()):
				var material := mesh_node.mesh.surface_get_material(surface) as StandardMaterial3D
				if material == null:
					continue
				var cache_key := "base:" + str(material.get_instance_id()) + ":" + str(first_person)
				var instance := _material_cache.get(cache_key) as StandardMaterial3D
				if instance == null:
					instance = material.duplicate() as StandardMaterial3D
					instance.vertex_color_use_as_albedo = true
					if first_person:
						# OpenSpades depthHack keeps view equipment clear of world walls.
						instance.no_depth_test = true
						instance.render_priority = 100
					_material_cache[cache_key] = instance
				mesh_node.set_surface_override_material(surface, instance)
	for child in node.get_children():
		_prepare(child, first_person)

static func set_tint(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			for surface in range(mesh_node.mesh.get_surface_count()):
				var material := mesh_node.get_surface_override_material(surface) as StandardMaterial3D
				if material == null:
					material = mesh_node.mesh.surface_get_material(surface) as StandardMaterial3D
				if material != null and material.resource_name == "TeamColor":
					if material.albedo_color == color:
						continue
					# Cache immutable colors; switching teams cannot recolor another soldier.
					# Retained resources also avoid material-lifetime errors in Godot 4.7.
					var cache_key := "team:" + str(material.no_depth_test) + ":" + str(color)
					var colored := _material_cache.get(cache_key) as StandardMaterial3D
					if colored == null:
						colored = material.duplicate() as StandardMaterial3D
						colored.albedo_color = color
						_material_cache[cache_key] = colored
					mesh_node.set_surface_override_material(surface, colored)
	for child in node.get_children():
		set_tint(child, color)
