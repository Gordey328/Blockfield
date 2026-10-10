class_name WeaponView
extends Node3D
signal tool_raised(tool: int,weapon: int)
## First-person original parts and skin animation stages, in camera-local space.
## Source: Resources/Scripts/Skin/*/View.as and ClientPlayer.cpp view-arm IK.

const MODELS = preload("res://presentation/openspades_models.gd")
const WEAPONS := ["Rifle", "SMG", "Shotgun"]
const VIEW_SCALE := 0.033
const RELOAD_SECONDS := [2.5, 2.5, 0.5]
const FIRE_SECONDS := [0.5,0.1,1.0]
const VIEW_LAYER := 1 << 18 # Layer 19; water-reflection camera excludes view equipment.
enum ToolAction { IDLE,BASH,DIG_START,DIG }

var _built := false
var _tool := 2
var _weapon := 0
var _rig: Node3D
var _source_root: Node3D
var _requested_tool := 2
var _requested_weapon := 0
var _parts: Dictionary = {}
var _forearms: Array[Node3D] = []
var _upperarms: Array[Node3D] = []
var _team_color := Color(0.18, 0.42, 0.86)
var _block_color := Color(0.60, 0.46, 0.32)
var _aim := 0.0
var _animations_enabled:=true
var _sprint := 0.0
var _sprint_state := 0.0
var _raise := 1.0
var _raise_raw := 1.0
var _vibration := 0.0
var _time := 0.0
var _fire_elapsed := 1000.0
var _reloading := false
var _reload_elapsed := 0.0
var _reload_progress := 0.0
var _last_external_reload := 0.0
var _cook_time := 0.0
var _digging := false
var _dig_progress := 0.0
var _ammo := 10
var _clip_size := 10
var _left_hand := Vector3.ZERO
var _right_hand := Vector3.ZERO
var _hand_matrix := Transform3D.IDENTITY
var _action_type := ToolAction.IDLE
var _action_progress := 0.0
var _source_action := false
var _ready_state := 1.0
var _source_ready := false
var _first_dig := true
var _post_reload_elapsed := -1.0
var _source_motion := false
var _local_velocity := Vector3.ZERO
var _walk_progress := 0.0
var _front_delta := Vector3.ZERO
var _manual_offset := Vector3.ZERO
var _view_offset := Vector3.ZERO
var _simulation_state: Dictionary = {}
const SIMULATION_FIELDS := ["desired_tool","displayed_tool","weapon","displayed_weapon","tool_raise","sprint_state","aim_down_state"]

func _ready() -> void:
	_ensure_built()

func refresh_resources() -> void:
	if not _built:
		return
	var sprint_state := _sprint
	var reload_state := [_reloading,_reload_elapsed,_reload_progress,_last_external_reload,_fire_elapsed]
	for node in [_rig] + _forearms + _upperarms:
		node.hide()
		node.queue_free()
	_built = false
	_parts.clear()
	_forearms.clear()
	_upperarms.clear()
	_ensure_built()
	_sprint = sprint_state
	_reloading = reload_state[0]
	_reload_elapsed = reload_state[1]
	_reload_progress = reload_state[2]
	_last_external_reload = reload_state[3]
	_fire_elapsed = reload_state[4]
	if _tool == 2:
		_update_gun(Vector3.ZERO)
	else:
		_update_tool(Vector3.ZERO)
	_update_view_arms()

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	if not is_instance_valid(_source_root):
		_source_root = Node3D.new()
		_source_root.name = "SourceViewAxes"
		# GetEyeMatrix x=-Right, while scene viewAxis0=-eyeAxis0. Imported mesh
		# coordinates use (x,-z,-y); native view coordinates need (-x,-z,-y).
		_source_root.scale.x = -1.0
		add_child(_source_root)
	_rig = Node3D.new()
	_rig.name = "OriginalViewEquipment"
	_source_root.add_child(_rig)
	for side in range(2):
		var forearm: Node3D = MODELS.create("Player/Arm", true)
		var upperarm: Node3D = MODELS.create("Player/UpperArm", true)
		_set_view_layer(forearm)
		_set_view_layer(upperarm)
		forearm.name = "Forearm" + str(side)
		upperarm.name = "UpperArm" + str(side)
		_source_root.add_child(forearm)
		_source_root.add_child(upperarm)
		_forearms.append(forearm)
		_upperarms.append(upperarm)
		MODELS.set_tint(forearm, _team_color)
		MODELS.set_tint(upperarm, _team_color)
	_rebuild_parts()
	update_pose(0.0, false, false, false, 0.0)

