# Offline client UI

## Game home and preparation

The user-authorized first game UI delivery adds a lightweight GameShell home and
map/weapon setup before Main is instantiated. It shares CombatTheme/Inter and
uses baked actual map/original weapon captures. Crossroads alone starts offline
3×3; Lab/Title/Mirage start training. Catalog selection persists independently of
existing preferences; Main loads/adopts the map and chooses the actual starting
weapon through its session adapter. CSS-sized EXPAND layout is scoped to the
shell and restores the cached Window on teardown. Dedicated entry stays separate.
See [ADR0030](decisions/0030-game-shell-and-offline-launch.md).

Frozen912adec passes shell415/0, real launch38/0 and the108-run registered gate,
with real Web desktop/portrait/landscape and public launch checks at
https://gordey328.github.io/Blockfield/game-ui/. Legacy training/settings/network
tools remain reachable; death/results/settings redesign is a later delivery.
Physical-phone feel/performance and complete source parity remain open. Exact
commands, failures, artifacts and hashes: [delivery evidence](game-ui-first-delivery.md).

Source baseline: OpenSpades v0.1.3, commit `dcf449c845d509bbde9d79239b32d201c1389961`.
This document records the current offline implementation and its limits; it does not certify complete OpenSpades parity or multiplayer readiness.

Scoreboard #IDs share LabMap's source32-color palette and ModifyColor calculation.
The existing per-player map-color preference updates minimap, large map and
scoreboard together, including live checkbox/console changes and saved settings.
Disabled IDs are white; following name/score text retains local/alive/dead tint.
Network IDs stay canonical while palette lookup wraps modulo32.

Graphics controls expose optional float HDR and its native minimum/maximum/adaptation-speed settings. The connected path has47 numeric,32 exposure GPU,79 color GPU and63 actual-Main GPU checks, plus exported WebGL32/79 checks; see ADR0004 for source formulas, pyramid budgets and later post-effect ordering. Color correction and bloom do not run twice while HDR is active.

## Source contracts and implementation

