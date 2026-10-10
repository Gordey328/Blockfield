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

func setup(local_session: LocalSession, identifier: int, point: Vector3) -> void:
	session = local_session
	target_id = identifier
	_origin = point
	position = point
	character = OpenSpadesExtensions.create_third_person_skin(skin_id,{"session":session,"target_id":target_id})
	add_child(character)
	_make_zone("head",Vector3(0,2.35,0),Vector3(0.6,0.6,0.6))
	_make_zone("torso",Vector3(0,1.65,0),Vector3(0.8,0.9,0.4))
	_make_zone("legs",Vector3(0,0.6,0),Vector3(0.7,1.2,0.5))
	_make_zone("arms",Vector3(-0.52,1.75,0),Vector3(0.3,0.9,0.45))
	_make_zone("arms",Vector3(0.52,1.75,0),Vector3(0.3,0.9,0.45))
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
	var crouching: bool=str(target.get("state","standing"))=="crouching"
	var sprinting: bool=str(target.get("state","standing"))=="sprinting"
	character.set_team(int(target.get("team",1)))
	character.set_pose(crouching,dead,sprinting)
	character.set_weapon(int(target.get("weapon",0)),int(target.get("tool",2)))
	character.set_intel_carrier(str(target.get("state","standing"))=="intel")
	character.animate_motion((5.0 if sprinting else 3.0) if moving else 0.0,_phase)
	_zones[0].position.y=1.5 if crouching else 2.35
	_zones[1].position.y=0.95 if crouching else 1.65
	_zones[3].position.y=1.4 if crouching else 1.75
	_zones[4].position.y=1.4 if crouching else 1.75
	_label.text="TARGET %02d  /  %d HP"%[target_id,int(target.get("health",100))]
	_label.modulate=Color("ed806d") if dead else Color("e8efe6")
	for area in _zones: area.collision_layer=0 if dead else 2
