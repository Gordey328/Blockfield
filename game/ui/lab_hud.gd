class_name LabHUD
extends CanvasLayer
signal alert_sound_requested
signal ui_sound_requested(kind: String)
signal chat_sound_requested
signal map_sound_requested(path: String)

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
var _alert_panel: Panel
var _alert_icon: TextureRect
var _alert_style: StyleBoxFlat
var _alert_kind: String="notice"
var _alert_age:=0.0
var _hit: TextureRect
var _scoreboard: LabScoreboard
var _map: LabMap
var _large_map: LabMap
var _chat: LabChat
var _status_effects: LabStatusEffects
var _build_cursor: LabBuildCursor
var _build_status: Label
var _weapon_status: Label
var _name_under_crosshair: Label
var _hottracked_player: OpenSpadesHottrackedPlayer
var _state_hint: Label
var _intel_icon: TextureRect
var _feed: RichTextLabel
var _results: Label
var _performance: Label
var _hud_hidden:=false
var _show_statistics:=false
var _events: Array[Dictionary]=[]
var _event_clock:=0.0
var _binding_action: String=""
var _binding_buttons: Dictionary={}
var _weapon_icon: LabAmmoStrip
var _cross: TextureRect
var _minimap_size:=180
var _show_names:=2
var _show_hit_feedback:=true
var _show_alerts:=true
var _map_weapon_icons:=true
var _map_player_colors:=true
var _graphics_controls: Dictionary={}
var _ui_settings_controls: Dictionary={}
var _notice_time:=0.0
var _hit_time:=0.0
var _hit_friendly:=false
var _follow_aim_state:=0.0
var _follow_aim_target:=-1
var _target_preview_controls: Dictionary={}
var _target_shot_ages: Dictionary={}
var _live: Label
var _palette: ColorPickerButton
var _native_palette: LabPalette
var _team_buttons: Array[Button] = []
var _spawn_team: OptionButton
var _network_menu: Control
const NETWORK_MENU=preload("res://ui/network_menu.gd")
var _team_metadata_cache: Array = []
const LANGUAGE=preload("res://presentation/openspades_localization.gd")

func setup(app: Node3D, local_session: LocalSession, local_player: BlockfieldPlayer, map_world: VoxelWorld) -> void:
	main=app
	session=local_session
	player=local_player
	world=map_world
	_hottracked_player=OpenSpadesHottrackedPlayer.new()
	_hottracked_player.name="HottrackedPlayer"
	add_child(_hottracked_player)
	_root=Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var theme:=Theme.new()
	theme.default_font=LANGUAGE.get_ui_font()
	_root.theme=theme
	add_child(_root)
	_load_ui_settings()
	_create_hud()
	_create_menu()
	# Loading/import/fullscreen failures must remain readable in the menu.
	_alert_panel.reparent(_root)
	_root.move_child(_alert_panel,_root.get_child_count()-1)
	_connect_menu_sounds(_menu)
	_load_ui_settings()
	session.match_event.connect(add_event)
	session.changed.connect(_update_team_choices)
	_update_team_choices()
	for event in session.event_log:add_event(event)

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
	node.add_theme_color_override("font_shadow_color",Color(0,0,0,.75))
	node.add_theme_constant_override("shadow_offset_x",1)
	node.add_theme_constant_override("shadow_offset_y",1)
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
	_status_effects=LabStatusEffects.new()
	_status_effects.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_status_effects.setup(session,player)
	_hud.add_child(_status_effects)
	var top:=_ui_label("BLOCKFIELD  /  МУЛЬТИПЛЕЕР","BLOCKFIELD  /  MULTIPLAYER",18) if _is_network() else _label("BLOCKFIELD  /  ЛОКАЛЬНЫЙ ПОЛИГОН",18)
	top.position=Vector2(26,20)
	_hud.add_child(top)
	_mode=_label("",13,Color("abc0c6"))
	_mode.position=Vector2(27,48)
	_hud.add_child(_mode)
	_stats=_label("",21)
	_stats.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_stats.position=Vector2(28,-84)
	_hud.add_child(_stats)
	_weapon_icon=LabAmmoStrip.new()
	_weapon_icon.session=session
	_weapon_icon.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_weapon_icon.position=Vector2(-280,-140)
	_weapon_icon.size=Vector2(252,50)
	_hud.add_child(_weapon_icon)
	_ammo=_label("",32)
	_ammo.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	_ammo.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_ammo.position=Vector2(-380,-90)
	_ammo.size=Vector2(352,60)
	_hud.add_child(_ammo)
	_weapon_status=_label("",16,Color("f1dbab"))
	_weapon_status.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	_weapon_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_weapon_status.position=Vector2(-420,-30)
	_weapon_status.size=Vector2(392,25)
	_hud.add_child(_weapon_status)
	_native_palette=LabPalette.new()
	_native_palette.player=player
	_native_palette.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_native_palette.position=Vector2(-100,-146)
	_native_palette.size=Vector2(90,90)
	_hud.add_child(_native_palette)
	_cross=_centered_image("Gfx/Sight.tga")
	_hit=_centered_image("Gfx/HitFeedback.png")
	_hit.visible=false
	_create_alert()
	_name_under_crosshair=_label("",16)
	_name_under_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_name_under_crosshair.position=Vector2(-200,35)
	_name_under_crosshair.size=Vector2(400,30)
	_name_under_crosshair.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_name_under_crosshair)
	_state_hint=_label("",18)
	_state_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_state_hint.position=Vector2(-320,-130)
	_state_hint.size=Vector2(640,90)
	_state_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_state_hint)
	_intel_icon=TextureRect.new()
	_intel_icon.texture=OpenSpadesExtensions.texture("Gfx/Intel.png")
	_intel_icon.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_intel_icon.position=Vector2(-280,-65)
	_intel_icon.size=Vector2(48,48)
	_intel_icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	_intel_icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hud.add_child(_intel_icon)
	_build_status=_label("",14)
	_build_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_build_status.position=Vector2(-260,-125)
	_build_status.size=Vector2(520,30)
	_build_status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_build_status)
	_map=LabMap.new()
	_map.anchor_left=1
	_map.anchor_right=1
	_map.position=Vector2(-210,24)
	_map.size=Vector2(180,180)
	_map.setup(world,player,session)
	_hud.add_child(_map)
	_large_map=LabMap.new()
	_large_map.large_map=true
	_large_map.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_large_map.position=Vector2(-256,-256)
	_large_map.size=Vector2(512,512)
	_large_map.setup(world,player,session,_map)
	_large_map.visible=false
	_root.add_child(_large_map)
	_scoreboard=LabScoreboard.new()
	_scoreboard.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_scoreboard.position=Vector2(-330,-205)
	_scoreboard.size=Vector2(660,410)
	_scoreboard.add_theme_stylebox_override("panel",_style(Color(0.06,0.1,0.13,0.95),Color("536f7a")))
	_scoreboard.setup(main,session)
	_scoreboard.visible=false
	_root.add_child(_scoreboard)
	_chat=LabChat.new()
	_chat.session=session
	_chat.completion_callable=Callable(main.console_service,"completion")
	_chat.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_chat.position=Vector2(28,-360)
	_chat.size=Vector2(560,260)
	_chat.submitted.connect(_send_chat)
	_chat.closed.connect(_close_chat)
	_hud.add_child(_chat)
	_feed=RichTextLabel.new()
	_feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_feed.position=Vector2(-560,230)
	_feed.size=Vector2(532,200)
	_feed.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_feed.add_theme_font_size_override("normal_font_size",14)
	_hud.add_child(_feed)
	_results=_label("",26,Color("f1e6ad"))
	_results.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_results.position=Vector2(-320,145)
	_results.size=Vector2(640,50)
	_results.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_results)
	_performance=_label("",13)
	_performance.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_performance.position=Vector2(28,-30)
	_hud.add_child(_performance)
	_build_cursor=LabBuildCursor.new()
	_build_cursor.setup(player)
	add_child(_build_cursor)

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
	if _is_network():
		_network_menu=NETWORK_MENU.new()
		margin.add_child(_network_menu)
		_network_menu.setup(self,main,session,player)
		return
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
	var multiplayer:=_tab(tabs,"Мультиплеер","Multiplayer")
	multiplayer.add_child(_ui_label("Играйте с другими игроками.","Play with other players.",20))
	multiplayer.add_child(_ui_button("Мультиплеер →","Multiplayer →",func():main.open_network_game()))
	var footer:=HBoxContainer.new()
	footer.add_theme_constant_override("separation",16)
	layout.add_child(footer)
	var start:=_button("ВОЙТИ НА ПОЛИГОН  →",func():set_menu_visible(false),true)
	start.custom_minimum_size.x=300
	footer.add_child(start)
	var help:=_label("ЛКМ  действие    ПКМ  прицел / копать / линия\nF  вид от третьего лица    N  карта    Tab  счёт",13,Color("98b2b8"))
	footer.add_child(help)
	var fullscreen:=_ui_button("Полный экран","Fullscreen",func():main.toggle_fullscreen())
	fullscreen.set_meta("lab_window","fullscreen")
	footer.add_child(fullscreen)

