# Mobile controls

Touch controls are an input presentation layer for the existing source movement/tool rules. `game/ui/mobile_controls.gd` owns finger claims and emits action, movement, look and menu signals; `LabHUD` owns their connection to the player and global Godot input. Neither the overlay nor its buttons grant local authority in a network session.

Settings → Mobile controls offers Auto/On/Off, saved as `[ui] touch_controls` in
`user://settings.cfg`. Auto detects native touch availability/platforms, coarse
browser pointers and small touch screens, with first-touch fallback. On also
enables a desktop mouse preview; Off restores the desktop scale and mouse input.
The mobile canvas expands from 854×480 landscape or 480×854 portrait to fill the
actual viewport. Menus use larger buttons/dropdown rows, wrapping text and two
columns in portrait; HP/ammo remain in the footer and the minimap clears both
toolbar rows. The read-only original block palette sits beside the minimap,
above the action buttons; select block colors through the Arsenal color picker.
[ADR0007](decisions/0007-mobile-controls.md) records the decision.

## Contract

`BlockfieldMobileControls.setup(player, hud)` accepts null HUD/player for isolated component use. `set_enabled`, `release_all`, `handle_touch` and `handle_drag` are the public lifecycle/input APIs. `get_hit_regions()` returns a copied dictionary of local logical-pixel rectangles: `move`, `look`, `primary`, `secondary`, `jump`, `crouch`, `sprint`, `reload`, four `tool_*` buttons, `map`, `view_toggle`, and `menu`.

Public touch indices must be nonnegative. Nonfinite coordinates/deltas are rejected. The real `_input` adapter converts viewport positions and deltas through the inverse canvas transform before using those same handlers. Touch-generated emulated mouse events are consumed while the overlay is active, avoiding a second mouse attack/look path. A forced desktop overlay supports its own mouse pointer over the designated controls/look area.

The joystick rectangle is 160×160 logical pixels, radius 62, radial deadzone 0.12. Outside the deadzone, strength is remapped across the remaining 0.88; diagonal magnitude stays at most 1. Negative Y means forward. The controller clamps finite `touch_movement`, rejects nonfinite values and combines it with physical-key movement through `get_source_movement_axis()`; offline and network input use that shared axis.

Exactly one finger owns the stick and one owns look. Additional touches on either region are consumed without stealing control. Each button counts its finger owners and emits only the first press/last release. Dragging out releases that button, while preserving the finger's original claim; dragging back can repress it. A button/stick finger cannot become look, and an unclaimed drag cannot rotate the camera. Look ownership survives movement across another control's rectangle.

Touch up/cancel releases that finger. `release_all`, disable, viewport resize, application/window focus loss and pause clear every claim, held action and movement vector. Pressing menu releases all controls before emitting `menu_requested`. The player permission gate also releases ownership when controls become disabled; Main/HUD owns menu/chat detection and the auto/on/off preference.

## Layout and bridge

Buttons are at least 60×60 logical pixels, with separate movement/look areas and a 52-pixel bottom HUD reserve. The top toolbar splits into two rows below 492 logical pixels of width. Required logical layouts include 960×540, 854×480 and 480×854; the component also supports raw 844×390. Root's viewport policy can expand a physical 844×390 phone into a taller logical canvas. Geometry checks establish usable hit targets and separation; they do not establish rendered text readability on a physical display.

HUD connects `action_changed` to `Input.parse_input_event(InputEventAction)`, preserving the existing controller's press/release edges for reload, selection and ADS. `movement_changed` updates `player.touch_movement`; `look_moved` calls `apply_mouse_motion`; menu opens the existing HUD menu. Deactivation must release overlay-owned actions before other global input cleanup. Networking remains `NetworkSession` → shared prediction → authenticated commands → authoritative Runtime, with unchanged wire/rule limits.

## Reproducible regression

The new repository-root fixture is `tests/ui/test_mobile_controls.gd`, run from the Godot game project:

```powershell
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path game --script res://../tests/ui/test_mobile_controls.gd
```

It exercises production public handlers and a real transformed `InputEventScreenTouch` adapter, three simultaneous fingers, shared-button counts, drag ownership, deadzone/strength, malformed coordinates, every advertised action, disable/resize/focus/pause/menu cleanup and finger reuse. Real viewport-dispatched mouse events cover stick, button and designated-look claims, outside release and emulated-mouse suppression. It then instantiates a real `BlockfieldPlayer` with source-query terrain and local session, checking actual movement, firing, weapon-only reload, selection and mouse-look handoff. A separate real loopback Runtime/Replica pair checks the same touch movement/fire/release through both WebSocket channels. Only presentation skin/audio are replaced with inert test dependencies; authority, motion, prediction, protocol and sockets are production code.

