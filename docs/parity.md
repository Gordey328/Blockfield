# OpenSpades → Godot feature parity

Baseline: OpenSpades `v0.1.3`, commit `dcf449c845d509bbde9d79239b32d201c1389961`, audited 2026-10-10. Source is pinned under `.cache/openspades`; paths below are relative to that checkout. [Pinned source](https://github.com/yvt/openspades/tree/dcf449c845d509bbde9d79239b32d201c1389961).

This is the acceptance ledger for the full port. An exported sandbox does **not** establish full parity. Every row needs a Godot implementation location plus recorded verification before `VERIFIED`. The subsystem log records partial work separately from accepted rows.

2026-10-12 first game UI delivery: [ADR0030](decisions/0030-game-shell-and-offline-launch.md)
and [evidence](game-ui-first-delivery.md) add lightweight Home, curated map/loadout
selection, actual session-owned launch and saved selection. Frozen912adec includes
shell415/0, launch38/0, the108-run gate and actual public Web checks. U01/U02/U10
remain IMPLEMENTED; this authored UI addition does not accept full source parity
or physical-phone ergonomics/performance.

2026-10-12 optimization branch: [ADR0027](decisions/0027-quality-preserving-web-optimization.md)
and [evidence](web-max-optimization.md) cover P06/P10/P13/W02/W09 and existing UI
and corpse presentation, preserving quality/rules. Independent ordered-collapse,
live-pellet and exact corpse-state fixtures validate the optimization contracts.
Full-row acceptance and statuses below are unchanged; component CPU savings do
not establish whole-game or physical-phone performance.

The user subsequently approves removal of corpse physics on this branch.
[ADR0028](decisions/0028-static-death-models.md) records the explicit static-model
presentation deviation and its verification contract. Authoritative death/respawn
rules and existing body retention remain; no full-row status is promoted.

Status vocabulary: `NOT_STARTED`, `IMPLEMENTED`, `VERIFIED`, `DEFERRED_ITERATION_2`. `IMPLEMENTED` requires complete code for the row but has not passed full acceptance. A partial subsystem is recorded in the evidence log while the row remains `NOT_STARTED`. When a requirement is intentionally adapted for the browser , record the decision in an ADR and link it in the row; do not silently remove the row.

Iteration 1 delivers the offline client and local authoritative rules, including a testing mode that exposes all original weapons, tools, team appearances and player states without a server. The user cancelled iteration2 on2026-10-12; only offline behavior is required. Historical networking measurements below remain evidence for their original revisions, not current code or pending acceptance.

## Current NexQuake mobile checkpoint1c046655fef2

Clean source1c046655fef23dcf46257dc10649d345ec4256d0 is merged into main and
published as bundle83ce7fa206d7f4e602fff2a01dfe0071e32d6b11. All85 native
behavioral/latency checks, import/smokes/export and30 exported actual-Main touch
assertions passed. Normal local/public mobile movement/look/fire were exercised;
public artifacts independently match SHA256. All other production game files match
the completed922f230 optimization source. Physical-phone comfort and complete-row
acceptance remain open; no status rows promoted. [Evidence](nexquake-mobile-camera.md).

## Earlier mobile FPS checkpoint31c513d0aa18

The earlier checked [Pages](https://gordey328.github.io/Blockfield/) release identified clean source31, bundle
`e28bfddd165209defbc388e398c9fc35d5bfae84`; public PCK SHA256 matches the checked export
(`7be6d3864fe75fa089082d0b4ad4cf1c99f350940ff1284b9592af675a0356bd`). Full79 behavioral/
latency checks, import/smokes/export passed on3c; subsequent exact UI-only diffs
repeated affected checks. Final31 import, controls2381/0, Main/HUD272/0,
touch-look/settings144/0, runtime and Web export passed. This is a validation chain,
not a claim that every suite reran on31. The compatible57 server/Docker prerelease
remains unchanged. Earlier57 original-map, CTF/chat and browser multiplayer evidence
belongs to that revision. Row statuses remain bound to full requirements; phone,
browser downloads/audio/fullscreen/effects/performance, Linux/container/public-WSS
and sustained32-client acceptance remain open. See [status](status.md) and
[acceptance gaps](acceptance-gaps.md).

Mobile FPS update (2026-10-10) supports existing movement/tool/UI paths without
promoting complete parity rows: immutable per-ID absolute look history, linear
touch/ADS gain, floating stick, primary fire-and-look, persistent settings,
56CSSpx minimum buttons and readable captions. Native and final public landscape/
portrait/small-screen evidence, plus hardware limits, are recorded in
[mobile controls](mobile-controls.md) and [ADR0008](decisions/0008-mobile-fps-input.md).

## Player and combat

2026-10-11 input adaptation: held primary-button camera look now applies to all
six item selections (rifle/SMG/shotgun/spade/block/grenade), per
[ADR0018](decisions/0018-all-tool-primary-look.md). Native/exported browser
evidence is recorded in [mobile controls](mobile-controls.md); this does not
promote full P01/P08–P16 or W03 acceptance.

| ID | Feature and acceptance requirement | Original evidence | Iteration | Status |
| --- | --- | --- | --- | --- |
| P01 | First-person movement, yaw/pitch, world collision and map boundaries | `Sources/Client/Player.cpp:349,991,1108`; `Client_Scene.cpp` | 1 | IMPLEMENTED |
| P02 | Jump, crouch, standing clearance, sneak, sprint, diagonal normalization, step climbing | `Player.h:36`; `Player.cpp:100,991,1099,1108,1213` | 1 | IMPLEMENTED |
| P03 | Water wading, air/ground/water friction, fall slowdown and damage feedback | `Player.cpp:978,1084,1160`; `PhysicsConstants.h:28`; `Client_Update.cpp:589` | 1 | IMPLEMENTED |
| P04 | 100 HP, hurt direction/screen feedback, death, respawn timer and resupply | `Player.cpp:66,286,370,1290`; `HurtRingView.cpp`; `Client_Draw.cpp:228,266,591` | 1 | IMPLEMENTED |
| P05 | Team 0, team 1, spectator; names and colors supplied by match state | `World.h:51`; `Player.h:146`; `NetClient.cpp:1192`; `LimboView.cpp:56` | 1 | IMPLEMENTED |
| P06 | Complete articulated soldier model: standing/crouching, walking/sprinting, arms, head, death and intel carrier; optimization branch uses approved static death model ([ADR0028](decisions/0028-static-death-models.md)) | `ClientPlayer.cpp:725,803,875,909,941,947,969` | 1 | IMPLEMENTED |
| P07 | First-person viewmodel + third-person tool/weapon models for every item | `ClientPlayer.cpp:224-258`; `Resources/Scripts/Skin/` | 1 | IMPLEMENTED |
| P08 | Rifle, both 0.75 and 0.76 tuning profiles | `Weapon.cpp:200,284,373` | 1 | IMPLEMENTED |
| P09 | SMG, both 0.75 and 0.76 tuning profiles | `Weapon.cpp:227,317,373` | 1 | IMPLEMENTED |
| P10 | Shotgun, 8 pellets, interruptible per-shell reload, both tuning profiles | `Weapon.cpp:254,345,373`; `Weapon.cpp:78,161` | 1 | IMPLEMENTED |
| P11 | Ammo/stock, firing cadence, dry fire, magazine reload, resupply, depleted-item selection rules | `Weapon.cpp:48,76,86,161`; `Player.cpp:1398,1408` | 1 | IMPLEMENTED |
| P12 | Aim down sights, half spread, crouch recoil reduction, viewmodel sway/bob and gun recoil | `Player.cpp:558,754`; `Client_Input.cpp:435`; `ClientPlayer.cpp:412,443` | 1 | IMPLEMENTED |
| P13 | Distinct head/torso/arm/leg hit volumes, occlusion and horizontal hit range | `Player.cpp:542,1316`; `World.cpp:WeaponRayCast`; `PhysicsConstants.h:55` | 1 | IMPLEMENTED |
| P14 | Spade primary melee/single-block damage and secondary three-block vertical dig | `Player.cpp:816,856,1250`; `NetClient.cpp:1142` | 1 | IMPLEMENTED |
| P15 | Grenades: stock, press-edge pin pull, cook, manual/forced throw distinction, drop on death, inherited velocity, bounce, water and explosion | `Player.cpp:136,147-159,492,783`; `Grenade.cpp:49,63,82`; `NetClient.cpp:1156` | 1 | NOT_STARTED |
| P16 | Weapon/team switching, all four tool hotkeys, wheel and last-tool selection | `LimboView.cpp`; `Client_Input.cpp:53,471,513,576`; `Player.cpp:1387` | 1 | IMPLEMENTED |

## Voxel world and modes

| ID | Feature and acceptance requirement | Original evidence | Iteration | Status |
| --- | --- | --- | --- | --- |
| W01 | Read genuine VXL maps at 512×512×64 with correct colors and solid interior | `GameMap.h:45`; `GameMap.cpp:519` | 1 | IMPLEMENTED |
| W02 | Efficient voxel rendering, world collision, surface hit raycast and minimap projection | `GameMap.cpp:162,177,361`; `Sources/Draw/GLMapRenderer.cpp`; `MapView.cpp` | 1 | IMPLEMENTED |
| W03 | Single-block placement, valid adjacent location, stock use, overlap/range restrictions and cursor feedback | `Player.cpp:161,379`; `World.cpp:281`; `ClientPlayer.cpp` | 1 | IMPLEMENTED |
| W04 | Right-button drag line, cube-line ordering, stock limit and invalid-line feedback | `Player.cpp:173`; `World.cpp:CubeLine`; `NetClient.cpp:1167` | 1 | IMPLEMENTED |
| W05 | Delayed block placement while jumping; cancel after landing or loss of stock | `Player.cpp:436` | 1 | IMPLEMENTED |
| W06 | Palette selection and eyedropper capture from existing map block | `PaletteView.cpp`; `Client_Input.cpp:374,534` | 1 | IMPLEMENTED |
| W07 | Block health, weapon/spade damage and damaged-block darkening; permanent damage replaces source recovery by user request ([ADR0010](decisions/0010-persistent-block-damage.md)) | `Player.cpp:674,917`; `World.cpp:96,191`; `Sources/Draw/GLMapChunk.cpp:247-252` | 1 | IMPLEMENTED |
| W08 | Dig removes vertical 3 cells; grenade removes 3×3×3; bedrock rules match baseline | `NetClient.cpp:1122`; `World.cpp:328` | 1 | IMPLEMENTED |
| W09 | Unsupported structures detach; user-accepted simplified sampled falling groups without collisions/debris, retained completion feedback (ADR0025) | `GameMapWrapper.cpp`; `World.cpp:281`; `FallingBlock.cpp`; `Client_LocalEnts.cpp` + user replacement2026-10-11 | 1 | IMPLEMENTED |
| W10 | Save/export edited map as VXL | `GameMap.cpp:93`; `Client_Input.cpp:562`; `Client_Draw.cpp:TakeMapShot` | 1 | IMPLEMENTED |
| M01 | CTF: bases/intel, pickup, carrier, drop, capture, scores/capture limit, winner and round reset | `CTFGameMode.h`; `CTFGameMode.cpp:PlayerHasIntel`; `NetClient.cpp:1192,1427,1447,1461`; `Client_NetHandler.cpp:121` | 1 | IMPLEMENTED |
| M02 | TC: neutral/owned territories, contested capture progress, ownership, winner and round reset | `TCGameMode.h`; `TCGameMode.cpp:47`; `NetClient.cpp:1367,1398`; `TCProgressView.cpp` | 1 | IMPLEMENTED |
| A01 | User addition: offline TDM 3×3 on Crossroads, five active bots, cover/flanks, score/time finish and restart | User 2026-10-11; ADR0020; original game/ai and OfflineTDMSession; [native/Web/Pages evidence](offline-tdm.md), smooth Web FPS remains open | 1 | VERIFIED |
| A02 | User addition: finite zombie survival, timed waves/growth, random detour/breach, elevated destruction, separate damage, grenadiers and small adapted levels, supplies/outcomes/retry | User2026-10-12; ADR0032–0034; frozen1630770 selected25/parser/export, source maps10/0, real levels34/0 with12alive cap, grenade66/0, GPU rig95/0, local desktop Web both imports, built Pages/public30 SHA-match; [expansion evidence and timing limits](survival-expansion.md); accepted survival maps are Crossroads/Minecraft Chunk/MIRA HQ; public/mobile UI repeats excluded by user; physical-phone FPS remains open | 1 | VERIFIED |
| M03 | Local authoritative offline rules for health, damage, respawn, restock and objectives | No offline server in original; client relies on `NetClient.cpp:919,1295,1482` | 1 | IMPLEMENTED |
| M04 | Match reset restores map and all objective/player/resource state | Original reset/map change driven by `NetClient.cpp:1348` | 1 | IMPLEMENTED |

## Market-oriented addition

| ID | Feature and acceptance requirement | Evidence | Iteration | Status |
| --- | --- | --- | --- | --- |
| A03 | Blockfield Rush: canonical three-minute survival, one-click Home/replay, kill-based run upgrades and per-weapon local records | User2026-10-12; [ADR0035](decisions/0035-market-oriented-rush.md); frozen3dd42ab/parser/export; Rush850/0, UI274/0, records13/0, real scene66/0; ordinary local/public start/fire/pause/results and controlled Web card render/input/freeze; built Pages/public30 SHA-match; [evidence and limits](rush-iteration.md). Physical phone, full-duration manual win, retention/market fit and portal acceptance remain separate | Market iteration | VERIFIED |
| A04 | Twenty original weapons/tools, bombs and stratagems, real effects and loadout | User2026-10-12; [plan](arsenal-plan.md), [ADR0036](decisions/0036-authored-arsenal.md), [individual evidence](arsenal-evidence.md); frozen a8545ca:17 suites/import/export; all20 desktop/synthetic-touch, Rush/AI/card/replay, bounded world/pools; public30SHA256 and real Pages input/crater. Physical phone/full port remain separate | Arsenal addition | VERIFIED |
| A05 | Optional full authored inventory and mouse-wheel selection | User2026-10-13; [ADR0037](decisions/0037-full-arsenal-wheel.md), [evidence](full-arsenal-evidence.md); fd4cfef13 suites/import/smoke/Web export; all21 wheel entries/wraps, finite resources and mode/records/pending/replay gates; real desktop/synthetic-touch headers; built Pages30SHA256/public button/wheel. Physical phone/full port remain separate | Arsenal option | VERIFIED |

## Presentation, UI and content

| ID | Feature and acceptance requirement | Original evidence | Iteration | Status |
| --- | --- | --- | --- | --- |
| U01 | Main menu, profile/player name, startup/loading/disconnect/error feedback | `Resources/Scripts/Gui/MainScreen/`; `Gui/StartupScreen/`; `Client_Draw.cpp:185,211,852` | 1 | IMPLEMENTED |
| U02 | Limbo team/weapon chooser, pause menu, setup and return-to-game | `LimboView.cpp`; `Resources/Scripts/Gui/Client/Menu.as` | 1 | IMPLEMENTED |
| U03 | HUD: HP, clip/stock, block/grenade stocks, crosshair, hit indicator, reload/cook states | `Client_Draw.cpp:393,446,764`; `ClientPlayer.cpp:Draw2D`; user-selected modern visual replacement [ADR0022](decisions/0022-modern-combat-ui.md), mobile layout/input addition [ADR0023](decisions/0023-mobile-thumb-layout-and-aim-friction.md), state/input evidence [UI](ui.md) | 1 | IMPLEMENTED |
| U04 | Minimap + large map, scale/zoom, coordinate grid, players, teams, bases/intel/territories | `MapView.cpp:172,178,239,549,585`; `Client_Input.cpp:536` | 1 | IMPLEMENTED |
| U05 | Scoreboard, team score, players/kills, map-linked player ID colors, spectator list and match result messages | `ScoreboardView.cpp:278,291-298`; `CenterMessageView.cpp`; `Client_NetHandler.cpp` | 1 | IMPLEMENTED |
| U06 | Kill feed, alerts, hurt overlay, names under crosshair and TC progress bar | `ChatWindow.cpp`; `HurtRingView.cpp`; `TCProgressView.cpp`; `Client_Draw.cpp:288,675,790` | 1 | IMPLEMENTED |
| U07 | Global/team chat, input history and scrollable log; offline event log for test sessions | `Resources/Scripts/Gui/Client/ChatSayWindow.as`; `FieldWithHistory.as`; `ChatLogWindow.as` | 1 | IMPLEMENTED |
| U08 | Free spectator, first/third-person following, dead-player camera and third-person debug view | `ClientCameraMode.h`; `Client_Scene.cpp`; `Client_Input.cpp:327` | 1 | IMPLEMENTED |
| U09 | Rebind controls; mouse sensitivity/exponent/invert; ADS hold/toggle and ADS sensitivity | `Client_Input.cpp:44-88`; `Resources/Scripts/Gui/Preferences.as:673` | 1 | IMPLEMENTED |
| U10 | Persist player profile, control bindings, graphics/audio/game preferences in browser storage | `Sources/Core/Settings.cpp`; `Resources/Scripts/Gui/Preferences.as` | 1 | IMPLEMENTED |
| U11 | Audio: spatial shots, reload/dry-fire, impacts, footsteps/water, grenade/collapse and objective/UI feedback | `Client_Update.cpp`; `Client_NetHandler.cpp`; `Resources/Scripts/Skin/` | 1 | IMPLEMENTED |
| U12 | Effects: blood, shell ejection, muzzle flash, tracers, fragments, smoke, grenade water/land effects and camera shake; accepted50 noncolliding particles/simple casings (ADR0025), approved static bodies on optimization branch ([ADR0028](decisions/0028-static-death-models.md)) | `Client_LocalEnts.cpp`; `Corpse.cpp`; `GunCasing.cpp`; `Tracer.cpp`; `Client_Update.cpp:51` + user replacement2026-10-11/12 | 1 | IMPLEMENTED |
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

## Retired multiplayer requirements

N01–N09 (transport/join, prediction/server, lag compensation, map replication,
remote teams/objectives, chat/scoreboard, discovery, server deployment and old
protocol compatibility) are withdrawn by the user's 2026-10-12 instruction.
They have no active implementation or acceptance status. The original rows and
pre-removal evidence are retained in the
[historical ledger](history/multiplayer-before-removal.md); see
[ADR0031](decisions/0031-offline-only-game.md). Local rules, objectives, equipment,
HUD and human-plus-five-bot combat remain within the offline scope.

## Evidence rules and release gates


Each row is accepted only after recording: implementation file(s), verification command or playtest scenario, result/date and any behavior difference with a linked ADR. Generated resource counts are not proof that animation, appearance or sound behavior matches. Passing parser/import checks is not proof of browser playability.

Iteration 1 release gate: all iteration-1 and offline portions of `1+2` rows verified, with any agreed platform adaptation explicitly documented; T01–T06 and B01–B04 verified; deployed URL tested. The multiplayer gate is withdrawn under ADR0031.

## Subsystem evidence log

2026-10-11 user-approved W07 replacement: automatic HP/color recovery removed
under ADR0010. Frozen4c051639e286 retains damage across long idle and respawn;
joining/reconnecting clients receive a flagged damage baseline plus bounded
tint-only loading hits. Genuine edits/reset clear the old incarnation. Controller194/0,
Match226/0, MapTransfer1186/0, Runtime223/0, actual socket/Main damage42/0,
mesh31/0 and exported Main Web11/0 passed. All81 registered behavioral/latency
checks are covered on this frozen source through the documented validation chain;
initial import/controller failures and their successful repeats are preserved.
Web and matching server exports/PCK smoke passed. Public Pages source4c05163,
bundle db3932405f3f, metadata/HTML/PCK hash-match; matching server ZIP downloaded
and verified. W07 stays IMPLEMENTED: this accepts the user's permanent-damage
replacement and does not claim full W07/port/public-multiplayer acceptance.
[Evidence and limits](persistent-block-damage.md).

2026-10-10 authorized three-gap repair: W07 cosmetic mask uses exact source integer
RGB halving without changing VXL/minimap/occupancy/collision/journal; offline and
confirmed network adapters own recovery and edit/reset cleanup (ADR0009). World
mesh31/0 and actual native sockets/Main damage32/0 passed. Source/controller189/0
and session166/0 cover effective grenade edges, held automatic throw, manual-only
cooldown, pin minimum and temporary input denial. UI284/0 and native GPU23/0 cover
actual ID glyph colors, live/saved option and canonical network IDs. Damage GPU5/0
changed10,568 pixels and recovered with zero pixel difference. Lab119/0,
mobile2381/0, touch-look144/0, network controller511/0 and shared rules144/0 passed.
W07/U05 return to IMPLEMENTED; full row/browser acceptance is still separate.
P15 stays partial/NOT_STARTED because the separate shared raw-button cooldown
gate remains open, documented in acceptance-gaps. Logs `.cache/logs/fidelity-*`;
Frozen validation chain0898d6c→dcee15f completed, with test-only07b3a1b audio cleanup;
actual exported WebGL probe8/0 checked darkening/recovery, grenade holds and ID colors.
Public dcee15f metadata/HTML/PCK match bundle812b316. Regular local/public scenes
were exercised with preserved mobile controls and Title.vxl. This evidence accepts
the three specific repairs, not every feature in these rows. [Fidelity evidence](fidelity-repairs.md).

2026-10-10 discussion-only fidelity audit: W07/P15/U05 have partial implementations
and are returned to NOT_STARTED under this ledger's complete-code rule. This does
not erase their recorded passing subsystem checks. W07 lacks surviving-hit terrain
darkening; block-recovery tests assert occupancy, not color. P15 offline input can
start another cook while primary remains held after forced release, and its release
helper always adds a0.5s cooldown; the shared network rules already preserve the
source press edge and automatic/manual distinction. The same offline paths were
confirmed in published source96 with git show. U05 omits the native per-player ID
palette link to the minimap when that option is enabled. All three are source/code
findings, not new browser reproductions. Documented terrain-interior/water/debris,
audio and extension adaptations are separate from these omissions. See
[fidelity audit](acceptance-gaps.md#discussion-only-fidelity-audit-2026-10-10).
No game/test/export changes or engine runs were made for this audit.

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

2026-10-11, U01/B01/B02: Web startup adds actual downloaded/total decimal MB from
Godot's existing progress callback and exported WASM/pack sizes. Parser/import,
normal export and throttled browser download/start pass. Frozen4a522ce repeats
parser/import, runtime smoke and Web export; Pages56bbc6f0 is built/hash-verified,
with public12.3→53.7/63.3MB, overlay removal and offline entry checked. Full-row
U01/B01 statuses stay IMPLEMENTED. Commands/artifacts: [ADR0017](decisions/0017-web-download-progress.md).

2026-10-11, W02/W07/U11/U12: continued warmed Title optimization batches unchanged
world units without per-column packed ownership overhead, skips identity particle
work/hidden statistics scans and predecodes49 original Opus clips to source-native
PCM16. PCM523/0, environment76/0 and deterministic fragment44/0 pass; frozen
19c4d51c73db repeats all89 registered native behavioral/latency invocations,
parser/import and normal Web export. Three gesture-activated
actual-Main browser pairs remove24 original Title cells each: baseline shoot
p95103.1/114.1/119.8ms, candidate46.6/46.7/45.9ms; mean instrumented script CPU
per shot−9.1%, idle CPU/realsecond−20.3%. Mixer/GPU/host and rare63.9ms frames are
explicit. Normal clean source19c4d51c73db is published as Pages bundle836f49c0;
public metadata/six-file hashes, Title/SMG terrain destruction, magazine/reload
and Verification render/input pass without public engine warnings/errors.
Full-row status stays IMPLEMENTED. Frozen normal release evidence and
exact commands/artifacts belong in [Title evidence](title-impact-performance.md)
and [ADR0016](decisions/0016-impact-cpu-batching.md).

2026-10-11, W02/W07/U12: terrain-hit optimization on b3e29b38c573 updates
surviving-hit color attributes in place and budgets staged geometry with atomic
mesh/collider publication. Minimap uploads follow changed image revisions;
batched-fragment substeps mirror their hidden nodes once per frame. Native
RGB4441/0, minimap37/0 and fragment29/0 cover the new contracts; CPU first-hit
cost and destructive peak slices fall substantially, with14–15% residual median
aggregate destruction overhead. Three actual-Main Web wall repeats lower p95,
but rare stalls remain and the shallow Title case does not improve overall.
No whole-row/device acceptance is implied; rows remain IMPLEMENTED. Commands,
frozen release and browser limits: [impact evidence](block-impact-performance.md),
[ADR0015](decisions/0015-budgeted-block-impact-rendering.md).

2026-10-11, U11/U12: the user's distant-blast report leads to an explicit shorter
grenade/collapse camera and grenade dry/wet audio range under
[ADR0019](decisions/0019-grenade-feedback-range.md). It supersedes the original
near-distance saturation contract below. Rules, world scale and particle sizes
stay unchanged; rows remain IMPLEMENTED. [Current evidence](grenade-feedback.md).

2026-10-11, U12: repair16f1e70 introduces bounded prewarmed effect pools and one
fragment MultiMesh draw, retains native emission counts/near-distance grenade
saturation, culls vibration beyond170 units, and consumes actual elapsed lifetime
during long frames. Matching headless effects32588/0 (3 explicit GPU readback skips),
native Compatibility32591/0 and camera45/0; frozen16 import/presentation504/0,
extensions68/0, lab119/0, lifecycle19/0, mobile-look144/0/runtime/Web export passed.
Actual-Main WebGL held-SMG wall scenario reached87 draw calls versus baseline571
with the same512 particle cap;5/80/180-unit grenade states match source attenuation
and cutoff. Browser throttling/concurrent work prevent controlled FPS acceptance.
Alpha fragment sorting is a documented batch adaptation; other particle simulation,
audio and terrain costs remain. U12 stays IMPLEMENTED. Exact hashes, commands,
failure/correction records and release handoff: [effects performance](effects-performance.md),
[ADR0011](decisions/0011-effect-pools-and-fragment-batching.md).

2026-10-11 optimization item4 evidence: bounded exact audio/tint caches and
cooperative private VXL jobs/browser staging are checked on frozen66e4b5b7eb89.
All85 registered native behavioral/latency checks, parser/runtime/Web/server
export and PCK smoke pass; separate corrected Web PCM113/0+DSP64/0 and production
JS lifecycle3/3 pass. Actual exported Main cancel/restart/save handled input;
downloaded VXL bytes equal raw input or the unchanged synchronous encoder.
Normal local/public browser rendered lab and Title, with movement/tools and
the existing pointer-lock drag fallback. Public metadata/HTML/JS/WASM/PCK and
server ZIP hashes match the frozen artifacts. This adds partial W01/W10/T06/
U11/U13 evidence; these rows remain IMPLEMENTED. It does not establish controlled
FPS/phone/RSS/subjective audio, Linux/Docker/TLS execution or full-port acceptance.
Failures, fixture correction, residual reset/COW stalls and commands:
[optimization item4](optimization-audio-vxl-memory.md),
[ADR0013](decisions/0013-audio-vxl-memory.md).