| Feature | Original evidence under `.cache/openspades/` | Godot implementation / evidence |
| --- | --- | --- |
| Bullet slots, resource stock, low-stock warnings, reload prompt | `Sources/Client/Client_Draw.cpp:450–573` | `LabAmmoStrip` uses original 7.62mm/9mm/12gauge images, source dimensions/spacing and spent-slot tint. HUD selects actual weapon, block or grenade stock; reload percent and grenade fuse supplement source warnings. |
| Native sight and hit feedback | `Resources/Scripts/Skin/BasicViewWeapon.as:238`, weapon `View.as::Draw2D`, `ClientPlayer.cpp:1015`; `Client_Draw.cpp:393–419`, `Client_Update.cpp:260–263,995–999` | Original 64×64 Sight/HitFeedback textures resolve through resource overrides. Sight remains for spade/block/grenade and sprinting; weapons hide only above actual ADS 0.6. Local and followed first-person cameras use the displayed tool, including delayed tool switches. Red hostile/green friendly feedback starts at 1 and fades 4/s (250ms); third-person/dead views hide it. |
| Typed alerts and menu/chat feedback | `Client.cpp:504–528`, `Client_Draw.cpp:675–761`, `Client_Update.cpp:1245`; `Gui/UIFramework/Button.as:55–59` | Original AlertIcon, yellow warning/red error border and icon, black half-opacity background, source position/margins. Notice holds 2.5s, warning/error 3s, then 1s fade; border fades 1.5/s. Warning/error request Alert audio unless quiet, even with visual alerts disabled. Menu buttons emit original Hover/Select requests; ordinary chat requests Chat feedback, console responses remain quiet. Main owns playback/chat-beep preference. |
| Intel carrier icon, death countdown, spectator help | `Client_Draw.cpp:423–442`, `:592–672` | Actual local flag carrier and respawn/camera states drive HUD. Followed-player ammo remains hidden, since native server does not supply it. |
| Name under aim | `Client_Draw.cpp:288–319` | Unshaken authoritative aim ray stops at terrain and intersects actual target hit zones. Optional name/distance, projected above original character eye. |
| Block cursor / line feedback | `Client_Draw.cpp::DrawBlockCursor`, `Client_Update.cpp:497–511` | `LabBuildCursor` shares `player.get_build_preview()` validation, shows depth-tested wire cells and valid/invalid/pending colors. HUD displays count, rejection reason and queued airborne construction. |
| Native block palette | `PaletteView.cpp:47–74,91–154,157–202` | `LabPalette` recreates all64 integer RGB colors, default index3, arrow wrapping±1/±8, original Palette.png regions/two-pass selection and in-game location. Only live block users handle its keys. Eyedropped native color selects a slot; arbitrary RGB remains available through the color picker without a false slot selection. |
| Match names/colors and target creation | `NetClient.cpp:1195–1204` and required lab T04 | Team chooser, scoreboard, map/objectives, TC bar, chat/feed/result consume `LocalSession.get_team_info`. Custom names stay literal; defaults retain localized lab names. Soldiers tab spawns stationary/moving visible targets for either team and resets all target authorities/views together. |
| Target animation inspection | Required lab T03; original `ClientPlayer.cpp`, `Resources/Scripts/Skin/` | Authored Soldiers controls expose observed ADS, reload stage (0..1.12 for final shotgun pump), grenade cook (0..3s), idle/bash/first/repeated dig and stage, block RGB and visual shot sequence. These change ephemeral target snapshots, never invoke local fire/damage/audio authority or save game preferences. Original FP spectator skin consumes the snapshots; LabSoldier forwards action/cook/readiness and block color to CharacterView. Reset removes preview fields/timers. |
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
| Additional source preferences and commands | `Preferences.as:643–654`, `ClientPlayer.cpp:330–347,683`, `ChatSayWindow.as:81–167` | Eject brass, animated/immediate ADS, chat notification, headshot feedback gain and weapon XYZ offset have connected/persisted controls. Disabling ADS animation leaves sprint/tool-raise timing intact. Main's LabConsole maps 48 supported variables to typed Godot settings; chat Tab completes command prefixes and shows up to 8 suggestions without switching channel. Unsupported backend cvars return explicit explanations. Validated HUD writes refresh corresponding widgets. |
| HUD hide/statistics/screenshots | `Client_Draw.cpp` (`cg_hideHud`, statistics); `Client` screenshot paths | F6 toggles HUD/cursor, F7 statistics; buttons/hotkeys 0 with HUD, 9 scene only; main owns PNG download/storage. `hud.set_capture_visible()` also hides the 3D cursor that a CanvasLayer hide alone would leave visible. |

## Default UI controls

Phones use an automatically enabled left movement stick, separate right look region,
fire/alternate/reload/jump/crouch/sprint buttons, tool selection, map, camera and menu.
Settings → Mobile controls provides Auto/On/Off and saves the choice. Menu/HUD scaling
supports landscape and portrait; input ownership/cleanup and regression evidence are
recorded in [mobile controls](mobile-controls.md).

`N` map; `M` four map scales; hold `Tab` scoreboard; `T` global local chat; `Y` team local chat; `H` expanded chat log; `Esc` cancel chat/close log/open lab; `F6` HUD; `F7` statistics; `0` screenshot; `9` scene screenshot; `8` save VXL; `L` flashlight. Arrow keys select native block palette colors while the block tool is active; `E` takes RGB from the actual voxel ray. All actions are remappable in Settings. While editing chat/menu, gameplay controls are disabled and held actions released on transitions, including closing chat.

Uploaded `.vxl` / data resource-pack `.zip` buttons call main import APIs. `hud.reload_resources()` refreshes original map/bullet/intel/hurt/TC textures through `OpenSpadesExtensions.texture()` after override changes. It does not execute uploaded source scripts.

## Persistence and APIs

`user://settings.cfg` retains `input`, `profile`, `audio`, `graphics` (main-owned), `controls` (LabInputBindings) and `ui` (LabHUD). Each writer loads the existing config before changing its own keys. UI tests preserve and restore the exact previous bytes. The GPU helper also records a durable test-only settings backup and recovers it on the next run if its renderer is interrupted; failed main-script loading exits early with restoration.

