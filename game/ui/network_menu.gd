class_name BlockfieldNetworkMenu
extends VBoxContainer
## Connection/selection controls only; authority and capabilities stay in Main.
const SERVER_BOOK = preload("res://ui/server_book.gd")
var controls: Dictionary = {}
var server_book_path := "user://servers.cfg"
var _hud: Node
var _app: Node3D
var _session: LocalSession
var _player: BlockfieldPlayer
var _status: Label
var _error: Label
var _progress: ProgressBar
var _game_url: LineEdit
var _map_url: LineEdit
var _name_field: LineEdit
var _spectator: CheckButton
var _team: OptionButton
var _connect_error := ""
var _book := SERVER_BOOK.new()
var _favorite_id := 0
var _favorite_name: LineEdit
var _favorite_filter: LineEdit
var _favorites: ItemList
var _favorite_message: Label
var _favorite_details: Label
var _favorite_rows: Array[Dictionary] = []
var _book_available := true

func setup(hud: Node,app: Node3D,session: LocalSession,player: BlockfieldPlayer) -> void:
	_hud=hud;_app=app;_session=session;_player=player
	add_theme_constant_override("separation",14)
	add_child(_label("BLOCKFIELD", "BLOCKFIELD",40))
	add_child(_label("Мультиплеер","Multiplayer",22))
	var tabs:=TabContainer.new()
	tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL
	add_child(tabs)
	var connection: VBoxContainer=_hud.call("_tab",tabs,"Подключение","Connection")
	connection.add_child(_label("Адрес игры","Game address"))
	_game_url=_field("wss://host/play","")
	controls.game_url=_game_url
	connection.add_child(_game_url)
	connection.add_child(_label("Адрес карты","Map address"))
	_map_url=_field("wss://host/map","")
	controls.map_url=_map_url
	connection.add_child(_map_url)
	connection.add_child(_label("Имя игрока","Player name"))
	_name_field=_field("",str(_app.get("player_name")))
	_name_field.max_length=24
	controls.player_name=_name_field
	connection.add_child(_name_field)
	_spectator=CheckButton.new()
	_text(_spectator,"Войти наблюдателем","Join as spectator")
	controls.spectator=_spectator
	connection.add_child(_spectator)
	var actions:=GridContainer.new();actions.columns=3
	connection.add_child(actions)
	_add_button(actions,"connect","Подключить","Connect",func():_connect(false))
	_add_button(actions,"resume","Повторный вход","Reconnect",func():_connect(true))
	_add_button(actions,"disconnect","Отключить","Disconnect",_disconnect)
	_status=_label("Не подключено","Not connected")
	_status.remove_meta("ui_ru");_status.remove_meta("ui_en")
	controls.status=_status
	connection.add_child(_status)
	_progress=ProgressBar.new()
	_progress.show_percentage=false
	_progress.indeterminate=true
	_progress.custom_minimum_size.y=12
	controls.progress=_progress
	connection.add_child(_progress)
	_error=_label("","",15)
	_error.remove_meta("ui_ru");_error.remove_meta("ui_en")
	_error.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_error.add_theme_color_override("font_color",Color("ed806d"))
	controls.error=_error
	connection.add_child(_error)
	connection.add_child(HSeparator.new())
	connection.add_child(_label("Команда","Team"))
	_team=OptionButton.new()
	for index in range(3):_team.add_item("")
	_team.item_selected.connect(func(index:int):if _is_live():_session.select_team(index))
	controls.team=_team
	connection.add_child(_team)
	connection.add_child(_label("Оружие","Weapon"))
	var weapons:=HBoxContainer.new()
	connection.add_child(weapons)
	for entry: Array in [["Винтовка","Rifle",0],["Пистолет-пулемёт","SMG",1],["Дробовик","Shotgun",2]]:
		var index: int=entry[2]
		_add_button(weapons,"weapon_%d" % index,entry[0],entry[1],func():if _is_live():_session.select_weapon(index))
	connection.add_child(_label("Смена оружия — при возрождении.","Weapon changes take effect on respawn.",14))
	connection.add_child(_label("Цвет блоков","Block color"))
	var palette:=ColorPickerButton.new()
	palette.color=_player.block_color
	palette.custom_minimum_size=Vector2(160,32)
	palette.color_changed.connect(func(color:Color):if _is_live():_player.block_color=color)
	controls.block_color=palette
	connection.add_child(palette)
	var servers: VBoxContainer=_hud.call("_tab",tabs,"Серверы","Servers")
	_build_servers(servers)
	var settings: VBoxContainer=_hud.call("_tab",tabs,"Настройки","Settings")
	_hud.call("_build_settings",settings)
	var footer:=HBoxContainer.new()
	add_child(footer)
	_add_button(footer,"enter","Войти →","Enter →",func():if _is_live():_hud.call("set_menu_visible",false))
	_add_button(footer,"offline","Локальный полигон","Offline lab",func():_app.call("open_offline_lab"))
	for field: LineEdit in [_game_url,_map_url,_name_field]:field.text_changed.connect(func(_value:String):refresh())
	refresh()

