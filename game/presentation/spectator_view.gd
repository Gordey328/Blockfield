class_name OpenSpadesSpectatorView
extends Node3D
## Camera-owned view equipment for an observed live soldier.
## ClientPlayer::Render uses AddToSceneFirstPerson for the camera target, not just
## the local player. This adapter reads snapshots and never calls game authority.
## The owner updates the follow-camera transform, then calls update_view(delta).

const EXTENSIONS = preload("res://presentation/openspades_extensions.gd")
const PROFILES = preload("res://gameplay/local_session.gd").WEAPON_PROFILES
const VIEW_LAYER := 1 << 18

var _camera: Camera3D
var _session: Object
var _skin: Node3D
var _skin_id := "original"
var _target_id := -1
var _enabled := false
var _skin_target := -1
var _profile := "0.75"
var animations_enabled:=true
var _has_profile_property := false
var _has_sample := false
var _last_position := Vector3.ZERO
var _last_front := Vector3.FORWARD
var _walk_progress := 0.0
var _was_reloading := false
var _last_reload_progress := 0.0
var _shot_sequence: Variant = null
var _visual_fire_age:=1.0e20

func _ready() -> void:
	hide()

func setup(camera: Camera3D,session: Object,skin_id: String = "original") -> void:
	clear()
	_camera = camera
	_session = session
	_skin_id = skin_id if skin_id in EXTENSIONS.get_skins() else "original"
	_profile = "0.75"
	_has_profile_property = false
	if is_instance_valid(_session):
		for property in _session.get_property_list():
			if property.name == "profile_version":
				_has_profile_property = true
				_profile = str(_session.get("profile_version"))
				break

func show_target(identifier: int,enabled: bool) -> void:
	if identifier == _target_id and enabled == _enabled: return
	_has_sample = false
	_target_id = identifier
	_enabled = enabled
	update_view(0.0)

func update_view(delta: float) -> void:
	if not _enabled or _target_id < 0 or not is_instance_valid(_camera) or not is_instance_valid(_session) or not _session.has_method("get_target"):
		_hide_target()
		return
	var value: Variant = _session.call("get_target",_target_id)
	if not value is Dictionary:
		_hide_target(true)
		return
	var target: Dictionary = value
	var point: Variant = target.get("position")
	var team := int(target.get("team",1))
	if target.is_empty() or not point is Vector3 or not point.is_finite() or not bool(target.get("alive",true)) or (bool(target.get("health_known",true)) and _number(target,"health",100.0)<=0.0) or team<0 or team>1 or str(target.get("state","standing"))=="dead":
		_hide_target(true)
		return
	var new_skin := not is_instance_valid(_skin) or _skin_target != _target_id
	if new_skin and not _replace_skin(target):
		_hide_target()
		return
	show()
	var animation_delta := clampf(delta,0.0,0.25) if is_finite(delta) else 0.0
	_visual_fire_age+=animation_delta
	var weapon := clampi(int(target.get("weapon",0)),0,2)
	var tool := clampi(int(target.get("tool",2)),0,3)
	_skin.set_selection(tool,weapon)
	_skin.set_team(team,_team_color(target,team))
	_skin.set_block_color(_color(target.get("block_color"),Color(0.6,0.46,0.32)))
	var version := str(target.get("profile",_session.get("profile_version") if _has_profile_property else _profile))
	var profile: Dictionary = PROFILES.get(version,PROFILES["0.75"])[weapon]
	var clip := maxi(1,int(target.get("clip_size",profile.clip_size)))
	_skin.set_ammo(maxi(0,int(target.get("ammo",target.get("magazine",clip)))),clip)
	_skin.set_grenade_cook(maxf(0.0,_number(target,"grenade_cook_time",_number(target,"cook_time",0.0))))
	var crouching := bool(target.get("crouching",str(target.get("state","standing"))=="crouching"))
	var sprinting := bool(target.get("sprinting",str(target.get("state","standing"))=="sprinting"))
	var aiming := bool(target.get("aiming",str(target.get("state","standing"))=="aiming"))
	var angles := Vector3(_number(target,"pitch",0.0),_number(target,"yaw",0.0),0)
	var axes := Basis.from_euler(angles)
	var front := -axes.z
	var motion := Vector3.ZERO
	if target.get("velocity") is Vector3:
		motion = _vector(target.velocity)
	elif _has_sample and is_finite(delta) and delta>0.00001:
		motion = (Vector3(point)-_last_position)/delta
	var front_delta := axes.inverse()*(front-_last_front) if _has_sample else Vector3.ZERO
	if _has_sample and not crouching and not aiming and not bool(target.get("sneaking",false)) and bool(target.get("on_ground",true)):
		_walk_progress += Vector2(Vector3(point).x-_last_position.x,Vector3(point).z-_last_position.z).length()*0.15
	_walk_progress = _number(target,"walk_progress",_walk_progress)
	if _skin.has_method("set_motion_state"):
		_skin.set_motion_state(axes.inverse()*motion,_walk_progress,front_delta)
	if _skin.has_method("set_aim"): _skin.set_aim(angles.x)
	if _skin.has_method("set_pose"): _skin.set_pose(crouching,false,sprinting)
	var action: Variant = target.get("action",target.get("action_type",0))
	var progress := _number(target,"action_progress",0.0)
	var action_type := 0
	var ready := _number(target,"ready_state",1.5 if tool==3 else (2.0 if tool==2 else 1.0))
	if action is Dictionary:
		action_type = int(action.get("type",0))
		progress = _number(action,"progress",progress)
		ready = _number(action,"ready",ready)
	elif action is int or action is float:
		action_type = int(action)
	if _skin.has_method("set_tool_action"):
		_skin.set_tool_action(clampi(action_type,0,3),clampf(progress,0.0,1.0),ready)
	else:
		_skin.set_spade_action(action_type>=2,clampf(progress,0.0,1.0))
	_update_reload(target,new_skin)
	# A sequence change triggers only the skin's visual recoil. No session fire,
	# damage, own-local audio or controller weapon event is called or connected.
	var sequence: Variant = target.get("shot_sequence",0)
	if _has_sample and sequence!=null and _shot_sequence!=null and sequence!=_shot_sequence:
		_skin.fire()
		_visual_fire_age=0.0
	_shot_sequence = sequence
	if _skin.has_method("set_animations_enabled"):_skin.set_animations_enabled(animations_enabled)
	_skin.update_pose(animation_delta,aiming,sprinting,crouching,motion.length(),_last_reload_progress if _was_reloading else 0.0)
	_set_view_layer(_skin)
	_last_position = point
	_last_front = front
	_has_sample = true