- `LabInputBindings.load_bindings(path)`, `save_bindings(path)->Error`, `bind_action(action,event)`, `reset_defaults()`, `binding_label(action)`, `release_actions()`.
- `LabHUD.setup(main,session,player,world)`, `set_menu_visible`, `is_menu_open`, `open_chat(team_only=false)`, `is_chat_open`, `show_hit`, `show_notice`, `set_hud_hidden`, `is_hud_hidden`, `set_capture_visible`, `reload_resources`, `add_map_tracer(start,end)`.
- `show_hit(part,damage,friendly=false)`, `show_alert(message,kind="notice",quiet=false)`; signals `alert_sound_requested`, `ui_sound_requested(kind)` and `chat_sound_requested`. Main/controller determine friendly hits and own original feedback playback. Alert sound survives disabled visual alerts; quiet warnings/errors suppress their sound.
- `get_console_setting(key)->Variant`, `set_console_setting(key,value)->bool`: bool HUD visibility/statistics/hit/alerts/map-icon/color choices, int minimap 128..256 and player-name mode 0..2. Invalid type/range/key is rejected; accepted writes refresh map/reticle/alert/widgets and preserve unrelated config sections.
- Target preview fields are lab-only: `aiming`, `is_reloading`, `reload_progress`, `grenade_cook_time`, `action_type` (0idle/1bash/2dig-start/3dig), `action_progress`, `block_color`, `shot_sequence`, `ammo`, `clip_size`, `profile`, `ready_state`. Visual shots use the source weapon profile for clip/readiness, without changing local ammunition, shots-fired statistics or any health. Iteration2 snapshot producers must validate remote fields rather than treating these controls as multiplayer authority.
- Settings/main-menu fullscreen buttons call `main.toggle_fullscreen()` for a browser user gesture; session-log button calls `main.export_event_log()`. Actual browser fullscreen/download success remains a release check.
- `get_chat_messages()->Array[Dictionary]` returns a deep copy for session-log export. The exporter cannot mutate the live chat, and this API performs no upload.
- HUD subscribes to `session.player_hurt(amount,origin,kind)` and `session.match_event(Dictionary)`. Root handles source state, spatial/audio feedback, imports, screenshots and settings APIs.
- Match teams use `session.get_team_info(index)->{name,color}` / `set_team_info(index,name,color)`. Team metadata/locale changes refresh chooser and chat once; ammo/TC events do not repeatedly rebuild expanded chat. Target buttons call main `spawn_lab_target(moving,team)->id` and `reset_targets()`.
- Additional graphics keys exposed through main are `gi` (initiallyoff), `water_waves`, `water_refraction` and `ragdolls` (initiallyon). Audio `environmental_audio` is a persisted main property, initiallyon. Indirect light is approximate; optional normalized float HDR supplies source auto exposure and pre-tone bloom. Relevant backend/browser evidence belongs in voxel.md/assets.md and the feature ledger.

## Verification

Latest headless checks include native reticle thresholds/displayed tools/following/friendly color and fade, alerts visible above an open menu and suppressed by HUD-hide, notification requests, actual target-animation widgets/Character hooks/observer recoil, preview isolation from damage/ammunition/settings, typed console writes and real chat Tab/submit, native preference controls/persistence, and fullscreen/event-log UI hooks.

`tests/ui/test_ui.gd`: **227 assertions, 0 failures** on Godot 4.7.2 headless, log `.cache/logs/ui-native-tests.log`. Exercises the actual main scene: real input routing/remapped movement, duplicate/unbound round trip and other config preservation, held scoreboard, chat input isolation/draft/history/channels/literal markup, reload/cook/resource state, locale-sensitive hit text, actual target-name ray, CTF carrier, original hurt formulas/lifetimes, real kill feed/score order, ally/dead/spectator map filtering, map extents/layout/edit texture, tracer first-person suppression/shutter/motion/expiry, TC orientation/fade/results, real build ray/cursor, screenshot hide state and graphics API effects. Added cases check live custom names/RGB, literal BBCode-like names, metadata validation, source ModifyColor, actual button-created authority+visible soldier, moving simulation, target-reset cleanup, golden native palette RGB/wrap/default/menu/tool rules real eyedropper matching/arbitrary RGB and backend routing of GI/water/corpse/environmental-audio switches. An aborted scenario counts as a failure.

`tests/integration/test_lab.gd`: **94 assertions, 0 failures**, log `.cache/logs/ui-regression.log`; previous weapon/movement/building/grenade scenarios still pass. Both verbose logs have no script errors, runtime errors, shutdown resource leaks or ObjectDB leaks at the recorded checkpoint.

