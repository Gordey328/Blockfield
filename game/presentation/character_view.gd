class_name CharacterView
extends Node3D
## Standing/crouching/dead assembly adapted from ClientPlayer.cpp's original parts.
## This node is anchored at feet; forward is local -Z, pitch is positive looking up.

const MODELS = preload("res://presentation/openspades_models.gd")
const BODY_SCALE := Vector3(0.1, 0.1, 0.1)
const ORIGIN_HEIGHT := 1.1
const WEAPONS := ["Rifle", "SMG", "Shotgun"]
const WORLD_AXES := Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN)
const MODEL_AXES_INVERSE := MODELS.SOURCE_AXES # Symmetric involution: S^-1 = S.
const SOURCE_BODY_SCALE := Basis(Vector3(-0.1,0,0),Vector3(0,-0.1,0),Vector3(0,0,0.1))
enum ToolAction { IDLE, BASH, DIG_START, DIG }

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
var _strafe_speed := 0.0
var _walk_progress := 0.0
var _tool_action := ToolAction.IDLE
var _action_progress := 0.0
var _cook_time := 0.0
var _ready_state := 1.0
var _raise_state := 1.0
var _block_color := Color(0.60,0.46,0.32)
var _ragdoll_enabled := false
var _rig: Node3D
var _torso: Node3D
var _crouch_torso: Node3D
var _head: Node3D
var _arms: Node3D
var _legs: Array[Node3D] = []
var _crouch_legs: Array[Node3D] = []
var _corpse: Node3D
var _equipment: Node3D
var _intel: Node3D
var _carrying_intel := false
var _intel_color := Color(-1,-1,-1,1)

func _ready() -> void:
	_ensure_built()

func refresh_resources() -> void:
	if not _built:
		return
	_rig.hide()
	_rig.queue_free()
	_built = false
	_equipment = null
	_intel = null
	_legs.clear()
	_crouch_legs.clear()
	_ensure_built()
	set_intel_carrier(_carrying_intel,_intel_color)

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_rig = Node3D.new()
	_rig.name = "OriginalCharacterParts"
	# World vectors and imported mesh vectors use different source-Y directions.
	# Convert each native matrix explicitly instead of mirroring tool hand offsets.
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
	# Native cg_ragdoll=0 fallback: Translate(GetOrigin + (0,0,1))*Scale(.1).
	_corpse.transform = source_transform(Basis.IDENTITY.scaled(BODY_SCALE),Vector3(0,0,1))
	_rig.add_child(_corpse)
	_corpse.top_level = true # Native fallback has no player yaw or pitch transform.
	_rebuild_equipment()
	MODELS.set_tint(_rig, _team_color)
	_update_equipment_tint()
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
		_update_equipment_tint()
	visible = index < 2
	_update_intel_tint()

func set_intel_carrier(carrying: bool, enemy_color: Color = Color(-1,-1,-1,1)) -> void:
	_ensure_built()
	_carrying_intel = carrying
	_intel_color = enemy_color
	if carrying and not is_instance_valid(_intel):
		_intel = MODELS.create("MapObjects/Intel")
		_intel.name = "CarriedEnemyIntel"
		_rig.add_child(_intel)
	_update_intel_tint()
	_apply_pose()

func _update_intel_tint() -> void:
	if is_instance_valid(_intel):
		MODELS.set_tint(_intel,_intel_color if _intel_color.r >= 0 else MODELS.TEAM_COLORS[1-clampi(_team,0,1)])

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
	_strafe_speed = 0.0
	_walk_progress = time * 1.6
	_apply_pose()

func set_motion_state(forward_speed: float, strafe_speed: float, walk_progress: float) -> void:
	_ensure_built()
	_motion_speed = clampf(forward_speed,-32.0,32.0)
	_strafe_speed = clampf(strafe_speed,-32.0,32.0)
	_walk_progress = walk_progress if is_finite(walk_progress) else 0.0
	_apply_pose()

func set_tool_action(action: int = ToolAction.IDLE, progress: float = 0.0, cook_time: float = 0.0,
		ready_state: float = 1.0, raise_state: float = 1.0) -> void:
	_ensure_built()
	_tool_action = clampi(action,ToolAction.IDLE,ToolAction.DIG)
	_action_progress = clampf(progress,0.0,1.0)
	_cook_time = maxf(cook_time,0.0)
	_ready_state = clampf(ready_state,0.0,1.0)
	_raise_state = clampf(raise_state,0.0,1.0)
	# Original third-person block/grenade skins receive these values but do not
	# animate them. Spade Bash alone contributes the native PitchBias.
	_apply_pose()

