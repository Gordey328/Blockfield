class_name LabAmmoStrip
extends Control
## Client_Draw.cpp::DrawJoinedAlivePlayerHUD, original bullet sprites and spacing.
var session: LocalSession
var _icons: Array[Texture2D]=[]

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	reload_resources()

func reload_resources() -> void:
	_icons.clear()
	for name in ["7.62mm","9mm","12gauge"]:_icons.append(OpenSpadesExtensions.texture("Gfx/Bullet/%s.png"%name))

func _process(_delta: float) -> void:queue_redraw()

func _draw() -> void:
	if session==null or session.current_tool!=2 or session.team>=2 or session.health<=0:return
	var weapon:=session.current_weapon
	var width: float=[6.0,4.0,30.0][weapon]
	var height:=width/4 if weapon==2 else width*4
	var spacing: float=-6 if weapon==2 else 2
	var clip_size:=maxi(int(session.get_weapon_info().clip_size),session.magazine)
	for index in clip_size:
		var tint:=Color.WHITE if index<session.magazine else Color(.4,.4,.4,1)
		draw_texture_rect(_icons[weapon],Rect2(size.x-(index+1)*(width+spacing),size.y-height,width,height),false,tint)
