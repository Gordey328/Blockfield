class_name LabHUD
extends CanvasLayer

var main: Node3D
var session: LocalSession
var player: BlockfieldPlayer
var world: VoxelWorld
var _root: Control
var _menu: Control
var _hud: Control
var _stats: Label
var _ammo: Label
var _mode: Label
var _notice: Label
var _hit: Label
var _scoreboard: PanelContainer
var _scores: Label
var _map: LabMap
var _large_map: LabMap
var _chat: LineEdit
var _chat_log: RichTextLabel
var _notice_time:=0.0
var _hit_time:=0.0
var _live: Label
var _palette: ColorPickerButton
const LANGUAGE=preload("res://presentation/openspades_localization.gd")

func setup(app: Node3D, local_session: LocalSession, local_player: BlockfieldPlayer, map_world: VoxelWorld) -> void:
	main=app
	session=local_session
	player=local_player
	world=map_world
	_root=Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var theme:=Theme.new()
	theme.default_font=LANGUAGE.get_ui_font()
	_root.theme=theme
	add_child(_root)
	_create_hud()
	_create_menu()

func _style(background: Color, border: Color=Color.TRANSPARENT) -> StyleBoxFlat:
	var style:=StyleBoxFlat.new()
	style.bg_color=background
	style.border_color=border
	style.set_border_width_all(1 if border.a>0 else 0)
	style.set_corner_radius_all(4)
	style.content_margin_left=20
	style.content_margin_right=20
	style.content_margin_top=16
	style.content_margin_bottom=16
	return style

func _label(text: String, font_size: int=16, color: Color=Color("e8eee7")) -> Label:
	var node:=Label.new()
	node.text=LANGUAGE.lab(text)
	node.set_meta("lab_text",text)
	node.add_theme_font_size_override("font_size",font_size)
	node.add_theme_color_override("font_color",color)
	return node

func _button(text: String, callback: Callable, accent: bool=false) -> Button:
	var node:=Button.new()
	node.text=LANGUAGE.lab(text)
	node.set_meta("lab_text",text)
	node.custom_minimum_size=Vector2(0,42)
	node.add_theme_font_size_override("font_size",16)
	node.add_theme_stylebox_override("normal",_style(Color("679374") if accent else Color("273b42"),Color("6c918b") if accent else Color("45606a")))
	node.add_theme_stylebox_override("hover",_style(Color("41616a"),Color("86b7c3")))
	node.add_theme_stylebox_override("pressed",_style(Color("182b31"),Color("86b7c3")))
	node.pressed.connect(callback)
	return node

func _create_hud() -> void:
	_hud=Control.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hud)
	var top:=_label("BLOCKFIELD  /  ЛОКАЛЬНЫЙ ПОЛИГОН",18)
	top.position=Vector2(26,20)
	_hud.add_child(top)
	_mode=_label("",13,Color("abc0c6"))
	_mode.position=Vector2(27,48)
	_hud.add_child(_mode)
	_stats=_label("",21)
	_stats.anchor_top=1
	_stats.anchor_bottom=1
	_stats.offset_left=28
	_stats.offset_top=-84
	_stats.offset_right=500
	_stats.offset_bottom=-40
	_hud.add_child(_stats)
	var controls:=_label("WASD  движение   •   1–4  инструменты   •   R  перезарядка   •   Esc  полигон",13,Color("c4d1cd"))
	controls.anchor_top=1
	controls.anchor_bottom=1
	controls.offset_left=28
	controls.offset_top=-40
	controls.offset_bottom=-15
	_hud.add_child(controls)
	_ammo=_label("",32)
	_ammo.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	_ammo.anchor_left=1
	_ammo.anchor_right=1
	_ammo.anchor_top=1
	_ammo.anchor_bottom=1
	_ammo.offset_left=-380
	_ammo.offset_right=-28
	_ammo.offset_top=-90
	_ammo.offset_bottom=-30
	_hud.add_child(_ammo)
	var cross:=_label("+",24,Color("ebf2eb"))
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	cross.position=Vector2(-7,-18)
	_hud.add_child(cross)
	_hit=_label("×",32,Color("eeb483"))
	_hit.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_hit.position=Vector2(-12,-23)
	_hit.visible=false
	_hud.add_child(_hit)
	_notice=_label("",17,Color("ffffff"))
	_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_notice.offset_left=-450
	_notice.offset_right=450
	_notice.offset_top=90
	_notice.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_notice)
	_map=LabMap.new()
	_map.anchor_left=1
	_map.anchor_right=1
	_map.position=Vector2(-210,24)
	_map.size=Vector2(180,180)
	_map.setup(world,player,session)
	_hud.add_child(_map)
	_large_map=LabMap.new()
	_large_map.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_large_map.position=Vector2(-230,-230)
	_large_map.size=Vector2(460,460)
	_large_map.setup(world,player,session)
	_large_map.visible=false
	_root.add_child(_large_map)
	_scoreboard=PanelContainer.new()
	_scoreboard.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_scoreboard.position=Vector2(-280,-200)
	_scoreboard.size=Vector2(560,400)
	_scoreboard.add_theme_stylebox_override("panel",_style(Color(0.06,0.1,0.13,0.95),Color("536f7a")))
	_scores=_label("",18)
	_scoreboard.add_child(_scores)
	_scoreboard.visible=false
	_root.add_child(_scoreboard)
	_chat=LineEdit.new()
	_chat.placeholder_text="Локальное сообщение — Enter отправить"
	_chat.position=Vector2(28,520)
	_chat.size=Vector2(480,36)
	_chat.visible=false
	_chat.text_submitted.connect(_send_chat)
	_root.add_child(_chat)
	_chat_log=RichTextLabel.new()
	_chat_log.position=Vector2(28,400)
	_chat_log.size=Vector2(480,110)
	_chat_log.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_chat_log.add_theme_font_size_override("normal_font_size",14)
	_root.add_child(_chat_log)