func _build_servers(column: VBoxContainer) -> void:
	column.add_theme_constant_override("separation", 8)
	column.add_child(_label("Выбор заполнит форму подключения. Сохраняются текущие адреса.", "Choose a server to fill the form, or save the current addresses.", 14))
	_favorite_filter = _field("", "")
	_text_placeholder(_favorite_filter, "Поиск по имени", "Filter by name")
	controls.favorite_filter = _favorite_filter
	column.add_child(_favorite_filter)
	_favorites = ItemList.new()
	_favorites.custom_minimum_size.y = 112
	_favorites.allow_reselect = true
	_favorites.item_selected.connect(_select_favorite)
	controls.favorites = _favorites
	column.add_child(_favorites)
	_favorite_details = _label("", "", 14)
	_favorite_details.remove_meta("ui_ru"); _favorite_details.remove_meta("ui_en")
	_favorite_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.favorite_details = _favorite_details
	column.add_child(_favorite_details)
	var edit_row := HBoxContainer.new()
	edit_row.add_theme_constant_override("separation", 12)
	column.add_child(edit_row)
	var name_column := VBoxContainer.new()
	name_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_column.size_flags_stretch_ratio = 2
	edit_row.add_child(name_column)
	name_column.add_child(_label("Имя сервера", "Server name"))
	_favorite_name = _field("", "")
	_favorite_name.max_length = 64
	controls.favorite_name = _favorite_name
	name_column.add_child(_favorite_name)
	var actions := HBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_row.add_child(actions)
	_add_button(actions, "favorite_add", "Добавить", "Add", func(): _save_favorite(false))
	_add_button(actions, "favorite_update", "Обновить", "Update", func(): _save_favorite(true))
	_add_button(actions, "favorite_delete", "Удалить", "Delete", _delete_favorite)
	_favorite_message = _label("", "", 14)
	_favorite_message.remove_meta("ui_ru"); _favorite_message.remove_meta("ui_en")
	_favorite_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.favorite_message = _favorite_message
	column.add_child(_favorite_message)
	_favorite_filter.text_changed.connect(func(_value: String): _refresh_favorites())
	_favorite_name.text_changed.connect(func(_value: String): refresh())
	# Keep an explicitly chosen file even when a corrupt initial load is rejected.
	_book_available = bool(_book.set_storage_path(server_book_path).ok)
	var loaded: Dictionary = _book.load(server_book_path) if _book_available else {"ok": false}
	if not loaded.ok: _favorite_notice("load")
	_refresh_favorites()

func _text_placeholder(field: LineEdit, ru: String, en: String) -> void:
	field.set_meta("ui_placeholder_ru", ru); field.set_meta("ui_placeholder_en", en)
	field.placeholder_text = _ui(ru, en)

func _join_active() -> bool:
	return str(_client_stats().get("status", "idle")) in ["live", "connecting", "joining", "preparing", "loading", "synchronizing"]

func _refresh_favorites() -> void:
	_favorite_rows = _book.list(_favorite_filter.text)
	_favorites.clear()
	var selected := false
	for record: Dictionary in _favorite_rows:
		var index := _favorites.add_item(record.name)
		_favorites.set_item_metadata(index, record.id)
		if int(record.id) == _favorite_id:
			_favorites.select(index); selected = true
	if not selected: _favorite_id = 0
	refresh()

