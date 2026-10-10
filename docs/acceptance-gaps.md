# Port implementation and remaining acceptance

Updated after the integrated renderer/network/UI handoffs on2026-10-10, against pinned OpenSpades v0.1.3. This report separates implemented code from acceptance evidence. Public57ad43b2b740 includes normalization/network/favorites changes and passed the complete registered frozen suite plus Web/Linux exports. Public metadata and PCK identity were verified separately; these checks do not make the full port complete.

## Discussion-only fidelity audit 2026-10-10

This is a bounded source/code/test audit prompted by missing block damage feedback,
not a complete port certification or a new browser playtest. Root coordinated three
read-only specialists with separate gameplay-feedback, renderer/effects and UI/audio
ownership. No specialist edited files or ran engine/export checks.

Confirmed incomplete requirements:

- **W07 damaged-block appearance:** original `Sources/Draw/GLMapChunk.cpp:247-252`
  halves RGB below100HP. Godot controller `_damage_block` keeps health outside voxel
  RGB; `world/voxel_chunk.gd:rebuild` never consumes it. Original packed color includes
  health; port data packs occupancy plus RGB. `tests/gameplay/test_source_parity.gd:
  test_block_recovery` and `tests/network/test_match_simulation.gd:block_damage`
  test survival/destruction/recovery, not damaged color. No recorded decision removes
  this cue. The connection between simulation state and terrain presentation was missed.
- **P15 offline grenade input:** original `Client/Player.cpp:147-159` begins cooking
  on a press edge; automatic >2.9s release at490-494 does not set manual-release cooldown.
  Godot `gameplay/player_controller.gd:_physics_process` begins cooking while primary
  remains held whenever the session is not cooking. `local_session.gd:release_grenade`
  always adds0.5s cooldown. Holding through forced release can start the next cook;
  an immediate new press is delayed. `simulation/player_rules.gd` and
  `tests/network/test_player_rules.gd:grenade_rules` already distinguish the source cases;
  offline tests do not. These offline paths also exist in published source96
  (`git show 96c36cdc740d19a9ab9c32928482dff06b76cade:<path>`).
- **U05 scoreboard ID color:** native `Client/ScoreboardView.cpp:278,291-298` uses
  the minimap's32-color player palette for #IDs when `cg_minimapPlayerColor=1`.
  `game/ui/lab_scoreboard.gd:_process` gives the whole row one color and does not
  consume the option; HUD settings affect only maps. `ui.md` records authored row
  formatting but no specific decision to omit this identification cue.

W07/P15/U05 are partial and therefore NOT_STARTED under the existing ledger vocabulary.
Passing checks for the implemented portions remain valid; they do not cover these gaps.

Separately, documented differences include fixed hidden-interior earth RGB instead of
native low-bit random variation (`Client/GameMap.cpp:44-46`, `world/vxl_reader.gd:8,42-44`,
`voxel.md:11`);32 strongest spectral modes instead of native full FFT water
(`Draw/GLWaterRenderer.cpp:178-186,517-525`, `world/spectral_wave.gd`, ADR0004);
4096 fragments/1024 smoke per falling cluster and24 active clusters instead of native
six fragments/one smoke per surface block (`Client/FallingBlock.cpp:149-180`,
`world/falling_cluster.gd:27-28,127-142`, `world/voxel_world.gd`, `voxel.md:57`).
These are recorded substitutions, not automatically accepted full-fidelity equivalents.

Next action is a source-driven review of complete player-visible transitions across
simulation, rendering, HUD and audio before implementation/acceptance. Existing renderer
and extension decisions do not explain or authorize the newly confirmed omissions.

## Authorized fidelity repair 2026-10-10

Implementation follow-up: the three specific omissions above are repaired and
published as client dcee15f0b7bc. Native checks, actual exported WebGL probe8/0,
public Title.vxl interaction and exact metadata/HTML/PCK hashes are recorded in
[fidelity evidence](fidelity-repairs.md). Mobile changes are preserved.
World's separate mesh-color mask and offline/confirmed-network expiry are specified
in [ADR0009](decisions/0009-block-damage-presentation.md). Offline grenade input
preserves effective press edges, pin minimum and manual-only cooldown. Scoreboard
IDs consume the existing map palette/preference without changing name/death tint.

