extends "render_audio.gd"
## Real post-limiter mixes: fixed variants, centered spatial sources, no settings.

func _run() -> void:
	var driver: String = AudioServer.get_driver_name()
	output = ProjectSettings.globalize_path("res://../.cache/previews/grenade-feedback").path_join(driver.to_lower())
	DirAccess.make_dir_recursive_absolute(output)
	master_was_muted = AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0,true)
	AudioServer.add_bus()
	bus_index = AudioServer.get_bus_count()-1
	AudioServer.set_bus_name(bus_index,BUS)
	AudioServer.set_bus_send(bus_index,"Master")
	capture = AudioEffectCapture.new()
	capture.buffer_length = 3.0
	AudioServer.add_bus_effect(bus_index,capture)
	AudioServer.set_bus_mute(bus_index,true)
	host = Node3D.new()
	root.add_child(host)
	var camera: Camera3D = Camera3D.new()
	host.add_child(camera)
	camera.current = true
	root.audio_listener_enable_3d = true
	audio = AUDIO.new()
	host.add_child(audio)
	audio.setup(null,camera)
	audio.set_output_bus(BUS)
	await create_timer(.15).timeout
	var ratios: Array[Dictionary] = []
	for water: bool in [false,true]:
		var energies: Array[float] = []
		for distance: float in [5.0,32.0,80.0]:
			var name: String = ("water" if water else "land")+"_"+str(int(distance))
			var result: Dictionary = await record(name,func():
				audio._random.seed = 328
				audio.explosion(Vector3(0,0,-distance),water),3.0)
			energies.append(float(result.energy))
		check(energies[1]<energies[0]*.16,"32-unit mixed blast is below40% of close RMS")
		check(energies[2]<energies[1]*.16,"80-unit mixed blast continues to decrease")
		check(energies[2]<energies[0]*.01,"80-unit mixed blast is below10% of close RMS")
		ratios.append({"water":water,"rms_32_over_5":sqrt(energies[1]/energies[0]),"rms_80_over_5":sqrt(energies[2]/energies[0])})
	var report: Dictionary = {"engine":Engine.get_version_info().string,"driver":driver,"checks":checks,"failures":failures,"ratios":ratios,"results":results,"browser_listening_verified":false}
	var file: FileAccess = FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	check(file!=null,"mixed grenade report saves")
	if file!=null:
		report.checks = checks
		report.failures = failures
		file.store_string(JSON.stringify(report,"\t"))
		file.close()
	print("GRENADE_MIX_RATIOS: "+JSON.stringify(ratios))
	await finish()
