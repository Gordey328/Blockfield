class_name CharacterView
extends Node3D
## Standing/crouching/dead assembly adapted from ClientPlayer.cpp's original parts.
## This node is anchored at feet; forward is local -Z, pitch is positive looking up.

const MODELS = preload("res://presentation/openspades_models.gd")
const BODY_SCALE := Vector3(0.1, 0.1, 0.1)
const ORIGIN_HEIGHT := 1.1
const WEAPONS := ["Rifle", "SMG", "Shotgun"]

var _built := false
var _team := 0
var _team_color := Color(0.18, 0.42, 0.86)
var _crouching := false
var _dead := false
var _sprinting := false
var _pitch := 0.0
var _weapon := 0
var _tool := 2
var _time := 0.0
var _motion_speed := 0.0
var _rig: Node3D
var _torso: Node3D
var _crouch_torso: Node3D
var _head: Node3D
var _arms: Node3D
var _legs: Array[Node3D] = []
var _crouch_legs: Array[Node3D] = []
var _corpse: Node3D
var _equipment: Node3D

func _ready() -> void:
	_ensure_built()

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_rig = Node3D.new()
	_rig.name = "OriginalCharacterParts"
	# OpenSpades's reference front points toward source -Y. Turn it to Godot -Z.
	_rig.rotation.y = PI
	_rig.position.y = ORIGIN_HEIGHT
	add_child(_rig)
	_torso = _body_part("Torso")
	_crouch_torso = _body_part("TorsoCrouch")
	_head = _body_part("Head")
	_arms = _body_part("Arms")
	for side in range(2):
		_legs.append(_body_part("Leg"))
		_crouch_legs.append(_body_part("LegCrouch"))
	_corpse = MODELS.create("Player/Dead")
	_corpse.scale = BODY_SCALE
	# Keep the lying corpse's lowest voxel just above the floor.
	_corpse.position.y = 0.35 - ORIGIN_HEIGHT
	_rig.add_child(_corpse)
	_rebuild_equipment()
	MODELS.set_tint(_rig, _team_color)
	_apply_pose()

func _body_part(part_name: String) -> Node3D:
	var part := MODELS.create("Player/" + part_name)
	part.name = part_name
	_rig.add_child(part)
	return part

func set_team(index: int, color: Color = Color(-1, -1, -1, 1)) -> void:
	_ensure_built()
	var next_color: Color = MODELS.TEAM_COLORS[clampi(index, 0, 1)] if color.r < 0 else color
	if _team != index or _team_color != next_color:
		_team = index
		_team_color = next_color
		MODELS.set_tint(_rig, _team_color)
	visible = index < 2

func set_pose(crouch: bool, dead: bool, sprint: bool) -> void:
	_ensure_built()
	_crouching = crouch
	_dead = dead
	_sprinting = sprint
	_apply_pose()

func set_weapon(index: int, tool: int = 2) -> void:
	_ensure_built()
	index = clampi(index, 0, 2)
	tool = clampi(tool, 0, 3)
	if _weapon == index and _tool == tool:
		return
	_weapon = index
	_tool = tool
	_rebuild_equipment()
	_apply_pose()

func set_aim(pitch: float) -> void:
	_ensure_built()
	_pitch = clampf(pitch, -PI * 0.5, PI * 0.5)
	_apply_pose()

func animate_motion(speed: float, time: float) -> void:
	_ensure_built()
	_motion_speed = clampf(speed, -8.0, 8.0)
	_time = time
	_apply_pose()

func _rebuild_equipment() -> void:
	if is_instance_valid(_equipment):
		_equipment.hide()
		_equipment.queue_free()
	var path: String
	match _tool:
		0: path = "Weapons/Spade/Spade"
		1: path = "Weapons/Block/Block2"
		3: path = "Weapons/Grenade/Grenade"
		_: path = "Weapons/" + WEAPONS[_weapon] + "/Weapon"
	_equipment = MODELS.create(path)
	_equipment.name = "HeldTool"
	_rig.add_child(_equipment)
	MODELS.set_tint(_equipment, _team_color)

func _apply_pose() -> void:
	if not _built:
		return
	# The source changes player origin on crouch. A feet-anchored view must do so too.
	_rig.position.y = 0.7 if _crouching and not _dead else ORIGIN_HEIGHT
	_corpse.visible = _dead
	_torso.visible = not _dead and not _crouching
	_crouch_torso.visible = not _dead and _crouching
	_head.visible = not _dead
	_arms.visible = not _dead
	_equipment.visible = not _dead
	var scaler := Basis(Vector3.UP, PI).scaled(BODY_SCALE)
	var torso_height := 0.55 if _crouching else 1.0
	var torso_origin := Vector3(0, torso_height, 0)
	_torso.transform = Transform3D(scaler, torso_origin)
	_crouch_torso.transform = Transform3D(scaler, torso_origin)
	_head.transform = Transform3D(MODELS.source_rotation(Vector3.RIGHT, _pitch) * scaler, torso_origin)
	var arm_pitch := _pitch - (0.5 if _sprinting else 0.0)
	if arm_pitch < 0.0:
		arm_pitch = maxf(arm_pitch, -PI * 0.5) * 0.9
	var arm_origin := torso_origin + Vector3(0, 0 if _crouching else -0.1, 0)
	var arms_basis: Basis = MODELS.source_rotation(Vector3.RIGHT, arm_pitch)
	_arms.transform = Transform3D(arms_basis * scaler, arm_origin)
	var gait := sin(_time * TAU * 1.6) * 0.6 * clampf(_motion_speed / 6.0, -1.0, 1.0)
	for side in range(2):
		var sign_value := -1.0 if side == 0 else 1.0
		var leg_origin: Vector3 = MODELS.source_vector(Vector3(sign_value * 0.25, 0.2 if _crouching else 0, -0.1))
		var leg_basis: Basis = MODELS.source_rotation(Vector3.RIGHT, gait * sign_value) * scaler
		_legs[side].transform = Transform3D(leg_basis, leg_origin)
		_crouch_legs[side].transform = Transform3D(leg_basis, leg_origin)
		_legs[side].visible = not _dead and not _crouching
		_crouch_legs[side].visible = not _dead and _crouching
	var tool_basis := Basis.IDENTITY.scaled(Vector3.ONE * 0.05)
	if _tool == 0 or _tool == 2:
		tool_basis = Basis(Vector3.UP, PI) * tool_basis
	_equipment.transform = Transform3D(arms_basis * tool_basis,
		arm_origin + arms_basis * MODELS.source_vector(Vector3(0.35, -1, 0)))
