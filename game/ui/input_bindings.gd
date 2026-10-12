class_name LabInputBindings
extends RefCounted
## Preferences.as: binding a used key clears the other action; Delete unbinds.
## Only physical keyboard keys and mouse buttons are persisted by this client.

const ACTIONS: Array[String] = ["forward", "back", "left", "right", "jump", "crouch", "sprint", "sneak", "primary", "secondary", "reload", "last_tool", "tool_spade", "tool_block", "tool_weapon", "tool_grenade", "eyedropper", "palette_left", "palette_right", "palette_up", "palette_down", "view_toggle", "map", "map_scale", "scoreboard", "pause", "chat", "chat_team", "chat_log", "hide_hud", "stats", "screenshot", "sceneshot", "save_map", "flashlight", "autofocus", "arsenal", "arsenal_bomb", "arsenal_strat_one", "arsenal_strat_two"]
static var _defaults: Dictionary = {}

static func capture_defaults() -> void:
	if not _defaults.is_empty():return
	for action in ACTIONS:
		if InputMap.has_action(action):_defaults[action]=InputMap.action_get_events(action).duplicate()

static func encode_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		return {"type":"key", "code":int(event.physical_keycode if event.physical_keycode else event.keycode), "physical":event.physical_keycode!=0, "shift":event.shift_pressed, "ctrl":event.ctrl_pressed, "alt":event.alt_pressed, "meta":event.meta_pressed}
	if event is InputEventMouseButton:
		return {"type":"mouse", "button":int(event.button_index)}
	return {}

static func decode_event(data: Dictionary) -> InputEvent:
	if data.get("type","")=="key" and int(data.get("code",0))>0:
		var key:=InputEventKey.new()
		if bool(data.get("physical",true)):key.physical_keycode=int(data.code)
		else:key.keycode=int(data.code)
		key.shift_pressed=bool(data.get("shift",false))
		key.ctrl_pressed=bool(data.get("ctrl",false))
		key.alt_pressed=bool(data.get("alt",false))
		key.meta_pressed=bool(data.get("meta",false))
		return key
	if data.get("type","")=="mouse" and int(data.get("button",0)) in range(1,10):
		var mouse:=InputEventMouseButton.new()
		mouse.button_index=int(data.button)
		return mouse
	return null

static func same_binding(a: InputEvent, b: InputEvent) -> bool:
	return encode_event(a)==encode_event(b)

static func bind_action(action: String, event: InputEvent) -> void:
	if action not in ACTIONS:return
	capture_defaults()
	if not InputMap.has_action(action):InputMap.add_action(action)
	if event!=null:
		for other in ACTIONS:
			if other==action or not InputMap.has_action(other):continue
			for existing in InputMap.action_get_events(other):
				if same_binding(existing,event):InputMap.action_erase_event(other,existing)
	InputMap.action_erase_events(action)
	if event!=null and not encode_event(event).is_empty():InputMap.action_add_event(action,event)

static func binding_label(action: String) -> String:
	if not InputMap.has_action(action):return "—"
	var labels:=PackedStringArray()
	for event in InputMap.action_get_events(action):labels.append(event.as_text())
	return " / ".join(labels) if not labels.is_empty() else "—"

static func load_bindings(path: String="user://settings.cfg") -> void:
	capture_defaults()
	var config:=ConfigFile.new()
	if config.load(path)!=OK:return
	for action in ACTIONS:
		if not config.has_section_key("controls",action):continue
		var encoded: Variant=config.get_value("controls",action,[])
		if not encoded is Array:continue
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action)
		for entry in encoded:
			if not entry is Dictionary:continue
			var event:=decode_event(entry)
			if event!=null:InputMap.action_add_event(action,event)

static func save_bindings(path: String="user://settings.cfg") -> Error:
	var config:=ConfigFile.new()
	config.load(path)
	for action in ACTIONS:
		var events: Array[Dictionary]=[]
		if InputMap.has_action(action):
			for event in InputMap.action_get_events(action):
				var encoded:=encode_event(event)
				if not encoded.is_empty():events.append(encoded)
		config.set_value("controls",action,events)
	return config.save(path)

static func reset_defaults() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):continue
		InputMap.action_erase_events(action)
		for event in _defaults.get(action,[]):InputMap.action_add_event(action,event)

static func release_actions() -> void:
	for action in ACTIONS:
		if InputMap.has_action(action):Input.action_release(action)
