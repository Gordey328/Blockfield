extends SceneTree
## Actual menu controls and chat paths, isolated from Main and preference writes.
const PLAYER=preload("res://gameplay/player_controller.gd")
const SCOREBOARD=preload("res://ui/lab_scoreboard.gd")
const NETWORK_MENU=preload("res://ui/network_menu.gd")
const SERVER_BOOK=preload("res://ui/server_book.gd")
var assertions:=0
var failures:=0
var render_menu:=false

class FakeClient extends RefCounted:
	var state: Dictionary={"status":"idle","error":"","map":{}}
	var sent: Array[Dictionary]=[]
	var allow_chat:=true
	func get_stats() -> Dictionary:return state.duplicate(true)
	func send_chat(message: String,team_only: bool) -> bool:
		if not allow_chat:return false
		sent.append({"message":message,"team":team_only});return true

class IntentSession extends LocalSession:
	var weapon_intents: Array[int]=[]
	var team_intents: Array[int]=[]
	func select_weapon(index: int) -> void:weapon_intents.append(index)
	func select_team(index: int) -> void:team_intents.append(index)
	func local_player_id() -> int:return 43

class FakeConsole extends RefCounted:
	var calls: Array[String]=[]
	var session: IntentSession
	func execute(command: String) -> Dictionary:
		calls.append(command)
		if command=="/unknown":return {"handled":false}
		if command=="/team blue":session.select_team(0)
		return {"handled":true,"message":"setting value"}

class AppDouble extends Node3D:
	var network_mode:=true
	var player_name:="Player"
	var locale:="en"
	var chat_beep:=true
	var hit_feedback_gain:=.2
	var network_client: FakeClient=FakeClient.new()
	var console_service: FakeConsole=FakeConsole.new()
	var can_resume:=false
	var attempts: Array[Dictionary]=[]
	var connect_failure:=""
	var disconnects:=0
	var offline_calls:=0
	var network_calls:=0
	var saves:=0
	func network_connect(game_url: String,map_url: String,player: String,spectator: bool,resume: bool=false) -> Dictionary:
		attempts.append({"game":game_url,"map":map_url,"name":player,"spectator":spectator,"resume":resume})
		if not connect_failure.is_empty():return {"ok":false,"error":connect_failure}
		network_client.state.status="connecting";return {"ok":true}
	func network_disconnect() -> void:disconnects+=1;network_client.state.status="closed"
	func network_can_resume() -> bool:return can_resume
	func open_offline_lab() -> void:offline_calls+=1
	func open_network_game() -> void:network_calls+=1
	func save_settings() -> void:saves+=1
	func set_locale(value: String) -> void:locale=value
	func toggle_fullscreen() -> void:pass
	func screenshot(_scene_only: bool) -> void:pass
	func export_event_log() -> void:pass

class MenuHUD extends LabHUD:
	var settings_calls:=0
	var offline_builders: Array[String]=[]
	var enter_calls:=0
	func _build_settings(column: VBoxContainer) -> void:
		settings_calls+=1
		super._build_settings(column)
	func _build_arsenal(_column: VBoxContainer) -> void:offline_builders.append("arsenal")
	func _build_soldiers(_column: VBoxContainer) -> void:offline_builders.append("soldiers")
	func _build_world(_column: VBoxContainer) -> void:offline_builders.append("world")
	func _build_checks(_column: VBoxContainer) -> void:offline_builders.append("checks")
	func set_menu_visible(enabled: bool) -> void:
		if not enabled:enter_calls+=1
		_menu.visible=enabled

func _initialize() -> void:
	render_menu="--render-menu" in OS.get_cmdline_user_args()
	if render_menu:root.size=Vector2i(1280,720)
	call_deferred("_run")
func check(condition: bool,message: String) -> void:
	assertions+=1
	if not condition:failures+=1;push_error("NETWORK MENU: "+message)