func refresh_resources() -> void:
	if is_instance_valid(_skin):
		_skin.refresh_resources()
		_set_view_layer(_skin)
	update_view(0.0)

func set_skin(id: String) -> bool:
	if id not in EXTENSIONS.get_skins(): return false
	if id == _skin_id: return true
	_skin_id = id
	_release_skin()
	update_view(0.0)
	return true

func clear() -> void:
	_enabled = false
	_target_id = -1
	_release_skin()
	_hide_target()

func _replace_skin(target: Dictionary) -> bool:
	_release_skin()
	_skin = EXTENSIONS.create_first_person_skin(_skin_id,{"target_id":_target_id,
		"snapshot":target.duplicate(true),"spectator":true,"local_audio":false})
	if _skin == null: return false
	add_child(_skin)
	var tool := clampi(int(target.get("tool",2)),0,3)
	var weapon := clampi(int(target.get("weapon",0)),0,2)
	if _skin.has_method("initialize_selection"):
		_skin.initialize_selection(tool,weapon)
	else:
		_skin.set_selection(tool,weapon)
	_skin_target = _target_id
	return true

func _release_skin() -> void:
	if is_instance_valid(_skin):
		_skin.hide()
		_skin.queue_free()
	_skin = null
	_skin_target = -1
	_has_sample = false
	_walk_progress = 0.0
	_was_reloading = false
	_last_reload_progress = 0.0
	_shot_sequence = null
	_visual_fire_age=1.0e20

func _hide_target(reset_skin: bool = false) -> void:
	hide()
	_has_sample = false
	if reset_skin: _skin_target = -1

func _update_reload(target: Dictionary,new_skin: bool) -> void:
	var reloading := bool(target.get("is_reloading",target.get("reloading",false)))
	var progress := clampf(_number(target,"reload_progress",0.0),0.0,1.12)
	if reloading and (new_skin or not _was_reloading or progress<_last_reload_progress):
		_skin.reload()
	elif not reloading and _was_reloading:
		if bool(target.get("reload_cancelled",false)): _skin.cancel_reload()
		else: _skin.reload_completed()
	_was_reloading = reloading
	_last_reload_progress = progress

func _team_color(target: Dictionary,team: int) -> Color:
	var explicit_color: Variant = target.get("team_color",target.get("color"))
	if explicit_color is Color: return _color(explicit_color,Color.WHITE)
	if _session.has_method("get_team_info"):
		var info: Variant = _session.call("get_team_info",team)
		if info is Dictionary and info.get("color") is Color:
			return _color(info.color,Color.WHITE)
	return Color(-1,-1,-1,1)

func _set_view_layer(node: Node) -> void:
	if node is MeshInstance3D or node is MultiMeshInstance3D: node.layers = VIEW_LAYER
	for child in node.get_children(): _set_view_layer(child)

func _number(data: Dictionary,key: String,fallback: float) -> float:
	var value: Variant = data.get(key,fallback)
	return float(value) if (value is float or value is int) and is_finite(float(value)) else fallback

func _vector(value: Variant) -> Vector3:
	return value if value is Vector3 and value.is_finite() else Vector3.ZERO

func _color(value: Variant,fallback: Color) -> Color:
	if value is Color and is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a): return value
	return fallback

func get_aim_down_state() -> float:
	return float(_skin.get_aim_down_state()) if is_instance_valid(_skin) and _skin.has_method("get_aim_down_state") else 0.0

func get_displayed_tool() -> int:
	if is_instance_valid(_skin) and _skin.has_method("get_displayed_tool"):return int(_skin.get_displayed_tool())
	var target: Dictionary=_session.call("get_target",_target_id) if is_instance_valid(_session) and _target_id>=0 else {}
	return int(target.get("tool",2))

func get_camera_motion_state() -> Dictionary:
	var sprint:=float(_skin.get_sprint_state()) if is_instance_valid(_skin) and _skin.has_method("get_sprint_state") else 0.0
	return {"raw_sprint":sprint,"walk_phase":_walk_progress,"fire_age":_visual_fire_age}
