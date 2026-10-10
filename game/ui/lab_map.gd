class_name LabMap
extends Control
## MapView.cpp: four zoom levels, focus clamping, 8x8 grid, team visibility.
const SCALES: Array[float]=[0.25,0.5,1.0,2.0]
const TEAM_COLORS: Array[Color]=[Color("66a7d6"),Color("98b678"),Color("b7bdc0")]
const PLAYER_PALETTE: Array[String]=["000000","ffffff","808080","ffff00","00ffff","ff00ff","ff0000","00ff00","0000ff","800000","008000","000080","808000","800080","008080","ff8000","ff0080","8000ff","0080ff","80ff00","00ff80","ff8080","80ff80","8080ff","80ffff","ffff80","ff80ff","a52a2a","ff4500","ffa500","8b4513","d2691e"]
var world: VoxelWorld
var player: BlockfieldPlayer
var session: LocalSession
var large_map:=false
var show_weapon_icons:=true
var per_player_colors:=true
var scale_mode:=2
var _scale:=1.0
var _texture: ImageTexture
var _dirty:=true
var _clock:=0.0
var _terrain_source: LabMap
var _icons: Dictionary={}
var _tracers: Array[Dictionary]=[]

func setup(map_world: VoxelWorld, local_player: BlockfieldPlayer, local_session: LocalSession, terrain_source: LabMap=null) -> void:
	world=map_world
	player=local_player
	session=local_session
	_terrain_source=terrain_source
	world.blocks_changed.connect(func(_changes):_dirty=true)
	world.map_loaded.connect(func(_name):_dirty=true)
	clip_contents=true
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	reload_resources()

func reload_resources() -> void:
	for icon in ["Player","Rifle","SMG","Shotgun","View","Intel","CommandPost"]:
		_icons[icon]=OpenSpadesExtensions.texture("Gfx/Map/%s.png"%icon)

func switch_scale() -> void:
	scale_mode=(scale_mode+1)%SCALES.size()
	queue_redraw()

func get_view_rect() -> Rect2:
	if world==null:return Rect2()
	var extent:=Vector2(world.dimensions.x,world.dimensions.z)
	if large_map:return Rect2(Vector2.ZERO,extent)
	var visible_extent:=Vector2(minf(size.x*_scale,extent.x),minf(size.y*_scale,extent.y))
	var focus:=get_focus_position()
	return Rect2(Vector2(clampf(focus.x-visible_extent.x*.5,0,extent.x-visible_extent.x),clampf(focus.y-visible_extent.y*.5,0,extent.y-visible_extent.y)),visible_extent)

func get_focus_position() -> Vector2:
	var position: Vector3=player.global_position
	if player.followed_target_id>=0:
		var target:=session.get_target(player.followed_target_id)
		if not target.is_empty():position=target.get("position",position)
	elif player.camera_mode in [BlockfieldPlayer.CameraMode.FREE,BlockfieldPlayer.CameraMode.DEATH]:position=player.camera.global_position
	return Vector2(position.x,position.z)

func map_point(position: Vector3) -> Vector2:
	var view:=get_view_rect()
	return (Vector2(position.x,position.z)-view.position)/view.size*size

func get_visible_target_ids() -> Array[int]:
	var ids: Array[int]=[]
	for target in session.targets:
		if bool(target.get("alive",false)) and (session.team>=2 or int(target.team)==session.team):ids.append(int(target.id))
	return ids

func add_tracer(start: Vector3, end: Vector3, weapon: int=0) -> void:
	var path:=Vector3(end.x-start.x,0,end.z-start.z)
	if path.length_squared()<.000001:return
	var velocity: float=[700.0,360.0,500.0][clampi(weapon,0,2)]
	# MapViewTracer stores velocity before a no-op multiplication of its local
	# constructor argument. Preserve the effective stored source velocity.
	_tracers.append({"start":start,"direction":path.normalized(),"length":path.length(),"velocity":velocity,"visible_length":velocity*.1,"distance":-velocity*.1+randf()*.1,"first_update":true})

func get_tracer_segment(tracer: Dictionary) -> Array[Vector3]:
	var first:=maxf(float(tracer.distance),0)
	var last:=minf(float(tracer.distance)+float(tracer.visible_length),float(tracer.length))
	var result: Array[Vector3]=[]
	if first<last:result.assign([tracer.start+tracer.direction*first,tracer.start+tracer.direction*last])
	return result

static func modify_color(color: Color) -> Color:
	var average:=(color.r+color.g+color.b)/3
	return Color((color.r+average)*.4+.2,(color.g+average)*.4+.2,(color.b+average)*.4+.2,1)

func player_color(id: int, team: int) -> Color:
	return modify_color(Color(PLAYER_PALETTE[posmod(id,32)])) if per_player_colors else modify_color(team_color_for(session,team))

static func team_color_for(local_session: LocalSession,index: int) -> Color:
	return local_session.get_team_info(index).color if local_session != null else TEAM_COLORS[clampi(index,0,2)]

static func team_name_for(local_session: LocalSession,index: int) -> String:
	if index >= 2: return OpenSpadesLocalization.lab("Наблюдатель")
	var name: String = str(local_session.get_team_info(index).name)
	# Keep localized lab defaults; match-provided custom names are literal text.
	if name == ["Blue","Green"][clampi(index,0,1)]:
		return OpenSpadesLocalization.lab(["Синяя команда","Зелёная команда"][index])
	return name