func _make_hud(app: AppDouble,session: IntentSession,player: BlockfieldPlayer) -> MenuHUD:
	var hud:=MenuHUD.new()
	root.add_child(hud);hud.set_process(false)
	hud.main=app;hud.session=session;hud.player=player
	hud._root=Control.new();hud._root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);hud.add_child(hud._root)
	var theme:=Theme.new();theme.default_font=OpenSpadesLocalization.get_ui_font();hud._root.theme=theme
	hud._chat=LabChat.new();hud._root.add_child(hud._chat)
	hud._create_menu()
	if hud._network_menu!=null:hud._network_menu.set_process(false)
	return hud

func _run() -> void:
	var settings_existed:=FileAccess.file_exists("user://settings.cfg")
	var settings_before:=FileAccess.get_file_as_bytes("user://settings.cfg") if settings_existed else PackedByteArray()
	var servers_existed:=FileAccess.file_exists("user://servers.cfg")
	var servers_before:=FileAccess.get_file_as_bytes("user://servers.cfg") if servers_existed else PackedByteArray()
	if servers_existed:DirAccess.remove_absolute(ProjectSettings.globalize_path("user://servers.cfg"))
	var original_locale:=TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	var app:=AppDouble.new()
	var session:=IntentSession.new()
	root.add_child(session);session.set_process(false)
	app.console_service.session=session
	var player:=PLAYER.new();player.session=session
	var hud:=_make_hud(app,session,player)
	var menu: NETWORK_MENU=hud._network_menu
	var c: Dictionary=menu.controls
	check(menu!=null and hud.offline_builders.is_empty(),"network branch creates no arsenal, target, world or cheat panels")
	check(hud.settings_calls==1 and not hud._binding_buttons.is_empty(),"online menu reuses actual input and display settings")
	check(c.game_url.text.is_empty() and c.map_url.text.is_empty(),"no invented configured public endpoint")
	check(c.game_url.placeholder_text=="wss://host/play" and c.map_url.placeholder_text=="wss://host/map","secure URL placeholders show both services")
	check(c.connect.disabled and c.resume.disabled and c.enter.disabled and c.team.disabled,"disconnected empty form cannot enter or select class")
	check(c.status.text=="Not connected" and not c.progress.visible,"idle status has no misleading progress")
	check(c.player_name.text==app.player_name,"connection form starts from current player name")
	var tabs: TabContainer=_find_tabs(menu)
	check(tabs.get_tab_count()==3 and tabs.get_tab_title(0)=="Connection" and tabs.get_tab_title(1)=="Servers" and tabs.get_tab_title(2)=="Settings","network tabs are manual connection, saved servers and shared settings")
	check(c.favorites.item_count==0 and not FileAccess.file_exists("user://servers.cfg"),"initial saved catalog is empty and menu construction never writes it")
	check(c.favorite_add.disabled and c.favorite_update.disabled and c.favorite_delete.disabled,"empty form and no selection cannot modify favorites")
	c.game_url.text="ws://127.0.0.1:19132/play";c.map_url.text="ws://127.0.0.1:19133/map"
	c.spectator.button_pressed=true;c.favorite_name.text="Zeta";menu.refresh();c.favorite_add.pressed.emit()
	check(c.favorites.item_count==1 and FileAccess.file_exists("user://servers.cfg") and c.favorite_message.text=="Server saved.","explicit Add saves current addresses and spectator role")
	var catalog:=SERVER_BOOK.new()
	check(catalog.load().ok and catalog.get_entry(1).spectator and catalog.get_entry(1).game_url==c.game_url.text,"actual saved config restores favorite identity, URL and role")
	c.game_url.text="wss://alpha.example/play";c.map_url.text="wss://alpha.example/map";c.spectator.button_pressed=false;c.favorite_name.text="Alpha";menu.refresh();c.favorite_add.pressed.emit()
	check(c.favorites.item_count==2 and c.favorites.get_item_text(0)=="Alpha" and c.favorites.get_item_text(1)=="Zeta","saved servers display stable name order")
	c.favorites.item_selected.emit(1)
	check(c.game_url.text=="ws://127.0.0.1:19132/play" and c.map_url.text=="ws://127.0.0.1:19133/map" and c.spectator.button_pressed and c.favorite_name.text=="Zeta","selection fills exact game/map/name/role form")
	check(app.attempts.is_empty() and c.player_name.text==app.player_name,"selecting favorite neither connects nor changes player identity")
	check(c.favorite_details.text.ends_with("Spectator") and not c.favorite_update.disabled and not c.favorite_delete.disabled,"selected favorite exposes saved role and explicit edit actions")
	var favorites_saved:=FileAccess.get_file_as_bytes("user://servers.cfg")
	c.favorite_filter.text=" AL ";c.favorite_filter.text_changed.emit(c.favorite_filter.text)
	check(c.favorites.item_count==1 and c.favorites.get_item_text(0)=="Alpha" and c.favorite_update.disabled and c.favorite_delete.disabled,"name filter clears hidden selection and cannot update wrong entry")
	check(FileAccess.get_file_as_bytes("user://servers.cfg")==favorites_saved,"filter and selection are read-only")
	c.favorite_filter.text="";c.favorite_filter.text_changed.emit("");c.favorites.item_selected.emit(1)
	c.favorite_name.text="Zeta updated";c.map_url.text="ws://127.0.0.1:19133/revised";menu.refresh();c.favorite_update.pressed.emit()
	catalog.load()
	check(catalog.get_entry(1).name=="Zeta updated" and catalog.get_entry(1).map_url==c.map_url.text and catalog.list().size()==2,"Update changes selected identity without inserting duplicate")
	var before_invalid:=FileAccess.get_file_as_bytes("user://servers.cfg")
	c.game_url.text="wss://host/play?token=NEVER_SAVE_TOKEN";c.favorite_name.text="Private address";menu.refresh();c.favorite_add.pressed.emit()
	check(FileAccess.get_file_as_bytes("user://servers.cfg")==before_invalid and c.favorites.item_count==2,"credential query is rejected before persistence")
	check(c.favorite_message.text.begins_with("Check the server") and "NEVER_SAVE_TOKEN" not in c.favorite_message.text,"favorite validation shows a concise error without echoing credentials")
	c.favorites.item_selected.emit(1)
	var persisted_hud:=_make_hud(app,session,player)
	check(persisted_hud._network_menu.controls.favorites.item_count==2 and app.attempts.is_empty(),"fresh actual menu loads persisted catalog without connecting")
	persisted_hud.free()
	if render_menu:
		tabs.current_tab=1
		await _capture(hud,menu,"english-servers")
		tabs.current_tab=0
	c.game_url.text="  ws://127.0.0.1:19132/play  ";c.map_url.text="ws://127.0.0.1:19133/map";c.player_name.text="  Actor43  "
	c.spectator.button_pressed=true;menu.refresh()
	check(not c.connect.disabled and c.resume.disabled,"populated form allows fresh connection without a capability")
	c.connect.pressed.emit()
	check(app.attempts.size()==1 and app.attempts[0]=={"game":"ws://127.0.0.1:19132/play","map":"ws://127.0.0.1:19133/map","name":"Actor43","spectator":true,"resume":false},"connect forwards trimmed explicit addresses and spectator intent to Main")
	check(c.connect.disabled and c.resume.disabled and not c.disconnect.disabled and not c.game_url.editable,"active connection freezes join fields but allows disconnect")
	check(c.progress.visible and c.progress.indeterminate and c.status.text=="Connecting…","connecting reports an honest indeterminate operation")
	var active_catalog:=FileAccess.get_file_as_bytes("user://servers.cfg")
	c.favorite_add.pressed.emit();c.favorite_update.pressed.emit();c.favorite_delete.pressed.emit();c.favorites.item_selected.emit(0)
	check(c.favorite_add.disabled and c.favorite_update.disabled and c.favorite_delete.disabled and not c.favorite_name.editable,"active connection disables saved-server modifications")
	check(FileAccess.get_file_as_bytes("user://servers.cfg")==active_catalog and c.game_url.text.strip_edges()=="ws://127.0.0.1:19132/play","premature favorite callbacks cannot alter active endpoints or persistent catalog")
	c.enter.pressed.emit();c.weapon_2.pressed.emit();c.team.item_selected.emit(1)
	check(hud.enter_calls==0 and session.weapon_intents.is_empty() and session.team_intents.is_empty(),"direct callbacks cannot enter or select before ready")
	app.network_client.state.status="preparing";menu.refresh()
	check(c.status.text=="Preparing match…" and c.progress.visible and c.enter.disabled and not c.game_url.editable,"early epoch announcement keeps gameplay and endpoints gated before map preparation")
	c.enter.pressed.emit();c.weapon_2.pressed.emit();c.team.item_selected.emit(1)
	check(hud.enter_calls==0 and session.weapon_intents.is_empty() and session.team_intents.is_empty(),"preparing callbacks cannot act on an uninstalled new match")
	app.network_client.state.status="loading";app.network_client.state.map={"work_phase":"hash","resume_token":"NEVER_SHOW_TOKEN"};menu.refresh()
	check(c.status.text=="Preparing map…" and c.progress.visible and c.enter.disabled,"map verification is visible and remains gated")
	check("NEVER_SHOW_TOKEN" not in _visible_text(menu),"menu reads no capability or diagnostic dictionary into labels")
	app.network_client.state.status="synchronizing";menu.refresh()
	check(c.status.text=="Synchronizing…" and c.enter.disabled,"map readiness alone does not enable entry before owner state")
	app.network_client.state.status="live";session.team=0;menu.refresh()
	check(not c.enter.disabled and not c.team.disabled and not c.weapon_0.disabled and not c.block_color.disabled,"confirmed live state enables join controls and class intent")
	check(c.status.text=="Connected" and not c.progress.visible,"live state ends loading indicator")
	if render_menu:
		await _capture(hud,menu,"english")
		var connection_scroll: ScrollContainer=tabs.get_tab_control(0).get_child(0)
		connection_scroll.scroll_vertical=100000
		await _capture(hud,menu,"english-selection")
		connection_scroll.scroll_vertical=0
	var magazine_before:=session.magazine
	var weapon_before:=session.current_weapon
	c.weapon_2.pressed.emit();c.team.item_selected.emit(1)
	check(session.weapon_intents==[2] and session.team_intents==[1],"weapon and team buttons send only intent through session")
	check(session.magazine==magazine_before and session.current_weapon==weapon_before,"class button does not grant ammo or replace authoritative weapon")
	var color:=Color(.3,.7,.2)
	c.block_color.color_changed.emit(color)
	check(player.block_color.is_equal_approx(color),"block color reaches controller selection intent")
	c.enter.pressed.emit();check(hud.enter_calls==1,"ready Enter delegates existing menu/input transition")
	c.offline.pressed.emit();check(app.offline_calls==1,"offline lab has an explicit scene action")
	c.disconnect.pressed.emit();app.can_resume=true;menu.refresh()
	check(app.disconnects==1 and c.status.text=="Disconnected" and not c.resume.disabled,"reconnect is exposed through safe boolean capability helper")
	c.resume.pressed.emit()
	check(app.attempts.size()==2 and bool(app.attempts[1].resume),"reconnect delegates token use to Main without reading it")
	app.network_client.state.status="closed";app.connect_failure="Use a secure connection.";menu.refresh();c.connect.pressed.emit()
	check(c.error.visible and c.error.text==app.connect_failure and c.game_url.editable,"Main URL/connect rejection remains visible and editable")
	app.connect_failure="";c.connect.pressed.emit();app.network_client.state.status="failed";app.network_client.state.error="Map connection lost";menu.refresh()
	check(c.error.visible and c.error.text=="Map connection lost" and c.status.text=="Connection interrupted","asynchronous failure is shown without raw transport state")
	app.network_client.state.error="";app.network_client.state.status="live";menu.refresh()
	TranslationServer.set_locale("ru");hud._translate_nodes(hud._menu);menu.refresh()
	check(c.connect.text=="Подключить" and c.status.text=="Подключено" and tabs.get_tab_title(0)=="Подключение" and tabs.get_tab_title(1)=="Серверы" and c.favorite_filter.placeholder_text=="Поиск по имени","live network controls, saved-server filter and status refresh Russian locale")
	if render_menu:
		await _capture(hud,menu,"russian")
		tabs.current_tab=1
		await _capture(hud,menu,"russian-servers")
		tabs.current_tab=0
	TranslationServer.set_locale("en");hud._translate_nodes(hud._menu);menu.refresh()
	check(c.resume.text=="Reconnect" and tabs.get_tab_title(1)=="Servers" and tabs.get_tab_title(2)=="Settings","network tabs and actions return to English")
	var beeps: Array[int]=[]
	hud.chat_sound_requested.connect(func():beeps.append(1))
	hud._send_chat("hello",true)
	check(app.network_client.sent==[{"message":"hello","team":true}],"online ordinary chat goes to the bound client and retains team channel")
	check(hud._chat.messages.is_empty() and beeps.is_empty(),"pending chat creates no optimistic duplicate echo or audio")
	app.network_client.allow_chat=false;hud._send_chat("lost",false)
	check(hud._chat.messages.back().text=="Message was not sent.","unsent chat reports local failure")
	for command in ["/restock","/reset","/mode ctf"]:hud._send_chat(command,false)
	check(app.console_service.calls.is_empty() and app.network_client.sent.size()==1,"offline authority commands never reach console or server chat")
	hud._send_chat("/help",false)
	check("/restock" not in hud._chat.messages.back().text and "/mode" not in hud._chat.messages.back().text and app.console_service.calls.is_empty(),"online help advertises only supported network and preference commands")
	hud._send_chat("/get cg_stats",false);hud._send_chat("/reset cg_stats",false);hud._send_chat("/team blue",false)
	check(app.console_service.calls==["/get cg_stats","/reset cg_stats","/team blue"],"read/display preferences and team intent keep console dispatch")
	check(session.team_intents==[1,0],"network team command follows session intent")
	hud._send_chat("/unknown",false)
	check(hud._chat.messages.back().text=="Unknown command." and app.network_client.sent.size()==1,"unknown slash command stays local")
	check(hud._kill_cause({"part":"weapon","weapon_known":false})=="Weapon","missing confirmed shot attribution does not invent a rifle kill")
	check(hud._kill_cause({"part":"weapon","weapon_known":true,"weapon":1})=="SMG","known confirmed shot retains exact weapon feed")
	for cause in ["melee","grenade","fall"]:
		check(hud._kill_cause({"part":cause,"weapon_known":false})==cause.capitalize(),"known %s cause remains visible without gun attribution"%cause)
	check(hud._kill_cause({"part":"team_change","weapon_known":false})=="Team change","team change cause is explicit instead of default gun")
	var scoreboard:=SCOREBOARD.new();scoreboard.setup(app,session)
	root.add_child(scoreboard);scoreboard.set_process(false)
	session.targets.assign([{"id":14,"name":"Flag carrier","team":1,"score":10,"kills":0,"alive":true},{"id":15,"name":"Legacy soldier","team":1,"kills":2,"alive":true}])
	var rows:=scoreboard.get_rows()
	check(_row(rows,14).score==10 and _row(rows,15).score==2,"scoreboard uses authoritative score including captures with offline kills fallback")
	scoreboard._process(0)
	check(scoreboard._title.text.begins_with("MULTIPLAYER MATCH"),"network scoreboard uses multiplayer title")
	app.network_mode=false
	var offline:=_make_hud(app,session,player)
	check(offline._network_menu==null and offline.offline_builders==["arsenal","soldiers","world","checks"] and offline.settings_calls==1,"offline menu retains its complete builder branch")
	var play:=_find_button(offline._menu,"Multiplayer →")
	check(play!=null,"offline menu contains an explicit multiplayer action")
	if play!=null:play.pressed.emit()
	check(app.network_calls==1,"offline multiplayer action delegates scene change to Main")
	scoreboard._process(0);check(scoreboard._title.text.begins_with("OFFLINE MATCH"),"offline scoreboard title remains compatible")
	check(app.saves==0,"constructing and operating network form writes no application preferences")
	check(FileAccess.file_exists("user://settings.cfg")==settings_existed and (not settings_existed or FileAccess.get_file_as_bytes("user://settings.cfg")==settings_before),"isolated menu checks preserve exact preference bytes")
	app.network_client.state.status="closed";menu.refresh();c.favorites.item_selected.emit(1);c.favorite_delete.pressed.emit()
	catalog.load()
	check(c.favorites.item_count==1 and catalog.get_entry(1).is_empty() and catalog.get_entry(2).name=="Alpha","Delete persists only selected favorite and preserves other server")
	check(app.attempts.size()==4,"favorites actions never create hidden connection attempts")
	offline.free();hud.free();scoreboard.free();player.free();app.free();session.free()
	if servers_existed:
		var restore_servers:=FileAccess.open("user://servers.cfg",FileAccess.WRITE)
		restore_servers.store_buffer(servers_before);restore_servers.close()
	else:DirAccess.remove_absolute(ProjectSettings.globalize_path("user://servers.cfg"))
	check(FileAccess.file_exists("user://servers.cfg")==servers_existed and (not servers_existed or FileAccess.get_file_as_bytes("user://servers.cfg")==servers_before),"actual server config restored byte-for-byte after explicit UI persistence tests")
	TranslationServer.set_locale(original_locale)
	print("NETWORK MENU CHECKS: %d assertions, %d failures"%[assertions,failures])
	quit(1 if failures>0 else 0)

