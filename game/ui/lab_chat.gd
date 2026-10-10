class_name LabChat
extends Control
## ChatSayWindow.as/FieldWithHistory.as: shared history and a retained draft.
## ChatWindow.cpp: compact messages expire after 15s; expanded history scrolls.
signal submitted(message: String, team_channel: bool)
signal closed
const HISTORY_LIMIT:=200
var team_channel:=false
var session: LocalSession
var expanded:=false
var is_open:=false
var messages: Array[Dictionary]=[]
var input_history: Array[Dictionary]=[]
var completion_callable: Callable
var completion_suggestions: Array[String] = []
var _clock:=0.0
var _draft: Dictionary={"text":"","caret":0}
var _history_index:=0
var _log: RichTextLabel
var _entry: LineEdit
var _channel: Button
var _box: PanelContainer
var _last_update:=-1.0
var _completion_hint: Label

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
	_entry.text_changed.connect(func(_text: String) -> void: _clear_completion())
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
	_completion_hint=Label.new()
	_completion_hint.add_theme_font_size_override("font_size",13)
	_completion_hint.modulate=Color(.8,.88,.9)
	_completion_hint.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_completion_hint.hide()
	add_child(_completion_hint)
	set_channel(false)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	if _log==null:return
	_log.position=Vector2.ZERO
	_log.size=Vector2(size.x,maxf(100,size.y-42))
	_box.position=Vector2(0,size.y-38)
	_box.size=Vector2(size.x,38)
	_completion_hint.position=Vector2(0,size.y-78)
	_completion_hint.size=Vector2(size.x,36)

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
	_clear_completion()
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
func set_input_text(text: String, caret: int = -1) -> void:
	_entry.text=text
	_entry.caret_column=text.length() if caret < 0 else clampi(caret,0,text.length())
func get_log_text() -> String:return _log.get_parsed_text()

func refresh_team_metadata() -> void:
	if _log != null: _render_log()

func handle_input(event: InputEvent) -> bool:
	if not is_open:return false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:cancel_input();return true
		if event.keycode==KEY_UP:_navigate_history(-1);return true
		if event.keycode==KEY_DOWN:_navigate_history(1);return true
		if event.keycode==KEY_TAB:
			if _entry.text.begins_with("/"): _complete_command()
			else: set_channel(not team_channel)
			return true
		if event.keycode in [KEY_ENTER,KEY_KP_ENTER]:_submit(_entry.text);return true
	return false

func _clear_completion() -> void:
	completion_suggestions.clear()
	if _completion_hint!=null:_completion_hint.hide()

func _complete_command() -> void:
	# ChatSayWindow.as:119–159 extends the case-insensitive common prefix only
	# at the end of an unselected command; chat's ordinary Tab keeps its channel.
	_clear_completion()
	if not completion_callable.is_valid() or _entry.has_selection() or _entry.caret_column != _entry.text.length(): return
	var candidates: Variant=completion_callable.call(_entry.text)
	if not candidates is Array:return
	for candidate: Variant in candidates:
		if completion_suggestions.size()>=32:break
		if candidate is String:
			completion_suggestions.append(str(candidate).left(160))
	if completion_suggestions.is_empty():return
	var common: String=completion_suggestions[0]
	for candidate: String in completion_suggestions:
		var length: int=0
		while length<mini(common.length(),candidate.length()) and common[length].to_lower()==candidate[length].to_lower():length+=1
		common=common.left(length)
	if common.length()>_entry.text.length():
		# Programmatic assignment does not emit text_changed, so suggestions
		# remain available for the visible ambiguity hint below.
		_entry.text=common
		_entry.caret_column=common.length()
	_completion_hint.text="   ".join(completion_suggestions.slice(0,8))
	_completion_hint.visible=completion_suggestions.size()>1

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
		var color := LabMap.team_color_for(session,int(message.team)) if int(message.team)<2 else Color.WHITE
		if not expanded:color.a=clampf(15-age,0,1)
		_log.push_color(color)
		_log.add_text(("[T] " if bool(message.team_channel) else "[G] ")+str(message.author)+": ")
		_log.pop()
		_log.push_color(Color(1,1,1,color.a))
		_log.add_text(str(message.text)+"\n")
		_log.pop()
	if expanded and not at_end:scrollbar.set_deferred("value",scroll_position)
