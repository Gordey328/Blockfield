class_name LabConsole
extends RefCounted
## Native chat cvars, explicitly mapped to this project's settings. No script
## evaluation, process execution or arbitrary object/property access.

enum ValueKind { BOOLEAN, INTEGER, DECIMAL }
const MAX_COMMAND_LENGTH: int = 160
const MAX_SUGGESTIONS: int = 32
const MOUSE_UNIT: float = 0.003 # Client_Input.cpp:197.
const LOCAL_COMMANDS: Array[String] = ["help", "restock", "reset", "mode", "team", "get", "set", "cvars"]
const UNSUPPORTED: Dictionary[String, String] = {
	"cg_smp": "native worker scheduling is replaced by Godot",
	"cg_unicode": "Unicode is always enabled in the port",
	"cg_serveralert": "server alerts require iteration 2 transport",
	"cg_skipdeadplayerswhendead": "the offline camera uses the port's follow policy",
	"cg_debughittest": "native hit-test debugger is not available",
	"cg_debugcorpse": "native debug-only corpse command is not available",
	"cg_screenshotformat": "the browser exports PNG screenshots",
	"r_blitframebuffer": "native OpenGL framebuffer controls are not available",
	"r_shadowmapsize": "Godot manages shadow-map allocation",
	"r_maxanisotropy": "native texture sampler controls are not available",
	"r_occlusionquery": "native OpenGL occlusion queries are not available",
	"r_swundersampling": "the native software renderer is not available",
	"r_swnumthreads": "the native software renderer is not available",
	"s_aldriver": "Godot owns the audio backend",
	"s_ysrdriver": "Godot owns the audio backend",
	"s_maxpolyphonics": "the port has a fixed bounded voice pool",
}

class Variable extends RefCounted:
	var name: String
	var scope: String
	var key: String
	var kind: ValueKind
	var default_value: Variant
	var minimum: float
	var maximum: float
	var choices: Array[int] = []
	var scale: float = 1.0
	var component: int = -1
	var note: String = ""

var _app: Node
var _variables: Dictionary[String, Variable] = {}