func _select_favorite(index: int) -> void:
	if _join_active() or index < 0 or index >= _favorite_rows.size(): return
	var record := _book.get_entry(int(_favorite_rows[index].id))
	if record.is_empty(): return
	_favorite_id = int(record.id)
	_favorite_name.text = record.name
	_game_url.text = record.game_url
	_map_url.text = record.map_url
	_spectator.button_pressed = record.spectator
	_connect_error = ""
	_favorite_notice("selected")
	refresh()

func _save_favorite(update: bool) -> void:
	if _join_active() or not _book_available: return
	if update and _favorite_id == 0: return
	var record := {"name": _favorite_name.text.strip_edges(), "game_url": _game_url.text.strip_edges(), "map_url": _map_url.text.strip_edges(), "spectator": _spectator.button_pressed}
	if update: record.id = _favorite_id
	var result := _book.upsert(record)
	if not result.ok:
		_favorite_notice("full" if not update and _book.list().size() >= SERVER_BOOK.MAX_SERVERS else "invalid"); return
	_favorite_id = int(result.id)
	if not _book.save().ok:
		_favorite_notice("save")
	else:
		_favorite_notice("saved")
	_refresh_favorites()

func _delete_favorite() -> void:
	if _join_active() or not _book_available or _favorite_id == 0: return
	if not _book.remove(_favorite_id).ok: return
	_favorite_id = 0
	_favorite_notice("deleted" if _book.save().ok else "save")
	_refresh_favorites()

func _favorite_notice(kind: String) -> void:
	var messages := {
		"load": ["Не удалось прочитать список серверов.", "Saved servers could not be loaded."],
		"save": ["Не удалось сохранить список серверов.", "Saved servers could not be written."],
		"invalid": ["Проверьте имя и адреса сервера. Пароли и параметры в адресах не сохраняются.", "Check the server name and addresses. Addresses with passwords or query parameters cannot be saved."],
		"full": ["Можно сохранить до 64 серверов.", "You can save up to 64 servers."],
		"selected": ["Адреса выбраны. Откройте вкладку подключения.", "Addresses selected. Open the Connection tab."],
		"saved": ["Сервер сохранён.", "Server saved."],
		"deleted": ["Сервер удалён.", "Server deleted."]}
	var text: Array = messages.get(kind, ["", ""])
	_favorite_message.set_meta("favorite_notice", kind)
	_favorite_message.text = _ui(text[0], text[1])
	_favorite_message.add_theme_color_override("font_color", Color("ed806d") if kind in ["load", "save", "invalid", "full"] else Color("c6dedc"))
	# Refresh also re-translates the dynamic notice after a locale change.
	_favorite_message.set_meta("ui_ru", text[0]); _favorite_message.set_meta("ui_en", text[1])

func _field(placeholder: String,value: String) -> LineEdit:
	var field:=LineEdit.new()
	field.placeholder_text=placeholder
	field.text=value
	field.max_length=2048
	field.custom_minimum_size.y=36
	return field

func _label(ru: String,en: String,size: int=15) -> Label:
	return _hud.call("_ui_label",ru,en,size) as Label

func _text(node: Control,ru: String,en: String) -> void:
	node.set_meta("ui_ru",ru);node.set_meta("ui_en",en)
	node.set("text",_ui(ru,en))

func _ui(ru: String,en: String) -> String:
	return str(_hud.call("_ui",ru,en))

func _add_button(parent: Node,key: String,ru: String,en: String,callback: Callable) -> void:
	var button: Button=_hud.call("_ui_button",ru,en,callback)
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button.set_meta("network_action",key)
	parent.add_child(button)
	controls[key]=button

func _client_stats() -> Dictionary:
	if _app==null:return {}
	var client: Variant=_app.get("network_client")
	if client!=null and client.has_method("get_stats"):
		var result: Variant=client.call("get_stats")
		if result is Dictionary:return result
	return {}

func _is_live() -> bool:
	return str(_client_stats().get("status","idle"))=="live"

