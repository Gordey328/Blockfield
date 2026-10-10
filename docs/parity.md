# OpenSpades → Godot feature parity

Baseline: OpenSpades `v0.1.3`, commit `dcf449c845d509bbde9d79239b32d201c1389961`, audited 2026-10-10. Source is pinned under `.cache/openspades`; paths below are relative to that checkout. [Pinned source](https://github.com/yvt/openspades/tree/dcf449c845d509bbde9d79239b32d201c1389961).

This is the acceptance ledger for the full port. An exported sandbox does **not** establish full parity. Every row needs a Godot implementation location plus recorded verification before `VERIFIED`. The subsystem log records partial work separately from accepted rows.

Status vocabulary: `NOT_STARTED`, `IMPLEMENTED`, `VERIFIED`, `DEFERRED_ITERATION_2`. `IMPLEMENTED` requires complete code for the row but has not passed full acceptance. A partial subsystem is recorded in the evidence log while the row remains `NOT_STARTED`. When a requirement is intentionally adapted for the browser or new multiplayer stack, record the decision in an ADR and link it in the row; do not silently remove the row.

Iteration 1 delivers the offline client and local authoritative rules, including a testing mode that exposes all original weapons, tools, team appearances and player states without a server. Iteration 2 delivers multiplayer. Rows marked `1+2` require offline behavior in iteration 1 and synchronized behavior in iteration 2.

## Published checkpoint57ad43b2b740

The complete frozen registered suite and Web/Linux exports passed. [Pages](https://gordey328.github.io/Blockfield/) metadata identifies clean source57; public PCK SHA256 matches the tested export (`835be72829cde3e26dbf1bd15aa67840f1014b364f343234b49d62a11fea0cb8`). The [matching server/Docker prerelease](https://github.com/Gordey328/Blockfield/releases/tag/godot-57ad43b2b740) was downloaded/hash-verified. Actual local exported clients completed both73/73 map barriers, rendered both CTF teams, delivered chat and performed a quick same-actor resume. Public Pages also loaded genuine Title.vxl without a server and retained an edited player name after reload. These are specific integration/publication results; row statuses remain bound to their full requirements. Browser download/fullscreen/audio/optional-effects/performance, Linux/container/public-WSS and sustained32-client capacity acceptance remain open. See [current status](status.md) and [acceptance gaps](acceptance-gaps.md).

Mobile input addition (2026-10-10) supports existing movement/tool/UI paths without
promoting complete parity rows: native touch component808/0, actual Main/HUD267/0,
and local exported landscape/portrait render/gesture checks. The approved extra
input adapter and its hardware acceptance limits are recorded in [mobile controls](mobile-controls.md).

## Player and combat

| ID | Feature and acceptance requirement | Original evidence | Iteration | Status |
| --- | --- | --- | --- | --- |
| P01 | First-person movement, yaw/pitch, world collision and map boundaries | `Sources/Client/Player.cpp:349,991,1108`; `Client_Scene.cpp` | 1+2 | IMPLEMENTED |
| P02 | Jump, crouch, standing clearance, sneak, sprint, diagonal normalization, step climbing | `Player.h:36`; `Player.cpp:100,991,1099,1108,1213` | 1+2 | IMPLEMENTED |
| P03 | Water wading, air/ground/water friction, fall slowdown and damage feedback | `Player.cpp:978,1084,1160`; `PhysicsConstants.h:28`; `Client_Update.cpp:589` | 1+2 | IMPLEMENTED |
| P04 | 100 HP, hurt direction/screen feedback, death, respawn timer and resupply | `Player.cpp:66,286,370,1290`; `HurtRingView.cpp`; `Client_Draw.cpp:228,266,591` | 1+2 | IMPLEMENTED |
| P05 | Team 0, team 1, spectator; names and colors supplied by match state | `World.h:51`; `Player.h:146`; `NetClient.cpp:1192`; `LimboView.cpp:56` | 1+2 | IMPLEMENTED |
| P06 | Complete articulated soldier model: standing/crouching, walking/sprinting, arms, head, death and intel carrier | `ClientPlayer.cpp:725,803,875,909,941,947,969` | 1+2 | IMPLEMENTED |
| P07 | First-person viewmodel + third-person tool/weapon models for every item | `ClientPlayer.cpp:224-258`; `Resources/Scripts/Skin/` | 1+2 | IMPLEMENTED |
| P08 | Rifle, both 0.75 and 0.76 tuning profiles | `Weapon.cpp:200,284,373` | 1+2 | IMPLEMENTED |
| P09 | SMG, both 0.75 and 0.76 tuning profiles | `Weapon.cpp:227,317,373` | 1+2 | IMPLEMENTED |
| P10 | Shotgun, 8 pellets, interruptible per-shell reload, both tuning profiles | `Weapon.cpp:254,345,373`; `Weapon.cpp:78,161` | 1+2 | IMPLEMENTED |
| P11 | Ammo/stock, firing cadence, dry fire, magazine reload, resupply, depleted-item selection rules | `Weapon.cpp:48,76,86,161`; `Player.cpp:1398,1408` | 1+2 | IMPLEMENTED |
| P12 | Aim down sights, half spread, crouch recoil reduction, viewmodel sway/bob and gun recoil | `Player.cpp:558,754`; `Client_Input.cpp:435`; `ClientPlayer.cpp:412,443` | 1+2 | IMPLEMENTED |
| P13 | Distinct head/torso/arm/leg hit volumes, occlusion and horizontal hit range | `Player.cpp:542,1316`; `World.cpp:WeaponRayCast`; `PhysicsConstants.h:55` | 1+2 | IMPLEMENTED |
| P14 | Spade primary melee/single-block damage and secondary three-block vertical dig | `Player.cpp:816,856,1250`; `NetClient.cpp:1142` | 1+2 | IMPLEMENTED |
| P15 | Grenades: stock, pull pin, cook, throw/drop on death, inherited velocity, bounce, water and explosion | `Player.cpp:136,492,783`; `Grenade.cpp:49,63,82`; `NetClient.cpp:1156` | 1+2 | IMPLEMENTED |
| P16 | Weapon/team switching, all four tool hotkeys, wheel and last-tool selection | `LimboView.cpp`; `Client_Input.cpp:53,471,513,576`; `Player.cpp:1387` | 1+2 | IMPLEMENTED |

## Voxel world and modes

| ID | Feature and acceptance requirement | Original evidence | Iteration | Status |
| --- | --- | --- | --- | --- |
| W01 | Read genuine VXL maps at 512×512×64 with correct colors and solid interior | `GameMap.h:45`; `GameMap.cpp:519` | 1 | IMPLEMENTED |
| W02 | Efficient voxel rendering, world collision, surface hit raycast and minimap projection | `GameMap.cpp:162,177,361`; `Sources/Draw/GLMapRenderer.cpp`; `MapView.cpp` | 1 | IMPLEMENTED |
| W03 | Single-block placement, valid adjacent location, stock use, overlap/range restrictions and cursor feedback | `Player.cpp:161,379`; `World.cpp:281`; `ClientPlayer.cpp` | 1+2 | IMPLEMENTED |
| W04 | Right-button drag line, cube-line ordering, stock limit and invalid-line feedback | `Player.cpp:173`; `World.cpp:CubeLine`; `NetClient.cpp:1167` | 1+2 | IMPLEMENTED |
| W05 | Delayed block placement while jumping; cancel after landing or loss of stock | `Player.cpp:436` | 1+2 | IMPLEMENTED |
| W06 | Palette selection and eyedropper capture from existing map block | `PaletteView.cpp`; `Client_Input.cpp:374,534` | 1 | IMPLEMENTED |
| W07 | Block health, weapon/spade damage and 10-second recovery of damaged surviving blocks | `Player.cpp:674,917`; `World.cpp:96,191` | 1+2 | IMPLEMENTED |
| W08 | Dig removes vertical 3 cells; grenade removes 3×3×3; bedrock rules match baseline | `NetClient.cpp:1122`; `World.cpp:328` | 1+2 | IMPLEMENTED |
| W09 | Unsupported structures detach, fall as clusters, collide and generate fragments/sounds | `GameMapWrapper.cpp`; `World.cpp:281`; `FallingBlock.cpp`; `Client_LocalEnts.cpp` | 1+2 | IMPLEMENTED |
| W10 | Save/export edited map as VXL | `GameMap.cpp:93`; `Client_Input.cpp:562`; `Client_Draw.cpp:TakeMapShot` | 1 | IMPLEMENTED |
| M01 | CTF: bases/intel, pickup, carrier, drop, capture, scores/capture limit, winner and round reset | `CTFGameMode.h`; `CTFGameMode.cpp:PlayerHasIntel`; `NetClient.cpp:1192,1427,1447,1461`; `Client_NetHandler.cpp:121` | 1+2 | IMPLEMENTED |
| M02 | TC: neutral/owned territories, contested capture progress, ownership, winner and round reset | `TCGameMode.h`; `TCGameMode.cpp:47`; `NetClient.cpp:1367,1398`; `TCProgressView.cpp` | 1+2 | IMPLEMENTED |
| M03 | Local authoritative offline rules for health, damage, respawn, restock and objectives | No offline server in original; client relies on `NetClient.cpp:919,1295,1482` | 1 | IMPLEMENTED |
| M04 | Match reset restores map and all objective/player/resource state | Original reset/map change driven by `NetClient.cpp:1348` | 1+2 | IMPLEMENTED |

## Presentation, UI and content

| ID | Feature and acceptance requirement | Original evidence | Iteration | Status |
| --- | --- | --- | --- | --- |
| U01 | Main menu, profile/player name, startup/loading/disconnect/error feedback | `Resources/Scripts/Gui/MainScreen/`; `Gui/StartupScreen/`; `Client_Draw.cpp:185,211,852` | 1+2 | IMPLEMENTED |
| U02 | Limbo team/weapon chooser, pause menu, setup and return-to-game | `LimboView.cpp`; `Resources/Scripts/Gui/Client/Menu.as` | 1 | IMPLEMENTED |
| U03 | HUD: HP, clip/stock, block/grenade stocks, crosshair, hit indicator, reload/cook states | `Client_Draw.cpp:393,446,764`; `ClientPlayer.cpp:Draw2D` | 1 | IMPLEMENTED |
| U04 | Minimap + large map, scale/zoom, coordinate grid, players, teams, bases/intel/territories | `MapView.cpp:172,178,239,549,585`; `Client_Input.cpp:536` | 1+2 | IMPLEMENTED |
| U05 | Scoreboard, team score, players/kills, spectator list and match result messages | `ScoreboardView.cpp`; `CenterMessageView.cpp`; `Client_NetHandler.cpp` | 1+2 | IMPLEMENTED |
| U06 | Kill feed, alerts, hurt overlay, names under crosshair and TC progress bar | `ChatWindow.cpp`; `HurtRingView.cpp`; `TCProgressView.cpp`; `Client_Draw.cpp:288,675,790` | 1+2 | IMPLEMENTED |
| U07 | Global/team chat, input history and scrollable log; offline event log for test sessions | `Resources/Scripts/Gui/Client/ChatSayWindow.as`; `FieldWithHistory.as`; `ChatLogWindow.as` | 1+2 | IMPLEMENTED |
| U08 | Free spectator, first/third-person following, dead-player camera and third-person debug view | `ClientCameraMode.h`; `Client_Scene.cpp`; `Client_Input.cpp:327` | 1+2 | IMPLEMENTED |
| U09 | Rebind controls; mouse sensitivity/exponent/invert; ADS hold/toggle and ADS sensitivity | `Client_Input.cpp:44-88`; `Resources/Scripts/Gui/Preferences.as:673` | 1 | IMPLEMENTED |
| U10 | Persist player profile, control bindings, graphics/audio/game preferences in browser storage | `Sources/Core/Settings.cpp`; `Resources/Scripts/Gui/Preferences.as` | 1 | IMPLEMENTED |
| U11 | Audio: spatial shots, reload/dry-fire, impacts, footsteps/water, grenade/collapse and objective/UI feedback | `Client_Update.cpp`; `Client_NetHandler.cpp`; `Resources/Scripts/Skin/` | 1 | IMPLEMENTED |
| U12 | Effects: blood, shell ejection, muzzle flash, tracers, fragments, smoke, grenade water/land effects and camera shake | `Client_LocalEnts.cpp`; `Corpse.cpp`; `GunCasing.cpp`; `Tracer.cpp`; `Client_Update.cpp:51` | 1 | IMPLEMENTED |
| U13 | Original map objects, soldier parts, weapon/tool models, UI textures and audio converted with provenance | `ClientPlayer.cpp`; `Client_Scene.cpp:546`; resource packs cited by `README.md:104` | 1 | IMPLEMENTED |
| U14 | Lighting, shadows, fog, water animation and flashlight | `Client_Scene.cpp`; `Client_Input.cpp:564`; `Resources/Scripts/Gui/StartupScreen/ConfigViewTabs.as:184,213` | 1 | IMPLEMENTED |
| U15 | Optional graphics: AA, GI, HDR, blur, bloom, lens flare, color correction, depth of field, SSAO, particle quality | `Resources/Scripts/Gui/StartupScreen/ConfigViewTabs.as:112-177`; `Sources/Draw/`; implemented Compatibility adaptations in [ADR0004](decisions/0004-compatibility-renderer.md) | 1 | IMPLEMENTED |
| U16 | Screenshot/sceneshot capture and download, HUD hide and statistics | `Client_Input.cpp:558`; `Client_Draw.cpp:63-75,889`; `SceneDefinition.cpp` | 1 | IMPLEMENTED |
| U17 | Existing localization messages, fonts/glyph coverage and selectable locale | `Resources/Locales/`; `Sources/Gui/Main.cpp:576`; `Fonts.cpp` | 1 | IMPLEMENTED |
| U18 | Mod/resource override contract and first/third-person skin extension points | `Sources/Core/FileManager.cpp`; `Sources/Gui/Main.cpp`; `Resources/Scripts/Reference/Skin/`; `ScriptBindings/ScriptManager.cpp` | 1 | IMPLEMENTED |
| U19 | Audio volume and positional audio choices adapted to browser-supported facilities | `Resources/Scripts/Gui/StartupScreen/ConfigViewTabs.as`; `Sources/Audio/`; `MumbleLink.cpp` | 1 | IMPLEMENTED |

## Required testing mode and web release

These are additions required by the user, rather than features to discover in the original.

| ID | Feature and acceptance requirement | Original evidence / contract | Iteration | Status |
| --- | --- | --- | --- | --- |
| T01 | Start testing mode directly without creating, configuring or joining a server | User requirement; local authority implements M03 | 1 | VERIFIED |
| T02 | Select rifle, SMG, shotgun plus spade/block/grenade at any time; resupply and unlimited-resource toggle | Original items P08–P16 + user requirement | 1 | IMPLEMENTED |
| T03 | Inspect both team soldier appearances, standing/crouching/moving/dead/intel states and all tool animations | Original P05–P07; no separate hero roster exists | 1 | IMPLEMENTED |
| T04 | Spawn/reset stationary and moving targets; report head/torso/limb/melee damage, kills and respawn | Original hit volumes P13 + user requirement | 1 | IMPLEMENTED |
| T05 | Select 0.75/0.76 tuning; switch offline sandbox, CTF and TC; inspect/reset objectives | Original P08–P10/M01/M02 + user requirement | 1 | IMPLEMENTED |
| T06 | Load a genuine original-format map, reset destruction, inspect performance and save edited VXL | W01/W10 + user requirement | 1 | IMPLEMENTED |
| B01 | Reproducible pinned Godot web export and CI build | New port requirement | 1 | IMPLEMENTED |
| B02 | GitHub Pages deployment, correct subpath/resources, HTTPS and browser startup | User delivery requirement | 1 | VERIFIED |
| B03 | Browser playtest: input/pointer lock, audio activation, fullscreen, reload/settings and graphics stability | Input/drag fallback, audio/fullscreen/export/storage paths and HDR browser probes implemented; full current-release interaction acceptance pending | 1 | IMPLEMENTED |
| B04 | Publish source, license notices and resource provenance with build | `LICENSE`; original file headers; separate resource inventory | 1 | IMPLEMENTED |

## Multiplayer iteration

| ID | Feature and acceptance requirement | Original evidence / replacement contract | Iteration | Status | Godot implementation / evidence |
| --- | --- | --- | --- | --- | --- |
| N01 | Browser-compatible transport, lobby/join/reconnect and disconnect/error handling | Replacement for `NetClient.cpp:395,430,476`; [ADR0005](decisions/0005-authoritative-multiplayer.md) | 2 | IMPLEMENTED | `ws_transport.gd`, `session_registry.gd`, `client_replica.gd`, Main/NetworkMenu; [runtime](server-runtime.md), [client](client-replica.md), [menu](network-menu.md). Real native join/resume/reset tested; browser WSS/TLS remains pending. |
| N02 | Authoritative server, player movement prediction/reconciliation and remote interpolation | Replacement for world/input/position packets in `NetClient.cpp:815,878,1592` | 2 | IMPLEMENTED | `simulation/player_rules.gd`, `match_simulation.gd`, `server_runtime.gd`, `client_prediction.gd`/RemotePoseBuffer, NetworkSession/controller; [prediction](client-prediction.md), [scene integration](server-runtime.md). |
| N03 | Server validation for shots, hit zones, ammo/cadence, melee, grenades and lag compensation | Original `NetClient.cpp:1759`; server rules are outside OpenSpades | 2 | IMPLEMENTED | Shared player/grenade/Match rules and `hit_history.gd`; same-time actor/terrain firearm rewind, life/color guards and missing-history denial; [rewind policy](match-rewind.md), [native hostile/late traffic](network-adversarial.md). Shaped WAN latency is unaccepted. |
| N04 | Synchronized block edits/collapse and snapshot + subsequent deltas for joining clients | Original `NetClient.cpp:1122,1167,1348`; `World.cpp:281` | 2 | IMPLEMENTED | VoxelData receipts, map transfer/transaction codecs, Replica barrier and World adoption; [runtime](server-runtime.md), [epoch reset](runtime-epoch.md). Native joins during real destruction/collapse converge exactly. |
| N05 | Teams, respawn/restock, CTF/TC objectives, wins, score and round/map resets | Original `NetClient.cpp:1192,1295,1367,1427,1482` | 2 | IMPLEMENTED | `match_objectives.gd`, `match_simulation.gd`, Runtime180-tick respawn and dedicated round coordinator; [Match](match-simulation.md), [reset](match-reset.md), [runtime epochs](runtime-epoch.md). Authored server policies are explicit. |
| N06 | Chat, server event log, scoreboard, spectator and team/weapon changes | Original `NetClient.cpp:1323,1505,1512,1775` | 2 | IMPLEMENTED | Runtime typed chat/request/events, `events_codec.gd`, NetworkSession and HUD/scoreboard/spectator adapters; [events](events-codec.md), [session](network-session.md), [menu/chat](network-menu.md). Owner-private outcomes and unknown remote HP are preserved. |
| N07 | Server discovery/list, sorting/filtering/favorites or an explicitly documented replacement | `Resources/Scripts/Gui/MainScreen/ServerList.as`; `MainScreenUI.as`; [manual-endpoint replacement ADR0006](decisions/0006-multiplayer-lobby.md) | 2 | IMPLEMENTED | `network_menu.gd`, `server_book.gd`: named local favorites, filter/sort, explicit selection/connect; [menu](network-menu.md). Empty initial catalog; no legacy master-server interoperability or invented public hosts. |
| N08 | Dedicated server packaging, configurable match/map, deployment, capacity and reconnect tests | New multiplayer backend requirement | 2 | IMPLEMENTED | Dedicated scene/entry, `tools/build_server.py`, Linux export preset, `deploy/` Docker/Caddy config and native capacity/reconnect fixtures; [deployment](server-deployment.md). Container/Linux execution, public WSS and sustained capacity are not verified. |
| N09 | Document original Ace of Spades compatibility decision; new transport is authorized but compatibility must be explicit | Original ENet 0.75/0.76 in `NetClient.cpp:395`; user permits different multiplayer engine; ADR0005 documents no old-server interoperability | 2 | VERIFIED | [ADR0005](decisions/0005-authoritative-multiplayer.md); source tuning profiles are distinct from wire compatibility. |

All N01–N08 statuses describe implemented production paths and test/configuration code, not completed multiplayer acceptance. Native localhost sockets and packaging export do not establish a hosted service, Docker execution, two exported browser clients, sustained60Hz capacity or shaped WAN/TCP behavior. The current public c4 development release predates these newer integrated slices.

## Evidence rules and release gates

Each row is accepted only after recording: implementation file(s), verification command or playtest scenario, result/date and any behavior difference with a linked ADR. Generated resource counts are not proof that animation, appearance or sound behavior matches. Passing parser/import checks is not proof of browser playability.

Iteration 1 release gate: all iteration-1 and offline portions of `1+2` rows verified, with any agreed platform adaptation explicitly documented; T01–T06 and B01–B04 verified; deployed URL tested. Iteration 2 release gate: multiplayer portions verified, two independent browser clients tested against deployed server, including join-after-destruction and reconnect.

## Subsystem evidence log

2026-10-10 unpublished final integration: native source-ray APIs377/0 preserve CastRay2 binary32/ties/step counts and legacy CastRay1024/wrapping/sky behavior. Root consumers use the corresponding families for weapons/build/spade/camera/focus, legacy eyedropper and audio; metric queries remain for authored unrelated rules. Actual Main offline lifecycle19/0 covers moving death bodies,16/6 corpse budgets, complete CTF/TC wins and reset. UI247/0, console76/0 and connection menu72/0 cover source gain/EFX controls, far eyedropper/fog fallback, preparation and exact first-person/follow OBB hottracking. Source wireframes pass6216/0 standalone plus6221/0 native GPU, with actual HUD name-independent gates checked. Camera rays11/0 and actual source input31/0 cover source nearest/flags, opposing keys, ADS audio, tool alerts, map sounds and slash chat; API reload gates bring session157/0. The progressive map image/upload-state check is headless, not texture readback. Environmental DSP has explicit adaptations in audio.md; native PCM134/81 and actual Web113/64 pass with clean diagnostics (audio-web-proof.md). These facts do not yet accept entire feature rows or subjective browser listening.

2026-10-10 shaped native TCP502/0 in8.094s covers40ms each-direction forwarding,75ms stall recovery, intentional350ms late-input rejection, two same-Replica resumes, application heartbeat timeout, private/deduplicated events and ordered terrain changes. Fixtures use bounded small maps and a shortened heartbeat for the timeout case. Public WSS, browser scheduling and sustained capacity remain separate; see network-latency.md.

2026-10-10 current public development release: source `c4f808990b84d068242dde47b8fe4f2951e322fe`, Pages bundle `d3ee96ad9451cd79f94123595bb22bee6b7f3bba`; deployed metadata reports `source_dirty=false` and Pages reports built/no error. This frozen publication predates newer normalized-HDR/network/favorites integration below. Publication/startup evidence does not verify those unpublished changes or complete either iteration.

2026-10-10 current integrated HDR handoff: explicit inverse-OETF normalization corrects the pinned Compatibility3D encoding before source metering/bloom/gamma. Headless47/0, native exposure32/0, color79/0 and actual-Main63/0; actual exported WebGL exposure32/0 and color79/0 with visible browser DOM results, reported renderer `WebKitWebGL` and `float_color_buffer=true`. Main connects exposure/dust bloom/pre-tone correction, prevents duplicate LDR processing and preserves spatial audio. Numeric and actual-scene visuals now agree on the corrected color boundary; [ADR0004](decisions/0004-compatibility-renderer.md) records budgets/fidelity limits. U15/B03 are IMPLEMENTED, with full browser interaction, Title-map quality and sustained performance still pending.

2026-10-10 multiplayer integration: production runtime103/0, Replica138/0, hostile real sockets392/0, epoch reset722/0 and inherited Main network scene27/0; same-time firearm rewind441/0 and history269/0. These cover owned input/resources, exact map baseline/deltas, late hits/cover/life guards, event privacy, chat,180-tick respawn, same-Replica resume and live/loading greater-epoch reset. Saved-server storage163/0, actual menu70/0 and native Compatibility menuGPU93/0 cover read-only selection and explicit persistence with exact preferences restored. N01–N08 are IMPLEMENTED. Server export/configuration exists, but Docker/Linux/public WSS, full browser play and capacity/latency acceptance remain open. Commands and measured limits are in the linked subsystem documents, not inferred from these counts.

2026-10-10 offline regression evidence: source scene151/0, session109/0, source motion128/0 and actual-scene integration119/0 with fixed60Hz; camera45/0+GPU7/0, weapons69/0+GPU10/0, spectator47/0+GPU11/0, HUD227/0+GPU27/0, console75/0. PCM126/0 each real WASAPI48kHz and Dummy44.1kHz is distinct from audible browser acceptance. A final frozen export and complete acceptance of the integrated workspace remain pending.

2026-10-10 expanded checkpoint: source grenade move/bounce/water/explosion tests17/0; session event journal77/0; lit terrain/AO/collider invalidation26/0; full-resolution topdown13/0; post79/0; data resource extensions67/0; HUD/map/chat/bindings88/0. Main integrates source map tracers, persistence, map/pack uploads, skin factories, flashlight and screenshot/download APIs. Local GPU evidence is recorded in ui.md/assets.md/voxel.md. Renderer/extension fidelity limits: decisions/0004-compatibility-renderer.md. Browser input, downloads, resource-pack import and all optional graphics still require deployed checks; entire feature rows remain unaccepted.

2026-10-10 public browser checkpoint: source9f876bb2a27bad24f64899cff7bf61c52fe739c0, bundle09793333b69d5efa1a2a76cae704e292c30aee78. Russian/English locale switch, local entry, rifle ADS, a100-damage headshot and genuine Title.vxl load exercised on Pages. Pointer lock returned Chromium UnknownError; waiting for VXL download timed out. These are partial B03/T06 checks, not complete acceptance.

2026-10-10: `game/gameplay/local_session.gd` implements local session state, both source weapon tuning profiles, ammo/cadence/reload, stocks, grenade cook/fuse events, target damage/respawn, team/spectator state and local CTF/TC rules. `tests/session/test_session.gd` exercises these contracts headlessly on Godot 4.7.2. This supports the simulation portions of P04/P05/P08–P11/P13/P15/P16/M01–M03/T02/T04/T05; it does not verify their input, models, sound, visual feedback or browser integration. Rows remain unaccepted until those checks are recorded.

Command: `.tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/session/test_session.gd`. Result is recorded after each relevant change in the session handoff; source constants are covered separately from authored offline melee/grenade/respawn/objective policy.

2026-10-10: `tools/build.py --export` passes world30, VXLsave19, falling/water21, session65, actual-scene integration94, presentation504, localization76 and effects3217 checks with zero failures, followed by parser/runtime/export success. Implementations and remaining visual/input differences are detailed in source-audit.md, voxel.md and assets.md. These support partial P01–P16/W02–W09/UI/test-lab work without accepting those entire rows. W01/W08/W10/M03/U17 are implemented; their browser and presentation acceptance remains pending.

2026-10-10, T01/B02: `game/ui/lab_hud.gd` enters `game/main.gd`'s `LocalSession` directly. Public HTTPS startup, original shotgun selection and entry into the rendered local FPS lab were exercised at https://gordey328.github.io/Blockfield/ using source `5d367dfafab5524c1f4c572218fb6a0605ec9c42`, Pages bundle `128f0059f686f14602ee669de1ba44cb75279b45`. No server creation/join flow is involved. GitHub Pages reports build `built` with no error. This verifies startup/publication and local entry for that revision; it does not verify mouse capture, audio or subsequent feature changes. Branch-publication adaptation: decisions/0003-pages-publication.md.

2026-10-10 source/render integration: complete offline code rows are IMPLEMENTED without promoting them to VERIFIED. Contracts/evidence: source-audit.md (source motion128/0, scene146/0 and subsequent tool/selection corrections), assets.md (character/corpse/native weapon/spectator), ui.md (custom metadata/native palette/settings), audio.md (126 routing/parameter checks), voxel.md (AO atlas/spectral/GI/real geometry reflections and fog). Later handoffs above include the completed UI/camera/audio/action paths and normalized float HDR. B01 uses the local-validation/branch-publication replacement in ADR0003 while Actions is externally blocked. Trusted skins/data ZIP and renderer differences are recorded in ADR0004 and extensions.md. Browser evidence applies to the recorded deployed SHA, not newer workspace code.