func _create_menu() -> void:
	_menu=Control.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_menu)
	var background:=ColorRect.new()
	background.color=Color(0.025,0.055,0.075,0.92)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(background)
	var margin:=MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right"]:margin.add_theme_constant_override("margin_"+side,52)
	for side in ["top","bottom"]:margin.add_theme_constant_override("margin_"+side,30)
	_menu.add_child(margin)
	var layout:=VBoxContainer.new()
	layout.add_theme_constant_override("separation",14)
	margin.add_child(layout)
	var header:=HBoxContainer.new()
	layout.add_child(header)
	var brand:=_label("BLOCKFIELD",40)
	brand.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	header.add_child(brand)
	header.add_child(_label("OPENSPADES → GODOT\nРАЗРАБОТКА · ИТЕРАЦИЯ 1",13,Color("87a6ae")))
	layout.add_child(_label("Испытательный полигон",22,Color("afc9c5")))
	var intro:=_label("Все оригинальные виды оружия и две команды. Локальная сессия — сервер не нужен.",15,Color("99b0b8"))
	layout.add_child(intro)
	var tabs:=TabContainer.new()
	tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size",17)
	layout.add_child(tabs)
	_build_arsenal(_tab(tabs,"Арсенал"))
	_build_soldiers(_tab(tabs,"Солдаты"))
	_build_world(_tab(tabs,"Мир и режимы"))
	_build_settings(_tab(tabs,"Настройки"))
	_build_checks(_tab(tabs,"Проверка"))
	var footer:=HBoxContainer.new()
	footer.add_theme_constant_override("separation",16)
	layout.add_child(footer)
	var start:=_button("ВОЙТИ НА ПОЛИГОН  →",func():set_menu_visible(false),true)
	start.custom_minimum_size.x=300
	footer.add_child(start)
	var help:=_label("ЛКМ  действие    ПКМ  прицел / копать / линия\nF  вид от третьего лица    N  карта    Tab  счёт",13,Color("98b2b8"))
	footer.add_child(help)

func _tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var panel:=MarginContainer.new()
	panel.name=title
	panel.set_meta("lab_title",title)
	for side in ["left","right","top","bottom"]:panel.add_theme_constant_override("margin_"+side,20)
	tabs.add_child(panel)
	tabs.set_tab_title(tabs.get_tab_count()-1,LANGUAGE.lab(title))
	var scroll:=ScrollContainer.new()
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	var column:=VBoxContainer.new()
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",12)
	scroll.add_child(column)
	return column