func set_block_color(color: Color) -> void:
	_ensure_built()
	_block_color = color
	if _tool == 1:
		MODELS.set_tint(_equipment,color)

func set_ragdoll_enabled(enabled: bool) -> void:
	_ragdoll_enabled = enabled
	_apply_pose()

static func source_transform(basis: Basis, origin: Vector3) -> Transform3D:
	return Transform3D(WORLD_AXES * basis * MODEL_AXES_INVERSE, WORLD_AXES * origin)

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
	_update_equipment_tint()

func _update_equipment_tint() -> void:
	# Original third-person skins only assign customColor for blocks. Other skins
	# retain ModelRenderParam's black default rather than coloring gun/tool voxels.
	MODELS.set_tint(_equipment,_block_color if _tool == 1 else Color.BLACK)

func _apply_pose() -> void:
	if not _built:
		return
	# The source changes player origin on crouch. A feet-anchored view must do so too.
	_rig.position.y = 0.7 if _crouching else ORIGIN_HEIGHT
	_corpse.visible = _dead and not _ragdoll_enabled
	if _corpse.visible:
		var dead_basis := source_transform(Basis.IDENTITY.scaled(BODY_SCALE),Vector3.ZERO).basis
		_corpse.global_transform = Transform3D(dead_basis,global_position+Vector3.UP*(_rig.position.y-1.0))
	_torso.visible = not _dead and not _crouching
	_crouch_torso.visible = not _dead and _crouching
	_head.visible = not _dead
	_arms.visible = not _dead
	_equipment.visible = not _dead
	var scaler := SOURCE_BODY_SCALE
	var torso_height := 0.55 if _crouching else 1.0
	var torso_origin := Vector3(0, 0, -torso_height)
	_torso.transform = source_transform(scaler, torso_origin)
	_crouch_torso.transform = source_transform(scaler, torso_origin)
	if is_instance_valid(_intel):
		# ClientPlayer.cpp: torso * Translate(0, .6, .5) * Scale(.1).
		_intel.transform = source_transform(scaler, torso_origin + Vector3(0, 0.6, 0.5))
		_intel.visible = _carrying_intel and not _dead
	_head.transform = source_transform(Basis(Vector3.RIGHT,_pitch) * scaler, torso_origin)
	var arm_pitch := _pitch - (0.5 if _sprinting else 0.0)
	if _tool == 0 and _tool_action == ToolAction.BASH:
		arm_pitch -= (1.0-_action_progress)*0.7
	if arm_pitch < 0.0:
		arm_pitch = maxf(arm_pitch, -PI * 0.5) * 0.9
	var arm_origin := torso_origin + Vector3(0, 0, 0 if _crouching else 0.1)
	var arms_basis := Basis(Vector3.RIGHT,arm_pitch)
	_arms.transform = source_transform(arms_basis * scaler, arm_origin)
	var gait := sin(_walk_progress * TAU) * 0.6
	var forward_angle := gait * _motion_speed / 32.0 * 4.0
	var strafe_angle := gait * _strafe_speed / 32.0 * 3.0
	for side in range(2):
		var sign_value := -1.0 if side == 0 else 1.0
		var leg_origin := Vector3(sign_value * 0.25, 0.2 if _crouching else 0, -0.1)
		var leg_basis := Basis(Vector3.RIGHT,-sign_value*forward_angle) * Basis(Vector3.UP,-sign_value*strafe_angle) * scaler
		_legs[side].transform = source_transform(leg_basis, leg_origin)
		_crouch_legs[side].transform = source_transform(leg_basis, leg_origin)
		_legs[side].visible = not _dead and not _crouching
		_crouch_legs[side].visible = not _dead and _crouching
	var tool_basis := Basis.IDENTITY.scaled(Vector3.ONE * 0.05)
	if _tool == 0 or _tool == 2:
		tool_basis = Basis(Vector3(0,0,1),PI) * tool_basis
	_equipment.transform = source_transform(arms_basis * tool_basis,
		arm_origin + arms_basis * Vector3(0.35,-1,0))