func _init() -> void:
	# Client_Input.cpp:44–49,83; Preferences.as:664–686.
	_register("cg_fov", "player", "base_fov", ValueKind.DECIMAL, 68.0, 45, 90)
	_register("cg_mouseSensitivity", "player", "sensitivity", ValueKind.DECIMAL, 1.0, .1, 10, MOUSE_UNIT)
	_register("cg_zoomedMouseSensScale", "player", "ads_sensitivity", ValueKind.DECIMAL, 1.0, .05, 3)
	_register("cg_mouseExpPower", "player", "mouse_exponent", ValueKind.DECIMAL, 1.0, .5, 4)
	_register("cg_invertMouseY", "player", "invert_mouse", ValueKind.BOOLEAN, false)
	_register("cg_holdAimDownSight", "player", "hold_aim_down_sight", ValueKind.BOOLEAN, false)
	_register("cg_switchToolByWheel", "player", "wheel_tool_direction", ValueKind.INTEGER, 1, -1, 1)
	_register("cg_thirdperson", "player", "third_person", ValueKind.BOOLEAN, false)
	# ClientPlayer.cpp:50–55; Client.cpp:58; Client_Update.cpp:51–54.
	_register("cg_animations", "player", "animations_enabled", ValueKind.BOOLEAN, true)
	_register("cg_ejectBrass", "player", "eject_brass", ValueKind.BOOLEAN, true)
	_register("cg_chatBeep", "app", "chat_beep", ValueKind.BOOLEAN, true)
	_register("cg_hitFeedbackSoundGain", "app", "hit_feedback_gain", ValueKind.DECIMAL, .2, 0, 1)
	_register("cg_environmentalAudio", "app", "environmental_audio", ValueKind.BOOLEAN, true)
	for axis: int in 3:
		var item := _register("cg_viewWeapon" + "XYZ"[axis], "player", "view_weapon_offset", ValueKind.DECIMAL, 0.0, -1, 1)
		item.component = axis
		item.note = "native skin axes; port bounds -1..1"
	_register("cg_autoFocusSpeed", "focus", "speed", ValueKind.DECIMAL, .4, 0, 3)
	_register("cg_manualFocus", "graphics", "manual_focus", ValueKind.BOOLEAN, false)
	_register("cg_depthOfFieldAmount", "graphics", "dof_strength", ValueKind.DECIMAL, 1.0, 0, 2)
	_register("cg_particles", "graphics", "particles", ValueKind.INTEGER, 2, 0, 2)
	_register("cg_shake", "graphics", "shake", ValueKind.INTEGER, 1, 0, 2)
	_register("cg_blood", "graphics", "blood", ValueKind.BOOLEAN, true)
	_register("cg_ragdoll", "graphics", "ragdolls", ValueKind.BOOLEAN, true)
	# GLSettings.cpp:23–66; these use the documented Compatibility replacements.
	for pair: Array in [["r_bloom","bloom",true], ["r_cameraBlur","camera_blur",true], ["r_colorCorrection","color_correction",true], ["r_depthOfField","dof",false], ["r_fxaa","fxaa",true], ["r_lens","lens",true], ["r_lensFlare","lens_flare",true], ["r_modelShadows","shadows",true], ["r_physicalLighting","lighting",false], ["r_radiosity","gi",false], ["r_ssao","ssao",false]]:
		_register(str(pair[0]), "graphics", str(pair[1]), ValueKind.BOOLEAN, bool(pair[2]))
	_register("r_saturation", "graphics", "saturation", ValueKind.DECIMAL, 1.0, 0, 2)
	_register("r_exposureValue", "graphics", "exposure", ValueKind.DECIMAL, 0.0, -4, 4)
	_register("r_hdr", "graphics", "hdr", ValueKind.BOOLEAN, false)
	_register("r_hdrAutoExposureMin", "graphics", "hdr_min_ev", ValueKind.DECIMAL, -1.5, -10, 10)
	_register("r_hdrAutoExposureMax", "graphics", "hdr_max_ev", ValueKind.DECIMAL, .5, -10, 10)
	_register("r_hdrAutoExposureSpeed", "graphics", "hdr_speed", ValueKind.DECIMAL, 1.0, 0, 5)
	_register("r_multisamples", "graphics", "msaa", ValueKind.INTEGER, 0, 0, 4).choices.assign([0, 2, 4])
	_register("r_water", "water", "water", ValueKind.INTEGER, 2, 0, 3).note = "0 off; 1 surface; 2 reflection; 3 reflection/refraction"
	_register("s_gain", "app", "source_audio_gain", ValueKind.DECIMAL, 1.0, 0, 4)
	_register("s_eax", "app", "source_audio_efx", ValueKind.BOOLEAN, true)
	_register("bf_positionalAudio", "app", "positional_audio", ValueKind.BOOLEAN, true).note = "port setting"
	# Client_Draw.cpp:63,71–73; MapView.cpp:36–38.
	for pair: Array in [["cg_hideHud","hide_hud",false], ["cg_stats","statistics",false], ["cg_hitIndicator","hit_indicator",true], ["cg_alerts","alerts",true], ["cg_minimapPlayerColor","minimap_player_colors",true], ["cg_minimapPlayerIcon","minimap_weapon_icons",true]]:
		_register(str(pair[0]), "hud", str(pair[1]), ValueKind.BOOLEAN, bool(pair[2]))
	_register("cg_minimapSize", "hud", "minimap_size", ValueKind.INTEGER, 128, 128, 256).note = "port UI bounds 128..256"
	_register("cg_playerNames", "hud", "player_names", ValueKind.INTEGER, 2, 0, 2)

func _register(name: String, scope: String, key: String, kind: ValueKind, default_value: Variant, minimum: float = 0, maximum: float = 1, scale: float = 1) -> Variable:
	var item := Variable.new()
	item.name = name
	item.scope = scope
	item.key = key
	item.kind = kind
	item.default_value = default_value
	item.minimum = minimum
	item.maximum = maximum
	item.scale = scale
	_variables[name.to_lower()] = item
	return item

func setup(app: Node) -> void:
	_app = app

func list_variables() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var names: Array[String] = _variables.keys()
	names.sort()
	for name: String in names:
		var item: Variable = _variables[name]
		entries.append({"name":item.name, "type":ValueKind.keys()[item.kind].to_lower(), "default":item.default_value,
			"minimum":item.minimum, "maximum":item.maximum, "choices":item.choices.duplicate(), "mapping":item.scope + "." + item.key,
			"status":"mapped", "note":item.note, "value":_read(item)})
	return entries