func _tab(tabs: TabContainer, title: String,english: String="") -> VBoxContainer:
	var panel:=MarginContainer.new()
	panel.name=title
	panel.set_meta("lab_title",title)
	if not english.is_empty():panel.set_meta("ui_title_ru",title);panel.set_meta("ui_title_en",english)
	for side in ["left","right","top","bottom"]:panel.add_theme_constant_override("margin_"+side,20)
	tabs.add_child(panel)
	tabs.set_tab_title(tabs.get_tab_count()-1,_ui(title,english) if not english.is_empty() else LANGUAGE.lab(title))
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
	column.add_child(_ui_label("Стрелки выбирают цвета оригинальной палитры во время строительства.","Arrow keys select original palette colors while building.",14))
	column.add_child(_palette)

func _build_soldiers(column: VBoxContainer) -> void:
	column.add_child(_label("В оригинале один солдат с командной окраской.\nПроверяйте оружие, позы, попадания и состояние после смерти.",16))
	var row:=HBoxContainer.new()
	column.add_child(row)
	for entry in [["Синяя команда",0],["Зелёная команда",1],["Наблюдатель",2]]:
		var index:int=entry[1]
		var button:=_button(entry[0],func():session.select_team(index))
		button.remove_meta("lab_text")
		_team_buttons.append(button)
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
	column.add_child(_ui_label("ДОБАВИТЬ МИШЕНЬ","ADD TARGET",14))
	_spawn_team=OptionButton.new()
	for index in 2: _spawn_team.add_item(LabMap.team_name_for(session,index))
	_spawn_team.selected=1
	column.add_child(_spawn_team)
	var spawn_buttons:=HBoxContainer.new()
	column.add_child(spawn_buttons)
	for moving in [false,true]:
		var button:=_ui_button("Движущаяся мишень" if moving else "Неподвижная мишень","Moving target" if moving else "Stationary target",func():main.spawn_lab_target(moving,_spawn_team.selected))
		button.set_meta("lab_spawn","moving" if moving else "stationary")
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		spawn_buttons.add_child(button)
	var reset_button:=_ui_button("Сбросить мишени","Reset targets",func():main.reset_targets())
	reset_button.set_meta("lab_spawn","reset")
	column.add_child(reset_button)
	_build_target_preview_controls(column)

func _update_team_choices() -> void:
	if session==null:return
	var first: Dictionary=session.get_team_info(0)
	var second: Dictionary=session.get_team_info(1)
	var metadata: Array=[first.name,first.color,second.name,second.color,TranslationServer.get_locale()]
	if metadata==_team_metadata_cache:return
	_team_metadata_cache=metadata
	for index in _team_buttons.size():
		_team_buttons[index].text=LabMap.team_name_for(session,index)
		_team_buttons[index].add_theme_color_override("font_color",LabMap.team_color_for(session,index))
	if _spawn_team!=null:
		for index in 2:_spawn_team.set_item_text(index,LabMap.team_name_for(session,index))
	if _chat!=null:_chat.refresh_team_metadata()

func _build_world(column: VBoxContainer) -> void:
	column.add_child(_button("Сбросить испытательный полигон",main.reset_lab))
	if main.has_method("reset_match"):column.add_child(_ui_button("Сбросить карту и матч","Reset current map and match",main.reset_match))
	column.add_child(_button("Загрузить оригинальную карту OpenSpades",main.load_original_map))
	column.add_child(_button("Сохранить изменённую карту .vxl",main.save_map))
	if main.has_method("load_map_file"):column.add_child(_ui_button("Загрузить карту .vxl","Load a .vxl map",main.load_map_file))
	if main.has_method("import_resource_pack"):column.add_child(_ui_button("Загрузить пакет ресурсов (.zip)","Load a resource pack (.zip)",main.import_resource_pack))
	if main.has_method("clear_resource_packs"):column.add_child(_ui_button("Сбросить пакеты ресурсов","Clear resource packs",main.clear_resource_packs))
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
	fov.min_value=45
	fov.max_value=90
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
	var fullscreen:=_ui_button("Полный экран","Fullscreen",func():main.toggle_fullscreen())
	fullscreen.set_meta("lab_window","fullscreen")
	column.add_child(fullscreen)
	_build_native_preferences(column)
	_build_ui_settings(column)
	_build_bindings(column)
	_build_graphics_settings(column)

func _build_checks(column: VBoxContainer) -> void:
	column.add_child(_label("Проверяйте без подключения к серверу",20))
	column.add_child(_label("01   Оружие: темп, разброс, отдача, прицел и перезарядка\n02   Солдаты: обе команды, попадания по голове / телу / конечностям\n03   Мир: строительство, линии, разрушение опор и взрывы\n04   Движение: бег, прыжок, приседание, тихий ход, наблюдатель\n05   Матч: смерть, возрождение, CTF, TC, счёт и карта",16))
	_live=_label("",14,Color("92b3b5"))
	column.add_child(_live)
	column.add_child(_label("Текущий билд находится в разработке. Полная готовность\nпереноса фиксируется по проверкам возможностей исходной игры.",14,Color("bcb6a0")))

