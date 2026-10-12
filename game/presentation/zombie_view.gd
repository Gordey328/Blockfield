class_name ZombieView
extends Node3D
## Authored, unarmed voxel walker. Simulation owns movement, hits and damage.
## One reusable six-part rig per actor slot; geometry/material are shared.

const CORPSE_SECONDS: float = 2.0
const SKIN: Color = Color("81945e")
const PALE_SKIN: Color = Color("a4b47b")
const CLOTH: Color = Color("5d4758")
const DARK_CLOTH: Color = Color("3c3545")
const TROUSERS: Color = Color("424d4d")
const DARK: Color = Color("242b2e")
const WOUND: Color = Color("733c3c")
const EYES: Color = Color("e8a64c")

static var _part_meshes: Dictionary[String, ArrayMesh] = {}
static var _material: StandardMaterial3D

var target_id: int = -1
var _rig: Node3D
var _torso: MeshInstance3D
var _head: MeshInstance3D
var _arms: Array[MeshInstance3D] = []
var _legs: Array[MeshInstance3D] = []
var _built: bool = false
var _alive: bool = false
var _generation: int = -1
var _corpse_age: float = CORPSE_SECONDS
var _previous_position: Vector3 = Vector3.ZERO
var _walk_phase: float = 0.0
var _moving: bool = false
var _attack_phase: float = 0.0
var _attack_kind: String = ""
var _animation_paused: bool = false


func _ready() -> void:
	_ensure_built()
	_apply_pose()


func setup(target: Dictionary) -> void:
	_ensure_built()
	update_state(target)


func set_paused(value: bool) -> void:
	_animation_paused = value


func update_state(target: Dictionary) -> void:
	_ensure_built()
	if target.is_empty() or str(target.get("kind", "zombie")) != "zombie":
		_alive = false
		_corpse_age = CORPSE_SECONDS
		hide()
		return
	var point: Variant = target.get("position", position)
	var yaw: float = float(target.get("yaw", rotation.y))
	if not point is Vector3:
		hide()
		return
	var pose_position: Vector3 = point
	if not pose_position.is_finite() or not is_finite(yaw):
		hide()
		return
	var generation: int = int(target.get("spawn_generation", 0))
	var alive: bool = bool(target.get("slot_alive", target.get("alive", false)))
	target_id = int(target.get("id", target.get("target_id", target_id)))
	if generation != _generation:
		_generation = generation
		_walk_phase = 0.0
		_previous_position = point
		_corpse_age = CORPSE_SECONDS
		_alive = false
	if alive:
		var distance: float = Vector2(point.x - _previous_position.x, point.z - _previous_position.z).length()
		# Teleport/slot replacement never winds the gait forward arbitrarily.
		if _alive and distance < 2.0:
			_walk_phase = fposmod(_walk_phase + distance * 3.4, TAU)
		position = point
		rotation.y = yaw
		_moving = bool(target.get("moving", false))
		var progress: float = float(target.get("attack_phase", 0.0))
		_attack_phase = clampf(progress, 0.0, 1.0) if is_finite(progress) else 0.0
		_attack_kind = str(target.get("attack_kind", ""))
		_corpse_age = CORPSE_SECONDS
		show()
	elif _alive:
		# Keep the captured death location/pose until this exact slot is reused.
		position = point
		rotation.y = yaw
		_corpse_age = 0.0
		_moving = false
		_attack_phase = 0.0
		_attack_kind = ""
	_alive = alive
	_previous_position = point
	_apply_pose()


func show_death(target: Dictionary = {}) -> void:
	# Idempotent for a death already observed in update_state().
	if not target.is_empty():
		var state: Dictionary = target.duplicate()
		state["alive"] = false
		state["slot_alive"] = false
		update_state(state)
	elif _alive:
		_alive = false
		_corpse_age = 0.0
		_moving = false
		_attack_phase = 0.0
		_attack_kind = ""
		_apply_pose()


func _process(delta: float) -> void:
	if _animation_paused or _alive or _corpse_age >= CORPSE_SECONDS:
		return
	_corpse_age = minf(CORPSE_SECONDS, _corpse_age + maxf(delta, 0.0))
	if _corpse_age >= CORPSE_SECONDS:
		hide()


func get_display_state() -> Dictionary:
	return {"target_id": target_id, "generation": _generation, "alive": _alive,
		"visible": visible, "corpse_age": _corpse_age, "walk_phase": _walk_phase,
		"attack_phase": _attack_phase, "attack_kind": _attack_kind,
		"mesh_parts": 6 if _built else 0, "paused": _animation_paused}


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_ensure_resources()
	_rig = Node3D.new()
	_rig.name = "UnarmedZombieRig"
	add_child(_rig)
	_torso = _part("Torso", "torso", Vector3.ZERO)
	_head = _part("Head", "head", Vector3(0, 1.08, -0.03))
	for side: int in 2:
		var direction: float = -1.0 if side == 0 else 1.0
		_arms.append(_part("LeftArm" if side == 0 else "RightArm", "arm", Vector3(direction * 0.46, 0.89, 0.0)))
		_legs.append(_part("LeftLeg" if side == 0 else "RightLeg", "leg", Vector3(direction * 0.24, 0, 0)))
	_apply_pose()


func _part(part_name: String, key: String, point: Vector3) -> MeshInstance3D:
	var part: MeshInstance3D = MeshInstance3D.new()
	part.name = part_name
	part.mesh = _part_meshes[key]
	part.material_override = _material
	part.position = point
	_rig.add_child(part)
	return part