func set_selection(tool: int, weapon: int) -> void:
	if not _simulation_state.is_empty():return
	_ensure_built()
	tool = clampi(tool, 0, 3)
	weapon = clampi(weapon, 0, 2)
	if _requested_tool == tool and _requested_weapon == weapon:
		return
	_requested_tool = tool
	_requested_weapon = weapon
	# Source lowers the old tool before replacing it, then raises the new one.
	# A lab weapon-class change has no native live-switch counterpart: rebuild it
	# immediately with the same native raising curve, while authority owns ammo.
	if _tool == tool and _weapon != weapon:
		_weapon = weapon
		_raise_raw = 0.0
		_rebuild_parts()
		tool_raised.emit(_tool,_weapon)
	_cook_time = 0.0
	_fire_elapsed = 1000.0
	_vibration = 0.0
	_digging = false
	_first_dig = true
	_source_action = false
	_source_ready = false
	_action_type = ToolAction.IDLE
	_reloading = false
	_post_reload_elapsed = -1.0

func initialize_selection(tool: int, weapon: int) -> void:
	# Initial selection for a newly created camera-target skin. This is not a live
	# tool change, so no lowering/raising delay or RaiseLocal signal is generated.
	_ensure_built()
	_tool = clampi(tool,0,3)
	_weapon = clampi(weapon,0,2)
	_requested_tool = _tool
	_requested_weapon = _weapon
	_raise_raw = 1.0
	_raise = 1.0
	_rebuild_parts()
	update_pose(0.0,false,false,false,0.0)

func set_team(index: int, color: Color = Color(-1, -1, -1, 1)) -> void:
	_ensure_built()
	var next_color: Color = MODELS.TEAM_COLORS[clampi(index, 0, 1)] if color.r < 0 else color
	if next_color == _team_color:
		return
	_team_color = next_color
	for side in range(2):
		MODELS.set_tint(_forearms[side], _team_color)
		MODELS.set_tint(_upperarms[side], _team_color)

func set_block_color(color: Color) -> void:
	_ensure_built()
	_block_color = color
	if _tool == 1:
		MODELS.set_tint(_rig, _block_color)

func set_ammo(ammo: int, clip_size: int) -> void:
	_ammo = ammo
	_clip_size = clip_size

func set_grenade_cook(seconds: float) -> void:
	_cook_time = maxf(seconds, 0.0)

func set_spade_action(digging: bool, progress: float = 0.0) -> void:
	if not digging: _first_dig = true
	elif _digging and progress < _dig_progress: _first_dig = false
	_digging = digging
	_dig_progress = clampf(progress, 0.0, 1.0)
	_source_action = false

func set_tool_action(action: int, progress: float, ready_state: float = 1.0) -> void:
	_action_type = clampi(action,ToolAction.IDLE,ToolAction.DIG)
	_action_progress = clampf(progress,0.0,1.0)
	_ready_state = ready_state if is_finite(ready_state) else 1.0
	_source_action = true
	_source_ready = true

func set_motion_state(local_velocity: Vector3, walk_progress: float,
		front_delta: Vector3 = Vector3.ZERO, manual_offset: Vector3 = Vector3.ZERO) -> void:
	_source_motion = true
	_local_velocity = local_velocity if local_velocity.is_finite() else Vector3.ZERO
	_walk_progress = walk_progress if is_finite(walk_progress) else 0.0
	_front_delta = front_delta if front_delta.is_finite() else Vector3.ZERO
	_manual_offset = manual_offset if manual_offset.is_finite() else Vector3.ZERO

func set_simulation_state(values: Dictionary) -> bool:
	# A network skin mirrors approved predicted/confirmed owner state. Validate
	# the complete scalar record atomically; render delta must not step gates.
	if values.size()!=SIMULATION_FIELDS.size():return false
	for field: String in SIMULATION_FIELDS:
		if not values.has(field):return false
	for field: String in ["desired_tool","displayed_tool","weapon","displayed_weapon"]:
		if typeof(values[field])!=TYPE_INT:return false
		var limit:=3 if field.ends_with("tool") else 2
		if values[field]<0 or values[field]>limit:return false
	for field: String in ["tool_raise","sprint_state","aim_down_state"]:
		if typeof(values[field]) not in [TYPE_FLOAT,TYPE_INT]:return false
		if not is_finite(float(values[field])) or values[field]<0 or values[field]>1:return false
	_ensure_built()
	_simulation_state=values.duplicate()
	_apply_simulation_state()
	return true