func _build_arsenal(column: VBoxContainer) -> void:
	column.add_child(_label("ОРУЖИЕ",13,Color("8ea7af")))
	var weapons:=HBoxContainer.new()
	column.add_child(weapons)
	for entry in [["Винтовка",0],["Пистолет-пулемёт",1],["Дробовик",2]]:
		var index:int=entry[1]
		var button:=_button(entry[0],func():session.select_weapon(index);session.select_tool(2))
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		weapons.add_child(button)
	column.add_child(_label("ИНСТРУМЕНТЫ",13,Color("8ea7af")))
	var tools:=HBoxContainer.new()
	column.add_child(tools)
	for entry in [["Лопата · 1",0],["Блоки · 2",1],["Оружие · 3",2],["Граната · 4",3]]:
		var index:int=entry[1]
		var button:=_button(entry[0],func():session.select_tool(index))
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		tools.add_child(button)
	column.add_child(_label("Профиль оригинальной игры",15))
	var profile:=OptionButton.new()
	profile.add_item("Ace of Spades 0.75")
	profile.add_item("Ace of Spades 0.76")
	profile.item_selected.connect(func(index):session.set_profile_version("0.75" if index==0 else "0.76"))
	column.add_child(profile)
	var unlimited:=CheckButton.new()
	unlimited.text="Неограниченные боеприпасы и материалы"
	unlimited.set_meta("lab_text",unlimited.text)
	unlimited.text=LANGUAGE.lab(unlimited.text)
	unlimited.button_pressed=true
	session.unlimited_ammo=true
	unlimited.toggled.connect(func(enabled):session.unlimited_ammo=enabled)
	column.add_child(unlimited)
	column.add_child(_button("Пополнить оружие, гранаты и блоки",session.restock))
	_palette=ColorPickerButton.new()
	_palette.color=player.block_color
	_palette.custom_minimum_size=Vector2(160,32)
	_palette.color_changed.connect(func(color):player.block_color=color)
	column.add_child(_label("Цвет блоков — E берёт цвет из мира",14))
	column.add_child(_palette)

func _build_soldiers(column: VBoxContainer) -> void:
	column.add_child(_label("В оригинале один солдат с командной окраской.\nПроверяйте оружие, позы, попадания и состояние после смерти.",16))
	var row:=HBoxContainer.new()
	column.add_child(row)
	for entry in [["Синяя команда",0],["Зелёная команда",1],["Наблюдатель",2]]:
		var index:int=entry[1]
		var button:=_button(entry[0],func():session.select_team(index))
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(button)
	var invulnerable:=CheckButton.new()
	invulnerable.text="Неуязвимость для испытаний"
	invulnerable.set_meta("lab_text",invulnerable.text)
	invulnerable.text=LANGUAGE.lab(invulnerable.text)
	invulnerable.button_pressed=true
	session.invulnerable=true
	invulnerable.toggled.connect(func(enabled):session.invulnerable=enabled)
	column.add_child(invulnerable)
	column.add_child(_button("Нанести себе 25 урона",func():var saved:=session.invulnerable;session.invulnerable=false;session.damage_player(25);session.invulnerable=saved))
	column.add_child(_button("Проверить смерть",func():var saved:=session.invulnerable;session.invulnerable=false;session.damage_player(1000);session.invulnerable=saved))
	column.add_child(_button("Возродиться",session.respawn))
	column.add_child(_button("Вид от первого / третьего лица",func():player.third_person=not player.third_person))
	column.add_child(_label("ПОЗЫ МИШЕНЕЙ — применяются ко всем солдатам",14))
	var poses:=OptionButton.new()
	var pose_texts:=["Стоя","Присев","Ходьба","Бег","После смерти","С разведданными"]
	poses.set_meta("lab_items",pose_texts)
	for text in pose_texts:poses.add_item(LANGUAGE.lab(text))
	poses.item_selected.connect(func(index):
		for target in session.targets:session.set_target_state(int(target.id),["standing","crouching","walking","sprinting","dead","intel"][index],int(target.weapon),int(target.tool)))
	column.add_child(poses)
	var items:=OptionButton.new()
	var item_texts:=["Винтовка","Пистолет-пулемёт","Дробовик","Лопата","Блок","Граната"]
	items.set_meta("lab_items",item_texts)
	for text in item_texts:items.add_item(LANGUAGE.lab(text))
	items.item_selected.connect(func(index):
		for target in session.targets:session.set_target_state(int(target.id),str(target.state),mini(index,2),2 if index<3 else [0,1,3][index-3]))
	column.add_child(items)