func _connect(resume: bool) -> void:
	if _app==null:return
	var result: Variant=_app.call("network_connect",_game_url.text.strip_edges(),_map_url.text.strip_edges(),_name_field.text.strip_edges(),_spectator.button_pressed,resume)
	_connect_error=str(result.get("error","")) if result is Dictionary and not bool(result.get("ok",false)) else ""
	refresh()

func _disconnect() -> void:
	_app.call("network_disconnect")
	_connect_error=""
	refresh()

func _process(_delta: float) -> void:
	if is_instance_valid(_hud):refresh()

func refresh() -> void:
	if _status==null or not controls.has("enter"):return
	var stats:=_client_stats()
	var state:=str(stats.get("status","idle"))
	var live:=state=="live"
	var busy:=state in ["connecting","joining","preparing","loading","synchronizing"]
	var active:=live or busy
	var valid_fields:=not _game_url.text.strip_edges().is_empty() and not _map_url.text.strip_edges().is_empty() and not _name_field.text.strip_edges().is_empty()
	controls.connect.disabled=active or not valid_fields
	controls.resume.disabled=active or not valid_fields or not (_app.has_method("network_can_resume") and bool(_app.call("network_can_resume")))
	controls.disconnect.disabled=not active
	controls.enter.disabled=not live
	for field: LineEdit in [_game_url,_map_url,_name_field]:field.editable=not active
	_spectator.disabled=active
	_team.disabled=not live
	for index in range(3):controls["weapon_%d" % index].disabled=not live
	controls.block_color.disabled=not live
	if _favorites != null:
		_favorite_filter.editable = not active
		_favorite_filter.placeholder_text = _ui("Поиск по имени", "Filter by name")
		_favorite_name.editable = not active
		for index in _favorites.item_count: _favorites.set_item_selectable(index, not active)
		var valid_favorite := not _favorite_name.text.strip_edges().is_empty() and not _game_url.text.strip_edges().is_empty() and not _map_url.text.strip_edges().is_empty()
		controls.favorite_add.disabled = active or not _book_available or not valid_favorite
		controls.favorite_update.disabled = active or not _book_available or not valid_favorite or _favorite_id == 0
		controls.favorite_delete.disabled = active or not _book_available or _favorite_id == 0
		_favorite_details.text = _ui("Список пуст.", "No saved servers.") if _book.list().is_empty() else (_ui("Совпадений нет.", "No matching servers.") if _favorite_rows.is_empty() else _ui("Найдено: %d", "Found: %d") % _favorite_rows.size())
		if _favorite_id != 0:
			var favorite := _book.get_entry(_favorite_id)
			if not favorite.is_empty():
				_favorite_details.text = "%s\n%s\n%s" % [favorite.game_url, favorite.map_url, _ui("Наблюдатель", "Spectator") if favorite.spectator else _ui("Игрок", "Player")]
	for index in range(3):_team.set_item_text(index,LabMap.team_name_for(_session,index))
	_team.select(clampi(_session.team,0,2))
	var texts: Dictionary={"idle":["Не подключено","Not connected"],"closed":["Отключено","Disconnected"],"failed":["Соединение прервано","Connection interrupted"],"connecting":["Подключение…","Connecting…"],"joining":["Вход в игру…","Joining…"],"preparing":["Подготовка матча…","Preparing match…"],"loading":["Загрузка карты…","Loading map…"],"synchronizing":["Синхронизация…","Synchronizing…"],"live":["Подключено","Connected"]}
	var caption: Array=texts.get(state,texts.idle)
	var map_stats: Dictionary=stats.get("map",{}) if stats.get("map",{}) is Dictionary else {}
	if state=="loading" and str(map_stats.get("work_phase","waiting")) in ["decode","hash","apply","apply_validate","apply_changes"]:caption=["Подготовка карты…","Preparing map…"]
	_status.text=_ui(caption[0],caption[1])
	_progress.visible=busy
	var failure:=_connect_error if not _connect_error.is_empty() else str(stats.get("error",""))
	_error.text=failure.strip_edges().substr(0,240)
	_error.visible=not _error.text.is_empty()