func _process(delta: float) -> void:
	if session==null:return
	_update_target_shots(delta)
	_event_clock+=delta
	_notice_time=maxf(-1.0,_notice_time-delta)
	_alert_age+=delta
	_hit_time=maxf(0.0,_hit_time-delta*4.0)
	_update_alert()
	_update_reticle(delta)
	_stats.text=LANGUAGE.lab("%d HP   /   %d блоков   /   %d гранат")%[session.health,session.blocks,session.grenades]
	var live:=session.health>0 and session.team<2
	_stats.visible=live
	_ammo.visible=live
	_weapon_status.visible=live
	_state_hint.text=""
	if session.health<=0 and session.team<2:
		_state_hint.text=OpenSpadesLocalization.text("You will respawn in: {0}","Client",[ceili(session.respawn_remaining)]) if session.respawn_remaining>0 else OpenSpadesLocalization.text("Waiting for respawn","Client")
	if player.followed_target_id>=0:
		var following:=session.get_target(player.followed_target_id)
		_state_hint.text+=str(following.get("name",""))+"\n"+_ui("Прыжок: сменить камеру · Перезарядка: перестать следить","Jump: change camera · Reload: unfollow")
	elif session.team>=2:_state_hint.text=_ui("Наблюдатель · Атака / альтернативная атака: выбрать солдата\nПрыжок / присесть: вверх / вниз","Spectator · Attack / alternate attack: follow a player\nJump / crouch: move up / down")
	_update_intel_indicator(live)
	var info:=session.get_weapon_info()
	var stock:=session.reserve if session.current_tool==2 else (session.grenades if session.current_tool==3 else session.blocks)
	var weapon_name:=OpenSpadesLocalization.text(str(info.name),"Client").to_upper()
	var tools:=["ЛОПАТА","БЛОКИ",weapon_name,"ГРАНАТА"] if _is_ru() else ["SPADE","BLOCKS",weapon_name,"GRENADE"]
	_ammo.text="%s\n%d / %d"%[tools[session.current_tool],session.magazine,session.reserve] if session.current_tool==2 else "%s\n%d"%[tools[session.current_tool],stock]
	var warning:=int(info.max_stock)/3 if session.current_tool==2 else 0
	_ammo.modulate=Color(1,.3,.3) if stock==0 else (Color(1,1,.3) if stock<=warning else Color.WHITE)
	_weapon_status.text=""
	if session.current_tool==2:
		if session.is_reloading:_weapon_status.text=OpenSpadesLocalization.text("Reloading","Client")+"  %d%%"%int(session.get_reload_progress()*100)
		elif session.magazine==0 and session.reserve==0:_weapon_status.text=OpenSpadesLocalization.text("Out of Ammo","Client")
		elif session.reserve>0 and session.magazine<floori(float(info.clip_size)/4):_weapon_status.text=OpenSpadesLocalization.text("Press [{0}] to Reload","Client",[LabInputBindings.binding_label("reload")])
	elif session.current_tool==1 and session.blocks==0:_weapon_status.text=OpenSpadesLocalization.text("Out of Block","Client")
	elif session.current_tool==3:
		if session.is_cooking_grenade:_weapon_status.text=_ui("Фитиль: %.1f с","Fuse: %.1f s")%maxf(0,3-session.grenade_cook_time)
		elif session.grenades==0:_weapon_status.text=OpenSpadesLocalization.text("Out of Grenade","Client")
	_mode.text="%s   ·   %s"%[world.map_name,session.mode.to_upper()]
	var stats:=world.get_stats()
	_performance.visible=_show_statistics
	_performance.text="%d FPS · %.1f ms · %s chunks · %d draw calls · %.1f MiB"%[Engine.get_frames_per_second(),1000.0/maxi(1,Engine.get_frames_per_second()),stats.get("chunks",0),RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0]
	if _live!=null:_live.text=_ui("Карта: %s  ·  Чанки: %s\nОружие: %s  ·  Профиль: %s","Map: %s  ·  Chunks: %s\nWeapon: %s  ·  Profile: %s")%[world.map_name,stats.get("chunks",0),info.name,session.profile_version]
	_build_cursor.enabled=_hud.is_visible_in_tree() and player.controls_enabled and live
	_native_palette.visible=live and session.current_tool==LocalSession.Tool.BLOCK
	_ammo.offset_left=-472 if _native_palette.visible else -380
	_ammo.offset_right=-120 if _native_palette.visible else -28
	if _palette!=null and not _palette.color.is_equal_approx(player.block_color):_palette.color=player.block_color
	var preview:=player.get_build_preview()
	_build_status.text=""
	if session.current_tool==1 and live:
		_build_status.text=_build_reason(str(preview.get("reason","")))
		if bool(preview.get("valid",false)):_build_status.text=_ui("Поставить: %d блоков","Place: %d blocks")%preview.get("cells",[]).size()
		if bool(preview.get("pending",false)):_build_status.text=_ui("Строительство в прыжке · ожидание места","Jump build: waiting for space")
	_results.text=_ui("Победа: %s","Winner: %s")%LabMap.team_name_for(session,session.winning_team) if session.winning_team>=0 else ""
	_update_hottracked_name()
	_update_feed()
	if _large_map.visible:
		var extent:=minf(512,minf(get_viewport().get_visible_rect().size.x-40,get_viewport().get_visible_rect().size.y-80))
		_large_map.size=Vector2(extent,extent)
		_large_map.offset_left=-extent*.5
		_large_map.offset_top=-extent*.5
		_large_map.offset_right=extent*.5
		_large_map.offset_bottom=extent*.5

func _build_reason(reason: String) -> String:
	var messages: Dictionary={"No block in view":"Нет блока под прицелом","Outside the map":"За границами карты","Out of reach":"Слишком далеко","Insufficient blocks":"Недостаточно блоков","Tool is cooling down":"Инструмент ещё не готов","The line has no support":"У линии нет опоры","Bedrock cannot be changed":"Нижний слой карты нельзя менять","Block intersects player":"Блок пересекает игрока","Block is occupied":"Место занято"}
	return str(messages.get(reason,reason)) if _is_ru() else reason

func _update_intel_indicator(live: bool) -> void:
	_intel_icon.visible=live and session.mode=="ctf" and session.is_local_intel_carrier()
	if _intel_icon.visible:_intel_icon.modulate=Color(1,1,1,absf(sin(session.session_time*2)))

func _update_hottracked_name() -> void:
	_name_under_crosshair.text=""
	_hottracked_player.hide_target()
	if not player.is_inside_tree():return
	if player.camera_mode not in [BlockfieldPlayer.CameraMode.FIRST_PERSON,BlockfieldPlayer.CameraMode.FOLLOW_FIRST_PERSON]:return
	var origin:=player.get_aim_origin()
	var direction:=player.get_aim_direction()
	var viewed_team: int=session.team
	var exclude_id: int=session.local_player_id()
	if player.camera_mode==BlockfieldPlayer.CameraMode.FOLLOW_FIRST_PERSON:
		var observed:=session.get_target(player.followed_target_id)
		if observed.is_empty() or not bool(observed.alive):return
		var crouched:=bool(observed.get("crouching",str(observed.state)=="crouching"))
		origin=Vector3(observed.position)+Vector3.UP*(1.35 if crouched else 2.25)
		direction=-Basis.from_euler(Vector3(float(observed.get("pitch",0)),float(observed.get("yaw",0)),0)).z
		viewed_team=int(observed.team)
		exclude_id=int(observed.id)
	var terrain:=world.cast_source_ray(origin,direction,256)
	var target: Dictionary={}
	var hit_parts: Array[String]=[]
	var closest:=INF
	for candidate: Dictionary in session.targets:
		if int(candidate.id)==exclude_id or not bool(candidate.alive) or int(candidate.team)>=2:continue
		var hit:=LabHitVolumes.cast_camera_ray(origin,direction,candidate.position,float(candidate.get("yaw",0)),bool(candidate.get("crouching",str(candidate.state)=="crouching")),float(candidate.get("pitch",0)),closest)
		if hit.hit and float(hit.distance)<closest:
			closest=hit.distance
			target=candidate
			hit_parts.assign(hit.parts)
	if target.is_empty():return
	# Strict source comparison retains a player at an exact terrain/player tie.
	if terrain.hit and origin.distance_to(terrain.position)<closest:return
	if viewed_team < 2 and int(target.team) != viewed_team:return
	_hottracked_player.show_pose(target.position,float(target.get("yaw",0)),bool(target.get("crouching",str(target.state)=="crouching")),float(target.get("pitch",0)),hit_parts,LabMap.team_color_for(session,int(target.team)))
	if _show_names==0:return
	_name_under_crosshair.text=str(target.get("name","Target %02d"%int(target.id)))
	var eye: Vector3=target.position+Vector3.UP*(1.35 if bool(target.get("crouching",str(target.state)=="crouching")) else 2.25)
	# Client_Draw deliberately measures from the local eye even while following.
	if _show_names==1:
		var distance:=roundi(player.get_aim_origin().distance_to(eye))
		_name_under_crosshair.text+=" [%d%s]"%[distance,"block" if distance==1 else "blocks"]
	if not player.camera.is_position_behind(eye):
		_name_under_crosshair.position=player.camera.unproject_position(eye)-Vector2(200,28)

