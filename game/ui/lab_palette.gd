class_name LabPalette
extends Control
## PaletteView.cpp:47–74,91–154,157–202; native 8 families × 8 shades.
var player: BlockfieldPlayer
var _texture: Texture2D

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	reload_resources()

func reload_resources() -> void:
	_texture=OpenSpadesExtensions.texture("Gfx/Palette.png")
	queue_redraw()

static func palette_colors() -> Array[Color]:
	var result: Array[Color]=[]
	var families: Array[Vector3i]=[Vector3i(128,128,128),Vector3i(256,0,0),Vector3i(256,128,0),Vector3i(256,256,0),Vector3i(0,256,0),Vector3i(0,256,256),Vector3i(0,0,256),Vector3i(256,0,256)]
	for family in families:
		for weight in [1,3,5,7]:
			var rgb:=Vector3(family)*float(weight)/8.0-Vector3.ONE
			result.append(Color(maxf(rgb.x,0)/255.0,maxf(rgb.y,0)/255.0,maxf(rgb.z,0)/255.0))
		for weight in [1,3,5,7]:
			var rgb:=Vector3(family)+Vector3(Vector3i(256,256,256)-family)*float(weight)/8.0-Vector3.ONE
			result.append(Color(rgb.x/255.0,rgb.y/255.0,rgb.z/255.0))
	return result

func get_selected_index() -> int:
	if player==null:return -1
	var held:=Vector3i(roundi(player.block_color.r*255),roundi(player.block_color.g*255),roundi(player.block_color.b*255))
	var colors:=palette_colors()
	for index in colors.size():
		var color:=colors[index]
		if held==Vector3i(roundi(color.r*255),roundi(color.g*255),roundi(color.b*255)):return index
	return -1

func move_selection(step: int) -> void:
	if player==null:return
	var index:=get_selected_index()
	player.block_color=palette_colors()[posmod((3 if index<0 else index)+step,64)]
	queue_redraw()

func handle_action(event: InputEvent) -> bool:
	for entry in [["palette_left",-1],["palette_right",1],["palette_up",-8],["palette_down",8]]:
		if InputMap.has_action(entry[0]) and event.is_action_pressed(entry[0]):
			move_selection(int(entry[1]))
			return true
	return false

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if player==null or _texture==null:return
	var selected:=get_selected_index()
	var colors:=palette_colors()
	# Native selection draws in a second pass above neighboring overlapping cells.
	for selected_pass in [false,true]:
		for index in colors.size():
			if (index==selected)!=selected_pass:continue
			var rectangle:=Rect2(Vector2(index%8,floori(index/8.0))*10.0,Vector2(16,16))
			var source_y:=16.0 if index==selected else 0.0
			draw_texture_rect_region(_texture,rectangle,Rect2(0,source_y,16,16),colors[index])
			draw_texture_rect_region(_texture,rectangle,Rect2(16,source_y,16,16),Color.WHITE)