The fixture creates only missing InputMap actions, releases its held actions and removes only those new mappings on exit. It starts/stops its own ephemeral loopback listeners. It never instantiates Main, reads/writes preferences, requests a GPU/audio device, or changes networking limits. Network waits have 10-second deadlines; fixed steps yield to real wall time rather than manufacturing input timestamps.

Godot 4.7.2 `--check-only` passed. The command above passed **808 assertions, 0 failures**, exit 0, with no engine/resource errors; process wall time was 5.857 seconds. Artifact: `.cache/logs/mobile-controls-final.log`. The real loopback handoff used production profile 0.75 and unchanged network limits, with no input rejection or stale retirement. Assertion counts include bounded runtime steps and may vary with scheduling; the mandatory gesture/controller assertions remain fixed.

Two fixture issues were corrected before that pass: synchronous reads preceded buffered `InputEventAction` delivery, and the headless physical window was 64×64 despite a 1280×720 logical viewport. The fixture now flushes/yields input as a frame does, and uses `Viewport.push_input(event, true)` to dispatch logical pointer coordinates through the real production `_input` adapter. Initial failing logs are retained under `.cache/logs/mobile-controls-*`; they do not establish a production failure. No production files were edited by the fixture author.

The separate actual Main/HUD suite in `tests/ui/test_ui.gd` passed270/0 on frozen
`96c36cdc740d19a9ab9c32928482dff06b76cade`: real
overlay mouse dispatch, Jump without accidental primary input, action/stick/look
bridges, saved mode, menu/chat/focus cleanup, desktop scale/mapping restoration,
single-row ammo and palette separation from the controls/minimap.
That fixture preserves preferences byte-for-byte on normal completion.

The registered checks were completed as a frozen validation chain, preserving
the initial scene-epoch fixture failure separately. Successful unchanged
prefix62 from876 was combined with affected UI and every remaining registered
check on310, including scene-epoch170/0, mobile808/0, shaped latency483/0,
runtime/server-launcher smoke and Web export. Exact presentation-only follow-ups
verified the diff, repeated import/UI/runtime/export, and repeated mobile808/0
on0c51; final96 changed only palette placement and one UI assertion. All final
diagnostics were clean. Validation manifests and logs are under
`.cache/release-{876a9828067e,31028524ad3b,0c51c5bae956,96c36cdc740d}`.
Unchanged generated asset imports were reused and revalidated by the engine in
the final placement follow-up. This is a chain of evidence, not a claim that
all suites were rerun on96. Full reproduction in a fresh checkout:

```text
python tools/release_checkpoint.py --revision 96c36cdc740d19a9ab9c32928482dff06b76cade
```

Local final exported Web views at844×390 and390×844 displayed the overlay/menu;
forced-On mode survived reload. The shared mobile input moved the rendered
player, rotated the view and switched to blocks. Both final orientations showed
palette/minimap/toolbar/action separation and the single-row footer.
These browser gestures use the desktop mouse fallback. Physical phone touch,
OS keyboard/safe-area behavior and hardware performance remain unverified.

## Public artifact

