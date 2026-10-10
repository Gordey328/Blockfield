# Offline client UI

Source baseline: OpenSpades v0.1.3, commit `dcf449c845d509bbde9d79239b32d201c1389961`.
This document records the current offline implementation and its limits; it does not certify complete OpenSpades parity or multiplayer readiness.

## Source contracts and implementation

| Feature | Original evidence under `.cache/openspades/` | Godot implementation / evidence |
| --- | --- | --- |
| Bullet slots, resource stock, low-stock warnings, reload prompt | `Sources/Client/Client_Draw.cpp:450–573` | `LabAmmoStrip` uses original 7.62mm/9mm/12gauge images, source dimensions/spacing and spent-slot tint. HUD selects actual weapon, block or grenade stock; reload percent and grenade fuse supplement source warnings. |
| Intel carrier icon, death countdown, spectator help | `Client_Draw.cpp:423–442`, `:592–672` | Actual local flag carrier and respawn/camera states drive HUD. Followed-player ammo remains hidden, since native server does not supply it. |
| Name under aim | `Client_Draw.cpp:288–319` | Unshaken authoritative aim ray stops at terrain and intersects actual target hit zones. Optional name/distance, projected above original character eye. |
| Block cursor / line feedback | `Client_Draw.cpp::DrawBlockCursor`, `Client_Update.cpp:497–511` | `LabBuildCursor` shares `player.get_build_preview()` validation, shows depth-tested wire cells and valid/invalid/pending colors. HUD displays count, rejection reason and queued airborne construction. |
| Map zoom, focus, clipping, player colors | `Sources/Client/MapView.cpp:101–174`, `:183–251`, `:467–548` | Four source scales 400/200/100/50%, easing, clamped focus, source 32-ID color palette/ModifyColor, configurable per-weapon icons. Alive allies visible to active team; spectators see both teams. Focus follows actual camera target/free camera. |
| Terrain, grid and objectives on map | `MapView.cpp:354–465`, `:551–602`; `GLFlatMapRenderer.cpp:54–73` | Shared full-resolution topmost-color texture from `world.get_topdown_image()`, incremental edits, A–H / 1–8 grid, CTF bases/flags/carrier blinking, TC ownership. Native 512 map uses source 64-block grid; 96-block lab divides its smaller map into eight cells. |
| Scoreboard and results | `Sources/Client/ScoreboardView.cpp` | Team columns with actual session points, score order, dead gray, local highlight, spectators, CTF limit and TC owned/total count. Winning round banner. Target names/deaths/kills come from local authoritative state. |
| Directional damage ring | `Sources/Client/HurtRingView.cpp:44–117` | Original HurtRing2 image, additive blend (native premultiplied alpha zero), size 0.3×screen height, camera-relative damage origin; 3s lifetime and final 0.5s fade. No invented direction for fall damage. |
| Hurt sprites and screen tint | `Client_Update.cpp:543–559`; `Client_Draw.cpp:228–285` | Original sprite count `max(6,18-int(health/100*8))`, random angle/scale/shift/strength ranges, source polygon geometry/UV crop and 1.5s strength decay; 0.35s health-dependent multiply tint + red wash. UI is sole owner of these overlays; post-processing retains separate renderer effects. |
| Territory progress | `Sources/Client/TCProgressView.cpp:40–173` | Source 18-block axis range, closest territory, previous territory 2s fade, local capture orientation, 12/256 border adjustment, original 256×32 bar/background textures, neutral/owner text; local contested label added. |
| Chat input/history and log | `Resources/Scripts/Gui/Client/ChatSayWindow.as`; `Gui/FieldWithHistory.as`; `Sources/Client/ChatWindow.cpp` | Shared global/team input history with caret/draft preservation, Up/Down, Enter/Escape, channel button/Tab, literal Unicode text, 15s compact lifetime, expanded scrollable messages. Local `/help`, `/restock`, `/reset`, `/mode`, `/team` commands act without a server. |
| Kill/event feed | `Client_Update.cpp:860–914`; `ChatWindow.cpp` | Actual session event signals, team-colored killer/victim, translated Rifle/SMG/Shotgun/Headshot/Melee/Grenade cause, death/respawn/CTF/TC/round entries, compact lifetime. |
| Remapping and persistence | `Resources/Scripts/Gui/Preferences.as:320–421`, `:515–528` | `LabInputBindings`: physical keys, modifier combinations, mouse buttons; Esc cancels, Backspace/Delete clears, duplicate keys clear previous action. Config preserves unrelated sections. Main loads bindings after creating defaults. |
| Settings | `Preferences.as` | Existing arsenal/soldiers/world/check tabs preserved. FOV source range 45–90; mouse/ADS/invert/exponent, audio/locale/name; added minimap size/icons/colors, names, hit feedback/alerts/statistics, complete action bindings and graphics controls wired to main APIs. Source languages preserved; new lab labels have Russian/English fallback. |
| HUD hide/statistics/screenshots | `Client_Draw.cpp` (`cg_hideHud`, statistics); `Client` screenshot paths | F6 toggles HUD/cursor, F7 statistics; buttons/hotkeys 0 with HUD, 9 scene only; main owns PNG download/storage. `hud.set_capture_visible()` also hides the 3D cursor that a CanvasLayer hide alone would leave visible. |

