class_name LabChat
extends Control
## ChatSayWindow.as/FieldWithHistory.as: shared history and a retained draft.
## ChatWindow.cpp: compact messages expire after 15s; expanded history scrolls.
signal submitted(message: String, team_channel: bool)
signal closed
const HISTORY_LIMIT:=200
var team_channel:=false
var expanded:=false
var is_open:=false
var messages: Array[Dictionary]=[]
var input_history: Array[Dictionary]=[]
var _clock:=0.0
var _draft: Dictionary={"text":"","caret":0}
var _history_index:=0
var _log: RichTextLabel
var _entry: LineEdit
var _channel: Button
var _box: PanelContainer
var _last_update:=-1.0

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	_log=RichTextLabel.new()
	_log.bbcode_enabled=false
	_log.scroll_following=true
	_log.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_log.add_theme_font_size_override("normal_font_size",15)
	add_child(_log)
	_box=PanelContainer.new()
	_box.visible=false
	var row:=HBoxContainer.new()
	_box.add_child(row)
	_channel=Button.new()
	_channel.pressed.connect(func():set_channel(not team_channel))
	row.add_child(_channel)
	_entry=LineEdit.new()
	_entry.max_length=160
	_entry.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_entry.text_submitted.connect(_submit)
	row.add_child(_entry)
	var send:=Button.new()
	send.text=OpenSpadesLocalization.text("Say","Client")
	send.pressed.connect(func():_submit(_entry.text))
	row.add_child(send)
	var cancel:=Button.new()
	cancel.text=OpenSpadesLocalization.text("Cancel","Client")
	cancel.pressed.connect(cancel_input)
	row.add_child(cancel)
	add_child(_box)
	set_channel(false)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	if _log==null:return
	_log.position=Vector2.ZERO
	_log.size=Vector2(size.x,maxf(100,size.y-42))
	_box.position=Vector2(0,size.y-38)
	_box.size=Vector2(size.x,38)

func set_channel(team_only: bool) -> void:
	team_channel=team_only
	if _channel!=null:_channel.text=OpenSpadesLocalization.text("Team" if team_only else "Global","Client")

func open(team_only: bool=false) -> void:
	set_channel(team_only)
	is_open=true
	_box.show()
	_history_index=input_history.size()
	_entry.text=str(_draft.text)
	_entry.caret_column=int(_draft.caret)
	_entry.grab_focus()
	set_expanded(true)

func cancel_input() -> void:
	_draft={"text":_entry.text,"caret":_entry.caret_column}
	_close()

func _close() -> void:
	is_open=false
	_box.hide()
	_entry.release_focus()
	set_expanded(false)
	closed.emit()

func _submit(message: String) -> void:
	if message.strip_edges().is_empty():cancel_input();return
	input_history.append({"text":message,"caret":message.length()})
	if input_history.size()>HISTORY_LIMIT:input_history.pop_front()
	_draft={"text":"","caret":0}
	submitted.emit(message.left(160),team_channel)
	_entry.text=""
	_close()

func set_expanded(enabled: bool) -> void:
	expanded=enabled
	_log.scroll_active=enabled
	_log.mouse_filter=Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	_render_log()

func receive(message: String, author: String, team_only: bool=false, author_team: int=2) -> void:
	messages.append({"text":message.left(512),"author":author.left(32),"team_channel":team_only,"team":author_team,"time":_clock})
	if messages.size()>HISTORY_LIMIT:messages.pop_front()
	_render_log()

func get_input_text() -> String:return _entry.text
func set_input_text(text: String) -> void:_entry.text=text;_entry.caret_column=text.length()
func get_log_text() -> String:return _log.get_parsed_text()

func handle_input(event: InputEvent) -> bool:
	if not is_open:return false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:cancel_input();return true
		if event.keycode==KEY_UP:_navigate_history(-1);return true
		if event.keycode==KEY_DOWN:_navigate_history(1);return true
		if event.keycode==KEY_TAB:set_channel(not team_channel);return true
		if event.keycode in [KEY_ENTER,KEY_KP_ENTER]:_submit(_entry.text);return true
	return false

func _navigate_history(direction: int) -> void:
	if _history_index==input_history.size():_draft={"text":_entry.text,"caret":_entry.caret_column}
	elif _history_index>=0:input_history[_history_index]={"text":_entry.text,"caret":_entry.caret_column}
	_history_index=clampi(_history_index+direction,0,input_history.size())
	var item: Dictionary=_draft if _history_index==input_history.size() else input_history[_history_index]
	_entry.text=str(item.text)
	_entry.caret_column=int(item.caret)

func _process(delta: float) -> void:
	_clock+=delta
	if not expanded and _clock-_last_update>.25:_last_update=_clock;_render_log()

func _render_log() -> void:
	if _log==null:return
	var scrollbar:=_log.get_v_scroll_bar()
	var scroll_position:=scrollbar.value
	var at_end:=scrollbar.value>=scrollbar.max_value-scrollbar.page-1
	_log.scroll_following=at_end or not expanded
	_log.clear()
	for message in messages:
		var age:=_clock-float(message.time)
		if not expanded and age>15:continue
		var color:=Color("66a7d6") if int(message.team)==0 else (Color("98b678") if int(message.team)==1 else Color.WHITE)
		if not expanded:color.a=clampf(15-age,0,1)
		_log.push_color(color)
		_log.add_text(("[T] " if bool(message.team_channel) else "[G] ")+str(message.author)+": ")
		_log.pop()
		_log.push_color(Color(1,1,1,color.a))
		_log.add_text(str(message.text)+"\n")
		_log.pop()
	if expanded and not at_end:scrollbar.set_deferred("value",scroll_position)