The final source review found a separate shared-network grenade gate discrepancy:
`simulation/player_rules.gd:281,312` retains raw previous primary buttons. A new
press held during manual cooldown/tool raising therefore needs another release
and press after the gate opens; source `Player.cpp:136-159` tracks the effective
gated input. The existing shared tests cover holding after automatic throw and
automatic cooldown, but not this extra gate case. It is outside this authorized
offline repair and remains open; P15 stays partial/NOT_STARTED. No network rules
or wire identity changes are included in this client release.

## Implemented HDR and renderer boundary

Optional HDR, native temporal luminance adaptation and pre-tone dust bloom exist in `hdr_scene_viewport.gd`, `hdr_exposure.gd` and their shaders, connected to Main/HUD/console. An actual-scene washout exposed nonlinear Godot3D colors entering linear filters. `hdr_normalize.gdshader` now reverses the pinned Compatibility output transfer exactly once before metering/bloom/gamma; linear2D callers bypass it. Headless **47/0**, native GPU exposure **32/0**, color **79/0** and actual-Main **63/0** cover this contract and visible equipment/HUD/depth, resize/MSAA and camera restoration. Exported WebGL exposure **32/0** and color **79/0** were observed in the actual browser DOM with reported renderer `WebKitWebGL` and `float_color_buffer=true`.

U15 and B03 are `IMPLEMENTED`, not `VERIFIED`. Bounded pyramid sizes, procedural grain, Godot color/lighting calibration, later lens/camera passes, bounded irradiance/water approximations and normalization's extra float target remain documented adaptations in [ADR0004](decisions/0004-compatibility-renderer.md). Isolated HDR browser evidence does not accept integrated Title-map quality, every optional effect, all browsers or sustained performance. See [HDR investigation](hdr-investigation.md).

## Gaps found and already fixed during this review

- **U11 chat notification:** `chat_beep` had settings/console controls but no sound use. Native `Sources/Client/Client.cpp:658–661` plays `Sounds/Feedback/Chat.opus` for received chat. Current HUD now emits `chat_sound_requested` after an ordinary local message; main gates `Feedback/Chat` by `chat_beep`. Console replies bypass the signal.
- **U11 nonlethal head-hit feedback:** native `Client_Update.cpp:984–993` plays feedback for every local head hit. The previous port only played on a kill. Current main connects `player.hit_confirmed` to `Feedback/HeadshotFeedback` when `part == "head"`, using the configured gain, and the kill handler no longer duplicates it.
- **B03 fullscreen:** no user-facing fullscreen path existed at the start of review. Current menu/settings buttons invoke `main.toggle_fullscreen`; `game/web/exports.js:40–42` uses the canvas Fullscreen API and returns rejection text through `_fullscreen_result`. This code exists now; entering/exiting fullscreen in the exported browser still needs acceptance.
- **U01 menu operation feedback:** the previous alert panel lived under the HUD hidden by an open menu. Assets moved it above the menu and added a real-scene visibility assertion; the coherent HUD handoff reports UI **227/0** and native UI GPU **27/0**. Loading, upload and fullscreen errors no longer rely on the user closing the menu before the alert expires.
- **U01/U16 desktop screenshot failure:** main now clears `_capture_pending` and returns an error alert when creating the screenshot file fails, rather than announcing a successful save. The coordinator reports a clean parser check after this change.

These observations are code evidence, not an audible/visual browser pass.

## Row-by-row implementation conclusions