func _build_world(column: VBoxContainer) -> void:
	column.add_child(_button("Сбросить испытательный полигон",main.reset_lab))
	column.add_child(_button("Загрузить оригинальную карту OpenSpades",main.load_original_map))
	column.add_child(_button("Сохранить изменённую карту .vxl",main.save_map))
	column.add_child(_label("Локальные правила матча",16))
	var mode:=OptionButton.new()
	var mode_texts:=["Свободные испытания","CTF — захват разведданных","TC — контроль территорий"]
	mode.set_meta("lab_items",mode_texts)
	for text in mode_texts:mode.add_item(LANGUAGE.lab(text))
	mode.item_selected.connect(func(index):session.set_mode(["sandbox","ctf","tc"][index]))
	column.add_child(mode)
	column.add_child(_label("Лопата: ЛКМ бьёт блок, ПКМ копает три блока.\nБлоки: ЛКМ поставить, ПКМ удерживать и отпустить для линии.\nГраната: удерживайте ЛКМ для приготовления, отпустите для броска.",15,Color("a6bdc2")))

func _build_settings(column: VBoxContainer) -> void:
	column.add_child(_label("Имя игрока",15))
	var name_field:=LineEdit.new()
	name_field.text=main.player_name
	name_field.max_length=24
	name_field.text_changed.connect(func(value):main.player_name=value;main.save_settings())
	column.add_child(name_field)
	column.add_child(_label("Язык",15))
	var language:=OptionButton.new()
	var languages:=LANGUAGE.get_languages()
	for choice in languages:
		language.add_item(str(choice.label))
		if str(choice.locale)==main.locale:language.select(language.item_count-1)
	language.item_selected.connect(func(index):main.set_locale(str(languages[index].locale)))
	column.add_child(language)
	column.add_child(_label("Поле зрения",15))
	var fov:=HSlider.new()
	fov.min_value=60
	fov.max_value=110
	fov.value=player.base_fov
	fov.value_changed.connect(func(value):player.base_fov=value;main.save_settings())
	column.add_child(fov)
	column.add_child(_label("Чувствительность мыши",15))
	var sensitivity:=HSlider.new()
	sensitivity.min_value=0.0005
	sensitivity.max_value=0.007
	sensitivity.step=0.0001
	sensitivity.value=player.sensitivity
	sensitivity.value_changed.connect(func(value):player.sensitivity=value;main.save_settings())
	column.add_child(sensitivity)
	var hold_aim:=CheckButton.new()
	hold_aim.text="Удерживать ПКМ для прицеливания"
	hold_aim.set_meta("lab_text",hold_aim.text)
	hold_aim.text=LANGUAGE.lab(hold_aim.text)
	hold_aim.button_pressed=player.hold_aim_down_sight
	hold_aim.toggled.connect(func(enabled):player.hold_aim_down_sight=enabled;main.save_settings())
	column.add_child(hold_aim)
	var invert:=CheckButton.new()
	invert.text="Инвертировать мышь по вертикали"
	invert.set_meta("lab_text",invert.text)
	invert.text=LANGUAGE.lab(invert.text)
	invert.button_pressed=player.invert_mouse
	invert.toggled.connect(func(enabled):player.invert_mouse=enabled;main.save_settings())
	column.add_child(invert)
	column.add_child(_label("Чувствительность при прицеливании",15))
	var ads:=HSlider.new()
	ads.min_value=0.1
	ads.max_value=2.0
	ads.step=0.05
	ads.value=player.ads_sensitivity
	ads.value_changed.connect(func(value):player.ads_sensitivity=value;main.save_settings())
	column.add_child(ads)
	column.add_child(_label("Экспонента движения мыши",15))
	var exponent:=HSlider.new()
	exponent.min_value=0.5
	exponent.max_value=2.0
	exponent.step=0.05
	exponent.value=player.mouse_exponent
	exponent.value_changed.connect(func(value):player.mouse_exponent=value;main.save_settings())
	column.add_child(exponent)
	column.add_child(_label("Громкость",15))
	var volume:=HSlider.new()
	volume.min_value=-40
	volume.max_value=0
	volume.value=AudioServer.get_bus_volume_db(0)
	volume.value_changed.connect(func(value):AudioServer.set_bus_volume_db(0,value);main.save_settings())
	column.add_child(volume)
	column.add_child(_button("Полный экран",func():DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if DisplayServer.window_get_mode()!=DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_WINDOWED)))

