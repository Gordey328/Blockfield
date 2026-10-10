# Local configuration console

`game/ui/lab_console.gd` owns an explicit typed setting registry. The chat accepts native-style `/cg_fov 68` commands, queries with `/cg_fov` or `/get cg_fov`, assignments with `/set cg_fov 68`, and native-default resets with `/reset cg_fov` or `/reset all`. `/cvars [prefix]` lists up to eight matching entries; `list_variables()` returns every supported name, current value, default, bounds, choices, mapping and note for callers.

Existing `/help`, `/restock`, `/reset`, `/mode sandbox|ctf|tc` and `/team blue|green|spectator` lab commands remain available. A bare `/reset` resets the lab; `/reset all` resets settings. Team arguments are stable lab aliases even when displayed team names change. Ordinary messages return `handled=false` and retain the existing local channel/history behavior.

The integration contract is `LabConsole.setup(app: Node)`, `execute(text: String) -> Dictionary{handled,message,changed}`, and `completion(prefix: String) -> Array[String]`. Main owns the instance and passes its completion callable to `LabChat`. HUD routes submitted commands through `execute` and displays a nonempty result message locally. These are project settings; the registry provides no general object-property access, script evaluator, operating-system commands or remote command execution.

## Native evidence and mappings

The reference is OpenSpades v0.1.3, commit `dcf449c845d509bbde9d79239b32d201c1389961`. `Resources/Scripts/Gui/Client/ChatSayWindow.as:81–159,268–292` supplies case-insensitive cvar matching and common-prefix Tab completion. Reading a value as a submitted command, named/all reset commands and bounded validation are additions for the offline port. Native chat accepts a configuration string directly; this port accepts only registered typed values.

| Names | Destination / accepted values | Reset values and limits |
| --- | --- | --- |
| `cg_fov` | `player.base_fov`, degrees | Native default 68; 45..90, from `Client_Scene.cpp:43,151–158` and `Preferences.as:664` |
| `cg_mouseSensitivity` | `player.sensitivity = value * 0.003` | Native default 1; native Preferences range 0.1..10. The `.003` coefficient is `Client_Input.cpp:197`; query reverses this conversion. Initial port preferences may differ. |
| `cg_zoomedMouseSensScale` | `player.ads_sensitivity` | Default 1; native Preferences 0.05..3 |
| `cg_mouseExpPower` | `player.mouse_exponent` | Default 1; port bounds 0.5..4 |
| `cg_invertMouseY`, `cg_holdAimDownSight` | Controller bools | Both default false; `Client_Input.cpp:44–49` |
| `cg_switchToolByWheel` | `player.wheel_tool_direction` | Default 1; -1 reverse, 0 disable, 1 forward; `Client_Input.cpp:83,204` |
| `cg_thirdperson` | `player.third_person` | Default false; `Client_Scene.cpp:44` |
| `cg_animations`, `cg_ejectBrass` | Controller preferences | Both default true; `ClientPlayer.cpp:50,334–342`, `Client_Update.cpp:53`. Main/controller apply them to presentation/effects. |
| `cg_viewWeaponX`, `cg_viewWeaponY`, `cg_viewWeaponZ` | Independent components of `player.view_weapon_offset` | Native XYZ skin axes, default 0, port bounds -1..1; view layer owns coordinate conversion and ADS attenuation. `ClientPlayer.cpp:53–55,683` |
| `cg_chatBeep`, `cg_environmentalAudio` | Main bool preferences | Both default true; `Client.cpp:58,658`, `ClientPlayer.cpp:52,1059` |
| `cg_hitFeedbackSoundGain` | `main.hit_feedback_gain` | Native default 0.2, persisted port bounds 0..1; `Client_Update.cpp:54` |
| `cg_autoFocusSpeed` | `main.focus_control.speed` | Native default 0.4, port bounds 0..3; `Client_LocalEnts.cpp:60,632–704` |
| `cg_manualFocus`, `cg_depthOfFieldAmount` | Graphics `manual_focus`, `dof_strength` | Defaults false, 1; strength bounds 0..2; `Client_Scene.cpp:45–46` |
| `cg_particles`, `cg_shake` | Graphics integer levels | Defaults 2, 1; 0..2; `Client_LocalEnts.cpp:57`, `Client_Scene.cpp:47` |
| `cg_blood`, `cg_ragdoll` | Graphics bools | Default true; `Client_LocalEnts.cpp:56`, `Client_Update.cpp:51` |
| `r_bloom`, `r_cameraBlur`, `r_colorCorrection`, `r_fxaa`, `r_lens`, `r_lensFlare`, `r_modelShadows` | Corresponding graphics replacement toggles | Native reset defaults true; `GLSettings.cpp:24–26,41,48–49,53`. Some initial port defaults are lower for browser cost. |
| `r_depthOfField`, `r_physicalLighting`, `r_radiosity`, `r_ssao` | Graphics `dof`, `lighting`, `gi`, `ssao` | Native reset defaults false; `GLSettings.cpp:35,57–58,65`. Godot/Compatibility implementations are documented replacements, not native renderer identity. |
| `r_saturation`, `r_exposureValue` | Graphics scalars | Defaults 1, 0; port limits 0..2 and -4..4; `GLSettings.cpp:39,59` |
| `r_multisamples` | Graphics `msaa` | Default 0; accepted 0/2/4 only, matching available port presets; native setting at `GLSettings.cpp:54` |
| `r_water` | Graphics water + reflections + refraction | Native default 2; 0 disables all, 1 surface, 2 surface/reflections, 3 adds refraction. `GLSettings.cpp:66`, `GLWaterRenderer.cpp:450–466`. Separate wave setting is preserved. |
| `s_gain` | Per-source linear gain before attenuation/AL effective-gain clamp | Native default1, range0..4. Persisted separately as `audio/source_gain`; the Settings volume slider remains a post-mix Master setting. |
| `s_eax` | Shared reverb and obstruction filtering | Separate default-on environment adapter, persisted as `audio/efx`. `cg_environmentalAudio` still controls gun ambience layers. |
| `bf_positionalAudio` | `main.positional_audio` | Port-specific bool, default true; no claim of a native cvar with this name |
| `cg_hideHud`, `cg_stats`, `cg_hitIndicator`, `cg_alerts` | HUD public console adapter | Defaults false,false,true,true; `Client_Draw.cpp:63,71–72`, `Client_Input.cpp:85` |
| `cg_minimapPlayerColor`, `cg_minimapPlayerIcon` | HUD map preferences | Default true; `MapView.cpp:37–38` |
| `cg_minimapSize`, `cg_playerNames` | HUD map/name preferences | Native defaults 128,2. Port persisted minimap limit 128..256; names 0..2. `MapView.cpp:36`, `Client_Draw.cpp:73` |