func _process(delta: float) -> void:
	_scale=move_toward(_scale,SCALES[scale_mode],maxf(absf(_scale-SCALES[scale_mode])*10.0,.2)*delta)
	_clock+=delta
	for index in range(_tracers.size()-1,-1,-1):
		if bool(_tracers[index].first_update):_tracers[index].first_update=false
		else:_tracers[index].distance=float(_tracers[index].distance)+delta*float(_tracers[index].velocity)
		if float(_tracers[index].distance)>float(_tracers[index].length):_tracers.remove_at(index)
	if world==null:return
	if _terrain_source==null and _clock>=.25 and _dirty:
		_clock=0
		_dirty=false
		var image: Image
		if world.has_method("get_topdown_image"):image=world.call("get_topdown_image")
		else:
			image=Image.create(64,64,false,Image.FORMAT_RGBA8)
			for z in 64:
				for x in 64:
					var cell:=Vector3i(x*world.dimensions.x/64,world.dimensions.y-1,z*world.dimensions.z/64)
					while cell.y>0 and world.get_block(cell)==0:cell.y-=1
					image.set_pixel(x,z,VoxelWorld.block_color(world.get_block(cell)))
		if _texture==null or _texture.get_size()!=Vector2(image.get_size()):_texture=ImageTexture.create_from_image(image)
		else:_texture.update(image)
	queue_redraw()

func _draw_icon(kind: String, point: Vector2, color: Color, yaw: float=0, width: float=14) -> void:
	var texture: Texture2D=_icons.get(kind)
	if texture==null:draw_circle(point,width*.25,color);return
	draw_set_transform(point,yaw)
	draw_texture_rect(texture,Rect2(Vector2(-width,-width)*.5,Vector2(width,width)),false,color)
	draw_set_transform(Vector2.ZERO)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("18252c"))
	if world==null or player==null:return
	var texture:=_texture if _terrain_source==null else _terrain_source._texture
	var view:=get_view_rect()
	if texture!=null:
		var factor:=texture.get_size()/Vector2(world.dimensions.x,world.dimensions.z)
		draw_texture_rect_region(texture,Rect2(Vector2.ZERO,size),Rect2(view.position*factor,view.size*factor),Color.WHITE)
	var font:=get_theme_default_font()
	var interval:=Vector2(world.dimensions.x,world.dimensions.z)/8.0
	for index in range(9):
		var grid:=Vector2(index,index)*interval
		var screen:=(grid-view.position)/view.size*size
		if screen.x>=0 and screen.x<=size.x:draw_line(Vector2(screen.x,0),Vector2(screen.x,size.y),Color(1,1,1,.24))
		if screen.y>=0 and screen.y<=size.y:draw_line(Vector2(0,screen.y),Vector2(size.x,screen.y),Color(1,1,1,.24))
		if index<8:
			var center:=(grid+interval*.5-view.position)/view.size*size
			if center.x>5 and center.x<size.x-6:draw_string(font,Vector2(center.x-5,14),String.chr(65+index),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
			if center.y>20 and center.y<size.y-5:draw_string(font,Vector2(4,center.y+4),str(index+1),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
	if session.mode=="ctf":
		for index in session.ctf_bases.size():_draw_icon("CommandPost",map_point(session.ctf_bases[index]),team_color_for(session,index),0,22)
		for flag in session.ctf_flags:
			if int(flag.carrier)<0:_draw_icon("Intel",map_point(flag.position),team_color_for(session,int(flag.team)),0,22)
			elif session.team<2:_draw_icon("Intel",map_point(flag.position),team_color_for(session,int(flag.team))*Color(1,1,1,absf(sin(session.session_time*4))),0,22)
	elif session.mode=="tc":
		for territory in session.territories:_draw_icon("CommandPost",map_point(territory.position),team_color_for(session,int(territory.owner)),0,22)
	for target in session.targets:
		if int(target.id) not in get_visible_target_ids():continue
		var kind: String=["Rifle","SMG","Shotgun"][clampi(int(target.get("weapon",0)),0,2)] if show_weapon_icons else "Player"
		_draw_icon(kind,map_point(target.position),player_color(int(target.id),int(target.team)),float(target.get("yaw",0)))
	if session.team<2 and session.health>0:
		_draw_icon(["Rifle","SMG","Shotgun"][session.current_weapon] if show_weapon_icons else "Player",map_point(player.global_position),player_color(session.local_player_id(),session.team),player.rotation.y)
	var focus:=get_focus_position()
	var facing:=-player.head.global_basis.z
	if player.followed_target_id>=0:facing=Vector3.FORWARD.rotated(Vector3.UP,float(session.get_target(player.followed_target_id).get("yaw",0)))
	elif player.camera_mode in [BlockfieldPlayer.CameraMode.FREE,BlockfieldPlayer.CameraMode.DEATH]:facing=-player.camera.global_basis.z
	_draw_icon("View",(focus-view.position)/view.size*size,Color(1,1,1,.65),atan2(facing.x,-facing.z),32)
	for tracer in _tracers:
		var segment:=get_tracer_segment(tracer)
		if segment.size()==2:draw_line(map_point(segment[0]),map_point(segment[1]),Color(1,.8,.6),2)
	draw_rect(Rect2(Vector2.ZERO,size),Color("74919e"),false,1.0)
	if not large_map:draw_string(font,Vector2(size.x-44,size.y-5),"%d%%"%int(100.0/_scale),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