func _build_checks(column: VBoxContainer) -> void:
	column.add_child(_label("Проверяйте без подключения к серверу",20))
	column.add_child(_label("01   Оружие: темп, разброс, отдача, прицел и перезарядка\n02   Солдаты: обе команды, попадания по голове / телу / конечностям\n03   Мир: строительство, линии, разрушение опор и взрывы\n04   Движение: бег, прыжок, приседание, тихий ход, наблюдатель\n05   Матч: смерть, возрождение, CTF, TC, счёт и карта",16))
	_live=_label("",14,Color("92b3b5"))
	column.add_child(_live)
	column.add_child(_label("Текущий билд находится в разработке. Полная готовность\nпереноса фиксируется по проверкам возможностей исходной игры.",14,Color("bcb6a0")))

func _process(delta: float) -> void:
	if session==null:return
	_notice_time=maxf(0.0,_notice_time-delta)
	_hit_time=maxf(0.0,_hit_time-delta)
	_notice.visible=_notice_time>0.0
	_hit.visible=_hit_time>0.0
	var tools:=["ЛОПАТА","БЛОКИ",str(session.get_weapon_info().name).to_upper(),"ГРАНАТА"]
	_stats.text=LANGUAGE.lab("%d HP   /   %d блоков   /   %d гранат")%[session.health,session.blocks,session.grenades]
	_ammo.text="%s\n%d / %d"%[tools[session.current_tool],session.magazine,session.reserve]
	_mode.text="%s   ·   %s   ·   %d FPS"%[world.map_name,str(session.get("mode")),Engine.get_frames_per_second()]
	if _live!=null:
		var stats:=world.get_stats()
		_live.text="Карта: %s  ·  Чанки: %s\nОружие: %s  ·  Профиль: %s"%[world.map_name,stats.get("chunks",0),session.get_weapon_info().name,session.profile_version]
	if _scoreboard.visible:
		_scores.text="ЛОКАЛЬНЫЙ МАТЧ\n\nИгрок — %d HP\n\n"%session.health
		for target in session.targets:_scores.text+="Мишень %02d   команда %d   HP %d\n"%[target.id,target.team,target.health]

func set_menu_visible(enabled: bool) -> void:
	if _menu==null:return
	_menu.visible=enabled
	_hud.visible=not enabled
	player.controls_enabled=not enabled
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if enabled else Input.MOUSE_MODE_CAPTURED

func is_menu_open() -> bool:return _menu!=null and _menu.visible
func toggle_scoreboard() -> void:_scoreboard.visible=not _scoreboard.visible
func toggle_map() -> void:_large_map.visible=not _large_map.visible

func show_notice(message: String) -> void:
	_notice.text=message
	_notice_time=3.0

func show_hit(part: String, damage: float) -> void:
	_hit_time=0.18
	show_notice("%s  ·  %d урона"%[part,int(damage)])

func open_chat() -> void:
	_chat.visible=true
	player.controls_enabled=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	_chat.grab_focus()

func _send_chat(message: String) -> void:
	_chat_log.append_text("Вы: %s\n"%message.left(160))
	_chat.text=""
	_chat.visible=false
	player.controls_enabled=true
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED

func _notification(what: int) -> void:
	if what==NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(_root):
		_translate_nodes(_root)

func _translate_nodes(node: Node) -> void:
	if node.has_meta("lab_text"):
		node.set("text",LANGUAGE.lab(str(node.get_meta("lab_text"))))
	if node is TabContainer:
		for index in node.get_tab_count():
			var panel: Control=node.get_tab_control(index)
			if panel.has_meta("lab_title"):node.set_tab_title(index,LANGUAGE.lab(str(panel.get_meta("lab_title"))))
	if node is OptionButton and node.has_meta("lab_items"):
		var texts: Array=node.get_meta("lab_items")
		for index in texts.size():node.set_item_text(index,LANGUAGE.lab(str(texts[index])))
	for child in node.get_children():_translate_nodes(child)