| Row | Complete code / status recommendation | Implementation evidence |
| --- | --- | --- |
| U01 | `IMPLEMENTED` for iteration 1 after the menu overlay fix | Authored lab menu and player-name editor: `lab_hud.gd:_create_menu/_build_settings`. Exported default HTML has startup progress and failure notices (`build/web/index.html:120,202–216`). Main yields a frame before original-map loading and reports parse/upload errors above the menu. Native `Client_Draw.cpp:205–225` draws startup loading; `DrawDisconnectScreen` is empty. Network join/disconnect is the iteration-2 portion, not an absent offline server requirement. |
| U03 | `IMPLEMENTED` | `lab_hud.gd:_process/_update_reticle`, `lab_ammo_strip.gd`, `LocalSession.get_reload_progress`. HP/ammo/stock, all tool resources, native Sight/HitFeedback textures, friendly tint, ADS/follow filtering, reload/cook and depletion prompts are present. |
| U06 | `IMPLEMENTED` | `lab_hud.gd:_update_feed/show_alert/_update_alert/_update_hottracked_name`, `lab_status_effects.gd:show_hurt/_draw/_draw_ring/_draw_tc`. Typed alerts, source hurt sprites/ring, kill/event feed, target names and source-shaped TC bar are implemented. Menu feedback has the fixed U01 overlay path. |
| U08 | `IMPLEMENTED` | `player_controller.gd:_sync_camera_mode/follow_target/_update_camera_transform/_move_free_camera`, `presentation/spectator_view.gd`, `source_camera_effects.gd`, main corpse-center and local third-person skin integration. Free/death/first-/third-person follow and own third-person views all have concrete paths. |
| U11 | `IMPLEMENTED` after the fixes above | `audio/openspades_audio.gd` source weapon layers, reload, flesh/terrain/water impacts and attenuation; controller shot/dry-fire/footstep/jump/land/reload hooks; main grenade/collapse/objective/restock/hurt/head-hit hooks; HUD alert/menu/chat signals. Godot spatial/environmental rendering replaces native audio backends under the documented browser adaptation. |
| U12 | `IMPLEMENTED` | `openspades_effects.gd:blood/block_hit/block_destroy/muzzle_fire/grenade_explosion/_underwater_explosion/water_hit/eject_shell/tracer`, source smoke frame animation, `corpse.gd`, controller `SourceCameraEffects` pose/FOV/radial-post integration. The named effects all exist; bounded particle/proxy budgets remain documented fidelity limits. |
| U15 | `IMPLEMENTED` | AA, bounded indirect light, normalized float HDR/source auto exposure and dust bloom, blur/lens/correction, focus/DoF, SSAO and quality paths are wired. Production helpers and budgets are documented in ADR0004; isolated exported32/0 and79/0 are distinct from full browser renderer acceptance. |
| U16 | `IMPLEMENTED` | Main `screenshot`, `_show_web_export`, `web/exports.js`; HUD screenshot/sceneshot buttons and key actions, `set_capture_visible`, hidden-HUD preference and FPS/memory/chunk/draw-call display. PNG/user-click export is the documented browser adaptation; desktop file-open failure is now reported correctly. |
| T03 | `IMPLEMENTED` | Soldiers tab chooses both teams, standing/crouch/walk/sprint/dead/intel states and every weapon/tool. `_build_target_preview_controls` adds aim, reload stage, grenade cook, spade action/progress, block color and shot previews; `LabSoldier`/`SpectatorView` consume these states. Local first-person tools remain playable. Previews explicitly produce no authority damage or audio. |
| T06 | `IMPLEMENTED` | World tab and main expose genuine Title.vxl, uploaded VXL, current-map baseline reset and edited VXL save. `VoxelWorld.encode_vxl`, HUD performance display and visible browser export link implement the row. Actual browser download/reimport remains a verification task. |
| B03 | `IMPLEMENTED`; full browser acceptance pending | Capture and anchored drag-look fallback, audio activation, fullscreen/error feedback, export dialogs, preferences and graphics paths exist. The historical Chromium pointer-lock failure remains revision-specific evidence; the current full gesture/capture/audio/fullscreen/storage flow still needs acceptance. Isolated WebGL HDR tests cover their filter/color contract only. |

B01 and B04 are already `IMPLEMENTED`: the pinned engine/bootstrap/export/test workflow, frozen Git-archive release and license/provenance packaging exist. B01's Actions run is externally blocked before steps by account billing; ADR0003 documents the repeatable local-validation/Pages-branch replacement. B02 and T01 retain their recorded revision-specific `VERIFIED` evidence; it does not validate subsequent changes.

## Remaining acceptance work, separate from missing functions

