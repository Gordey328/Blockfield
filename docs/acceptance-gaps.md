# Iteration 1 acceptance gap audit

Read-only code/source review, 2026-10-10. Scope: the remaining `NOT_STARTED` U/T/B rows in `docs/parity.md`, against the live workspace and pinned OpenSpades v0.1.3. This report does not change the ledger, establish browser acceptance or assume a running export contains newer workspace edits. Main/HUD were being integrated during the review; fixes already visible below are identified explicitly.

## Concrete remaining code gaps

| Priority / row | Actual missing behavior | Evidence / smallest useful fix |
| --- | --- | --- |
| P1 — U15 | Native HDR luminance adaptation and brightness-pyramid bloom are absent. LDR tone mapping exposes no HDR exposure state or native auto-exposure parameters. | Native `Sources/Draw/GLSettings.cpp:42–46`, `GLAutoExposureFilter.cpp`, `GLBloomFilter.cpp`; port `game/presentation/post_color.gdshader:14,110–114`, `openspades_post_effects.gd:11,116,163`. Implement a dedicated HDR/exposure path and its meaningful dynamic-light tests, or retain an explicitly accepted renderer replacement with this loss visible. A renamed checkbox cannot close the gap. ADR0004 already accurately describes it. |

The HDR gap in this audit has since been implemented by `hdr_scene_viewport.gd`, `hdr_exposure.gd` and the source dust-bloom shaders, connected in main/HUD/console. Numeric37/0, actual GPU30/0, WebGL30/0 and actual-main GPU63/0 cover radiance above1, temporal adaptation, original bloom, pre-tone correction, camera restoration, resize/MSAA and visible weapon/HUD/depth effects. HDR remains optional with bounded pyramid sizes and the documented renderer ordering/calibration differences in ADR0004. Integrated release/browser acceptance remains pending; this earlier finding is no longer an absent function.

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
| U15 | Incomplete | AA, indirect light, blur, bloom, lens, correction, focus/DoF, SSAO and quality paths exist. The native HDR component remains absent as stated above. |
| U16 | `IMPLEMENTED` | Main `screenshot`, `_show_web_export`, `web/exports.js`; HUD screenshot/sceneshot buttons and key actions, `set_capture_visible`, hidden-HUD preference and FPS/memory/chunk/draw-call display. PNG/user-click export is the documented browser adaptation; desktop file-open failure is now reported correctly. |
| T03 | `IMPLEMENTED` | Soldiers tab chooses both teams, standing/crouch/walk/sprint/dead/intel states and every weapon/tool. `_build_target_preview_controls` adds aim, reload stage, grenade cook, spade action/progress, block color and shot previews; `LabSoldier`/`SpectatorView` consume these states. Local first-person tools remain playable. Previews explicitly produce no authority damage or audio. |
| T06 | `IMPLEMENTED` | World tab and main expose genuine Title.vxl, uploaded VXL, current-map baseline reset and edited VXL save. `VoxelWorld.encode_vxl`, HUD performance display and visible browser export link implement the row. Actual browser download/reimport remains a verification task. |
| B03 | No remaining absent fullscreen function after the fix; keep browser acceptance pending | Capture input is routed through HUD controls and Godot; browser audio is supplied by the exported engine. Fullscreen, export dialogs, preference storage and graphics paths are implemented. The historical deployed Chromium pointer-lock failure remains unresolved evidence until a current exported build is tested successfully. A parser or desktop GPU run cannot accept this row. |

B01 and B04 are already `IMPLEMENTED`: the pinned engine/bootstrap/export/test workflow, frozen Git-archive release and license/provenance packaging exist. B01's Actions run is externally blocked before steps by account billing; ADR0003 documents the repeatable local-validation/Pages-branch replacement. B02 and T01 retain their recorded revision-specific `VERIFIED` evidence; it does not validate subsequent changes.

## Remaining acceptance work, separate from missing functions

- The coherent HUD handoff was followed by a successful full `test_source_parity.gd` run: **151 assertions, 0 failures**, process exit 0, with no warnings, script errors or leaked-resource diagnostics in `.cache/logs/selection-source-parity.log`. This includes selection-cancellation regressions and sprint activation based on previous native horizontal speed `.1`. The coordinator still needs the final import and remaining registered suites for the release snapshot.
- Export the exact committed snapshot and verify pointer capture/release/re-entry, audible shots/head-hit/chat/beep-off, fullscreen enter/exit/error feedback, scene screenshot visibility/download, edited VXL download/reimport, resource-pack upload/error, and reload of saved profile/bindings/UI/graphics/audio.
- Exercise the optional effects on the exported browser and record the actual renderer substitutions and remaining HDR gap. Correct stale prose in `docs/ui.md` that still says cvar completion, menu/notification sounds and log export are unported; code now contains them.

The review deliberately does not invent server creation, remote chat recipients, AI combat or old AoS protocol compatibility as iteration-1 requirements. Multiplayer rows remain iteration 2.
