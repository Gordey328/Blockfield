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

func _ready() -> void:
	var path:="res://assets/openspades/models/Grenade/Grenade.glb"
	if ResourceLoader.exists(path):
		var model: Node3D=(load(path) as PackedScene).instantiate()
		model.scale=Vector3.ONE*0.025
		add_child(model)
	else:
		var visual:=MeshInstance3D.new()
		var sphere:=SphereMesh.new()
		sphere.radius=0.12
		sphere.height=0.24
		visual.mesh=sphere
		add_child(visual)

func _physics_process(delta: float) -> void:
	if finished or world==null:return
	velocity.y-=32.0*delta
	var offset:=velocity*delta
	var hit:=world.cast_voxel(global_position,offset.normalized(),offset.length()+0.12)
	if hit.hit:
		global_position=hit.position+Vector3(hit.normal)*0.13
		velocity=velocity.bounce(Vector3(hit.normal))*0.36
	else: global_position+=offset
	rotation+=Vector3(2,3,1)*delta
	if session!=null:session.set_grenade_position(grenade_id,global_position)

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
		if player!=null:session.damage_player(_damage_at(player.global_position+Vector3.UP*1.2))
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
