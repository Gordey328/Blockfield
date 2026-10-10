class_name LabStatusEffects
extends Control
## HurtRingView.cpp, Client_Draw.cpp::DrawHurtScreenEffect, TCProgressView.cpp.
var session: LocalSession
var player: BlockfieldPlayer
var hurt_items: Array[Dictionary]=[]
var hurt_sprites: Array[Dictionary]=[]
var _hurt_elapsed:=10.0
var _hurt_ring: Texture2D
var _hurt_sprite: Texture2D
var _tc_background: Texture2D
var _tc_bar: Texture2D
var _tint: ColorRect
var _wash: ColorRect
var _ring_view: Control
var _tc_view: Control
var _last_territory:=-1
var _last_territory_time:=-10.0

func setup(local_session: LocalSession, local_player: BlockfieldPlayer) -> void:
	session=local_session
	player=local_player
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	reload_resources()
	_tint=ColorRect.new()
	_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tint.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var material:=CanvasItemMaterial.new()
	material.blend_mode=CanvasItemMaterial.BLEND_MODE_MUL
	_tint.material=material
	add_child(_tint)
	_wash=ColorRect.new()
	_wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wash.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(_wash)
	_ring_view=Control.new()
	_ring_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ring_view.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var ring_material:=CanvasItemMaterial.new()
	ring_material.blend_mode=CanvasItemMaterial.BLEND_MODE_ADD
	_ring_view.material=ring_material
	_ring_view.draw.connect(func():_draw_ring(_ring_view))
	add_child(_ring_view)
	_tc_view=Control.new()
	_tc_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tc_view.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_tc_view.draw.connect(func():_draw_tc(_tc_view))
	add_child(_tc_view)
	session.player_hurt.connect(show_hurt)

func reload_resources() -> void:
	_hurt_ring=OpenSpadesExtensions.texture("Gfx/HurtRing2.png")
	_hurt_sprite=OpenSpadesExtensions.texture("Gfx/HurtSprite.png")
	_tc_background=OpenSpadesExtensions.texture("Gfx/TC/ProgressBg.png")
	_tc_bar=OpenSpadesExtensions.texture("Gfx/TC/ProgressBar.png")

func show_hurt(_amount: float, origin: Vector3=Vector3.INF, _kind: String="weapon") -> void:
	_hurt_elapsed=0.0
	# Client_Update.cpp:546: regenerated for every health reduction, including falls.
	hurt_sprites.clear()
	var hp_fraction:=session.health/100.0
	for index in maxi(6,18-int(hp_fraction*8)):
		var strength:=.3+randf()*.7
		if hp_fraction>.5:strength*=1.5-hp_fraction
		hurt_sprites.append({"angle":randf()*TAU,"scale":.2+randf()*randf()*.7,"horizontal_shift":randf(),"strength":strength})
	if origin.is_finite():
		var direction:=origin-player.global_position
		direction.y=0
		if direction.length_squared()>.0001:hurt_items.append({"direction":direction.normalized(),"remaining":3.0})

func get_tc_state() -> Dictionary:
	if session.mode!="tc" or session.health<=0 or session.team>=2:
		_last_territory=-1
		return {}
	var nearest:=-1
	var distance:=INF
	for index in session.territories.size():
		var diff: Vector3=session.territories[index].position-player.get_aim_origin()
		if absf(diff.x)<18 and absf(diff.y)<18 and absf(diff.z)<18 and diff.length_squared()<distance:
			distance=diff.length_squared()
			nearest=index
	var fade:=1.0
	if nearest>=0:
		_last_territory=nearest
		_last_territory_time=session.session_time
	elif _last_territory>=0 and _last_territory<session.territories.size() and session.session_time<_last_territory_time+2:
		nearest=_last_territory
		fade=1.0-(session.session_time-_last_territory_time)/2.0
	if nearest<0:return {}
	var territory: Dictionary=session.territories[nearest]
	var left_team:=int(territory.owner)
	var right_team:=int(territory.capturing_team)
	var progress:=float(territory.progress) if right_team>=0 else 0.0
	if right_team<0:right_team=2
	if right_team==session.team:
		right_team=left_team
		left_team=session.team
		progress=1-progress
	return {"index":nearest,"owner":int(territory.owner),"left_team":left_team,"right_team":right_team,"progress":float(territory.progress),"display_progress":progress+(.5-progress)*12.0/256.0,"fade":fade,"contested":bool(territory.contested)}