func _apply_pose() -> void:
	if not _built:
		return
	if not _alive:
		visible = _corpse_age < CORPSE_SECONDS
		_rig.position = Vector3(0, 0.34, 0)
		_rig.rotation = Vector3(-PI * 0.5, 0, -0.12)
		_torso.rotation = Vector3.ZERO
		_head.rotation = Vector3(-0.12, 0.15, 0.09)
		for side: int in 2:
			var direction: float = -1.0 if side == 0 else 1.0
			_arms[side].rotation = Vector3(0.2, 0, direction * 0.42)
			_legs[side].rotation = Vector3(0.02, 0, direction * 0.12)
		return
	var gait: float = sin(_walk_phase) if _moving else 0.0
	var windup: float = sin(_attack_phase * PI)
	var attacking: bool = not _attack_kind.is_empty() and _attack_phase > 0.0
	_rig.position = Vector3(0, 1.03 + absf(gait) * 0.025, 0)
	_rig.rotation = Vector3(-0.08 - (windup * 0.2 if attacking else 0.0), 0, gait * 0.022)
	_torso.rotation = Vector3(0, gait * 0.035, -0.04)
	_head.rotation = Vector3(-0.12 - (windup * 0.18 if attacking else 0.0), 0.08, 0.07)
	for side: int in 2:
		var direction: float = -1.0 if side == 0 else 1.0
		# Bent reaching arms, asymmetric shuffle and bare jaw read as a walker.
		_arms[side].rotation = Vector3(0.88 + direction * 0.1 + gait * direction * 0.1 + (windup * 0.45 if attacking else 0.0), 0, direction * 0.07)
		_legs[side].rotation = Vector3(gait * direction * 0.29, 0, direction * 0.035)


static func _ensure_resources() -> void:
	if not _part_meshes.is_empty():
		return
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0
	_material.resource_name = "AuthoredZombieVertexColor"
	_part_meshes["torso"] = _mesh([
		[Vector3(0, 0.48, 0), Vector3(0.74, 0.86, 0.34), CLOTH],
		[Vector3(0, 0.04, 0), Vector3(0.67, 0.18, 0.31), DARK_CLOTH],
		[Vector3(-0.14, 0.65, -0.18), Vector3(0.22, 0.26, 0.025), SKIN],
		[Vector3(-0.12, 0.63, -0.2), Vector3(0.08, 0.18, 0.018), WOUND],
		[Vector3(0.28, 0.13, -0.18), Vector3(0.12, 0.2, 0.028), SKIN],
		[Vector3(-0.24, 0.04, -0.01), Vector3(0.2, 0.16, 0.35), CLOTH],
		[Vector3(0.15, 0.02, 0.03), Vector3(0.16, 0.12, 0.34), CLOTH]])
	_part_meshes["head"] = _mesh([
		[Vector3(0, 0.2, 0), Vector3(0.54, 0.51, 0.48), PALE_SKIN],
		[Vector3(0, -0.11, -0.13), Vector3(0.44, 0.13, 0.3), SKIN],
		[Vector3(0, 0.37, 0.08), Vector3(0.55, 0.12, 0.36), DARK],
		[Vector3(-0.15, 0.22, -0.249), Vector3(0.15, 0.085, 0.028), DARK],
		[Vector3(0.15, 0.22, -0.249), Vector3(0.15, 0.085, 0.028), DARK],
		[Vector3(-0.15, 0.21, -0.267), Vector3(0.055, 0.05, 0.022), EYES],
		[Vector3(0.15, 0.21, -0.267), Vector3(0.055, 0.05, 0.022), EYES],
		[Vector3(0, 0.09, -0.27), Vector3(0.08, 0.11, 0.085), SKIN],
		[Vector3(0, -0.02, -0.25), Vector3(0.27, 0.085, 0.03), DARK],
		[Vector3(0.035, 0.006, -0.27), Vector3(0.15, 0.03, 0.018), Color("d8ce9e")],
		[Vector3(-0.23, 0.06, -0.25), Vector3(0.075, 0.15, 0.028), WOUND]])
	_part_meshes["arm"] = _mesh([
		[Vector3(0, -0.2, 0), Vector3(0.2, 0.4, 0.24), CLOTH],
		[Vector3(0, -0.49, -0.06), Vector3(0.18, 0.28, 0.23), SKIN],
		[Vector3(0, -0.7, -0.13), Vector3(0.16, 0.22, 0.2), PALE_SKIN],
		[Vector3(0, -0.84, -0.17), Vector3(0.19, 0.14, 0.25), SKIN],
		[Vector3(0.045, -0.47, -0.182), Vector3(0.055, 0.12, 0.024), WOUND]])
	_part_meshes["leg"] = _mesh([
		[Vector3(0, -0.41, 0), Vector3(0.27, 0.81, 0.28), TROUSERS],
		[Vector3(0, -0.48, -0.15), Vector3(0.19, 0.18, 0.035), SKIN],
		[Vector3(0, -0.93, -0.05), Vector3(0.29, 0.21, 0.39), DARK]])


static func _mesh(boxes: Array) -> ArrayMesh:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for box: Array in boxes:
		_append_box(surface, box[0], box[1], box[2])
	return surface.commit()


static func _append_box(surface: SurfaceTool, center: Vector3, extent: Vector3, color: Color) -> void:
	# One surface for all voxel details of a part, never one node per cube.
	var faces: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	for normal: Vector3 in faces:
		var u: Vector3 = Vector3.UP if absf(normal.x) > 0.5 else Vector3.RIGHT
		var v: Vector3 = normal.cross(u)
		var points: Array[Vector3] = []
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			points.append(center + (normal + u * corner.x + v * corner.y) * extent * 0.5)
		# Godot's front faces use clockwise winding.
		for index: int in [0, 2, 1, 0, 3, 2]:
			surface.set_normal(normal)
			surface.set_color(color)
			surface.add_vertex(points[index])