[Pages](https://gordey328.github.io/Blockfield/) publishes clean96 source, bundle
`e5c246c8f1135b54b69fa64bea19aae8403d7de0`; GitHub reports built/no error.
Public HTML/PCK downloaded independently match the local final export. PCK
SHA256: `fc22a7eb53ff460c5d9849d8b2cabec4b38483d2ae7cd6b387fa463a91fdf3fc`.
The existing57 server is compatible by unchanged network/simulation files and
network-4 IDs; no new server package was produced for this input-only update.

Actual Pages desktop-mouse preview: On persisted after reload; stick moved the
rendered player and right drag turned the camera. Fire changed10/50→9/50;
Jump kept9/50; reload displayed a separate readable progress row and completed
at10/49. Portrait block selection displayed the palette beside the minimap
above all six action buttons. Returning to Auto restored desktop layout.
Temporary test tabs/HTTP servers were closed and the viewport override reset.
Screenshots/report: `.cache/previews/public-mobile-96c36cdc740d.{jpg,json}` and
`.cache/previews/public-mobile-portrait-96c36cdc740d.jpg`.

## Research 2026-10-10

The user reports jitter when moving the joystick and looking with another finger.
This turn is research/documentation only: implementation, new tests, skill installation
and a new release wait for the user's next instruction. Root owns the investigation;
no specialist or engine lease was opened. The agent has not reproduced physical-phone
multitouch. Device/browser and offline/network comparison were requested but are pending.

### Findings and confidence

Current `MobileControls._input` converts `InputEventScreenDrag.relative` into local
canvas coordinates and passes it through `handle_drag`. `_drag_pointer` correctly
accepts camera motion only from the claimed LOOK owner. Each claim currently stores
kind/action/holding, without a previous position. HUD forwards `look_moved` to
`PlayerController.apply_mouse_motion`, including the existing mouse sensitivity,
exponent and weapon zoom/ADS policy. The controller suppresses its desktop mouse
path while mobile controls are active.

[Godot issue94346](https://github.com/godotengine/godot/issues/94346) reports a closely
matching Web failure: another touch corrupts a tracked finger's relative motion while
its absolute position stays correct. The linked [PR94899](https://github.com/godotengine/godot/pull/94899)
proposes indexing previous positions by touch ID; both pages showed Open when inspected.
The issue's minimal FPS reproduction includes a position-difference workaround. Its
single shared previous-position example is insufficient for our multi-owner contract.

This is not only an older-version report: the pinned [Godot Web C++ source at ed1daf0bf](https://raw.githubusercontent.com/godotengine/godot/ed1daf0bf/platform/web/display_server_web.cpp)
sets the event index from `identifier[i]`, but computes its relative motion from
`touches[i]` (lines688-718). The matching [JavaScript adapter](https://raw.githubusercontent.com/godotengine/godot/ed1daf0bf/platform/web/js/libs/library_godot_input.js)
passes `changedTouches` (lines550-565), whose list slots need not represent the same
finger between events. This proves a vulnerable data path in the referenced source;
the actual phone's event trace is still required to establish the user's complete cause.

[Issue116465](https://github.com/godotengine/godot/issues/116465) additionally reports
Android Chrome mouse-motion events despite disabled touch-to-mouse emulation, plus
inflated screen-relative touch motion in Godot4.6. Our overlay already rejects marked
emulated mouse events and requires a mouse claim for mouse dragging, so this report
does not establish duplicate camera processing in Blockfield. Keep that as a secondary
trace check; a real touch and a desktop preview must not rotate through two input paths.

### Practices and code references

- Preserve one movement owner, one look owner and independent action owners for the
  whole down-to-up/cancel lifetime; crossing rectangles must not change a finger's role.
  [ScreenTouch](https://docs.godotengine.org/en/stable/classes/class_inputeventscreentouch.html)
  documents finger index/cancellation. Existing Blockfield ownership/lifecycle behavior
  already implements most of this contract.
- A proposed Web workaround stores previous absolute position per claimed finger,
  initializes it on down, subtracts only that finger's previous position on drag and
  clears it on release/cancel/resize/focus/menu. Use one coordinate space for both
  positions; an unclaimed/reused ID must never inherit another finger's baseline.
- [ScreenDrag documentation](https://docs.godotengine.org/en/stable/classes/class_inputeventscreendrag.html)
  recommends `screen_relative` for aiming because `relative` is content-scaled.
  Merely replacing one field with the other does not fix the pinned Web path: it copies
  the same computed displacement into both. Evaluate normalization by screen extent
  after rebuilding the displacement from owned positions.
- [Apple game-control guidance](https://developer.apple.com/design/human-interface-guidelines/game-controls)
  recommends left-side movement, right-side direct camera dragging, generous input areas,
  reachable buttons, safe areas, visible press states and frequent targets at least44pt.
  Its floating-stick recommendation is useful as an option; retain the current fixed
  layout for comparison. Native points, CSS pixels and our logical canvas pixels are
  different units: inspect rendered hit targets on the real device.
- [Virtual-Joystick-Godot source](https://github.com/MarcoFazioRandom/Virtual-Joystick-Godot/blob/Main/addons/virtual_joystick/virtual_joystick.gd)
  demonstrates remembered touch index, absolute-position stick updates, radial deadzone
  remapping and fixed/dynamic/following modes (MIT). Its global action press/release and
  desktop-emulation policy are examples to review, not drop-in replacements for our bridge.
- The official [VirtualJoystick node](https://docs.godotengine.org/en/stable/classes/class_virtualjoystick.html)
  also offers these modes. Its documentation warns that node and InputMap deadzones can
  stack. Changing joystick implementation alone would not repair camera displacement.
- Unity's [OnScreenStick isolated actions](https://docs.unity3d.com/Packages/com.unity.inputsystem@1.14/api/UnityEngine.InputSystem.OnScreen.OnScreenStick.html#UnityEngine_InputSystem_OnScreen_OnScreenStick_useIsolatedInputActions)
  prevent cancellation caused by automatic device switching. The transferable principle
  is stable, separate input ownership; this is not a Godot setting or a fix for issue94346.
- [MDN touch-action](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/touch-action)
  explains browser gesture cancellation and game-surface `touch-action: none`.
  The frozen96 exported HTML already contains that rule, so missing CSS is not the
  primary candidate. Avoid introducing another DOM touch listener without evidence.

### Proposed starting settings (not accepted device-tuned values)

| Area | Proposed baseline |
|---|---|
| Stick | Retain radius62 and radial deadzone0.12 initially; expose roughly0.10-0.15 for comparison, with only one deadzone stage. |
| Stick placement | Fixed/dynamic choice, adjustable size and thumb position; following mode optional. |
| Look | Linear response, separate mobile sensitivity; a candidate calibration is a swipe across30% of screen width giving about90 degrees of yaw. Normalize delta and extent in the same coordinate space. |
| ADS | Keep existing weapon-zoom reduction initially, extra mobile ADS multiplier1.0; tune separately without accidentally applying the same reduction twice. |
| Smoothing | Off for diagnosis. Only evaluate optional light target-angle smoothing after eliminating malformed/duplicate displacement and measuring latency. |
| Actions | Configurable hold/toggle ADS and accessible fire placement; verify move/look/fire together before adding compound fire-and-look gestures. |
| Input batching | Compare default accumulated input with disabled accumulation only if traces show a remaining latency problem. [Godot Input](https://docs.godotengine.org/en/stable/classes/class_input.html#class-input-property-use-accumulated-input) documents the CPU/reactivity tradeoff. |

### Skills

Discovery used the system skill-installer workflow; its anonymous curated-catalog
request returned HTTP403. Selected candidates were inspected directly at the already
pinned GodotPrompter revision, rather than assuming catalog availability.

- [input-handling](https://github.com/jame581/GodotPrompter/blob/1e7d79d3cbbd6fd8016cd9cc77c6a79f342ea218/skills/input-handling/SKILL.md):
  input propagation, touch index and input actions. Its [basic touch reference](https://github.com/jame581/GodotPrompter/blob/1e7d79d3cbbd6fd8016cd9cc77c6a79f342ea218/skills/input-handling/references/touch.md)
  uses `relative` and is not a complete mobile FPS controller or a workaround for this bug.
- [responsive-ui](https://github.com/jame581/GodotPrompter/blob/1e7d79d3cbbd6fd8016cd9cc77c6a79f342ea218/skills/responsive-ui/SKILL.md):
  stretch/aspect/DPI/layout checks. Verify native safe-area recipes separately for Web.
- Existing `gdscript-patterns`, `godot-testing`, `blockfield-port-parity` and
  `blockfield-web-release` cover implementation, regression, evidence and eventual release.
  Keep the current test runner; discovery is not a reason to replace it with GUT/gdUnit.
- Native `mobile-development`/`godot-platform-mobile` and
  [godot-adapt-desktop-to-mobile](https://github.com/thedivergentai/GD-Agentic-Skills/blob/main/skills/godot-adapt-desktop-to-mobile/SKILL.md)
  contain broader mobile advice. App-store/signing, native renderer recommendations and
  pinch/two-finger rotation gesture helpers are not the browser FPS input contract.
  A future focused `blockfield-mobile-input` skill could record routing/units/acceptance
  procedures; diagnoses and current settings belong here, not in skill instructions.

### Next implementation and acceptance, after the user's instruction

1. Capture timestamp/type/index/device/position/engine-relative/owner and controller
   yaw/pitch, plus frame timing. Compare each relative value with the same ID's absolute
   position difference. Establish whether jitter exists offline and in network play.
2. Add a regression where LOOK position is unchanged but its supplied relative value
   is corrupted while MOVE changes. Verify controller yaw/pitch receives no look motion.
   Also cover simultaneous moving fingers, reversed down order, lift/re-add/ID reuse,
   third-finger fire, rectangle crossings and cancel/focus/orientation cleanup.
3. Implement the minimal owned-position correction and trace-confirmed mouse gating;
   then tune mobile look independently. Motion displacement is not multiplied by frame
   delta a second time. Distinguish view-angle jumps from walk/recoil effects/frame stalls.
4. Run parser/import, existing affected UI/gameplay checks and export. Verify physical
   Android Chrome and iPhone Safari multitouch, both orientations and sustained play;
   desktop mouse preview alone cannot accept the fix. Publish only after authorized work
   reaches the existing release gates. No new build was produced in this research turn.