func _input(event: InputEvent) -> void:
	if session==null:return
	if not _binding_action.is_empty():
		if _capture_binding(event):get_viewport().set_input_as_handled()
		return
	if _chat.is_open:
		if _chat.handle_input(event):get_viewport().set_input_as_handled()
		return
	if event.is_action_released("scoreboard"):_scoreboard.hide()
	if is_menu_open():
		if event.is_action_pressed("pause") and not event.is_echo():set_menu_visible(false);get_viewport().set_input_as_handled()
		return
	if player.controls_enabled and session.health>0 and session.team<2 and session.current_tool==LocalSession.Tool.BLOCK and _native_palette.handle_action(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause") and not event.is_echo():
		if _chat.expanded:_chat.set_expanded(false);_sync_controls()
		else:set_menu_visible(true)
	elif event.is_action_pressed("scoreboard"):_scoreboard.show()
	elif event.is_action_pressed("map") and not event.is_echo():toggle_map()
	elif event.is_action_pressed("map_scale") and not event.is_echo():change_map_scale()
	elif event.is_action_pressed("chat") and not event.is_echo():open_chat(false)
	elif event.is_action_pressed("chat_team") and not event.is_echo():open_chat(true)
	elif event is InputEventKey and event.pressed and not event.echo and (event.unicode==47 or event.keycode==KEY_SLASH):
		open_chat(false)
		_chat.set_input_text("/")
	elif event.is_action_pressed("chat_log") and not event.is_echo():_chat.set_expanded(not _chat.expanded);_sync_controls()
	elif event.is_action_pressed("hide_hud") and not event.is_echo():set_hud_hidden(not _hud_hidden)
	elif event.is_action_pressed("stats") and not event.is_echo():_show_statistics=not _show_statistics;_save_ui_settings()
	elif event.is_action_pressed("screenshot") and not event.is_echo():main.screenshot(false)
	elif event.is_action_pressed("sceneshot") and not event.is_echo():main.screenshot(true)
	elif event.is_action_pressed("save_map") and not event.is_echo():main.save_map()
	else:return
	get_viewport().set_input_as_handled()

func _sync_controls() -> void:
	player.controls_enabled=not is_menu_open() and not _chat.is_open and not _chat.expanded
	LabInputBindings.release_actions()
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED if player.controls_enabled else Input.MOUSE_MODE_VISIBLE

func set_menu_visible(enabled: bool) -> void:
	if _menu==null:return
	_menu.visible=enabled
	_hud.visible=not enabled and not _hud_hidden
	if enabled:
		_scoreboard.hide()
		_large_map.hide()
		if _chat.is_open:_chat.cancel_input()
		_chat.set_expanded(false)
	_sync_controls()

func is_menu_open() -> bool:return _menu!=null and _menu.visible
func is_chat_open() -> bool:return _chat!=null and _chat.is_open
func get_chat_messages() -> Array[Dictionary]:
	return _chat.messages.duplicate(true) if _chat!=null else []
func toggle_scoreboard() -> void:_scoreboard.visible=not _scoreboard.visible
func toggle_map() -> void:
	_large_map.visible=not _large_map.visible
	map_sound_requested.emit("Misc/OpenMap" if _large_map.visible else "Misc/CloseMap")

func change_map_scale() -> void:
	_map.switch_scale()
	map_sound_requested.emit("Misc/SwitchMapZoom")

func set_hud_hidden(hidden: bool) -> void:
	_hud_hidden=hidden
	_hud.visible=not hidden and not is_menu_open()
	_build_cursor.enabled=not hidden and not is_menu_open()
	_large_map.hide()
	_scoreboard.hide()
	_update_alert()
	_save_ui_settings()

func is_hud_hidden() -> bool:return _hud_hidden

func set_capture_visible(enabled: bool) -> void:
	visible=enabled
	_build_cursor.visible=enabled

func reload_resources() -> void:
	if _native_palette!=null:_native_palette.reload_resources()
	_map.reload_resources()
	_large_map.reload_resources()
	_weapon_icon.reload_resources()
	_status_effects.reload_resources()
	_intel_icon.texture=OpenSpadesExtensions.texture("Gfx/Intel.png")
	_alert_icon.texture=OpenSpadesExtensions.texture("Gfx/AlertIcon.png")
	for entry in [[_cross,"Gfx/Sight.tga"],[_hit,"Gfx/HitFeedback.png"]]:
		entry[0].texture=OpenSpadesExtensions.texture(entry[1])
		_center_image(entry[0])

func add_map_tracer(start: Vector3,end: Vector3,weapon: int=0,local_first_person: bool=false) -> void:
	if local_first_person:return
	_map.add_tracer(start,end,weapon)
	_large_map.add_tracer(start,end,weapon)

func show_notice(message: String) -> void:
	show_alert(message)

func show_alert(message: String, kind: String="notice", quiet: bool=false) -> void:
	_alert_kind=kind if kind in ["notice","warning","error"] else "notice"
	_notice.text=message
	_notice_time=2.5 if _alert_kind=="notice" else 3.0
	_alert_age=0.0
	# Client::LocalPlayerBuildError preserves sound with cg_alerts disabled.
	if _alert_kind!="notice" and not quiet:alert_sound_requested.emit()
	_update_alert()

func show_hit(part: String, damage: float, friendly: bool=false) -> void:
	_hit_time=1.0
	_hit_friendly=friendly
	_update_reticle(0.0)
	show_notice("%s  ·  %d %s"%[part,int(damage),_ui("урона","damage")])

func open_chat(team_only: bool=false) -> void:
	if is_menu_open():return
	if _hud_hidden:set_hud_hidden(false)
	_chat.open(team_only)
	_sync_controls()

func _close_chat() -> void:_sync_controls()

func _send_chat(message: String, team_only: bool=false) -> void:
	if _is_network():
		_send_network_chat(message,team_only)
		return
	if main.get("console_service")!=null:
		var result: Dictionary=main.console_service.execute(message)
		if bool(result.get("handled",false)):
			if not str(result.get("message","")).is_empty():_chat.receive(str(result.message),_ui("Консоль","Console"))
			return
	if message.begins_with("/"):
		var parts:=message.split(" ",false)
		match parts[0].to_lower():
			"/help":_chat.receive("/help /restock /reset /mode sandbox|ctf|tc /team blue|green|spectator",_ui("Полигон","Lab"));return
			"/restock":session.restock();return
			"/reset":main.reset_lab();return
			"/mode":
				if parts.size()>1 and parts[1] in ["sandbox","ctf","tc"]:session.set_mode(parts[1])
				return
			"/team":
				if parts.size()>1 and parts[1] in ["blue","green","spectator"]:session.select_team(["blue","green","spectator"].find(parts[1]))
				return
	_chat.receive(message,str(main.player_name),team_only,session.team)
	chat_sound_requested.emit()

func _is_network() -> bool:
	return main!=null and main.get("network_mode")==true

func _send_network_chat(message: String,team_only: bool) -> void:
	if message.begins_with("/"):
		var parts:=message.substr(1).split(" ",false)
		var command:=parts[0].to_lower() if not parts.is_empty() else ""
		if command=="help":
			_chat.receive("/help /team blue|green|spectator; /cvars [prefix], /get name, /set name value, /reset name|all",_ui("Консоль","Console"))
			return
		if command in ["restock","mode"] or (command=="reset" and parts.size()==1):
			_chat.receive(_ui("Эта команда доступна на локальном полигоне.","This command is available in the offline lab."),_ui("Консоль","Console"))
			return
		var console: Variant=main.get("console_service")
		if console!=null:
			var result: Dictionary=console.execute(message)
			if bool(result.get("handled",false)):
				if not str(result.get("message","")).is_empty():_chat.receive(str(result.message),_ui("Консоль","Console"))
				return
		_chat.receive(_ui("Неизвестная команда.","Unknown command."),_ui("Консоль","Console"))
		return
	var client: Variant=main.get("network_client")
	if client==null or not bool(client.send_chat(message,team_only)):_chat.receive(_ui("Сообщение не отправлено.","Message was not sent."),_ui("Сеть","Network"))

func clear_match_feedback() -> void:
	_events.clear()
	_hit_time=0.0
	_hit_friendly=false
	_follow_aim_state=0.0
	_follow_aim_target=-1
	_target_shot_ages.clear()
	if _status_effects!=null:
		_status_effects.hurt_items.clear()
		_status_effects.hurt_sprites.clear()
		_status_effects._hurt_elapsed=10.0
		_status_effects._last_territory=-1
		_status_effects._last_territory_time=-10.0
	if _feed!=null:_feed.clear()

func add_event(event: Dictionary) -> void:
	if str(event.get("type",""))=="reset":
		clear_match_feedback()
		_chat.receive(_ui("Полигон сброшен","Lab reset"),_ui("Полигон","Lab"))
		return
	var entry:=event.duplicate(true)
	entry["hud_time"]=_event_clock
	_events.append(entry)
	if _events.size()>128:_events.pop_front()
	_update_feed()

func _update_feed() -> void:
	_feed.clear()
	var shown:=0
	for index in range(_events.size()-1,-1,-1):
		var event:=_events[index]
		var age:=_event_clock-float(event.hud_time)
		if age>15 or shown>=7:continue
		var text:=_event_text(event)
		if text.is_empty():continue
		shown+=1
		_feed.push_color(Color(1,1,1,clampf(15-age,0,1)))
		if str(event.get("type",""))=="kill":
			_feed.push_color(LabMap.team_color_for(session,int(event.get("killer_team",2))))
			_feed.add_text(str(event.get("killer","")))
			_feed.pop()
			_feed.add_text(" ["+_kill_cause(event)+"] ")
			_feed.push_color(LabMap.team_color_for(session,int(event.get("victim_team",2))))
			_feed.add_text(str(event.get("victim",""))+"\n")
			_feed.pop()
		else:_feed.add_text(text+"\n")
		_feed.pop()

func _kill_cause(event: Dictionary) -> String:
	var part:=str(event.get("part",""))
	if part=="team_change":return _ui("Смена команды","Team change")
	if not bool(event.get("weapon_known",true)) and part not in ["head","melee","grenade","fall"]:
		return _ui("Оружие","Weapon") if part=="weapon" else _ui("Убийство","Kill")
	var cause: String={"head":"Headshot","melee":"Melee","grenade":"Grenade","fall":"Fall"}.get(part,["Rifle","SMG","Shotgun"][clampi(int(event.get("weapon",0)),0,2)])
	return OpenSpadesLocalization.text(cause,"Client")

func _event_text(event: Dictionary) -> String:
	match str(event.get("type","")):
		"kill":
			return "%s  [%s]  %s"%[event.get("killer",""),_kill_cause(event),event.get("victim","")]
		"death":return "%s · %s"%[event.get("name",""),_ui("погиб","died")]+(" ["+str(event.get("kind",""))+"]")
		"respawn":return str(event.get("name",""))+" · "+_ui("возродился","respawned")
		"intel_pickup":return str(event.get("name",""))+" · "+_ui("взял разведданные","picked up intel")
		"intel_drop":return str(event.get("name",""))+" · "+_ui("уронил разведданные","dropped intel")
		"intel_return":return str(event.get("name",""))+" · "+_ui("вернул разведданные","returned intel")
		"intel_capture":return str(event.get("name",""))+" · "+_ui("доставил разведданные","captured intel")
		"territory_capture":return _ui("Территория %d · %s","Territory %d · %s")%[int(event.get("territory",0))+1,LabMap.team_name_for(session,int(event.get("team",0)))]
		"team":return str(event.get("name",""))+" · "+LabMap.team_name_for(session,int(event.get("team",0)))
		"mode":return _ui("Режим: ","Mode: ")+str(event.get("mode",""))
		"round_won":return _ui("Раунд завершён · %s","Round won · %s")%LabMap.team_name_for(session,int(event.get("team",0)))
	return ""

func _is_ru() -> bool:return TranslationServer.get_locale().begins_with("ru")
func _ui(ru: String,en: String) -> String:return ru if _is_ru() else en

func _notification(what: int) -> void:
	if what==NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(_root):
		_translate_nodes(_root)

func _translate_nodes(node: Node) -> void:
	if node.has_meta("ui_ru"):node.set("text",_ui(str(node.get_meta("ui_ru")),str(node.get_meta("ui_en"))))
	if node.has_meta("lab_text"):
		node.set("text",LANGUAGE.lab(str(node.get_meta("lab_text"))))
	if node is TabContainer:
		for index in node.get_tab_count():
			var panel: Control=node.get_tab_control(index)
			if panel.has_meta("lab_title"):node.set_tab_title(index,LANGUAGE.lab(str(panel.get_meta("lab_title"))))
			if panel.has_meta("ui_title_ru"):node.set_tab_title(index,_ui(str(panel.get_meta("ui_title_ru")),str(panel.get_meta("ui_title_en"))))
	if node is OptionButton and node.has_meta("lab_items"):
		var texts: Array=node.get_meta("lab_items")
		for index in texts.size():node.set_item_text(index,LANGUAGE.lab(str(texts[index])))
	if node is OptionButton and node.has_meta("ui_items_ru"):
		var texts: Array=node.get_meta("ui_items_ru") if _is_ru() else node.get_meta("ui_items_en")
		for index in texts.size():node.set_item_text(index,str(texts[index]))
	for child in node.get_children():_translate_nodes(child)
	if node==_root:
		_refresh_binding_labels()
		_update_team_choices()

func _ui_label(ru: String,en: String,size: int=15) -> Label:
	var label:=_label(_ui(ru,en),size)
	label.remove_meta("lab_text")
	label.set_meta("ui_ru",ru)
	label.set_meta("ui_en",en)
	return label

func _ui_button(ru: String,en: String,callback: Callable) -> Button:
	var button:=_button(_ui(ru,en),callback)
	button.remove_meta("lab_text")
	button.set_meta("ui_ru",ru)
	button.set_meta("ui_en",en)
	return button

func _ui_check(column: VBoxContainer,ru: String,en: String,value: bool,callback: Callable) -> CheckButton:
	var button:=CheckButton.new()
	button.text=_ui(ru,en)
	button.set_meta("ui_ru",ru)
	button.set_meta("ui_en",en)
	button.button_pressed=value
	button.toggled.connect(callback)
	column.add_child(button)
	return button

func _build_ui_settings(column: VBoxContainer) -> void:
	column.add_child(_ui_label("ИНТЕРФЕЙС","INTERFACE",18))
	_ui_settings_controls.statistics=_ui_check(column,"Показывать статистику","Show statistics",_show_statistics,func(enabled):_show_statistics=enabled;_save_ui_settings())
	_ui_settings_controls.hit_indicator=_ui_check(column,"Показывать подтверждение попадания","Show hit feedback",_show_hit_feedback,func(enabled):_show_hit_feedback=enabled;_save_ui_settings())
	_ui_settings_controls.alerts=_ui_check(column,"Показывать уведомления","Show alerts",_show_alerts,func(enabled):_show_alerts=enabled;_save_ui_settings())
	_ui_settings_controls.minimap_weapon_icons=_ui_check(column,"Значки оружия на карте","Weapon icons on map",_map_weapon_icons,func(enabled):_map_weapon_icons=enabled;_map.show_weapon_icons=enabled;_large_map.show_weapon_icons=enabled;_save_ui_settings())
	_ui_settings_controls.minimap_player_colors=_ui_check(column,"Разные цвета игроков на карте","Per-player map colors",_map_player_colors,func(enabled):_map_player_colors=enabled;_map.per_player_colors=enabled;_large_map.per_player_colors=enabled;_save_ui_settings())
	column.add_child(_ui_label("Размер миникарты","Minimap size"))
	var map_size:=HSlider.new()
	map_size.min_value=128
	map_size.max_value=256
	map_size.step=8
	map_size.value=_minimap_size
	map_size.value_changed.connect(func(value):_minimap_size=int(value);_apply_map_settings();_save_ui_settings())
	_ui_settings_controls.minimap_size=map_size
	column.add_child(map_size)
	column.add_child(_ui_label("Имена под прицелом","Player names"))
	var names:=OptionButton.new()
	for choice in [_ui("Скрыть","Hide"),_ui("Имя и расстояние","Name and distance"),_ui("Только имя","Name only")]:names.add_item(choice)
	names.select(_show_names)
	names.item_selected.connect(func(index):_show_names=index;_save_ui_settings())
	_ui_settings_controls.player_names=names
	column.add_child(names)
	column.add_child(_ui_button("Скрыть / показать HUD · F6","Hide / show HUD · F6",func():set_hud_hidden(not _hud_hidden)))
	column.add_child(_ui_button("Скриншот с интерфейсом · 0","Screenshot with HUD · 0",func():main.screenshot(false)))
	column.add_child(_ui_button("Скриншот сцены · 9","Scene screenshot · 9",func():main.screenshot(true)))
	var log_export:=_ui_button("Скачать журнал сессии","Download session log",func():main.export_event_log())
	log_export.set_meta("lab_export","event_log")
	column.add_child(log_export)

func _load_ui_settings() -> void:
	var config:=ConfigFile.new()
	if config.load("user://settings.cfg")==OK:
		_minimap_size=clampi(int(config.get_value("ui","minimap_size",180)),128,256)
		_show_statistics=bool(config.get_value("ui","statistics",false))
		_show_hit_feedback=bool(config.get_value("ui","hit_feedback",true))
		_show_alerts=bool(config.get_value("ui","alerts",true))
		_show_names=clampi(int(config.get_value("ui","player_names",2)),0,2)
		_map_weapon_icons=bool(config.get_value("ui","map_weapon_icons",true))
		_map_player_colors=bool(config.get_value("ui","map_player_colors",true))
		_hud_hidden=bool(config.get_value("ui","hidden",false))
	_apply_map_settings()
	_refresh_ui_controls()

func _apply_map_settings() -> void:
	if _map==null:return
	_map.size=Vector2(_minimap_size,_minimap_size)
	_map.offset_left=-_minimap_size-28
	_map.offset_right=-28
	_map.offset_top=24
	_map.offset_bottom=24+_minimap_size
	_map.show_weapon_icons=_map_weapon_icons
	_large_map.show_weapon_icons=_map_weapon_icons
	_map.per_player_colors=_map_player_colors
	_large_map.per_player_colors=_map_player_colors
	_feed.position.y=_minimap_size+50

func _save_ui_settings() -> void:
	var config:=ConfigFile.new()
	config.load("user://settings.cfg")
	var values: Dictionary={"minimap_size":_minimap_size,"statistics":_show_statistics,"hit_feedback":_show_hit_feedback,"alerts":_show_alerts,"player_names":_show_names,"map_weapon_icons":_map_weapon_icons,"map_player_colors":_map_player_colors,"hidden":_hud_hidden}
	for key in values:config.set_value("ui",key,values[key])
	config.save("user://settings.cfg")

func _build_bindings(column: VBoxContainer) -> void:
	column.add_child(_ui_label("НАЗНАЧЕНИЕ КЛАВИШ","KEY BINDINGS",18))
	column.add_child(_ui_label("Нажмите кнопку, затем клавишу или кнопку мыши.\nEsc — отмена; Delete / Backspace — убрать назначение. Дубликат снимается.","Click a binding, then press a key or mouse button.\nEsc cancels; Delete / Backspace unbinds. Duplicate bindings are cleared."))
	var names:= {"forward":"Вперёд|Forward","back":"Назад|Back","left":"Влево|Left","right":"Вправо|Right","jump":"Прыжок / камера|Jump / camera","crouch":"Присесть|Crouch","sprint":"Бег|Sprint","sneak":"Тихий ход|Sneak","primary":"Атака|Attack","secondary":"Прицел / альтернативная атака|Aim / alternate attack","reload":"Перезарядить / перестать следить|Reload / unfollow","last_tool":"Последний инструмент|Last tool","tool_spade":"Лопата|Spade","tool_block":"Блоки|Blocks","tool_weapon":"Оружие|Weapon","tool_grenade":"Граната|Grenade","eyedropper":"Пипетка|Color picker","view_toggle":"Вид камеры|Camera view","map":"Карта|Map","map_scale":"Масштаб карты|Map zoom","scoreboard":"Таблица счёта|Scoreboard","pause":"Меню|Menu","chat":"Глобальный чат|Global chat","chat_team":"Командный чат|Team chat","chat_log":"Журнал чата|Chat history","hide_hud":"Скрыть HUD|Hide HUD","stats":"Статистика|Statistics","screenshot":"Скриншот|Screenshot","sceneshot":"Скриншот сцены|Scene screenshot","save_map":"Сохранить карту|Save map","flashlight":"Фонарик|Flashlight"}
	for action in LabInputBindings.ACTIONS:
		if action=="autofocus":names[action]="Автофокус|Autofocus"
		if action.begins_with("palette_"):
			names[action]={"palette_left":"Палитра влево|Palette left","palette_right":"Палитра вправо|Palette right","palette_up":"Палитра вверх|Palette up","palette_down":"Палитра вниз|Palette down"}[action]
		var row:=HBoxContainer.new()
		column.add_child(row)
		var captions: PackedStringArray=str(names.get(action,action+"|"+action)).split("|")
		var label:=_ui_label(captions[0],captions[1])
		label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var button:=Button.new()
		button.custom_minimum_size=Vector2(300,34)
		button.pressed.connect(func():_binding_action=action;button.text=_ui("Нажмите клавишу…","Press a key…"))
		row.add_child(button)
		_binding_buttons[action]=button
	column.add_child(_ui_button("Сбросить назначения","Reset bindings",func():LabInputBindings.reset_defaults();LabInputBindings.save_bindings();_refresh_binding_labels()))
	_refresh_binding_labels()

func _capture_binding(event: InputEvent) -> bool:
	var binding: InputEvent
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:_binding_action="";_refresh_binding_labels();return true
		if event.keycode not in [KEY_DELETE,KEY_BACKSPACE]:
			binding=event.duplicate()
			binding.pressed=false
			if binding.physical_keycode==0:binding.physical_keycode=binding.keycode
			binding.keycode=0
	elif event is InputEventMouseButton and event.pressed:binding=event.duplicate();binding.pressed=false
	else:return false
	LabInputBindings.bind_action(_binding_action,binding)
	LabInputBindings.save_bindings()
	_binding_action=""
	_refresh_binding_labels()
	return true

func _refresh_binding_labels() -> void:
	for action in _binding_buttons:_binding_buttons[action].text=LabInputBindings.binding_label(action)

func _build_graphics_settings(column: VBoxContainer) -> void:
	if not main.has_method("get_graphics_options"):return
	column.add_child(_ui_label("ГРАФИКА — WEB COMPATIBILITY","GRAPHICS — WEB COMPATIBILITY",18))
	var presets:=HBoxContainer.new()
	column.add_child(presets)
	for entry in [["Низкая","Low","low"],["Средняя","Medium","medium"],["Высокая","High","high"]]:
		var key: String=entry[2]
		presets.add_child(_ui_button(entry[0],entry[1],func():main.set_graphics_preset(key);_refresh_graphics_controls()))
	var options: Dictionary=main.get_graphics_options()
	_graphics_controls["hdr"]=_ui_check(column,"HDR и автоэкспозиция","HDR and auto exposure",bool(options.get("hdr",false)),func(value):main.set_graphics_option("hdr",value);_refresh_graphics_controls())
	for entry in [["lighting","Освещение","Lighting"],["ambient_occlusion","Затенение вокселей","Voxel ambient occlusion"],["shadows","Тени","Shadows"],["fog","Туман","Fog"],["water","Вода","Water"],["blood","Кровь","Blood"],["fxaa","FXAA","FXAA"],["bloom","Свечение","Bloom"],["lens","Эффекты линз","Lens effects"],["lens_flare","Блики линз","Lens flare"],["color_correction","Коррекция цвета","Color correction"],["tone_map","Тональная обработка LDR","LDR tone mapping"],["camera_blur","Размытие камеры","Camera blur"],["dof","Глубина резкости","Depth of field"],["ssao","Экранное затенение","Screen-space ambient occlusion"]]:
		var key: String=entry[0]
		_graphics_controls[key]=_ui_check(column,entry[1],entry[2],bool(options.get(key,false)),func(value):main.set_graphics_option(key,value))
	for entry in [["gi","Непрямой свет","Indirect lighting",false],["water_waves","Волны воды","Water waves",true],["water_refraction","Преломление воды","Water refraction",true],["water_reflections","Отражения в воде","Water reflections",false],["ragdolls","Физика тел после смерти","Corpse physics",true]]:
		var key: String=entry[0]
		_graphics_controls[key]=_ui_check(column,entry[1],entry[2],bool(options.get(key,entry[3])),func(value):main.set_graphics_option(key,value))
	_graphics_controls["manual_focus"]=_ui_check(column,"Ручной фокус: колесо / средняя кнопка","Manual focus: wheel / middle button",bool(options.get("manual_focus",false)),func(value):main.set_graphics_option("manual_focus",value))
	for entry in [["draw_distance","Дальность видимости","Draw distance",16,160,16],["saturation","Насыщенность","Saturation",0,2,.1],["exposure","Экспозиция","Exposure",-4,4,.1],["hdr_min_ev","Минимум автоэкспозиции HDR","HDR minimum exposure",-4,4,.1],["hdr_max_ev","Максимум автоэкспозиции HDR","HDR maximum exposure",-4,4,.1],["hdr_speed","Скорость автоэкспозиции HDR","HDR adaptation speed",0,5,.1],["dof_strength","Сила глубины резкости","Depth-of-field strength",0,2,.1],["ssao_strength","Сила экранного затенения","SSAO strength",0,2,.1],["ambient_energy","Фоновый свет","Ambient light",0,1.5,.05]]:
		var key: String=entry[0]
		column.add_child(_ui_label(entry[1],entry[2]))
		var slider:=HSlider.new()
		slider.min_value=entry[3];slider.max_value=entry[4];slider.step=entry[5]
		slider.value=float(options.get(key,1))
		slider.value_changed.connect(func(value):main.set_graphics_option(key,value))
		column.add_child(slider)
		_graphics_controls[key]=slider
	for entry in [["particles","Частицы","Particles",[0,1,2]],["shake","Тряска камеры","Camera shake",[0,1,2]],["quality","Качество постобработки","Post-processing quality",[0,1,2]],["msaa","MSAA","MSAA",[0,2,4]]]:
		var key: String=entry[0]
		var values: Array=entry[3]
		column.add_child(_ui_label(entry[1],entry[2]))
		var choice:=OptionButton.new()
		for value in values:choice.add_item(str(value))
		choice.select(maxi(0,values.find(int(options.get(key,0)))))
		choice.set_meta("values",values)
		choice.item_selected.connect(func(index):main.set_graphics_option(key,values[index]))
		column.add_child(choice)
		_graphics_controls[key]=choice
	_ui_check(column,"Позиционный звук","Positional audio",bool(main.get("positional_audio")),func(value):main.set("positional_audio",value);main.save_settings())
	var environmental:=_ui_check(column,"Звуки окружения","Environmental audio",true if main.get("environmental_audio")==null else bool(main.get("environmental_audio")),func(value):main.set("environmental_audio",value);main.save_settings())
	environmental.set_meta("lab_audio_key","environmental_audio")
	var efx:=_ui_check(column,"Реверберация и преграды","Reverb and occlusion",true if main.get("source_audio_efx")==null else bool(main.get("source_audio_efx")),func(value):main.set("source_audio_efx",value);main.save_settings())
	efx.set_meta("lab_audio_key","source_audio_efx")
	column.add_child(_ui_label("Усиление источников","Source gain"))
	var source_gain:=HSlider.new()
	source_gain.min_value=0;source_gain.max_value=4;source_gain.step=.05
	source_gain.value=1.0 if main.get("source_audio_gain")==null else float(main.get("source_audio_gain"))
	source_gain.set_meta("lab_audio_key","source_audio_gain")
	source_gain.value_changed.connect(func(value):main.set("source_audio_gain",value);main.save_settings())
	column.add_child(source_gain)

func _refresh_graphics_controls() -> void:
	var options: Dictionary=main.get_graphics_options()
	for key in _graphics_controls:
		var control: Control=_graphics_controls[key]
		if control is CheckButton:control.set_pressed_no_signal(bool(options.get(key,false)))
		elif control is HSlider:control.set_value_no_signal(float(options.get(key,0)))
		elif control is OptionButton:control.select(maxi(0,control.get_meta("values").find(int(options.get(key,0)))))

func _centered_image(path: String) -> TextureRect:
	var image:=TextureRect.new()
	image.texture=OpenSpadesExtensions.texture(path)
	image.mouse_filter=Control.MOUSE_FILTER_IGNORE
	image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode=TextureRect.STRETCH_SCALE
	_hud.add_child(image)
	_center_image(image)
	return image

func _center_image(image: TextureRect) -> void:
	image.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var dimensions:=image.texture.get_size() if image.texture!=null else Vector2.ZERO
	# position is absolute in parent coordinates once parent has a real size;
	# source pixel offsets must remain relative to the .5 anchors after resize.
	image.offset_left=-dimensions.x*.5
	image.offset_top=-dimensions.y*.5
	image.offset_right=dimensions.x*.5
	image.offset_bottom=dimensions.y*.5

func _update_reticle(delta: float) -> void:
	var first_person:=player.camera_mode==BlockfieldPlayer.CameraMode.FIRST_PERSON
	var followed:=player.camera_mode==BlockfieldPlayer.CameraMode.FOLLOW_FIRST_PERSON
	var tool:=session.current_tool
	var valid:=first_person and session.health>0.0 and session.team<2
	var aim:=player.get_aim_down_state()
	if followed:
		var target:=session.get_target(player.followed_target_id)
		valid=not target.is_empty() and bool(target.get("alive",true)) and (not bool(target.get("health_known",true)) or float(target.get("health",100))>0.0) and int(target.get("team",2))<2
		tool=int(target.get("tool",2))
		if _follow_aim_target!=player.followed_target_id:
			_follow_aim_target=player.followed_target_id
			_follow_aim_state=0.0
		var aiming:=bool(target.get("aiming",str(target.get("state",""))=="aiming"))
		_follow_aim_state=clampf(_follow_aim_state+maxf(delta,0.0)*(8.0 if aiming and tool==2 else -3.0),0,1)
		aim=_follow_aim_state
	else:
		_follow_aim_target=-1
		_follow_aim_state=0.0
	if player.has_method("get_camera_aim_down_state"):
		aim=clampf(float(player.call("get_camera_aim_down_state")),0,1)
	if player.has_method("get_camera_tool"):tool=clampi(int(player.call("get_camera_tool")),0,3)
	# BasicViewWeapon/Spade/Block/Grenade::Draw2D, weapon View.as threshold.
	_cross.visible=valid and (tool!=2 or aim<=0.6)
	_hit.visible=valid and _show_hit_feedback and _hit_time>0.0
	var tint:=Color(.02,1,.02) if _hit_friendly else Color(1,.02,.04)
	tint.a=_hit_time
	_hit.modulate=tint

func _create_alert() -> void:
	_alert_panel=Panel.new()
	_alert_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_alert_style=StyleBoxFlat.new()
	_alert_style.bg_color=Color(0,0,0,.5)
	_alert_style.set_border_width_all(1)
	_alert_style.border_blend=false
	_alert_panel.add_theme_stylebox_override("panel",_alert_style)
	_hud.add_child(_alert_panel)
	_notice=_label("",17,Color.WHITE)
	_notice.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_notice.remove_meta("lab_text")
	_alert_panel.add_child(_notice)
	_alert_icon=TextureRect.new()
	_alert_icon.texture=OpenSpadesExtensions.texture("Gfx/AlertIcon.png")
	_alert_icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_alert_icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	_alert_icon.size=Vector2(16,16)
	_alert_panel.add_child(_alert_icon)
	_alert_panel.hide()

func _update_alert() -> void:
	if _alert_panel==null:return
	var fade:=clampf(1.0+_notice_time,0.0,1.0)
	var border_fade:=clampf(1.0-_alert_age*1.5,0.0,1.0)
	_alert_panel.visible=_show_alerts and not _hud_hidden and fade>0.0 and not _notice.text.is_empty()
	_alert_panel.modulate=Color(1,1,1,fade)
	var color:=Color.YELLOW if _alert_kind=="warning" else Color.RED
	color.a=.7*border_fade if _alert_kind!="notice" else 0.0
	_alert_style.border_color=color
	_alert_icon.visible=_alert_kind!="notice"
	_alert_icon.modulate=Color.YELLOW if _alert_kind=="warning" else Color.RED
	var text_size:=_notice.get_minimum_size()
	var contents:=Vector2(floorf(text_size.x+16.0+(22.0 if _alert_kind!="notice" else 0.0)),floorf(maxf(text_size.y,16.0)+16.0))
	_alert_panel.size=contents
	_alert_panel.position=((get_viewport().get_visible_rect().size-contents)*Vector2(.5,.7)+Vector2(0,40)).floor()
	_notice.position=Vector2(contents.x-text_size.x-8.0,(contents.y-text_size.y)*.5)
	_notice.size=text_size
	_alert_icon.position=Vector2(8.0,(contents.y-16.0)*.5)

func _connect_menu_sounds(node: Node) -> void:
	if node is BaseButton:
		node.mouse_entered.connect(func():
			if node.is_visible_in_tree() and not node.disabled:ui_sound_requested.emit("hover"))
		node.pressed.connect(func():
			if not node.disabled:ui_sound_requested.emit("select"))
	for child in node.get_children():_connect_menu_sounds(child)

func _build_target_preview_controls(column: VBoxContainer) -> void:
	column.add_child(_ui_label("АНИМАЦИИ МИШЕНЕЙ — только визуальная проверка","TARGET ANIMATIONS — visual inspection only",14))
	var aiming:=_ui_check(column,"Прицеливание мишеней","Targets aim down sights",false,func(value):_set_target_preview({"aiming":value}))
	aiming.set_meta("lab_target_preview","aiming")
	_target_preview_controls.aiming=aiming
	var reload_toggle:=_ui_check(column,"Перезарядка мишеней","Targets reload",false,func(value):_set_target_preview({"is_reloading":value}))
	reload_toggle.set_meta("lab_target_preview","reloading")
	_target_preview_controls.reloading=reload_toggle
	_target_preview_slider(column,"reload_progress","Стадия перезарядки","Reload stage",0.0,1.12,0.0,func(value):_set_target_preview({"reload_progress":value}))
	_target_preview_slider(column,"cook_time","Удержание гранаты, секунды","Grenade cook, seconds",0.0,3.0,0.0,func(value):_set_target_preview({"grenade_cook_time":value}))
	column.add_child(_ui_label("Действие лопатой","Spade action"))
	var action:=OptionButton.new()
	action.set_meta("ui_items_ru",["Покой","Удар","Первое копание","Повторное копание"])
	action.set_meta("ui_items_en",["Idle","Bash","First dig","Repeated dig"])
	for label in (action.get_meta("ui_items_ru") if _is_ru() else action.get_meta("ui_items_en")):action.add_item(label)
	action.item_selected.connect(func(index):_set_target_preview({"action_type":index}))
	action.set_meta("lab_target_preview","action")
	_target_preview_controls.action=action
	column.add_child(action)
	_target_preview_slider(column,"action_progress","Стадия действия","Action stage",0.0,1.0,0.0,func(value):_set_target_preview({"action_progress":value}))
	column.add_child(_ui_label("Цвет блока мишеней","Target block color"))
	var color:=ColorPickerButton.new()
	color.color=Color(.6,.46,.32)
	color.custom_minimum_size=Vector2(0,36)
	color.color_changed.connect(func(value):_set_target_preview({"block_color":value}))
	color.set_meta("lab_target_preview","block_color")
	_target_preview_controls.block_color=color
	column.add_child(color)
	var shot:=_ui_button("Выстрел мишеней — без урона и звука","Target shot — no damage or sound",_preview_target_shot)
	shot.set_meta("lab_target_preview","shot")
	_target_preview_controls.shot=shot
	column.add_child(shot)
	var reset:=_ui_button("Сбросить анимации мишеней","Reset target animations",reset_target_preview)
	reset.set_meta("lab_target_preview","reset")
	_target_preview_controls.reset=reset
	column.add_child(reset)

func _target_preview_slider(column: VBoxContainer,key: String,ru: String,en: String,minimum: float,maximum: float,initial: float,callback: Callable) -> void:
	column.add_child(_ui_label(ru,en))
	var slider:=HSlider.new()
	slider.min_value=minimum
	slider.max_value=maximum
	slider.step=.01
	slider.value=initial
	slider.set_meta("lab_target_preview",key)
	slider.value_changed.connect(callback)
	_target_preview_controls[key]=slider
	column.add_child(slider)

func _set_target_preview(patch: Dictionary) -> void:
	# Authored test snapshots are separate from local player/game authority.
	for target in session.targets:
		for key in patch:target[key]=patch[key]
	session.changed.emit()

func _preview_target_shot() -> void:
	for target in session.targets:
		if not bool(target.get("alive",true)):continue
		var profile:=_target_profile(target)
		target.profile=session.profile_version
		target.clip_size=int(profile.clip_size)
		target.ammo=maxi(0,int(target.get("ammo",profile.clip_size))-1)
		target.shot_sequence=int(target.get("shot_sequence",0))+1
		target.ready_state=0.0
		_target_shot_ages[int(target.id)]=0.0
	session.changed.emit()

func _target_profile(target: Dictionary) -> Dictionary:
	return LocalSession.WEAPON_PROFILES[session.profile_version][clampi(int(target.get("weapon",0)),0,2)]

func _update_target_shots(delta: float) -> void:
	for id in _target_shot_ages.keys():
		var target:=session.get_target(int(id))
		if target.is_empty() or not bool(target.get("alive",true)):
			_target_shot_ages.erase(id)
			continue
		var elapsed:=float(_target_shot_ages[id])+maxf(delta,0.0)
		var delay:=float(_target_profile(target).delay)
		target.ready_state=elapsed/delay
		if elapsed>=delay*2.0:_target_shot_ages.erase(id)
		else:_target_shot_ages[id]=elapsed

func reset_target_preview() -> void:
	_target_shot_ages.clear()
	var keys:=["aiming","is_reloading","reload_progress","grenade_cook_time","action_type","action_progress","block_color","shot_sequence","ammo","clip_size","profile","ready_state"]
	for target in session.targets:
		for key in keys:target.erase(key)
	for key in _target_preview_controls:
		var control: Control=_target_preview_controls[key]
		if control is CheckButton:control.set_pressed_no_signal(false)
		elif control is HSlider:control.set_value_no_signal(0.0)
		elif control is OptionButton:control.select(0)
		elif control is ColorPickerButton:control.color=Color(.6,.46,.32)
	session.changed.emit()

func get_console_setting(key: String) -> Variant:
	return {"hide_hud":_hud_hidden,"statistics":_show_statistics,"minimap_size":_minimap_size,"player_names":_show_names,"hit_indicator":_show_hit_feedback,"alerts":_show_alerts,"minimap_player_colors":_map_player_colors,"minimap_weapon_icons":_map_weapon_icons}.get(key)

func set_console_setting(key: String,value: Variant) -> bool:
	if key in ["minimap_size","player_names"]:
		if not value is int:return false
		if key=="minimap_size" and (value<128 or value>256):return false
		if key=="player_names" and (value<0 or value>2):return false
	elif not value is bool:return false
	match key:
		"hide_hud":set_hud_hidden(value)
		"statistics":_show_statistics=value
		"minimap_size":_minimap_size=value
		"player_names":_show_names=value
		"hit_indicator":_show_hit_feedback=value
		"alerts":_show_alerts=value
		"minimap_player_colors":_map_player_colors=value
		"minimap_weapon_icons":_map_weapon_icons=value
		_:return false
	_apply_map_settings()
	_refresh_ui_controls()
	_update_alert()
	_update_reticle(0)
	_save_ui_settings()
	return true

func _refresh_ui_controls() -> void:
	for key in _ui_settings_controls:
		var control: Control=_ui_settings_controls[key]
		var value: Variant=get_console_setting(key)
		if control is CheckButton:control.set_pressed_no_signal(bool(value))
		elif control is HSlider:control.set_value_no_signal(float(value))
		elif control is OptionButton:control.select(int(value))

func _build_native_preferences(column: VBoxContainer) -> void:
	column.add_child(_ui_label("ПРЕДСТАВЛЕНИЕ И ЗВУКИ","PRESENTATION AND FEEDBACK",18))
	var brass:=_ui_check(column,"Выбрасывать гильзы","Eject brass",player.eject_brass,func(value):player.eject_brass=value;main.save_settings())
	brass.set_meta("native_preference","eject_brass")
	var animations:=_ui_check(column,"Плавное прицеливание","Animate aiming",player.animations_enabled,func(value):player.animations_enabled=value;main.save_settings())
	animations.set_meta("native_preference","animations_enabled")
	var beep:=_ui_check(column,"Звук сообщений чата","Chat notification sound",bool(main.get("chat_beep")),func(value):main.set("chat_beep",value);main.save_settings())
	beep.set_meta("native_preference","chat_beep")
	column.add_child(_ui_label("Громкость звука попадания в голову","Headshot feedback volume"))
	var gain:=HSlider.new()
	gain.min_value=0.0
	gain.max_value=1.0
	gain.step=.01
	var saved_gain: Variant=main.get("hit_feedback_gain")
	gain.value=float(saved_gain) if saved_gain!=null else .2
	gain.set_meta("native_preference","hit_feedback_gain")
	gain.value_changed.connect(func(value):main.set("hit_feedback_gain",value);main.save_settings())
	column.add_child(gain)
	for axis in 3:
		column.add_child(_ui_label(["Смещение оружия: вбок","Смещение оружия: вперёд","Смещение оружия: вниз"][axis],["Weapon offset: sideways","Weapon offset: forward","Weapon offset: down"][axis]))
		var slider:=HSlider.new()
		slider.min_value=-.5
		slider.max_value=.5
		slider.step=.005
		slider.value=player.view_weapon_offset[axis]
		slider.set_meta("native_preference","weapon_offset_"+str(axis))
		slider.value_changed.connect(func(value):
			var offset:=player.view_weapon_offset
			offset[axis]=value
			player.view_weapon_offset=offset
			main.save_settings())
		column.add_child(slider)