func clear_simulation_state() -> void:
	# Preserve the last presentation pose and resume the existing offline clocks.
	_simulation_state.clear()

func _apply_simulation_state() -> void:
	var rebuild:=_tool!=int(_simulation_state.displayed_tool) or _weapon!=int(_simulation_state.displayed_weapon)
	_requested_tool=int(_simulation_state.desired_tool)
	_requested_weapon=int(_simulation_state.weapon)
	_tool=int(_simulation_state.displayed_tool)
	_weapon=int(_simulation_state.displayed_weapon)
	_raise_raw=float(_simulation_state.tool_raise)
	_raise=1.0-minf(pow(1.0-_raise_raw,2.0)*1.5,1.0)
	_sprint_state=float(_simulation_state.sprint_state)
	_aim=float(_simulation_state.aim_down_state)
	if rebuild:_rebuild_parts()

func fire() -> void:
	_vibration = 1.0
	_fire_elapsed = 0.0
	_cook_time = 0.0

func reload() -> void:
	_reloading = true
	_reload_elapsed = 0.0
	_reload_progress = 0.0
	_last_external_reload = 0.0
	_post_reload_elapsed = -1.0

func cancel_reload() -> void:
	if not _reloading and _post_reload_elapsed >= 0.0:
		return # Owner's completed-reload cleanup must not cancel the native pump.
	_reloading = false
	_reload_progress = 0.0
	_last_external_reload = 0.0
	_post_reload_elapsed = -1.0

func reload_completed() -> void:
	_reloading = false
	_last_external_reload = 0.0
	_reload_progress = 1.0
	_post_reload_elapsed = 0.0 if _weapon == 2 else -1.0

func update_pose(delta: float, aiming: bool, sprinting: bool, crouching: bool,
		speed: float, reload_progress: float = 0.0) -> void:
	_ensure_built()
	_time += delta
	_fire_elapsed += delta
	_vibration = maxf(_vibration - delta * 10.0, 0.0)
	if not _simulation_state.is_empty():
		_apply_simulation_state()
	else:
		_advance_selection(delta)
		_aim = clampf(_aim+delta*(8.0 if aiming and _requested_tool==2 and not sprinting else -3.0),0.0,1.0)
		if not _animations_enabled:_aim=1.0 if aiming and _requested_tool==2 and not sprinting else 0.0
		_sprint_state = clampf(_sprint_state+delta*(4.0 if sprinting else -3.0),0.0,1.0)
	var sprint_target := pow(smoothstep(0.0,1.0,_sprint_state),2.0)
	if sprint_target > _sprint:
		_sprint += (sprint_target - _sprint) * (1.0 - pow(0.001, delta))
	else:
		_sprint = sprint_target
	_update_reload(delta, reload_progress)
	if not _source_ready:
		_ready_state = _fire_elapsed/0.5 if _tool==3 else (float(_fire_elapsed>=0.5) if _tool==1 else _fire_elapsed/float(FIRE_SECONDS[_weapon]))
	var swing := _update_swing(delta,aiming,speed)
	if _tool == 2:
		_update_gun(swing)
	else:
		_update_tool(swing)
	_update_view_arms()

func _advance_selection(delta: float) -> void:
	if _tool != _requested_tool:
		_raise_raw -= delta*4.0
		if _raise_raw < 0.0:
			_raise_raw = 0.0
			_tool = _requested_tool
			_weapon = _requested_weapon
			_rebuild_parts()
			tool_raised.emit(_tool,_weapon)
	else:
		_raise_raw = minf(_raise_raw+delta*4.0,1.0)
	_raise = 1.0-minf(pow(1.0-_raise_raw,2.0)*1.5,1.0)

func _soft_limit(value: float, low: float, high: float) -> float:
	var transition := (high-low)*0.5
	if value < low: return lerpf(value,low,minf((low-value)/transition,1.0))
	if value > high: return lerpf(value,high,minf((value-high)/transition,1.0))
	return value