## Default UI controls

`N` map; `M` four map scales; hold `Tab` scoreboard; `T` global local chat; `Y` team local chat; `H` expanded chat log; `Esc` cancel chat/close log/open lab; `F6` HUD; `F7` statistics; `0` screenshot; `9` scene screenshot; `8` save VXL; `L` flashlight. All actions are remappable in Settings. While editing chat/menu, gameplay controls are disabled and held actions released on transitions, including closing chat.

Uploaded `.vxl` / data resource-pack `.zip` buttons call main import APIs. `hud.reload_resources()` refreshes original map/bullet/intel/hurt/TC textures through `OpenSpadesExtensions.texture()` after override changes. It does not execute uploaded source scripts.

## Persistence and APIs

`user://settings.cfg` retains `input`, `profile`, `audio`, `graphics` (main-owned), `controls` (LabInputBindings) and `ui` (LabHUD). Each writer loads the existing config before changing its own keys. UI tests preserve and restore the exact previous bytes.

- `LabInputBindings.load_bindings(path)`, `save_bindings(path)->Error`, `bind_action(action,event)`, `reset_defaults()`, `binding_label(action)`, `release_actions()`.
- `LabHUD.setup(main,session,player,world)`, `set_menu_visible`, `is_menu_open`, `open_chat(team_only=false)`, `is_chat_open`, `show_hit`, `show_notice`, `set_hud_hidden`, `is_hud_hidden`, `set_capture_visible`, `reload_resources`, `add_map_tracer(start,end)`.
- HUD subscribes to `session.player_hurt(amount,origin,kind)` and `session.match_event(Dictionary)`. Root handles source state, spatial/audio feedback, imports, screenshots and settings APIs.

## Verification

`tests/ui/test_ui.gd`: **88 assertions, 0 failures** on Godot 4.7.2 headless, log `.cache/logs/ui-tests.log`. Exercises the actual main scene: real input routing/remapped movement, duplicate/unbound round trip and other config preservation, held scoreboard, chat input isolation/draft/history/channels/literal markup, reload/cook/resource state, locale-sensitive hit text, actual target-name ray, CTF carrier, original hurt formulas/lifetimes, real kill feed/score order, ally/dead/spectator map filtering, map extents/layout/edit texture, tracer first-person suppression/shutter/motion/expiry, TC orientation/fade/results, real build ray/cursor, screenshot hide state and graphics API effects. An aborted scenario counts as a failure.

`tests/integration/test_lab.gd`: **94 assertions, 0 failures**, log `.cache/logs/ui-regression.log`; previous weapon/movement/building/grenade scenarios still pass. Both verbose logs have no script errors, runtime errors, shutdown resource leaks or ObjectDB leaks at the recorded checkpoint.

`tests/ui/render_ui.gd`: eight real **OpenGL Compatibility** captures on Intel UHD, `.cache/previews/ui/{menu,hud,scoreboard,map,chat,hurt,tc,results}.png`, log `.cache/logs/ui-render.log`. Manual inspection confirmed map placement/grid, scoreboard, readable Cyrillic, actual bullet icons, chat controls, TC bar and additive hurt ring. This found and fixed two bugs invisible to state-only checks: minimap/large map offset reset outside viewport and an opaque black HurtRing rectangle. The render helper preserves user settings and drains audio before quitting.

Run:

```powershell
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/ui/test_ui.gd --verbose
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --path game --rendering-method gl_compatibility --script ../tests/ui/render_ui.gd
```

## Explicit differences / remaining work

- UI layout, normal text font, lab tabs, scoreboard row formatting and result banner are authored Godot UI; this is functional migration, not a pixel-identical recreation of native drawing. The small lab map grid is scaled to its dimensions.
- Offline chat has no remote recipients. It keeps a bounded 200 messages/history entries; native buffer pruning is based on rendered height. Tab switches channel rather than original arbitrary cvar autocomplete. Only listed local commands exist; native cvar reflection/completion, server alerts/notify sounds and network log export remain unported.
- New UI descriptions have Russian/English fallbacks; the original 17-language localization remains available for source message IDs. Additional authored labels in other languages await translations.
- Map tracer state follows `MapView.cpp:651–694` and `Client_Update.cpp:1069–1087`: velocities 700/360/500, 0.1s shutter, initial random offset, first-update skip and hit endpoint expiry. The constructor's local `bulletVel *= 4` does not change stored native velocity; effective behavior is preserved. The drawn line is a Godot 2px primitive in place of the native Ball texture; root-owned controller connects authoritative shots. Source suppression applies to local first-person traces on both maps and 3D view.
- Browser pointer-lock and browser download behavior need deployed-browser acceptance. The state/GPU tests verify scene-only visibility restoration, not actual browser download dialogs. GPU captures do not prove all screen sizes, especially narrow/mobile layouts.
- Data resource packs are the documented Godot replacement for native script mod loading. They do not establish AngelScript, executable mod, custom uploaded-font or native title/server-browser parity.
- Post-processing toggles expose Compatibility replacements; LDR tone mapping and ambient light are explicitly labeled replacements for original HDR/GI. See renderer documentation/ADR for fidelity limits.
