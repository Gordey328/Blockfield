extends SceneTree
## godot --headless --path game --script ../tests/presentation/test_localization.gd
const Localization = preload("res://presentation/openspades_localization.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(Localization.install() == 17, "All 16 original catalogs and authored Russian lab catalog load")
	_check(Localization.install() == 17, "Installation is idempotent")
	var choices := Localization.get_languages()
	_check(choices.size() == 17, "All original selectable locale descriptions survive")
	for language in choices:
		_check(not language.label.is_empty(), "Native language name: " + language.source_id)
		_check(Localization.set_locale(language.source_id) == language.locale, "Locale normalization: " + language.source_id)
		_check(not Localization.text("Rifle", "Client").is_empty(), "Catalog lookup: " + language.source_id)
	_check(Localization.normalize_locale("pt-br") == "pt_BR", "Brazilian locale maps to Godot spelling")
	_check(Localization.normalize_locale("pt_pt") == "pt_PT", "Portuguese locale maps to Godot spelling")
	_check(Localization.normalize_locale("ru-RU") == "ru", "Region variant maps to available original catalog")
	_check(Localization.normalize_locale("xx") == "en_US", "Unknown locale falls back to English")
	Localization.set_locale("ru")
	_check(Localization.text("Rifle", "Client") == "Винтовка", "Original Russian message context is retained")
	_check(Localization.text("Language", "StartupScreen") == "Язык", "Original startup-screen catalog context is retained")
	_check(Localization.text("Map saved: {0}", "Client", ["test.vxl"]) == "Карта сохранена: test.vxl", "Original numbered substitutions are supported")
	_check(Localization.plural("{0} block", "{0} blocks", 1, "Client", [1]) == "1 блок", "Russian singular uses original gettext rules")
	_check(Localization.plural("{0} block", "{0} blocks", 2, "Client", [2]) == "2 блока", "Russian few uses original gettext rules")
	_check(Localization.plural("{0} block", "{0} blocks", 5, "Client", [5]) == "5 блоков", "Russian many uses original gettext rules")
	_check(Localization.lab("Арсенал") == "Арсенал", "Authored offline-lab Russian translation is available")
	Localization.set_locale("en_us")
	_check(Localization.text("Rifle", "Client") == "Rifle", "Original English source is the fallback")
	_check(Localization.lab("Арсенал") == "Arsenal", "Authored offline-lab source is English")
	Localization.set_locale("de")
	_check(Localization.text("Rifle", "Client") == "Gewehr", "Another original catalog resolves independently")
	_check(Localization.lab("Арсенал") == "Arsenal", "Untranslated lab strings fall back to English")
	var ui_font := Localization.get_ui_font()
	_check(ui_font != null and ui_font.fallbacks.size() == 1, "Original multilingual bitmap fallback is installed")
	for code in [0x0410, 0x4e2d, 0x65e5, 0xd55c]:
		_check(ui_font.has_char(code), "Original fallback contains Cyrillic/Chinese/Japanese/Korean glyph: %x" % code)
	_check(ui_font.get_string_size("中文 日本語 한국어", HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x > 100, "Bitmap fallback shapes multilingual text at UI sizes")
	ui_font = null
	Localization.uninstall()
	_check(not "ru" in TranslationServer.get_loaded_locales(), "Teardown removes owned translations")
	await process_frame
	print("LOCALIZATION_CHECKS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
