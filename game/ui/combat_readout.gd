class_name CombatReadout
extends Control
## Small, readable edge islands. All values come from the existing adapter.
var session: LocalSession
var arsenal_state: Dictionary = {}
var compact: bool = false
var score_text: String = ""
var survival_text: String = ""
var _last_survival_text: String = ""
var score_y: float = 18.0
var status_text: String = ""
var _last_state: Dictionary = {}
var _last_size := Vector2.ZERO
var _last_compact: bool = false
var _last_score: String = ""
var _last_score_y: float = -1.0
var _last_status: String = ""
var _panel: StyleBoxFlat = CombatTheme.panel()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func get_display_state() -> Dictionary:
	if session == null: return {}
	var tool: int = session.current_tool
	var weapon_label: String = OpenSpadesLocalization.text(str(session.get_weapon_info().name), "Client").to_upper()
	var ru: bool = TranslationServer.get_locale().begins_with("ru")
	if tool != 2: weapon_label = (["ЛОПАТА", "БЛОКИ", "", "ГРАНАТА"] if ru else ["SPADE", "BLOCKS", "", "GRENADE"])[tool]
	var result: Dictionary = {"health": session.health, "blocks": session.blocks, "grenades": session.grenades,
		"ammo": session.magazine, "reserve": session.reserve, "weapon_label": weapon_label,
		"tool": tool, "reload_progress": session.get_reload_progress() if session.is_reloading else -1.0,
		"ammo_warning": tool == 2 and session.magazine <= maxi(1, int(session.get_weapon_info().clip_size) / 4),
		"live": session.health > 0 and session.team < 2,
		"cook": maxf(0.0, 3.0-session.grenade_cook_time) if session.is_cooking_grenade else -1.0}
	if tool == 2 and not arsenal_state.is_empty() and bool(arsenal_state.get("enabled", false)):
		var item: Dictionary = ArsenalCatalog.get_item(str(arsenal_state.get("selected_item", "")))
		if not item.is_empty():
			result.weapon_label = str(item.get("name_ru" if ru else "name_en", "")).to_upper()
			result.ammo = int(arsenal_state.get("magazine", 0)) if str(item.category) == "primary" else int((arsenal_state.get("stock", {}) as Dictionary).get(str(item.id), 0))
			result.reserve = int(arsenal_state.get("reserve", 0)) if str(item.category) == "primary" else 0
			result.ammo_warning = int(result.ammo) <= 1
	return result

func get_panel_rects() -> Array[Rect2]:
	if compact: return [Rect2(12,size.y-52,180,48),Rect2(size.x-182,size.y-52,170,48)]
	return [Rect2(28,size.y-126,236,98),Rect2(size.x-264,size.y-126,236,98)]

func _process(_delta: float) -> void:
	var state: Dictionary = get_display_state()
	if state != _last_state or size != _last_size or compact != _last_compact or score_text != _last_score or score_y != _last_score_y or status_text != _last_status or survival_text != _last_survival_text:
		_last_state = state
		_last_size = size
		_last_compact = compact
		_last_score = score_text
		_last_score_y = score_y
		_last_status = status_text
		_last_survival_text = survival_text
		queue_redraw()

func _text(value: String, position: Vector2, height: int, tint: Color = CombatTheme.WHITE) -> void:
	draw_string(CombatTheme.font(),position+Vector2(0,1),value,HORIZONTAL_ALIGNMENT_LEFT,-1,height,Color(0,0,0,.6))
	draw_string(CombatTheme.font(),position,value,HORIZONTAL_ALIGNMENT_LEFT,-1,height,tint)

func _right_text(value: String, position: Vector2, height: int, tint: Color = CombatTheme.WHITE) -> void:
	_text(value,position-Vector2(CombatTheme.font().get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,height).x,0),height,tint)

func _draw() -> void:
	var state: Dictionary = get_display_state()
	if state.is_empty(): return
	if not score_text.is_empty(): _draw_score()
	if not survival_text.is_empty(): _draw_survival()
	if not bool(state.live): return
	var islands: Array[Rect2] = get_panel_rects()
	for rectangle: Rect2 in islands: draw_style_box(_panel,rectangle)
	var hp: Color = CombatTheme.DANGER if int(state.health) <= 25 else CombatTheme.ACCENT
	var left: Vector2 = islands[0].position
	var right: Vector2 = islands[1].position
	if compact:
		CombatTheme.draw_icon(self,"health",Rect2(left+Vector2(10,10),Vector2(18,18)),hp)
		_text(str(state.health),left+Vector2(34,28),23)
		draw_line(left+Vector2(12,39),left+Vector2(74,39),Color(1,1,1,.14),3,true)
		draw_line(left+Vector2(12,39),left+Vector2(12+62*clampf(float(state.health)/100,0,1),39),hp,3,true)
		CombatTheme.draw_icon(self,"tool_block",Rect2(left+Vector2(87,9),Vector2(16,16)),CombatTheme.MUTED)
		_text(str(state.blocks),left+Vector2(108,26),14)
		CombatTheme.draw_icon(self,"tool_grenade",Rect2(left+Vector2(135,9),Vector2(16,16)),CombatTheme.MUTED)
		_text(str(state.grenades),left+Vector2(156,26),14)
		_right_text(status_text if not status_text.is_empty() else str(state.weapon_label),right+Vector2(157,14),10,CombatTheme.WARNING if not status_text.is_empty() else CombatTheme.MUTED)
		_draw_stock(state,right+Vector2(157,39),25)
	else:
		CombatTheme.draw_icon(self,"health",Rect2(left+Vector2(16,17),Vector2(23,23)),hp)
		_text(str(state.health),left+Vector2(48,46),35)
		_text("HP",left+Vector2(117,43),12,CombatTheme.MUTED)
		draw_line(left+Vector2(17,60),left+Vector2(219,60),Color(1,1,1,.15),4,true)
		draw_line(left+Vector2(17,60),left+Vector2(17+202*clampf(float(state.health)/100,0,1),60),hp,4,true)
		CombatTheme.draw_icon(self,"tool_block",Rect2(left+Vector2(17,73),Vector2(15,15)),CombatTheme.MUTED)
		_text(str(state.blocks),left+Vector2(40,87),14)
		CombatTheme.draw_icon(self,"tool_grenade",Rect2(left+Vector2(108,73),Vector2(15,15)),CombatTheme.MUTED)
		_text(str(state.grenades),left+Vector2(133,87),14)
		CombatTheme.draw_icon(self,["tool_spade","tool_block","tool_weapon","tool_grenade"][int(state.tool)],Rect2(right+Vector2(17,16),Vector2(30,30)),CombatTheme.MUTED)
		_right_text(str(state.weapon_label),right+Vector2(219,25),12,CombatTheme.MUTED)
		_draw_stock(state,right+Vector2(219,68),40)
		_draw_slots(right)
		if not status_text.is_empty(): _right_text(status_text,right+Vector2(230,-10),13,CombatTheme.WARNING)
	if float(state.reload_progress) >= 0:
		var progress_rect := Rect2(islands[1].position+Vector2(16,islands[1].size.y-4),Vector2((islands[1].size.x-32)*clampf(float(state.reload_progress),0,1),2))
		draw_rect(progress_rect,CombatTheme.WARNING)