`tests/ui/render_ui.gd`: thirteen real **OpenGL Compatibility** captures on Intel UHD, `.cache/previews/ui/{menu,hud,scoreboard,map,chat,hurt,tc,results,custom_teams_menu,target_spawn_controls,custom_teams_scoreboard,spawned_targets,native_palette}.png`, log `.cache/logs/ui-render.log`. Manual inspection confirmed map placement/grid, scoreboard, readable Cyrillic, actual bullet icons, chat controls, TC bar and additive hurt ring; custom team names/colors and real extra soldier spawns have additional captures. Earlier QA found and fixed two bugs invisible to state-only checks: minimap/large map offset reset outside viewport and an opaque black HurtRing rectangle. The render helper preserves user settings and drains audio before quitting.

`tests/ui/render_native_feedback.gd` adds thirteen real Compatibility captures and **27 assertions, 0 failures**, logs `.cache/logs/native-ui-gpu{,-errors}.log`, previews `.cache/previews/native-ui/`. Checks screen-center sight pixels, sparse red/green source hit pixels (excluding green terrain), warning/error original icon pixels, final alert fade, warning visible above an actual open menu, observed rifle ADS/grenade sight, Russian/English animation controls and real console suggestions. GPU inspection found a centering bug that state-only checks missed: setting Control.position after parenting cancelled the center anchors. Explicit source pixel offsets fixed it; both headless global-center and pixel checks now guard against recurrence. User settings have a durable recovery backup and are restored; previews are ignored development evidence, not shipped assets. Fullscreen controls have a backend-hook UI check; actual browser fullscreen remains unverified here.

Run:

```powershell
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/ui/test_ui.gd --verbose
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --path game --rendering-method gl_compatibility --script ../tests/ui/render_ui.gd
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --path game --rendering-method gl_compatibility --script ../tests/ui/render_native_feedback.gd
```

## Explicit differences / remaining work

- UI layout, normal text font, lab tabs, scoreboard row formatting and result banner are authored Godot UI; this is functional migration, not a pixel-identical recreation of native drawing. The small lab map grid is scaled to its dimensions.
- Offline chat has no remote recipients. It keeps a bounded 200 messages/history entries; native buffer pruning is based on rendered height. Ordinary Tab switches channel; command Tab completes the mapped registry. Arbitrary native cvar reflection is replaced by validated Godot settings, with unsupported backend commands explained. Server-delivered alerts/chat require iteration 2 transport. The downloadable offline event log is bounded; it does not reproduce the continuously written native NetLog file.
- New UI descriptions have Russian/English fallbacks; the original 17-language localization remains available for source message IDs. Additional authored labels in other languages await translations.
- Map tracer state follows `MapView.cpp:651–694` and `Client_Update.cpp:1069–1087`: velocities 700/360/500, 0.1s shutter, initial random offset, first-update skip and hit endpoint expiry. The constructor's local `bulletVel *= 4` does not change stored native velocity; effective behavior is preserved. The drawn line is a Godot 2px primitive in place of the native Ball texture; root-owned controller connects authoritative shots. Source suppression applies to local first-person traces on both maps and 3D view.
- Browser pointer-lock and browser download behavior need deployed-browser acceptance. The state/GPU tests verify scene-only visibility restoration, not actual browser download dialogs. GPU captures do not prove all screen sizes, especially narrow/mobile layouts.
- Data resource packs are the documented Godot replacement for native script mod loading. They do not establish AngelScript, executable mod, custom uploaded-font or native title/server-browser parity.
- Post-processing toggles expose Compatibility adaptations, including optional float HDR and bounded indirect light. See renderer documentation/ADR for fidelity limits. GI/water/corpse/environmental-audio switches require backend and deployed-browser acceptance.
# Browser pointer capture fallback

## Modern combat presentation — 2026-10-11

User-selected presentation replacement: [ADR0022](decisions/0022-modern-combat-ui.md).
CombatReadout presents authoritative health/resources/ammunition in rounded
translucent edge islands, with a slim cyan/red HP bar and large tabular digits.
Reload/fuse/depletion feedback is localized; low magazine uses amber. Desktop
shows four icon/hotkey slots. Mobile uses a compact footer and circular action
controls; tool tiles retain labels and selected-tool emphasis. TDM keeps the
centered score/timer through death. The native block palette sits beside the map.