func _process(delta: float) -> void:
	if session==null:return
	_hurt_elapsed+=delta
	for index in range(hurt_items.size()-1,-1,-1):
		hurt_items[index].remaining=float(hurt_items[index].remaining)-delta
		if float(hurt_items[index].remaining)<0:hurt_items.remove_at(index)
	if session.health<=0:hurt_items.clear()
	var intensity:=clampf((1.0-_hurt_elapsed/.35)*(.3+(1.0-session.health/100.0)*.7),0,.9)
	_tint.color=Color(1,1-intensity,1-intensity,1)
	_wash.color=Color(1,0,0,intensity*.1)
	queue_redraw()
	_ring_view.queue_redraw()
	_tc_view.queue_redraw()

func _draw() -> void:
	if player==null:return
	if _hurt_elapsed<1.5:
		var screen_radius:=size.length()*.5
		for sprite in hurt_sprites:
			var alpha:=clampf(float(sprite.strength)-_hurt_elapsed/1.5,0,1)
			if alpha<=0:continue
			var radial:=Vector2(cos(float(sprite.angle)),sin(float(sprite.angle)))
			var tangent:=Vector2(-radial.y,radial.x)
			var extent:=float(sprite.scale)*screen_radius
			var base:=radial*screen_radius+size*.5
			var center:=radial*-extent
			var side1:=tangent*(extent*4*float(sprite.horizontal_shift))
			var side2:=tangent*(extent*4*(float(sprite.horizontal_shift)-1))
			var first:=base+center+side1
			var second:=base+center+side2
			var fourth:=base+side1
			var top_uv:=8.0/_hurt_sprite.get_height()
			draw_polygon(PackedVector2Array([first,second,second+fourth-first,fourth]),PackedColorArray([Color(0,0,0,alpha)]),PackedVector2Array([Vector2(0,top_uv),Vector2(1,top_uv),Vector2(1,1),Vector2(0,1)]),_hurt_sprite)
func _draw_tc(canvas: Control) -> void:
	var state:=get_tc_state()
	if state.is_empty():return
	var point:=Vector2((size.x-256)*.5,size.y*.7)
	var fade:=float(state.fade)
	canvas.draw_texture_rect(_tc_background,Rect2(point,Vector2(256,32)),false,LabMap.team_color_for(session,int(state.owner))*Color(1,1,1,fade))
	var boundary:=256.0*(1.0-float(state.display_progress))
	if int(state.left_team)<2:canvas.draw_texture_rect_region(_tc_bar,Rect2(point,Vector2(boundary,32)),Rect2(0,0,boundary,32),LabMap.team_color_for(session,int(state.left_team))*Color(1,1,1,fade*.8))
	if int(state.right_team)<2:canvas.draw_texture_rect_region(_tc_bar,Rect2(point+Vector2(boundary,0),Vector2(256-boundary,32)),Rect2(boundary,0,256-boundary,32),LabMap.team_color_for(session,int(state.right_team))*Color(1,1,1,fade*.8))
	var team_name := LabMap.team_name_for(session,int(state.owner))
	var text:=OpenSpadesLocalization.text("Neutral Territory","Client") if int(state.owner)==2 else OpenSpadesLocalization.text("{0}'s Territory","Client",[team_name])
	if bool(state.contested):text+=" · "+("Оспаривается" if TranslationServer.get_locale().begins_with("ru") else "Contested")
	var font:=get_theme_default_font()
	canvas.draw_string(font,point+Vector2((256-font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x)*.5,50),text,HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color(1,1,1,fade))

func _draw_ring(canvas: Control) -> void:
	if player==null:return
	var radius:=size.y*.3
	var forward:=-player.head.global_basis.z
	var front_angle:=atan2(forward.x,-forward.z)
	for item in hurt_items:
		var direction: Vector3=item.direction
		var angle:=atan2(direction.x,-direction.z)-front_angle
		canvas.draw_set_transform(size*.5,angle)
		canvas.draw_texture_rect(_hurt_ring,Rect2(Vector2(-radius,-radius),Vector2(radius*2,radius)),false,Color(1,1,1,minf(1,float(item.remaining)*2)))
	canvas.draw_set_transform(Vector2.ZERO)
