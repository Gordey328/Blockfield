class_name LabSoldier
extends Node3D

func refresh_resources() -> void:
	if character!=null:character.refresh_resources()

var target_id: int = -1
var session: LocalSession
var character: Node3D
var skin_id := "original"
var _label: Label3D
var _zones: Array[Area3D] = []
var _origin := Vector3.ZERO
var _phase := 0.0
var _previous_position:=Vector3.ZERO
var _walk_distance:=0.0

func setup(local_session: LocalSession, identifier: int, point: Vector3) -> void:
	session = local_session
	target_id = identifier
	_origin = point
	position = point
	_previous_position=point
	character = OpenSpadesExtensions.create_third_person_skin(skin_id,{"session":session,"target_id":target_id})
	add_child(character)
	for volume in LabHitVolumes.volumes(false):
		_make_zone(volume.part,Vector3.ZERO,volume.box.size)
	_update_hit_zones(false,0.0)
	_label=Label3D.new()
	_label.position.y=2.65
	_label.pixel_size=0.004
	_label.font_size=30
	_label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test=false
	add_child(_label)
	_phase=randf()*TAU

func set_skin(id: String) -> void:
	if id not in OpenSpadesExtensions.get_skins():return
	var replacement:=OpenSpadesExtensions.create_third_person_skin(id,{"session":session,"target_id":target_id})
	if replacement==null:return
	if character!=null:
		character.hide()
		character.queue_free()
	skin_id=id
	character=replacement
	add_child(character)

func _make_zone(part: String, center: Vector3, size: Vector3) -> void:
	var area:=Area3D.new()
	area.collision_layer=2
	area.collision_mask=0
	area.position=center
	area.set_meta("target_id",target_id)
	area.set_meta("hit_part",part)
	var collision:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=size
	collision.shape=box
	area.add_child(collision)
	add_child(area)
	_zones.append(area)

func _process(delta: float) -> void:
	if session==null or character==null:return
	var target: Dictionary=session.get_target(target_id)
	if target.is_empty(): return
	var dead: bool=float(target.get("health",100))<=0.0
	_phase+=delta
	var moving: bool=target.get("moving",false)
	position=target.position
	rotation.y=float(target.get("yaw",0.0))
	var crouching: bool=bool(target.get("crouching",str(target.get("state","standing"))=="crouching"))
	var sprinting: bool=bool(target.get("sprinting",str(target.get("state","standing"))=="sprinting"))
	character.set_team(int(target.get("team",1)),session.get_team_info(int(target.get("team",1))).color)
	character.set_aim(float(target.get("pitch",0.0)))
	character.set_pose(crouching,dead,sprinting)
	character.set_weapon(int(target.get("weapon",0)),int(target.get("tool",2)))
	if character.has_method("set_block_color"):
		var color: Variant=target.get("block_color",Color(.6,.46,.32))
		if color is Color:character.set_block_color(color)
	if character.has_method("set_tool_action"):
		var action: Variant=target.get("action",target.get("action_type",0))
		var action_type:=int(action.get("type",0)) if action is Dictionary else int(action)
		var progress:=float(action.get("progress",target.get("action_progress",0.0))) if action is Dictionary else float(target.get("action_progress",0.0))
		var ready:=float(action.get("ready",target.get("ready_state",1.0))) if action is Dictionary else float(target.get("ready_state",1.0))
		character.set_tool_action(clampi(action_type,0,3),clampf(progress,0,1),maxf(float(target.get("grenade_cook_time",0.0)),0),ready,float(target.get("raise_state",1.0)))
	character.set_intel_carrier(str(target.get("state","standing"))=="intel",session.get_team_info(1-int(target.team)).color)
	var motion:=((position-_previous_position)/maxf(delta,.00001)) if moving and not dead else Vector3.ZERO
	_previous_position=position
	if moving and not dead and not crouching and not bool(target.get("aiming",false)):_walk_distance+=Vector2(motion.x,motion.z).length()*delta*.15
	if character.has_method("set_motion_state"):character.set_motion_state(motion.dot(-global_basis.z),motion.dot(global_basis.x),_walk_distance)
	else:character.animate_motion((5.0 if sprinting else 3.0) if moving else 0.0,_phase)
	_update_hit_zones(crouching,float(target.get("pitch",0.0)))
	_label.text="TARGET %02d  /  %d HP"%[target_id,int(target.get("health",100))]
	_label.modulate=Color("ed806d") if dead else Color("e8efe6")
	for area in _zones: area.collision_layer=0 if dead else 2

func _update_hit_zones(crouch: bool,pitch: float) -> void:
	var volumes:=LabHitVolumes.volumes(crouch,pitch)
	for index in range(_zones.size()):
		var volume: Dictionary=volumes[index]
		var box: AABB=volume.box
		_zones[index].transform=volume.transform*Transform3D(Basis.IDENTITY,box.get_center())
		(_zones[index].get_child(0).shape as BoxShape3D).size=box.size