func _update_swing(delta: float, aiming: bool, speed: float) -> Vector3:
	var phase := _walk_progress if _source_motion else _time*1.6
	var velocity := _local_velocity/32.0 if _source_motion else Vector3(0,0,-absf(speed)/32.0)
	_view_offset += Vector3(velocity.x,velocity.z,velocity.y)*delta
	_view_offset += Vector3(_front_delta.x,0,_front_delta.y)*0.05
	_front_delta = Vector3.ZERO
	_view_offset *= pow(0.02,delta)
	for axis in range(3): _view_offset[axis] = _soft_limit(_view_offset[axis],-0.06,0.06)
	if aiming and _tool == 2:
		_view_offset *= pow(0.01,delta)
		_view_offset.x = _soft_limit(_view_offset.x,-0.003,0.003)
		_view_offset.z = _soft_limit(_view_offset.z,0,0.003)
	var swing := _view_offset
	var gain := 1.0-_aim
	var bob_gain := gain*0.3*minf(1.0,velocity.length()*5.0)
	swing.x += sin(phase*TAU)*0.013*bob_gain
	swing.z += pow(cos(phase*TAU),2.0)*0.018*bob_gain
	swing += Vector3(0.001,0.0007,0.003)*sin(_time)*gain
	swing += _manual_offset*gain
	return swing

func get_eye_bob() -> float:
	return pow(cos(_walk_progress*TAU-0.8),16.0)*0.06*smoothstep(0.0,1.0,_sprint_state)

func get_sprint_state() -> float:
	return _sprint_state

func is_changing_tool() -> bool:
	# ClientPlayer::IsChangingTool compares the raw counter, not the eased skin
	# RaiseState: a nearly raised mesh must still obey the native use-tool gate.
	return _tool != _requested_tool or _raise_raw < 0.999

func _update_reload(delta: float, external_progress: float) -> void:
	if external_progress > 0.0:
		_reloading = external_progress < 1.0
		_reload_progress = clampf(external_progress, 0.0, 1.0)
		_reload_elapsed = _reload_progress * float(RELOAD_SECONDS[_weapon])
		_last_external_reload = external_progress
	elif _last_external_reload > 0.9:
		reload_completed()
	elif _reloading:
		_reload_elapsed += delta
		_reload_progress = clampf(_reload_elapsed / float(RELOAD_SECONDS[_weapon]), 0.0, 1.0)
		if _reload_progress >= 1.0:
			reload_completed()
	elif _post_reload_elapsed >= 0.0:
		_post_reload_elapsed += delta
		_reload_progress = 1.0+_post_reload_elapsed/float(RELOAD_SECONDS[_weapon])

func _rebuild_parts() -> void:
	for child in _rig.get_children():
		if child is Node3D:
			(child as Node3D).hide()
		child.queue_free()
	_parts.clear()
	if _tool == 2:
		var group: String = "Weapons/" + WEAPONS[_weapon] + "/"
		if _weapon == 0:
			_add_part("body", group + "WeaponNoMagazine", 0.5, Vector3(-0.25, 0, 0))
			_add_part("rear_sight", group + "Sight1", 0.025, Vector3(0.0125, -8, -4.5))
			_add_part("front_sight", group + "Sight2", 0.05, Vector3(0.025, 16, -4.575))
			_add_part("magazine", group + "Magazine", 1, Vector3(0, 1, 1))
		elif _weapon == 1:
			_add_part("body", group + "WeaponNoMagazine")
			_add_part("front_sight", group + "Sight1", 0.1, Vector3(0.05, 5, -4.85))
			_add_part("front_pin", group + "Sight3", 0.05, Vector3(0.025, 5, -4.875))
			_add_part("rear_sight", group + "Sight2", 0.08, Vector3(0.04, -9, -4.9))
			_add_part("magazine", group + "Magazine", 1, Vector3(0, 3, 1))
		else:
			_add_part("body", group + "WeaponNoPump")
			_add_part("rear_sight", group + "Sight2", 0.05, Vector3(0.025, -9, -4.4))
			_add_part("front_sight", group + "Sight1", 0.05, Vector3(0.025, 8.5, -4.4))
			_add_part("pump", group + "Pump")
	else:
		var path: String = "Weapons/Spade/Spade"
		if _tool == 1:
			path = "Weapons/Block/Block2"
		elif _tool == 3:
			path = "Weapons/Grenade/Grenade"
		_add_part("body", path)
	MODELS.set_tint(_rig,_block_color if _tool==1 else Color.BLACK)

