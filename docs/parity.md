# OpenSpades → Godot feature parity

Baseline: OpenSpades `v0.1.3`, commit `dcf449c845d509bbde9d79239b32d201c1389961`, audited 2026-10-10. Source is pinned under `.cache/openspades`; paths below are relative to that checkout. [Pinned source](https://github.com/yvt/openspades/tree/dcf449c845d509bbde9d79239b32d201c1389961).

This is the acceptance ledger for the full port. An exported sandbox does **not** establish full parity. Every row needs a Godot implementation location plus recorded verification before `VERIFIED`. The subsystem log records partial work separately from accepted rows.

Status vocabulary: `NOT_STARTED`, `IMPLEMENTED`, `VERIFIED`, `DEFERRED_ITERATION_2`. `IMPLEMENTED` requires complete code for the row but has not passed full acceptance. A partial subsystem is recorded in the evidence log while the row remains `NOT_STARTED`. When a requirement is intentionally adapted for the browser or new multiplayer stack, record the decision in an ADR and link it in the row; do not silently remove the row.

Iteration 1 delivers the offline client and local authoritative rules, including a testing mode that exposes all original weapons, tools, team appearances and player states without a server. Iteration 2 delivers multiplayer. Rows marked `1+2` require offline behavior in iteration 1 and synchronized behavior in iteration 2.

## Player and combat

| ID | Feature and acceptance requirement | Original evidence | Iteration | Status |
| --- | --- | --- | --- | --- |
| P01 | First-person movement, yaw/pitch, world collision and map boundaries | `Sources/Client/Player.cpp:349,991,1108`; `Client_Scene.cpp` | 1+2 | NOT_STARTED |
| P02 | Jump, crouch, standing clearance, sneak, sprint, diagonal normalization, step climbing | `Player.h:36`; `Player.cpp:100,991,1099,1108,1213` | 1+2 | NOT_STARTED |
| P03 | Water wading, air/ground/water friction, fall slowdown and damage feedback | `Player.cpp:978,1084,1160`; `PhysicsConstants.h:28`; `Client_Update.cpp:589` | 1+2 | NOT_STARTED |
| P04 | 100 HP, hurt direction/screen feedback, death, respawn timer and resupply | `Player.cpp:66,286,370,1290`; `HurtRingView.cpp`; `Client_Draw.cpp:228,266,591` | 1+2 | NOT_STARTED |
| P05 | Team 0, team 1, spectator; names and colors supplied by match state | `World.h:51`; `Player.h:146`; `NetClient.cpp:1192`; `LimboView.cpp:56` | 1+2 | NOT_STARTED |
| P06 | Complete articulated soldier model: standing/crouching, walking/sprinting, arms, head, death and intel carrier | `ClientPlayer.cpp:725,803,875,909,941,947,969` | 1+2 | NOT_STARTED |
| P07 | First-person viewmodel + third-person tool/weapon models for every item | `ClientPlayer.cpp:224-258`; `Resources/Scripts/Skin/` | 1+2 | NOT_STARTED |
| P08 | Rifle, both 0.75 and 0.76 tuning profiles | `Weapon.cpp:200,284,373` | 1+2 | NOT_STARTED |
| P09 | SMG, both 0.75 and 0.76 tuning profiles | `Weapon.cpp:227,317,373` | 1+2 | NOT_STARTED |
| P10 | Shotgun, 8 pellets, interruptible per-shell reload, both tuning profiles | `Weapon.cpp:254,345,373`; `Weapon.cpp:78,161` | 1+2 | NOT_STARTED |
| P11 | Ammo/stock, firing cadence, dry fire, magazine reload, resupply, depleted-item selection rules | `Weapon.cpp:48,76,86,161`; `Player.cpp:1398,1408` | 1+2 | NOT_STARTED |
| P12 | Aim down sights, half spread, crouch recoil reduction, viewmodel sway/bob and gun recoil | `Player.cpp:558,754`; `Client_Input.cpp:435`; `ClientPlayer.cpp:412,443` | 1+2 | NOT_STARTED |
| P13 | Distinct head/torso/arm/leg hit volumes, occlusion and horizontal hit range | `Player.cpp:542,1316`; `World.cpp:WeaponRayCast`; `PhysicsConstants.h:55` | 1+2 | NOT_STARTED |
| P14 | Spade primary melee/single-block damage and secondary three-block vertical dig | `Player.cpp:816,856,1250`; `NetClient.cpp:1142` | 1+2 | NOT_STARTED |
| P15 | Grenades: stock, pull pin, cook, throw/drop on death, inherited velocity, bounce, water and explosion | `Player.cpp:136,492,783`; `Grenade.cpp:49,63,82`; `NetClient.cpp:1156` | 1+2 | NOT_STARTED |
| P16 | Weapon/team switching, all four tool hotkeys, wheel and last-tool selection | `LimboView.cpp`; `Client_Input.cpp:53,471,513,576`; `Player.cpp:1387` | 1+2 | NOT_STARTED |

## Voxel world and modes

| ID | Feature and acceptance requirement | Original evidence | Iteration | Status |
| --- | --- | --- | --- | --- |
| W01 | Read genuine VXL maps at 512×512×64 with correct colors and solid interior | `GameMap.h:45`; `GameMap.cpp:519` | 1 | IMPLEMENTED |
| W02 | Efficient voxel rendering, world collision, surface hit raycast and minimap projection | `GameMap.cpp:162,177,361`; `Sources/Draw/GLMapRenderer.cpp`; `MapView.cpp` | 1 | NOT_STARTED |
| W03 | Single-block placement, valid adjacent location, stock use, overlap/range restrictions and cursor feedback | `Player.cpp:161,379`; `World.cpp:281`; `ClientPlayer.cpp` | 1+2 | NOT_STARTED |
| W04 | Right-button drag line, cube-line ordering, stock limit and invalid-line feedback | `Player.cpp:173`; `World.cpp:CubeLine`; `NetClient.cpp:1167` | 1+2 | NOT_STARTED |
| W05 | Delayed block placement while jumping; cancel after landing or loss of stock | `Player.cpp:436` | 1+2 | NOT_STARTED |
| W06 | Palette selection and eyedropper capture from existing map block | `PaletteView.cpp`; `Client_Input.cpp:374,534` | 1 | NOT_STARTED |
| W07 | Block health, weapon/spade damage and 10-second recovery of damaged surviving blocks | `Player.cpp:674,917`; `World.cpp:96,191` | 1+2 | NOT_STARTED |
| W08 | Dig removes vertical 3 cells; grenade removes 3×3×3; bedrock rules match baseline | `NetClient.cpp:1122`; `World.cpp:328` | 1+2 | IMPLEMENTED |
| W09 | Unsupported structures detach, fall as clusters, collide and generate fragments/sounds | `GameMapWrapper.cpp`; `World.cpp:281`; `FallingBlock.cpp`; `Client_LocalEnts.cpp` | 1+2 | NOT_STARTED |
| W10 | Save/export edited map as VXL | `GameMap.cpp:93`; `Client_Input.cpp:562`; `Client_Draw.cpp:TakeMapShot` | 1 | IMPLEMENTED |
| M01 | CTF: bases/intel, pickup, carrier, drop, capture, scores/capture limit, winner and round reset | `CTFGameMode.h`; `CTFGameMode.cpp:PlayerHasIntel`; `NetClient.cpp:1192,1427,1447,1461`; `Client_NetHandler.cpp:121` | 1+2 | NOT_STARTED |
| M02 | TC: neutral/owned territories, contested capture progress, ownership, winner and round reset | `TCGameMode.h`; `TCGameMode.cpp:47`; `NetClient.cpp:1367,1398`; `TCProgressView.cpp` | 1+2 | NOT_STARTED |
| M03 | Local authoritative offline rules for health, damage, respawn, restock and objectives | No offline server in original; client relies on `NetClient.cpp:919,1295,1482` | 1 | IMPLEMENTED |
| M04 | Match reset restores map and all objective/player/resource state | Original reset/map change driven by `NetClient.cpp:1348` | 1+2 | NOT_STARTED |

## Presentation, UI and content

| ID | Feature and acceptance requirement | Original evidence | Iteration | Status |
| --- | --- | --- | --- | --- |
| U01 | Main menu, profile/player name, startup/loading/disconnect/error feedback | `Resources/Scripts/Gui/MainScreen/`; `Gui/StartupScreen/`; `Client_Draw.cpp:185,211,852` | 1+2 | NOT_STARTED |
| U02 | Limbo team/weapon chooser, pause menu, setup and return-to-game | `LimboView.cpp`; `Resources/Scripts/Gui/Client/Menu.as` | 1 | NOT_STARTED |
| U03 | HUD: HP, clip/stock, block/grenade stocks, crosshair, hit indicator, reload/cook states | `Client_Draw.cpp:393,446,764`; `ClientPlayer.cpp:Draw2D` | 1 | NOT_STARTED |
| U04 | Minimap + large map, scale/zoom, coordinate grid, players, teams, bases/intel/territories | `MapView.cpp:172,178,239,549,585`; `Client_Input.cpp:536` | 1+2 | NOT_STARTED |
| U05 | Scoreboard, team score, players/kills, spectator list and match result messages | `ScoreboardView.cpp`; `CenterMessageView.cpp`; `Client_NetHandler.cpp` | 1+2 | NOT_STARTED |
| U06 | Kill feed, alerts, hurt overlay, names under crosshair and TC progress bar | `ChatWindow.cpp`; `HurtRingView.cpp`; `TCProgressView.cpp`; `Client_Draw.cpp:288,675,790` | 1+2 | NOT_STARTED |
| U07 | Global/team chat, input history and scrollable log; offline event log for test sessions | `Resources/Scripts/Gui/Client/ChatSayWindow.as`; `FieldWithHistory.as`; `ChatLogWindow.as` | 1+2 | NOT_STARTED |
| U08 | Free spectator, first/third-person following, dead-player camera and third-person debug view | `ClientCameraMode.h`; `Client_Scene.cpp`; `Client_Input.cpp:327` | 1+2 | NOT_STARTED |
| U09 | Rebind controls; mouse sensitivity/exponent/invert; ADS hold/toggle and ADS sensitivity | `Client_Input.cpp:44-88`; `Resources/Scripts/Gui/Preferences.as:673` | 1 | NOT_STARTED |
| U10 | Persist player profile, control bindings, graphics/audio/game preferences in browser storage | `Sources/Core/Settings.cpp`; `Resources/Scripts/Gui/Preferences.as` | 1 | NOT_STARTED |
| U11 | Audio: spatial shots, reload/dry-fire, impacts, footsteps/water, grenade/collapse and objective/UI feedback | `Client_Update.cpp`; `Client_NetHandler.cpp`; `Resources/Scripts/Skin/` | 1 | NOT_STARTED |
| U12 | Effects: blood, shell ejection, muzzle flash, tracers, fragments, smoke, grenade water/land effects and camera shake | `Client_LocalEnts.cpp`; `Corpse.cpp`; `GunCasing.cpp`; `Tracer.cpp`; `Client_Update.cpp:51` | 1 | NOT_STARTED |
| U13 | Original map objects, soldier parts, weapon/tool models, UI textures and audio converted with provenance | `ClientPlayer.cpp`; `Client_Scene.cpp:546`; resource packs cited by `README.md:104` | 1 | NOT_STARTED |
| U14 | Lighting, shadows, fog, water animation and flashlight | `Client_Scene.cpp`; `Client_Input.cpp:564`; `Resources/Scripts/Gui/StartupScreen/ConfigViewTabs.as:184,213` | 1 | NOT_STARTED |
| U15 | Optional graphics: AA, GI, HDR, blur, bloom, lens flare, color correction, depth of field, SSAO, particle quality | `Resources/Scripts/Gui/StartupScreen/ConfigViewTabs.as:112-177`; `Sources/Draw/` | 1 | NOT_STARTED |
| U16 | Screenshot/sceneshot capture and download, HUD hide and statistics | `Client_Input.cpp:558`; `Client_Draw.cpp:63-75,889`; `SceneDefinition.cpp` | 1 | NOT_STARTED |
| U17 | Existing localization messages, fonts/glyph coverage and selectable locale | `Resources/Locales/`; `Sources/Gui/Main.cpp:576`; `Fonts.cpp` | 1 | IMPLEMENTED |
| U18 | Mod/resource override contract and first/third-person skin extension points | `Sources/Core/FileManager.cpp`; `Sources/Gui/Main.cpp`; `Resources/Scripts/Reference/Skin/`; `ScriptBindings/ScriptManager.cpp` | 1 | NOT_STARTED |
| U19 | Audio volume and positional audio choices adapted to browser-supported facilities | `Resources/Scripts/Gui/StartupScreen/ConfigViewTabs.as`; `Sources/Audio/`; `MumbleLink.cpp` | 1 | NOT_STARTED |

## Required testing mode and web release

These are additions required by the user, rather than features to discover in the original.

| ID | Feature and acceptance requirement | Original evidence / contract | Iteration | Status |
| --- | --- | --- | --- | --- |
| T01 | Start testing mode directly without creating, configuring or joining a server | User requirement; local authority implements M03 | 1 | VERIFIED |
| T02 | Select rifle, SMG, shotgun plus spade/block/grenade at any time; resupply and unlimited-resource toggle | Original items P08–P16 + user requirement | 1 | NOT_STARTED |
| T03 | Inspect both team soldier appearances, standing/crouching/moving/dead/intel states and all tool animations | Original P05–P07; no separate hero roster exists | 1 | NOT_STARTED |
| T04 | Spawn/reset stationary and moving targets; report head/torso/limb/melee damage, kills and respawn | Original hit volumes P13 + user requirement | 1 | NOT_STARTED |
| T05 | Select 0.75/0.76 tuning; switch offline sandbox, CTF and TC; inspect/reset objectives | Original P08–P10/M01/M02 + user requirement | 1 | NOT_STARTED |
| T06 | Load a genuine original-format map, reset destruction, inspect performance and save edited VXL | W01/W10 + user requirement | 1 | NOT_STARTED |
| B01 | Reproducible pinned Godot web export and CI build | New port requirement | 1 | NOT_STARTED |
| B02 | GitHub Pages deployment, correct subpath/resources, HTTPS and browser startup | User delivery requirement | 1 | VERIFIED |
| B03 | Browser playtest: input/pointer lock, audio activation, fullscreen, reload/settings and graphics stability | New web platform requirement | 1 | NOT_STARTED |
| B04 | Publish source, license notices and resource provenance with build | `LICENSE`; original file headers; separate resource inventory | 1 | NOT_STARTED |

## Multiplayer iteration

| ID | Feature and acceptance requirement | Original evidence / replacement contract | Iteration | Status |
| --- | --- | --- | --- | --- |
| N01 | Browser-compatible transport, lobby/join/reconnect and disconnect/error handling | Replacement for `NetClient.cpp:395,430,476` | 2 | NOT_STARTED |
| N02 | Authoritative server, player movement prediction/reconciliation and remote interpolation | Replacement for world/input/position packets in `NetClient.cpp:815,878,1592` | 2 | NOT_STARTED |
| N03 | Server validation for shots, hit zones, ammo/cadence, melee, grenades and lag compensation | Original `NetClient.cpp:1759`; server rules are outside OpenSpades | 2 | NOT_STARTED |
| N04 | Synchronized block edits/collapse and snapshot + subsequent deltas for joining clients | Original `NetClient.cpp:1122,1167,1348`; `World.cpp:281` | 2 | NOT_STARTED |
| N05 | Teams, respawn/restock, CTF/TC objectives, wins, score and round/map resets | Original `NetClient.cpp:1192,1295,1367,1427,1482` | 2 | NOT_STARTED |
| N06 | Chat, server event log, scoreboard, spectator and team/weapon changes | Original `NetClient.cpp:1323,1505,1512,1775` | 2 | NOT_STARTED |
| N07 | Server discovery/list, sorting/filtering/favorites or an explicitly documented replacement | `Resources/Scripts/Gui/MainScreen/ServerList.as`; `MainScreenUI.as` | 2 | NOT_STARTED |
| N08 | Dedicated server packaging, configurable match/map, deployment, capacity and reconnect tests | New multiplayer backend requirement | 2 | NOT_STARTED |
| N09 | Document original Ace of Spades compatibility decision; new transport is authorized but compatibility must be explicit | Original ENet 0.75/0.76 in `NetClient.cpp:395`; user permits different multiplayer engine | 2 | NOT_STARTED |

## Evidence rules and release gates

Each row is accepted only after recording: implementation file(s), verification command or playtest scenario, result/date and any behavior difference with a linked ADR. Generated resource counts are not proof that animation, appearance or sound behavior matches. Passing parser/import checks is not proof of browser playability.

Iteration 1 release gate: all iteration-1 and offline portions of `1+2` rows verified, with any agreed platform adaptation explicitly documented; T01–T06 and B01–B04 verified; deployed URL tested. Iteration 2 release gate: multiplayer portions verified, two independent browser clients tested against deployed server, including join-after-destruction and reconnect.

## Subsystem evidence log

2026-10-10: `game/gameplay/local_session.gd` implements local session state, both source weapon tuning profiles, ammo/cadence/reload, stocks, grenade cook/fuse events, target damage/respawn, team/spectator state and local CTF/TC rules. `tests/session/test_session.gd` exercises these contracts headlessly on Godot 4.7.2. This supports the simulation portions of P04/P05/P08–P11/P13/P15/P16/M01–M03/T02/T04/T05; it does not verify their input, models, sound, visual feedback or browser integration. Rows remain unaccepted until those checks are recorded.

Command: `.tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/session/test_session.gd`. Result is recorded after each relevant change in the session handoff; source constants are covered separately from authored offline melee/grenade/respawn/objective policy.

2026-10-10: `tools/build.py --export` passes world30, VXLsave19, falling/water21, session65, actual-scene integration94, presentation504, localization76 and effects3217 checks with zero failures, followed by parser/runtime/export success. Implementations and remaining visual/input differences are detailed in source-audit.md, voxel.md and assets.md. These support partial P01–P16/W02–W09/UI/test-lab work without accepting those entire rows. W01/W08/W10/M03/U17 are implemented; their browser and presentation acceptance remains pending.

2026-10-10, T01/B02: `game/ui/lab_hud.gd` enters `game/main.gd`'s `LocalSession` directly. Public HTTPS startup, original shotgun selection and entry into the rendered local FPS lab were exercised at https://gordey328.github.io/Blockfield/ using source `5d367dfafab5524c1f4c572218fb6a0605ec9c42`, Pages bundle `128f0059f686f14602ee669de1ba44cb75279b45`. No server creation/join flow is involved. GitHub Pages reports build `built` with no error. This verifies startup/publication and local entry for that revision; it does not verify mouse capture, audio or subsequent feature changes. Branch-publication adaptation: decisions/0003-pages-publication.md.