func execute(text: String) -> Dictionary:
	if not text.begins_with("/"): return _result(false)
	if text.length() > MAX_COMMAND_LENGTH: return _result(true, "Command exceeds 160 characters.")
	for index: int in text.length():
		if text.unicode_at(index) < 32: return _result(true, "Control characters are not accepted in commands.")
	var parts: PackedStringArray = text.substr(1).split(" ", false)
	if parts.is_empty() or text.begins_with("/ "): return _result(true, "Use /help for local commands.")
	if parts.size() > 3: return _result(true, "Too many command arguments.")
	var name: String = parts[0].to_lower()
	if name == "help": return _result(true, "/help /restock /reset /mode sandbox|ctf|tc /team blue|green|spectator; /cvars [prefix], /get name, /set name value, /reset name|all; /cg_fov [value]")
	if name == "cvars":
		if parts.size() > 2: return _result(true, "Usage: /cvars [prefix]")
		var prefix: String = parts[1] if parts.size() == 2 else ""
		var suggestions: Array[String] = completion("/" + prefix)
		return _result(true, "Supported variables: " + ", ".join(suggestions.slice(0,8)) + ("; narrow with /cvars prefix" if suggestions.size() > 8 else ""))
	if name in ["get", "set"]:
		if parts.size() != (2 if name == "get" else 3): return _result(true, "Usage: /%s name%s" % [name, " value" if name == "set" else ""])
		return _variable_command(parts[1], parts[2] if name == "set" else "", name == "set")
	if name == "reset" and parts.size() == 2:
		if parts[1].to_lower() == "all": return _reset_all()
		return _variable_command(parts[1], "", false, true)
	if name in ["restock", "reset", "mode", "team"]: return _local_command(name, parts)
	if parts.size() > 2: return _result(true, "Usage: /name [value]")
	return _variable_command(name, parts[1] if parts.size() == 2 else "", parts.size() == 2)

func _variable_command(name: String, raw: String, setting: bool, resetting: bool = false) -> Dictionary:
	var lower: String = name.to_lower()
	if not _variables.has(lower):
		var reason: String = str(UNSUPPORTED.get(lower, ""))
		if lower.begins_with("cg_key"): reason = "use the project's Controls menu for saved input bindings"
		return _result(true, "Unsupported %s: %s." % [name, reason] if not reason.is_empty() else "Unknown local command or variable: " + name)
	var item: Variable = _variables[lower]
	var old_value: Variant = _read(item)
	if old_value == null: return _result(true, "Unavailable setting: " + item.name)
	if not setting and not resetting: return _result(true, "%s = %s (default %s; %s)" % [item.name, _format(old_value), _format(item.default_value), _bounds(item)])
	var parsed: Dictionary = {"valid":true, "value":item.default_value} if resetting else _parse(item, raw)
	if not bool(parsed.valid): return _result(true, "Invalid %s value; expected %s." % [item.name, _bounds(item)])
	var value: Variant = parsed.value
	if old_value == value: return _result(true, "%s = %s" % [item.name, _format(value)])
	if not _write(item, value): return _result(true, "Unable to apply: " + item.name)
	return _result(true, "%s = %s" % [item.name, _format(_read(item))], true)

func _parse(item: Variable, raw: String) -> Dictionary:
	var value: Variant
	match item.kind:
		ValueKind.BOOLEAN:
			var lower: String = raw.to_lower()
			if lower not in ["0","1","false","true","off","on"]: return {"valid":false}
			value = lower in ["1","true","on"]
		ValueKind.INTEGER:
			if not raw.is_valid_int(): return {"valid":false}
			value = raw.to_int()
		ValueKind.DECIMAL:
			if not raw.is_valid_float(): return {"valid":false}
			# String.to_float reports extreme exponents to the engine log before
			# returning a nonfinite value. Reject those literals before conversion.
			var exponent_index: int = maxi(raw.find("e"), raw.find("E"))
			if exponent_index >= 0:
				var exponent: String = raw.substr(exponent_index + 1)
				if exponent.length() > 4 or not exponent.is_valid_int() or absi(exponent.to_int()) > 308: return {"valid":false}
			value = raw.to_float()
	if not is_finite(float(value)) or float(value) < item.minimum or float(value) > item.maximum: return {"valid":false}
	if not item.choices.is_empty() and int(value) not in item.choices: return {"valid":false}
	return {"valid":true, "value":value}

func _target(item: Variable) -> Object:
	if not is_instance_valid(_app): return null
	match item.scope:
		"player": return _app.get("player") as Object
		"focus": return _app.get("focus_control") as Object
		"hud": return _app.get("hud") as Object
	return _app

func _has_property(target: Object, key: String) -> bool:
	if not is_instance_valid(target): return false
	for property: Dictionary in target.get_property_list():
		if str(property.name) == key: return true
	return false

func _read(item: Variable) -> Variant:
	if not is_instance_valid(_app): return null
	if item.scope in ["graphics", "water"]:
		if not _app.has_method("get_graphics_options"): return null
		var options: Dictionary = _app.call("get_graphics_options")
		if item.scope == "water":
			if not bool(options.get("water", false)): return 0
			return 3 if bool(options.get("water_reflections", false)) and bool(options.get("water_refraction", false)) else (2 if bool(options.get("water_reflections", false)) else 1)
		return options.get(item.key)
	if item.scope == "audio": return AudioServer.get_bus_volume_linear(0)
	var target: Object = _target(item)
	if item.scope == "hud": return target.call("get_console_setting", item.key) if is_instance_valid(target) and target.has_method("get_console_setting") else null
	if not _has_property(target, item.key): return null
	var value: Variant = target.get(item.key)
	if item.component >= 0:
		var offset: Vector3 = value
		return float(offset[item.component])
	return float(value) / item.scale if item.scale != 1.0 else value