func _draw_stock(state: Dictionary, end: Vector2, height: int) -> void:
	var tool: int = int(state.tool)
	if tool == 2:
		var reserve: String = "/ %d" % int(state.reserve)
		_right_text(reserve,end,height/2,CombatTheme.MUTED)
		var gap: float = CombatTheme.font().get_string_size(reserve,HORIZONTAL_ALIGNMENT_LEFT,-1,height/2).x+10
		_right_text("%02d" % int(state.ammo),end-Vector2(gap,0),height,CombatTheme.WARNING if bool(state.ammo_warning) else CombatTheme.WHITE)
	elif tool == 0: _right_text("—",end,height,CombatTheme.WHITE)
	else: _right_text(str(state.blocks if tool == 1 else state.grenades),end,height,CombatTheme.WHITE)

func _draw_slots(origin: Vector2) -> void:
	for index: int in 4:
		var x: float = 18.0+index*51.0
		var selected: bool = index == session.current_tool
		CombatTheme.draw_icon(self,["tool_spade","tool_block","tool_weapon","tool_grenade"][index],Rect2(origin+Vector2(x,77),Vector2(16,16)),CombatTheme.ACCENT if selected else CombatTheme.MUTED)
		_text(str(index+1),origin+Vector2(x+21,90),10,CombatTheme.ACCENT if selected else CombatTheme.MUTED)

func _draw_survival() -> void:
	var width: float = 218.0 if compact else 328.0
	var lines: PackedStringArray = survival_text.split("\n")
	var line_count: int = mini(3, lines.size())
	var panel_height: float = (48.0 if compact else 56.0) + (19.0 if line_count > 2 else 0.0)
	var rectangle: Rect2 = Rect2((size.x - width) * 0.5, score_y, width, panel_height)
	draw_style_box(_panel, rectangle)
	for index: int in line_count:
		var height: int = (13 if compact else 17) if index == 0 else (11 if compact else 13)
		var text_width: float = CombatTheme.font().get_string_size(lines[index], HORIZONTAL_ALIGNMENT_LEFT, -1, height).x
		while height > 9 and text_width > width - 16.0:
			height -= 1
			text_width = CombatTheme.font().get_string_size(lines[index], HORIZONTAL_ALIGNMENT_LEFT, -1, height).x
		_text(lines[index], Vector2(rectangle.get_center().x - text_width * 0.5, rectangle.position.y + 19.0 + index * 19.0), height, CombatTheme.ACCENT if index == 0 else CombatTheme.WHITE)

func _draw_score() -> void:
	# At the480px portrait canvas, this clears the112px minimap frame.
	var width: float = 204.0 if compact else 296.0
	var height: float = 32.0 if compact else 48.0
	var rectangle := Rect2((size.x-width)/2,score_y,width,height)
	draw_style_box(_panel,rectangle)
	var center: Vector2 = rectangle.get_center()
	var pieces: PackedStringArray = score_text.split("   ·   ")
	var scores: PackedStringArray = pieces[0].split(" : ")
	if scores.size() != 2 or pieces.size() != 2: return
	var baseline: float = center.y+(6 if compact else 9)
	var number_size: int = 21 if compact else 29
	_right_text(scores[0],Vector2(center.x-57,baseline),number_size,Color("8fc9ff"))
	_text(scores[1],Vector2(center.x+57,baseline),number_size,Color("a9e69a"))
	var time_width: float = CombatTheme.font().get_string_size(pieces[1],HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
	_text(pieces[1],Vector2(center.x-time_width/2,center.y+5),14)
	draw_line(Vector2(center.x-44,center.y-9),Vector2(center.x-44,center.y+9),Color(1,1,1,.16),1,true)
	draw_line(Vector2(center.x+44,center.y-9),Vector2(center.x+44,center.y+9),Color(1,1,1,.16),1,true)
