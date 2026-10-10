class_name LabGrenade
extends Node3D
## Source Grenade.cpp displacement uses velocity * dt * 32; here velocity is meters/s.
var world: VoxelWorld
var session: LocalSession
var velocity:=Vector3.ZERO
var fuse:=3.0
var grenade_id: int=-1
var finished:=false
signal detonated(point: Vector3)
signal bounced(point: Vector3,water: bool)
signal dropped_into_water(point: Vector3)
var orientation := Quaternion.IDENTITY
var _visual: Node3D

func _ready() -> void:
	var path:="res://assets/openspades/models/Weapons/Grenade/Grenade.glb"
	if ResourceLoader.exists(path):
		var model: Node3D=OpenSpadesModels.create("Weapons/Grenade/Grenade")
		model.scale=Vector3.ONE*0.03
		add_child(model)
		_visual=model
	else:
		var visual:=MeshInstance3D.new()
		var sphere:=SphereMesh.new()
		sphere.radius=0.12
		sphere.height=0.24
		visual.mesh=sphere
		add_child(visual)
		_visual=visual
	_update_visual()

func _physics_process(delta: float) -> void:
	if finished or world==null:return
	move_step(delta)
	if session!=null:session.set_grenade_position(grenade_id,global_position)

func move_step(delta: float) -> int:
	# Grenade::MoveGrenade tests the endpoint, reverts to the previous position,
	# flips one axis (vertical first) and damps all components. Meter velocity
	# is the original native velocity multiplied by 32.
	var old_position := global_position
	velocity.y -= 32.0 * delta
	global_position += velocity * delta
	var roll_axis := Vector3(-velocity.z, 0.0, velocity.x) * (delta / 0.12)
	if roll_axis.length_squared() > 0.000001:
		orientation = (Quaternion(roll_axis.normalized(), roll_axis.length()) * orientation).normalized()
	basis = Basis(orientation)
	var cell := Vector3i(global_position.floor())
	var previous := Vector3i(old_position.floor())
	if world.water_enabled and cell.y < floori(world.water_level) and previous.y >= floori(world.water_level):
		dropped_into_water.emit(global_position)
	if not world.clip_world(global_position):
		_update_visual()
		return 0
	var audible := absf(velocity.x) > 3.2 or absf(velocity.y) > 3.2 or absf(velocity.z) > 3.2
	if cell.y != previous.y and ((cell.x == previous.x and cell.z == previous.z) or not world.clip_world(Vector3(cell.x, previous.y, cell.z))):
		velocity.y = -velocity.y
	elif cell.x != previous.x and ((cell.z == previous.z and cell.y == previous.y) or not world.clip_world(Vector3(previous.x, cell.y, cell.z))):
		velocity.x = -velocity.x
	elif cell.z != previous.z and ((cell.x == previous.x and cell.y == previous.y) or not world.clip_world(Vector3(cell.x, cell.y, previous.z))):
		velocity.z = -velocity.z
	global_position = old_position
	velocity *= 0.36
	_update_visual()
	if audible and global_position.y > world.water_level: bounced.emit(global_position, false)
	return 2 if audible else 1

func _update_visual() -> void:
	if _visual==null:return
	_visual.position=basis.inverse()*Vector3.UP*0.09
	_visual.visible=world==null or global_position.y>=world.water_level

func detonate() -> void:
	if finished:return
	finished=true
	world.explode(global_position,1.5)
	if session!=null:
		# Offline authority supplies a quadratic radial policy. Voxel occlusion
		# is evaluated here after terrain destruction, for players and targets.
		for target in session.targets:
			var point: Vector3=target.position+Vector3.UP*1.2
			var amount:=_damage_at(point)
			session.apply_target_damage(int(target.id),amount,"grenade")
		var player: Node3D=get_tree().get_first_node_in_group("local_player")
		if player!=null:session.damage_player(_damage_at(player.global_position+Vector3.UP*1.2),global_position,"grenade")
	detonated.emit(global_position)
	queue_free()

func _damage_at(point: Vector3) -> float:
	var offset:=point-global_position
	var distance:=offset.length()
	if distance>=LocalSession.LOCAL_GRENADE_DAMAGE_RADIUS:return 0.0
	if distance>0.01:
		var cover:=world.cast_voxel(global_position,offset/distance,distance)
		if cover.hit:return 0.0
	var factor:=1.0-distance/LocalSession.LOCAL_GRENADE_DAMAGE_RADIUS
	return 100.0*factor*factor