func _add_part(key: String, path: String, scalar: float = 1.0, source_offset: Vector3 = Vector3.ZERO) -> void:
	var model: Node3D = MODELS.create(path, true)
	_set_view_layer(model)
	model.name = key
	model.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scalar), MODELS.source_vector(source_offset))
	_rig.add_child(model)
	_parts[key] = model

func _set_view_layer(node: Node) -> void:
	if node is MeshInstance3D or node is MultiMeshInstance3D: node.layers = VIEW_LAYER
	for child in node.get_children(): _set_view_layer(child)

func _rotate_before(matrix: Transform3D, axis: Vector3, angle: float) -> Transform3D:
	return Transform3D(MODELS.source_rotation(axis, angle), Vector3.ZERO) * matrix

func _basic_matrix(swing: Vector3) -> Transform3D:
	var matrix := Transform3D.IDENTITY
	if _sprint > 0:
		matrix = _rotate_before(matrix, Vector3(0, 1, 0), _sprint * -0.1)
		matrix = _rotate_before(matrix, Vector3.RIGHT, _sprint * 0.3)
		matrix = _rotate_before(matrix, Vector3(0, 0, 1), _sprint * -0.55)
		matrix = MODELS.source_translation(Vector3(0.23, -0.05, 0.15) * _sprint) * matrix
	var put_down := 1.0 - _raise
	matrix = _rotate_before(matrix, Vector3(0, 0, 1), put_down * -1.3)
	matrix = _rotate_before(matrix, Vector3(0, 1, 0), put_down * 0.2)
	matrix = MODELS.source_translation(Vector3(0.1, -0.3, 0.1) * put_down) * matrix
	var aim_amount := smoothstep(0.0, 1.0, _aim)
	var gain := 1.0 - aim_amount * 0.4
	var offsets := [0.052, 0.038, 0.0535]
	var z_position: float = 0.2 - aim_amount * float(offsets[_weapon])
	var vib := _vibration
	var hip := Vector3(sin(vib * TAU) * 0.008, vib * (vib - 1.0) * 0.14, vib * (1.0 - vib) * 0.03) * gain
	var ads := Vector3(0, vib * (vib - 1.0) * vib * 0.3, 0) * gain
	var offset := Vector3(-0.13 * (1.0 - aim_amount), 0.5, z_position)
	offset += swing * gain + hip.lerp(ads, aim_amount)
	matrix = MODELS.source_translation(offset) * matrix
	return matrix.scaled_local(Vector3.ONE * VIEW_SCALE)

func _align_sight(matrix: Transform3D, source_point: Vector3) -> Transform3D:
	var fade := clampf((smoothstep(0.0, 1.0, _aim) - 0.8) / 0.2, 0, 1)
	if fade <= 0:
		return matrix
	var point: Vector3 = MODELS.SOURCE_AXES.inverse() * (matrix * MODELS.source_vector(source_point))
	if absf(point.y) > 0.0001:
		matrix = _rotate_before(matrix, Vector3(0, 0, 1), atan(point.x / point.y) * fade)
		matrix = _rotate_before(matrix, Vector3(-1, 0, 0), atan(point.z / point.y) * fade)
	return matrix

func _update_gun(swing: Vector3) -> void:
	var matrix := _basic_matrix(swing)
	_hand_matrix = matrix # Native hands/rest targets are set before sight alignment.
	var points := [Vector3(0, 16, -4.6), Vector3(0, 5, -4.9), Vector3(0, 8.5, -4.4)]
	_rig.transform = _align_sight(matrix, points[_weapon])
	_rig.visible = true
	_left_hand = _hand_point(Vector3(1, 6, 1))
	_right_hand = _hand_point(Vector3(0, -8, 4 if _weapon == 1 else 2))
	match _weapon:
		0: _rifle_reload_hands()
		1: _smg_reload_hands()
		2: _shotgun_hands()

func _hand_point(value: Vector3) -> Vector3:
	return (_hand_matrix if _tool==2 else _rig.transform)*MODELS.source_vector(value)