Booleans accept `0/1/false/true/off/on`, case-insensitively. Integer variables reject fractional strings. Floating values must be finite and within the stated limits; invalid assignments leave values and saved preferences untouched. Limits described as **port bounds** are authored validation, not a claim that native C++ enforces the same range.

## Unsupported native controls

`r_hdr` selects the floating-point scene viewport; `r_hdrAutoExposureMin`, `r_hdrAutoExposureMax` and `r_hdrAutoExposureSpeed` map to the connected source exposure filter. Float-target support is checked in the browser; an unavailable target retains ordinary rendering and reports the effective setting as off. The separate `tone_map` option controls the LDR fallback.

`s_alDriver`, `s_ysrDriver`, `s_eax` and `s_maxPolyphonics` report that Godot owns the backend/voice pool. Native framebuffer, shadow allocation, anisotropy, OpenGL occlusion queries and software-renderer worker parameters are not writable through aliases. Native debug commands and renderer scheduling (`cg_smp`) are unavailable. `cg_unicode` is fixed on; `cg_screenshotFormat` reports PNG browser export; server alert behavior belongs to iteration 2. `cg_skipDeadPlayersWhenDead` reports the fixed offline camera policy.

All `cg_key*` aliases explicitly direct the user to the Controls menu, which retains the port's saved remapping API. Unknown names report an unknown local command/variable and create no property. No unsupported assignment is silently saved or presented as effective.

Commands are limited to 160 characters and three tokens; control characters, multiple commands, quoted expressions and arbitrary trailing values cannot execute. Completion returns at most 32 registered suggestions and displays at most eight. These limits intentionally replace native free-form configuration storage.

## Chat completion and verification

`LabChat.completion_callable` supplies suggestions. Tab extends the case-insensitive shared prefix only when the caret is at the end and no text is selected; ambiguity leaves the shared prefix and exposes a compact hint. Any slash-prefixed draft keeps its channel even when it cannot complete. In ordinary text, Tab retains the existing global/team toggle. Closing chat clears suggestions and retains its ordinary draft/history behavior.

Run `& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/ui/test_console.gd --verbose`. The suite exercises the registry against typed application adapters and the actual `LabChat`, restores the Master bus, and writes no user preference files. It checks native sensitivity units, independent offsets, water levels, persistence routing, bounds/malformed input, unsupported variables, reset isolation, retained lab commands and completion/channel/caret behavior. Full-scene preference persistence and visible command feedback require main/HUD integration and browser acceptance; this isolated suite does not establish that evidence.

Current isolated result: **71 assertions, 0 failures**, Godot **4.7.2-stable**; verbose log `.cache/logs/console-tests.log` contains no script errors, warnings or leak reports.
