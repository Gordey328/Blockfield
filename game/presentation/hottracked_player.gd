class_name OpenSpadesHottrackedPlayer
extends Node3D
## Client_Scene.cpp:514–539,783–800: five source hit boxes, twelve edges each.
## Caller owns camera/team/alive/terrain eligibility, independently of name labels.

const HITS = preload("res://gameplay/lab_hit_volumes.gd")
const PARTS: Array[String] = ["head", "torso", "legs", "legs", "arms"]
const EDGE_INDICES: Array[int] = [
	0,4, 1,5, 2,6, 3,7,
	0,2, 1,3, 4,6, 5,7,
	0,1, 2,3, 4,5, 6,7,
]
const LINE_SHADER := """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_opaque;
void fragment() { ALBEDO = COLOR.rgb; }
"""

var _instance: MeshInstance3D
var _mesh: ArrayMesh
var _material: ShaderMaterial
var _vertices := PackedVector3Array()
var _colors := PackedColorArray()
var _pose_cache_valid: bool = false
var _cached_feet := Vector3.ZERO
var _cached_yaw: float = 0.0
var _cached_crouching: bool = false
var _cached_pitch: float = 0.0
var _cached_hit_mask: int = 0
var _cached_color := Color.WHITE
var _geometry_upload_count: int = 0

func _init() -> void:
	visible = false
	top_level = true
	set_process(false)

func show_pose(feet: Vector3, yaw: float, crouching: bool, pitch: float,
		hit_parts: Array[String], team_color: Color) -> bool:
	var hit_mask: int = _hit_mask(hit_parts)
	if not feet.is_finite() or not is_finite(yaw) or not is_finite(pitch) or hit_mask < 0 or not _valid_color(team_color):
		clear()
		return false
	var color := Color(team_color.r,team_color.g,team_color.b,1)
	# Camera eligibility still runs every frame. Reuse only an identical valid
	# world-space outline, including its hit-part colors, at full update rate.
	if _pose_cache_valid and feet == _cached_feet and yaw == _cached_yaw and crouching == _cached_crouching and pitch == _cached_pitch and hit_mask == _cached_hit_mask and color == _cached_color:
		transform = Transform3D.IDENTITY
		visible = true
		return true
	var base := Transform3D(Basis(Vector3.UP, yaw), feet)
	var matrices: Array[Transform3D] = []
	var boxes: Array[AABB] = []
	for volume: Dictionary in HITS.volumes(crouching, pitch):
		matrices.append(base * Transform3D(volume.transform))
		boxes.append(volume.box)
	if not _show_boxes(matrices, boxes, hit_parts, team_color):return false
	_pose_cache_valid = true
	_cached_feet = feet
	_cached_yaw = yaw
	_cached_crouching = crouching
	_cached_pitch = pitch
	_cached_hit_mask = hit_mask
	_cached_color = color
	return true

func show_prepared(pose: LabHitVolumes.PreparedPose, hit_parts: Array[String],
		team_color: Color) -> bool:
	if pose == null or pose.get_volume_count() != 5 or pose.get_parts() != PARTS:
		clear()
		return false
	var matrices: Array[Transform3D] = []
	for inverse: Transform3D in pose.get_inverse_transforms():
		if not inverse.is_finite() or absf(inverse.basis.determinant()) < 0.000001:
			clear()
			return false
		matrices.append(inverse.affine_inverse())
	return _show_boxes(matrices, pose.get_boxes(), hit_parts, team_color)

func hide_target() -> void:
	# Ordinary target loss keeps the one bounded mesh ready for the next target.
	visible = false

func clear() -> void:
	visible = false
	_pose_cache_valid = false
	_vertices.clear()
	_colors.clear()
	if _mesh != null:
		_mesh.clear_surfaces()

func get_line_vertices() -> PackedVector3Array:
	return _vertices.duplicate()

func get_line_colors() -> PackedColorArray:
	return _colors.duplicate()

func get_geometry_upload_count() -> int:
	return _geometry_upload_count

static func _hit_mask(hit_parts: Array[String]) -> int:
	if hit_parts.size() > 4:return -1
	var mask: int = 0
	for part: String in hit_parts:
		match part:
			"head":mask |= 1
			"torso":mask |= 2
			"legs":mask |= 4
			"arms":mask |= 8
			_:return -1
	return mask

func _show_boxes(matrices: Array[Transform3D], boxes: Array[AABB],
		hit_parts: Array[String], team_color: Color) -> bool:
	# Prepared poses may change the renderer independently of show_pose's key.
	_pose_cache_valid = false
	if matrices.size() != 5 or boxes.size() != 5 or not _valid_color(team_color) or hit_parts.size() > 4:
		clear()
		return false
	for part: String in hit_parts:
		if part not in PARTS:
			clear()
			return false
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	vertices.resize(120)
	colors.resize(120)
	for volume in range(5):
		var matrix := matrices[volume]
		var box := boxes[volume]
		if not matrix.is_finite() or not box.position.is_finite() or not box.size.is_finite() or box.size.x <= 0 or box.size.y <= 0 or box.size.z <= 0:
			clear()
			return false
		var color := Color.WHITE if PARTS[volume] in hit_parts else Color(team_color.r, team_color.g, team_color.b, 1)
		var corners := PackedVector3Array()
		corners.resize(8)
		for corner in range(8):
			var offset := Vector3(float((corner >> 2) & 1), float((corner >> 1) & 1), float(corner & 1))
			corners[corner] = matrix * (box.position + offset * box.size)
			if not corners[corner].is_finite():
				clear()
				return false
		for endpoint in range(24):
			vertices[volume * 24 + endpoint] = corners[EDGE_INDICES[endpoint]]
			colors[volume * 24 + endpoint] = color
	_ensure_mesh()
	_vertices = vertices
	_colors = colors
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_COLOR] = _colors
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	_geometry_upload_count += 1
	# Vertices are in world space even when parented beneath a transformed view.
	transform = Transform3D.IDENTITY
	visible = true
	return true

func _ensure_mesh() -> void:
	if _mesh != null:
		return
	var shader := Shader.new()
	shader.code = LINE_SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_mesh = ArrayMesh.new()
	if _instance == null:
		_instance = MeshInstance3D.new()
		_instance.name = "NativeHottrackLines"
		add_child(_instance)
	_instance.mesh = _mesh
	_instance.material_override = _material
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_instance.layers = 1

static func _valid_color(color: Color) -> bool:
	return is_finite(color.r) and is_finite(color.g) and is_finite(color.b) \
		and color.r >= 0 and color.r <= 1 and color.g >= 0 and color.g <= 1 and color.b >= 0 and color.b <= 1

func _exit_tree() -> void:
	clear()
	if _instance != null:
		_instance.mesh = null
		_instance.material_override = null
	_mesh = null
	_material = null