Inter4.1 is bundled under OFL1.1 with Latin/Cyrillic and the existing multilingual
fallback; font provenance/reproduction is in game/assets/fonts/README.md.
Procedural icons are authored here. No game art is copied from the references.
HUD adapters and touch hit regions/claims/gestures retain their contracts.

Pinned Godot4.7.2.stable.official.ed1daf0bf and OpenSpades
dcf449c845d509bbde9d79239b32d201c1389961. Workspace parser/import passes;
UI284/0, controls3099/0, look226/0, actual combat readout166/0 pass.
The new fixture's initial WeakRef type warning is fixed; failed log retained.
Existing lab fixture119/1 reproduces its saved-HDR-preference dependency;
the final frozen check uses private test settings. Native Compatibility helper
captures desktop rifle/lowHP/block palette/grenade, touch landscape/portrait and
TDM. Export/browser evidence and exact release source are recorded below when
available. Original U03–U07 row acceptance remains IMPLEMENTED.

Commands (bundled Python/engine paths are in status.md):
`python -c "import sys; sys.path.insert(0,'tools'); import build; build.run('combat-hud',['--fixed-fps','60','--script','../tests/ui/test_combat_hud.gd'])"`;
`Godot_v4.7.2-stable_win64_console.exe --path game --rendering-method gl_compatibility --script ../tests/ui/render_combat_hud.gd`.
Native previews: `.cache/previews/combat-ui/`; browser acceptance remains separate
from headless state assertions and these GPU captures.

Final frozen source `2f1e1147099e102c792b629df82033e5c44df774` passes all93
test runs (92 Godot fixtures and latency462/0), import, both smokes and normal Web export.
The isolated actual lab119/0, UI284/0, controls3099/0, look225/0, modern HUD166/0
and TDM62/0 pass. `tools/release_checkpoint.py --revision 2f1e1147099e102c792b629df82033e5c44df774 --import-cache game/.godot`
provides the archived source, private fixture settings and reproducible logs.
Local ordinary Web: rifle10→8, reload18% then10/48, movement, block stock50 and
palette relocation; portrait390×844 Fire10→9/reload10%, landscape844×390 and
TDM3:6 at4:31 are observed. Rounded score capsule clears portrait minimap and
both toolbar rows. Viewport and touch Auto preference are restored. Local IAB
has two known pointer-lock WrongDocumentErrors; no claim of successful capture
is made. Seven native Compatibility captures are retained; initial map-not-ready
captures were repeated after progressive preparation before visual acceptance.
Pages bundle `ed057d408453cda87c588787eb3a0f6f7b773ffa` is built. Public metadata,
six core SHA256s and Inter license match in `.cache/combat-pages-verification.json`.
Normal public UI starts with the new touch/HUD treatment; captured warning/error
list is empty. The final browser tab stays open for visual review.
This is a development release with an accepted visual replacement; original
parity status and physical-phone/performance limits remain separate.

Current unpublished integration passed actual-Main UI247/0, console76/0 and
preparation menu72/0. It adds legacy source eyedropper/fog miss behavior,
progressive map completion, independent source gain/EFX preferences and exact
Euclidean OBB hottracking from the observed first-person eye. Displayed name
distance remains measured from the local eye. The source wireframe is independent
of the name toggle, respects target team/alive/camera/terrain gates, and highlights
accumulated hit parts. See hottracked-player.md for standalone6216/0 and GPU6221/0.
Actual source-input integration31/0 covers newest opposing-key priority, ADS
sound edges/hold-toggle/gates, weapon-only reload, three depleted-tool alerts,
native map sounds and the slash-prefilled chat shortcut. Main maps UI feedback
to centered dry playback. These are focused native checks; current exported
browser interaction remains an acceptance gate.

The normal game uses Godot pointer capture. When the browser actually emits `pointerlockerror`, main releases the cursor and shows a quiet alert; dragging with a held mouse button still turns the camera with the same source sensitivity/ADS rules. Ordinary free cursor movement does not turn the camera. Successful later capture restores normal controls. This is an additional browser fallback, not evidence that native pointer capture was accepted in the embedded runner.