func _aligned_hand_point(value: Vector3) -> Vector3:
	return _rig.transform*MODELS.source_vector(value)

func _magazine_point(offset: Vector3) -> Vector3:
	var magazine := _parts["magazine"] as Node3D
	return _rig.transform * (magazine.transform * MODELS.source_vector(offset))

func _smooth(value: float) -> float:
	return smoothstep(0.0, 1.0, clampf(value, 0, 1))

func _rifle_reload_hands() -> void:
	var magazine := _parts["magazine"] as Node3D
	magazine.position = MODELS.source_vector(Vector3(0, 1, 1))
	if not _reloading:
		return
	var stage := _reload_progress * 2.5
	var left_rest := _left_hand
	var right_rest := _right_hand
	var discard := _hand_point(Vector3(5, -10, 4))
	var right_bolt := _hand_point(Vector3(-2, -7, -4))
	var right_pull := _hand_point(Vector3(-3, -4, -6))
	if stage < 0.1:
		_left_hand = _left_hand.lerp(_magazine_point(Vector3(0, 0, 4)), _smooth(stage / 0.1))
	elif stage < 0.7:
		var per := (stage - 0.1) / 0.6
		if per < 0.2:
			per = clampf(per * 4.0 - 0.4, 0, 0.2)
		if per > 0.5:
			per += per - 0.5
		magazine.position = MODELS.source_vector(Vector3(0, 1, 1 + per * per * 10))
		_left_hand = _magazine_point(Vector3(0, 0, 4))
		if per > 0.5:
			_left_hand = _left_hand.lerp(discard, _smooth(per - 0.5))
	elif stage < 1.4:
		var per := (1.4 - stage) / 0.7
		if per < 0.3:
			per = clampf(per * 4.0 - 0.4, 0, 0.3)
		magazine.position = MODELS.source_vector(Vector3(0, 1, 1 + per * per * 10))
		_left_hand = _magazine_point(Vector3(0, 0, 4))
	elif stage < 1.9:
		var per := _smooth((stage - 1.4) / 0.5)
		_left_hand = _magazine_point(Vector3(0, 0, 4)).lerp(left_rest, per)
		_right_hand = right_rest.lerp(right_bolt, per)
	elif stage < 2.2:
		_right_hand = right_bolt.lerp(right_pull, _smooth((stage - 1.9) / 0.3))
	else:
		_right_hand = right_pull.lerp(right_rest, _smooth((stage - 2.2) / 0.3))

func _smg_reload_hands() -> void:
	var magazine := _parts["magazine"] as Node3D
	magazine.position = MODELS.source_vector(Vector3(0, 3, 1))
	if not _reloading:
		return
	var stage := _reload_progress * 2.5
	var left_rest := _left_hand
	var discard := _hand_point(Vector3(5, -10, 4))
	var charge := _hand_point(Vector3(1, 6, -4))
	var pull := _hand_point(Vector3(1, 9, -6))
	if stage < 0.7:
		var per := stage / 0.7
		magazine.position = MODELS.source_vector(Vector3(0, 3, 1 + per * per * 50))
		_left_hand = _left_hand.lerp(discard, _smooth(per))
	elif stage < 1.4:
		var per := (1.4 - stage) / 0.7
		if per < 0.3:
			per = clampf(per * 4.0 - 0.4, 0, 0.3)
		magazine.position = MODELS.source_vector(Vector3(0, 3, 1 + per * per * 10))
		_left_hand = _magazine_point(Vector3(0, 0, 4))
	elif stage < 1.9:
		_left_hand = _magazine_point(Vector3(0, 0, 4)).lerp(charge, _smooth((stage - 1.4) / 0.5))
	elif stage < 2.2:
		_left_hand = charge.lerp(pull, _smooth((stage - 1.9) / 0.3))
	else:
		_left_hand = pull.lerp(left_rest, _smooth((stage - 2.2) / 0.3))