func _find_tabs(node: Node) -> TabContainer:
	if node is TabContainer:return node
	for child in node.get_children():
		var found:=_find_tabs(child)
		if found!=null:return found
	return null
func _find_button(node: Node,text: String) -> Button:
	if node is Button and node.text==text:return node
	for child in node.get_children():
		var found:=_find_button(child,text)
		if found!=null:return found
	return null
func _visible_text(node: Node) -> String:
	var result:=str(node.get("text")) if node is Label or node is Button or node is LineEdit else ""
	for child in node.get_children():result+="\n"+_visible_text(child)
	return result
func _row(rows: Array[Dictionary],id: int) -> Dictionary:
	for row in rows:
		if int(row.id)==id:return row
	return {}
func _capture(hud: MenuHUD,menu: NETWORK_MENU,language: String) -> void:
	if DisplayServer.get_name()=="headless":check(false,"menu capture requires real graphics context");return
	hud._menu.show()
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	var output:=ProjectSettings.globalize_path("res://../.cache/previews/network-menu")
	DirAccess.make_dir_recursive_absolute(output)
	check(image.save_png(output+"/"+language+".png")==OK,"real GPU menu readback saved")
	check(image.get_size()==Vector2i(1280,720),"real GPU menu captured at intended viewport size")
	var enter: Button=menu.controls.enter
	check(enter.get_global_rect().end.y<=root.get_visible_rect().size.y-20 and enter.get_global_rect().position.x>=20,"menu footer stays inside rendered viewport after layout")
	if language.ends_with("servers"):
		var tabs:=_find_tabs(menu)
		for key in ["favorite_name","favorite_add","favorite_update","favorite_delete"]:
			var control: Control=menu.controls[key]
			check(control.get_global_rect().end.y<=tabs.get_global_rect().end.y-20 and control.get_global_rect().position.x>=60,"favorite save controls remain visible without scrolling")
