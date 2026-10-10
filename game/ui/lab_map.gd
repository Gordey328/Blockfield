class_name LabMap
extends Control
var world: VoxelWorld
var player: Node3D
var session: LocalSession
var _texture: ImageTexture
var _dirty:=true
var _clock:=0.0

func setup(map_world: VoxelWorld, local_player: Node3D, local_session: LocalSession) -> void:
	world=map_world
	player=local_player
	session=local_session
	world.blocks_changed.connect(func(_changes):_dirty=true)
	world.map_loaded.connect(func(_name):_dirty=true)

func _process(delta: float) -> void:
	_clock+=delta
	if _clock<0.25:return
	_clock=0.0
	if world==null:return
	if _dirty:
		_dirty=false
		var image:=Image.create(64,64,false,Image.FORMAT_RGBA8)
		for z in 64:
			for x in 64:
				var cell:=Vector3i(x*world.dimensions.x/64,world.dimensions.y-1,z*world.dimensions.z/64)
				var packed:=0
				while cell.y>0:
					packed=world.get_block(cell)
					if packed!=0:break
					cell.y-=1
				image.set_pixel(x,z,VoxelWorld.block_color(packed).darkened(0.35))
		_texture=ImageTexture.create_from_image(image)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("18252c"))
	if _texture!=null:draw_texture_rect(_texture,Rect2(Vector2.ZERO,size),false)
	if world==null or player==null:return
	var p:=Vector2(player.global_position.x/world.dimensions.x,player.global_position.z/world.dimensions.z)*size
	draw_circle(p,4.0,Color("ffffff"))
	var forward:=-player.global_basis.z
	draw_line(p,p+Vector2(forward.x,forward.z)*15.0,Color("ffffff"),2.0)
	if session!=null:
		for target in session.targets:
			var point: Vector3=target.get("position",Vector3.ZERO)
			var icon:=Vector2(point.x/world.dimensions.x,point.z/world.dimensions.z)*size
			draw_circle(icon,2.0,Color("66a7d6") if int(target.get("team",1))==0 else Color("98b678"))
	draw_rect(Rect2(Vector2.ZERO,size),Color("74919e"),false,1.0)