func _shotgun_hands() -> void:
	_left_hand = _aligned_hand_point(Vector3(0, 4, 2))
	if _reloading:
		var stage := _reload_progress * 0.5
		var left_rest := _left_hand
		var reach := _hand_point(Vector3(5, -10, 4))
		var insert := _hand_point(Vector3(1, 1, 2))
		if stage < 0.2:
			_left_hand = left_rest.lerp(reach, _smooth(stage / 0.2))
		elif stage < 0.35:
			_left_hand = reach.lerp(insert, _smooth((stage - 0.2) / 0.15))
		else:
			_left_hand = insert.lerp(left_rest, _smooth((stage - 0.35) / 0.15))
	var cock := 0.0
	var timing := 1.0-_ready_state
	if timing < 0.0:
		var stage := _reload_progress*0.5
		if _ammo>=_clip_size and stage>0.5 and stage<1.0:
			timing = stage-0.5
			if timing>=0.05 and timing<0.12: cock = (timing-0.05)/0.07
			elif timing>=0.12 and timing<0.26: cock = 1.0
			elif timing>=0.26 and timing<0.36: cock = 1.0-(timing-0.26)/0.1
	elif timing>=0.2 and timing<0.3: cock = (timing-0.2)/0.1
	elif timing>=0.3 and timing<0.42: cock = 1.0
	elif timing>=0.42 and timing<0.52: cock = 1.0-(timing-0.42)/0.1
	var cock_fade := 1.0
	if _reloading:
		cock_fade = 0.0 if _reload_progress < 0.5 or _ammo < _clip_size - 1 else clampf((_reload_progress * 0.5 - 0.25) * 10, 0, 1)
	cock *= cock_fade
	var pump := _parts["pump"] as Node3D
	pump.position = MODELS.source_vector(Vector3(0, cock * -1.5, 0))
	if cock_fade > 0:
		_left_hand = _left_hand.lerp(_rig.transform * (pump.transform * MODELS.source_vector(Vector3(0, 4, 2))), cock_fade)

func _update_tool(swing: Vector3) -> void:
	var matrix := Transform3D.IDENTITY.scaled_local(Vector3.ONE * VIEW_SCALE)
	var put_down := 1.0 - _raise
	_rig.visible = true
	if _tool == 0:
		var action := _action_type if _source_action else (ToolAction.DIG_START if _digging and _first_dig else (ToolAction.DIG if _digging else (ToolAction.BASH if _fire_elapsed<0.2 else ToolAction.IDLE)))
		var progress := _action_progress if _source_action else (_dig_progress if _digging else clampf(_fire_elapsed/0.2,0.0,1.0))
		if action == ToolAction.DIG_START or action == ToolAction.DIG:
			var angle := 0.6
			var front := -0.8
			var side := 1.0
			if progress < 0.5:
				if action == ToolAction.DIG_START:
					var per := 4.0*progress*progress
					angle = per*0.6
					side = per
					front = per*-0.8
				else:
					var per := pow((0.5 - progress) / 0.5, 4)
					angle += per * 0.6
					front += per * 2.0
			else:
				var per := 1.0 - pow(1.0 - (progress - 0.5) / 0.5, 2)
				angle += per * 0.6
				front += per * 2.0
			matrix = _rotate_before(matrix, Vector3.RIGHT, angle)
			matrix = _rotate_before(matrix, Vector3(0, 0, 1), front * 0.15)
			matrix = MODELS.source_translation(Vector3(side*0.3, front * 0.1, front * 0.02)) * matrix
		elif action == ToolAction.BASH:
			var bash := 1.0-progress
			matrix = _rotate_before(matrix, Vector3.RIGHT, bash * 1.7)
			matrix = MODELS.source_translation(Vector3(0, bash * 0.3, 0)) * matrix
		var per := maxf(_sprint, put_down)
		matrix = _rotate_before(matrix, Vector3(0, 1, 0), per * 1.3)
		matrix = MODELS.source_translation(Vector3(0.3, -0.4, -0.1) * per) * matrix
		matrix = MODELS.source_translation(Vector3(-0.3, 0.7 - put_down * 0.3, 0.3) + swing) * matrix
		_rig.transform = matrix
		_left_hand = _hand_point(Vector3(0, 0, 7))
		_right_hand = _hand_point(Vector3(0, 0, -2))
	elif _tool == 1:
		if _ready_state < 0.99:
			_rig.visible = false
			_left_hand = MODELS.source_vector(Vector3(0.5,0.5,0.6))
			_right_hand = MODELS.source_vector(Vector3(-0.5,0.5,0.6))
			return
		matrix = _rotate_before(matrix, Vector3(0, 0, 1), _sprint * -0.3)
		matrix = MODELS.source_translation(Vector3(0.1, -0.4, -0.05) * _sprint) * matrix
		matrix = MODELS.source_translation(Vector3(-0.3, 0.7, 0.3) + swing + Vector3(-0.1, -0.3, 0.2) * put_down) * matrix
		_rig.transform = matrix
		_left_hand = _hand_point(Vector3(5, -1, 4))
		_right_hand = _hand_point(Vector3(-5.5, 3, -5))
	else:
		var pin := minf(_cook_time * 8.0, 2.0)
		var side := maxf(pin - 1.0, 0.0)
		var bring := minf((_ready_state-1.0)*2.0,1.0)
		bring = 1.0-pow(1.0-bring,2.0)-side*2.0
		matrix = _rotate_before(matrix, Vector3(0, 0, 1), _sprint * -0.3)
		matrix = MODELS.source_translation(Vector3(0.1, -0.2, -0.05) * _sprint) * matrix
		matrix = MODELS.source_translation(Vector3(-0.3 - side * 0.8, 0.8 - bring * 0.1, 0.45 - bring * 0.15)
			+ swing + Vector3(-0.1, -0.3, 0.1) * put_down) * matrix
		_rig.transform = matrix
		_rig.visible = _ready_state>0.9999
		_left_hand = _hand_point(Vector3(10, -1, 10))
		_right_hand = _hand_point(Vector3(-3, 1, 5))
		var pull := _hand_point(Vector3(2, 1, -2))
		if pin < 1:
			_left_hand = _left_hand.lerp(pull, pin)
		else:
			_left_hand = pull.lerp(_hand_point(Vector3(8, -1, 10)), pin - 1)
		if not _rig.visible:
			var per := minf(_ready_state * 3.0, 1.0)
			var arc := 0.9 - pow(per - 0.6, 2) * 2.5
			_left_hand = MODELS.source_vector(Vector3(0.5, 0.5, 0.6))
			_right_hand = MODELS.source_vector(Vector3(-0.2, arc, -0.9 + per * 1.8))