func _write(item: Variable, value: Variant) -> bool:
	if not is_instance_valid(_app): return false
	if item.scope in ["graphics", "water"]:
		if not _app.has_method("set_graphics_option"): return false
		if item.scope == "water":
			_app.call("set_graphics_option", "water", int(value) > 0)
			_app.call("set_graphics_option", "water_reflections", int(value) >= 2)
			_app.call("set_graphics_option", "water_refraction", int(value) >= 3)
		else: _app.call("set_graphics_option", item.key, value)
		return _read(item) == value
	if item.scope == "audio": AudioServer.set_bus_volume_linear(0, float(value))
	else:
		var target: Object = _target(item)
		if item.scope == "hud": return bool(target.call("set_console_setting", item.key, value))
		if not _has_property(target, item.key): return false
		if item.component >= 0:
			var offset: Vector3 = target.get(item.key)
			offset[item.component] = float(value)
			target.set(item.key, offset)
		else: target.set(item.key, float(value) * item.scale if item.scale != 1.0 else value)
	if _app.has_method("save_settings"): _app.call("save_settings")
	return true

func _local_command(name: String, parts: PackedStringArray) -> Dictionary:
	if not is_instance_valid(_app): return _result(true, "Local session is unavailable.")
	var session: LocalSession = _app.get("session") as LocalSession
	if session == null: return _result(true, "Local session is unavailable.")
	match name:
		"restock":
			if parts.size() != 1: return _result(true, "Usage: /restock")
			session.restock()
		"reset":
			if parts.size() != 1: return _result(true, "Usage: /reset [name|all]")
			if not _app.has_method("reset_lab"): return _result(true, "Lab reset is unavailable.")
			_app.call("reset_lab")
		"mode":
			if parts.size() != 2 or parts[1].to_lower() not in ["sandbox","ctf","tc"]: return _result(true, "Usage: /mode sandbox|ctf|tc")
			session.set_mode(parts[1].to_lower())
		"team":
			var teams: Array[String] = ["blue", "green", "spectator"]
			if parts.size() != 2 or parts[1].to_lower() not in teams: return _result(true, "Usage: /team blue|green|spectator")
			session.select_team(teams.find(parts[1].to_lower()))
	return _result(true, "", true)

func _reset_all() -> Dictionary:
	var changed: bool = false
	var unavailable: int = 0
	for item: Variable in _variables.values():
		var result: Dictionary = _variable_command(item.name, "", false, true)
		changed = changed or bool(result.changed)
		if str(result.message).begins_with("Unavailable") or str(result.message).begins_with("Unable"): unavailable += 1
	return _result(true, "Supported settings reset to native defaults (%d unavailable)." % unavailable, changed)

func completion(prefix: String) -> Array[String]:
	var results: Array[String] = []
	if not prefix.begins_with("/") or prefix.length() > MAX_COMMAND_LENGTH: return results
	var parts: PackedStringArray = prefix.substr(1).split(" ", false)
	var stem: String = "/"
	var needle: String = prefix.substr(1).to_lower()
	var include_commands: bool = true
	if prefix.contains(" "):
		if parts.is_empty() or parts[0].to_lower() not in ["get", "set", "reset"] or parts.size() > 2: return results
		stem = "/" + parts[0].to_lower() + " "
		needle = parts[1].to_lower() if parts.size() == 2 else ""
		include_commands = false
	for item: Variable in _variables.values():
		if item.name.to_lower().begins_with(needle): results.append(stem + item.name)
	if include_commands:
		for name: String in LOCAL_COMMANDS:
			if name.begins_with(needle): results.append("/" + name)
	results.sort()
	return results.slice(0, MAX_SUGGESTIONS)

func _bounds(item: Variable) -> String:
	if item.kind == ValueKind.BOOLEAN: return "0|1|true|false|on|off"
	if not item.choices.is_empty(): return str(item.choices)
	return "%s %s..%s" % ["integer" if item.kind == ValueKind.INTEGER else "number", item.minimum, item.maximum]

func _format(value: Variant) -> String:
	if typeof(value) == TYPE_BOOL: return "1" if bool(value) else "0"
	return str(value)

func _result(handled: bool, message: String = "", changed: bool = false) -> Dictionary:
	return {"handled":handled, "message":message, "changed":changed}
