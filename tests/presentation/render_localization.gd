extends SceneTree
## Native GPU preview of the original multilingual bitmap fallback.
const Localization = preload("res://presentation/openspades_localization.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var output := OS.get_cache_dir().path_join("blockfield-localization-preview")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1100, 640)
	var panel := ColorRect.new()
	panel.color = Color(0.08, 0.13, 0.17)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var theme := Theme.new()
	theme.default_font = Localization.get_ui_font()
	panel.theme = theme
	root.add_child(panel)
	var column := VBoxContainer.new()
	column.position = Vector2(50, 35)
	column.add_theme_constant_override("separation", 13)
	panel.add_child(column)
	var heading := Label.new()
	heading.text = "ORIGINAL GNU UNIFONT FALLBACK — CATALOG LANGUAGE NAMES"
	heading.add_theme_font_size_override("font_size", 26)
	column.add_child(heading)
	var languages := GridContainer.new()
	languages.columns = 2
	languages.add_theme_constant_override("h_separation", 70)
	languages.add_theme_constant_override("v_separation", 18)
	column.add_child(languages)
	for language in Localization.get_languages():
		var label := Label.new()
		label.text = "%s   /   %s" % [language.english, language.label]
		label.add_theme_font_size_override("font_size", 18)
		languages.add_child(label)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("languages.png"))
	panel.queue_free()
	Localization.uninstall()
	await process_frame
	await process_frame
	print("LOCALIZATION_GPU_PREVIEW: " + output)
	quit()