func _update_view_arms() -> void:
	# Solve the original equal-length two-segment arms, preserving original bend side.
	var shoulders := [Vector3(0.4, 0, 0.25), Vector3(-0.4, 0, 0.25)]
	var bend_directions := [Vector3(0.5, 0.2, 0), Vector3(-0.5, 0.2, 0)]
	var hands := [_left_hand, _right_hand]
	for side in range(2):
		var shoulder: Vector3 = shoulders[side]
		var hand: Vector3 = MODELS.SOURCE_AXES.inverse() * hands[side]
		var difference := hand - shoulder
		var bend_length := sqrt(maxf(0.25 - difference.length_squared() * 0.25, 0.0))
		var bend: Vector3 = bend_directions[side].cross(difference).normalized()
		if bend.z < 0:
			bend.z = -bend.z
		var elbow := (hand + shoulder) * 0.5 + bend * bend_length
		_arm_segment(_forearms[side], elbow, hand)
		_arm_segment(_upperarms[side], shoulder, elbow)

func _arm_segment(part: Node3D, start: Vector3, end: Vector3) -> void:
	var axis_z := (end - start).normalized()
	if axis_z.length_squared() < 0.0001:
		part.visible = false
		return
	part.visible = true
	var axis_x := Vector3(0, 0, 1)
	var axis_y := axis_z.cross(axis_x).normalized()
	if axis_y.length_squared() < 0.0001:
		axis_y = Vector3(0, 1, 0)
	axis_x = axis_y.cross(axis_z).normalized()
	var axes := Basis(axis_x, axis_y, axis_z)
	part.transform = Transform3D(MODELS.source_basis(axes).scaled(Vector3.ONE * 0.05), MODELS.source_vector(start))

func get_muzzle_transform() -> Transform3D:
	_ensure_built()
	# ClientPlayer::FiredWeapon uses this fixed eye-local point for all muzzle FX,
	# independent of ADS/reload and of the mesh's animated barrel location.
	return _source_root.global_transform*MODELS.source_translation(Vector3(-0.13,1.5,0.2))

func get_aim_down_state() -> float:
	return _aim

func get_displayed_tool() -> int:
	return _tool

func set_animations_enabled(enabled: bool) -> void:
	_animations_enabled=enabled