- Frozen57ad43b2b740 passed source parity **151/0**, all other registered checks, runtime/server launchers and Web/Linux exports. The first import exited1 without an explanatory engine error; unchanged diagnostic and full retries passed. Logs remain under `.cache/release-57ad43b2b740/.cache/logs/`. Browser and publication evidence are separate from native contracts.
- Export the exact committed snapshot and verify pointer capture/release/re-entry, audible shots/head-hit/chat/beep-off, fullscreen enter/exit/error feedback, scene screenshot visibility/download, edited VXL download/reimport, resource-pack upload/error, and reload of saved profile/bindings/UI/graphics/audio.
- Exercise the integrated optional effects on actual original-map gameplay in the browser, including HDR on/off, lighting/water/depth/lens combinations, resize, ordinary/HDR color comparison and sustained frame/memory cost. The normalization pass adds7.03MiB at1280×720 before depth/MSAA/driver overhead; passing float probes is not a performance result.

## Implemented multiplayer, remaining deployment and play acceptance

Frozen57ad43b2b740 was also checked with two actual local HTTP IAB clients and the same frozen native authority: both73/73 baseline barriers completed, CTF blue/green views rendered, chat reached the second client, and a quick same-actor reconnect returned to gameplay. An earlier resume after the30s grace correctly received HELLO rejection; its artifact is retained. Pre-cleanup admissions3/resumes1/chat1, input_rejections0/map_resyncs0/timeouts0/backpressure0. Files: `.cache/previews/browser-frozen-57-network.{jpg,log,json}` and the separate expired-resume log. A hidden second client showed1FPS while the first showed24–27FPS; this is not capacity/performance acceptance. Offline drag-look, Shotgun6/48 and block palette were observed. IAB reported pointer-lock Chromium UnknownError; fullscreen DOM stayed inactive and automated PNG download timed out despite a valid visible preview/link. Neither public WSS nor the full B03 gesture/export flow is accepted by this evidence.

N01–N08 now have production implementations and corresponding rules/runtime/UI/configuration slices, recorded as `IMPLEMENTED` in [parity.md](parity.md). Native evidence includes runtime **103/0**, Replica **138/0**, real adversarial sockets **392/0**, live/loading epoch reset **722/0** and inherited Main network scene **27/0**. These cover fixed-step ownership, prediction, same-time actor/terrain firearm rewind, baseline plus ordered map/collapse changes, objectives/respawn, confirmed private/public events, chat and same-object reconnect. Server favorites add explicit name/filter/sort/select/save/delete under [ADR0006](decisions/0006-multiplayer-lobby.md); no legacy master service or public host is invented.

The matching [Linux export and Docker/Caddy package](https://github.com/Gordey328/Blockfield/releases/tag/godot-57ad43b2b740) is published and its public ZIP hash verified, with native launcher smoke and local Caddy configuration validation. Docker is unavailable here; Linux/container execution, public DNS/certificate/WSS/Origin/proxy behavior remain unverified and no public multiplayer service has been created. [Deployment instructions](server-deployment.md) record that boundary.

Iteration2 still requires two independent exported browser clients through the chosen public WSS host: join during destruction, event/audio deduplication and private routing, team/class/spectator/follow, CTF/TC wins/automatic rounds, reconnect/reset while joining, and background-tab behavior. Current dirty diagnostic Web PCK `4581f1740b767e459158b29a2c15b42ed12a5f413374eeaac7bea8346600241b` passed partial two-browser/local-native scenarios: both73/73-chunk baselines, CTF rendering, cross-client chat, tool selection, spectator/class/respawn and same-actor reconnect. Four stale commands were retired without execution; no input rejection, heartbeat timeout or backpressure occurred before deliberate cleanup. Two clients showed10–11FPS here; this does not establish acceptable performance. The historical authority3 shaped test intentionally rejected350ms input backlog; authority4 now retires validated stale input up to120 ticks without extending executable history beyond15. See network-latency.md for separately measured revisions. Sustained capacity on original-size maps remains open. The capacity benchmark's zero failures do not establish a32-player60Hz service. Count-bounded codecs/history/transfers can still cause long synchronous pauses. Native loopback and trusted fixture edits are not WAN/browser/capacity acceptance. The user selected Docker/configuration preparation; public DNS/WSS cannot be accepted until a host is selected.

The review deliberately does not invent server creation, remote chat recipients, AI combat or old AoS protocol compatibility as iteration-1 requirements. Multiplayer rows remain iteration 2.
