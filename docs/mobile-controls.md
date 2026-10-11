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
[ADR0007](decisions/0007-mobile-controls.md) records the initial overlay;
[ADR0008](decisions/0008-mobile-fps-input.md) records the mobile FPS update.
[ADR0014](decisions/0014-nexquake-mobile-camera.md) records the selected NexQuake
camera reference and its implementation; [current evidence](nexquake-mobile-camera.md)
distinguishes automated/browser checks from physical-phone acceptance.

The update adds separate touch look/ADS gain and inversion, floating/fixed stick,
fire-and-look and control size, with a reset button. `[input]` stores
`touch_sensitivity` (0.25–3.0), `touch_ads_sensitivity` (0.25–2.0), `invert_touch`;
`[ui]` stores `floating_stick`, `touch_control_scale` (0.8–1.4), `fire_drag_look`,
`left_handed_touch` (default false).
Defaults are gain1, ADS gain1, normal Y, floating stick, size1 and fire-and-look on.

## Contract

`BlockfieldMobileControls.setup(player, hud)` accepts null HUD/player for isolated component use. `set_enabled`, `release_all`, `handle_touch` and `handle_drag` are the public lifecycle/input APIs. `get_hit_regions()` returns a copied dictionary of local logical-pixel rectangles: `move`, `look`, `primary`, `secondary`, `jump`, `crouch`, `sprint`, `reload`, four `tool_*` buttons, `map`, `view_toggle`, and `menu`.

Public touch indices accept the complete signed32 range used by Godot's Web
`Touch.identifier` bridge. Each is normalized with `index & 0xffffffff` before
ownership lookup, keeping native negative IDs distinct from internal mouse/no-owner
markers. Nonfinite coordinates/deltas and out-of-range indices are rejected.
The real `_input` adapter converts viewport positions through the inverse canvas
transform. Each accepted DOWN initializes its owner's absolute-position history;
look uses the difference between this pointer's consecutive positions and ignores
finite engine-relative values. The same rule applies to desktop preview drags.
Touch-generated emulated mouse events are consumed while the overlay is active;
mouse preview is disabled when genuine touch is detected.

The resting joystick has a 160-pixel extent and radius62 at size1. Floating mode
accepts the left40% full-height movement zone, starts neutral under the thumb and keeps its base
fixed for that gesture. Edge-clamped bases retain a grab offset so DOWN is neutral.
Fixed mode retains the resting activation rectangle inside that column. The
right60% accepts look at full height, with buttons taking priority on DOWN.
Left-handed mode mirrors zones, buttons and stick. Radial deadzone0.12 is
remapped once across the remaining0.88; diagonal magnitude stays at most1.
Negative Y means forward. The controller clamps finite `touch_movement` and combines
it with keyboard movement through `get_source_movement_axis()`; offline/network
input use that shared axis.

Exactly one finger owns the stick and one owns look. Additional touches cannot
steal those roles. Ordinary buttons count their owners, emitting the first press
and last release; dragging out releases and re-entry can repress the same action.
Primary fire can claim the free look role at DOWN for a living player in
their own first/third-person view. That composite gesture fires and looks until
UP/cancel, including outside the button. If another pointer already owns look,
primary stays an ordinary button. Rifle, SMG, shotgun, spade, block and grenade
all support this gesture; primary still performs the selected item's existing
action, including grenade cook/throw on release. Spectator selection retains
ordinary action behavior. See [ADR0018](decisions/0018-all-tool-primary-look.md).
Roles never change mid-gesture; look crossing buttons
does not press them, and unclaimed drags cannot rotate the camera.

Touch up/cancel releases that finger. Normal UP retains already queued look;
an engine event with `canceled=true` clears it. Pinned Godot maps browser DOM
`touchcancel` to ordinary UP, so browser cancellation currently releases ownership
without the stronger queued-look cancellation guarantee. `release_all`, disable, viewport resize, application/window
focus loss and pause clear every claim, held action, movement vector and pending
look. Pressing menu releases all controls before emitting `menu_requested`. The
player permission gate also releases ownership when controls become disabled;
Main/HUD owns menu/chat detection and the auto/on/off preference.

## Layout and bridge

Controls respect the size preference and a 56 CSS-pixel Web button floor, derived
from actual canvas bounds and local canvas size. Native/headless fallback is a
logical-pixel floor, not a claim about physical display units. The toolbar and
action grid wrap on narrow canvases; map/palette placement follows actual toolbar
height. Drawn controls retain a 52-pixel bottom HUD reserve; blank movement/look
areas extend to the canvas edge. Required layouts
include960×540,854×480,480×854 and raw844×390, plus size0.8/1.4. Root's expanding
viewport can turn physical844×390 into a taller logical canvas. Geometry checks
do not establish phone text readability or OS safe-area handling.
Button captions and gesture hints retain a12 CSS-pixel font floor, measured only
when laying out. This keeps the smallest controls legible on568×320 without
adding Web interop to the drawing loop.

HUD connects actions to `Input.parse_input_event(InputEventAction)`, preserving
reload, selection and ADS edges. Movement updates `player.touch_movement`; look
calls `queue_touch_motion(delta, overlay.size)`. Both touch axes normalize by the
overlay width: at gain1 a45%-width swipe gives180° before weapon zoom. The next
render/physics boundary consumes displacement once, before command sampling.
Network life changes discard stale queued gestures; orbit refresh retains the
last sampled camera shake without ticking effects again. Touch gain
is independent of mouse exponent/sensitivity/inversion, without frame-time gain
or smoothing. Existing own-view ADS zoom, spectator behavior and pitch bounds
apply. Menu opens the existing HUD menu; deactivation releases overlay actions
before global cleanup. Networking remains the same prediction/authenticated
command/authoritative Runtime path with unchanged wire/rule limits.

## All-item primary look — 2026-10-11

Frozen source `6d61ea9cc26037e3c26553fdfed677dde3cfdc45` changes exactly one
production line compared with `4a522ce`: remove the `Tool.WEAPON` gate in
MobileControls. Godot `4.7.2.stable.official.ed1daf0bf`, upstream
`dcf449c845d509bbde9d79239b32d201c1389961`.

Import/parser, MobileControls3099/0, actual Main/HUD/Player look225/0, UI284/0,
source-input35/0, source-parity194/0, network-controller511/0, camera-target-rays11/0,
grenade17/0, runtime smoke and normal Web export pass. These are the eight affected
suites; the previous complete89-check release is separate evidence, not a new run.
Native userdata was isolated; original project config was restored before normal
import/export. Logs and SHA256 manifest: `.cache/all-tool-look-6d61ea9cc260/`.
The existing Web download-MB shell is retained.

The same new overlay regression against baseline4a fails3099/3, precisely for
spade/block/grenade (`.cache/all-tool-look-red/`). Initial483 Main225/1 bypassed
selection callbacks by directly assigning tool fields; beginning a grenade then
correctly observed the new tool and released the old trigger. Fixtures now use
normal `select_weapon`/`select_tool`; production rules were unchanged. Failed logs
remain under `.cache/all-tool-look-483305092d49/`.

Reproduction commands (bundled Python path is in status):

```powershell
python .cache/all-tool-look-validate.py 6d61ea9cc260 .cache/all-tool-look-483305092d49/game/.godot
python tools/export_mobile_probe.py --source .cache/all-tool-look-6d61ea9cc260 --name all-tool-6d61ea9 --import-cache .cache/all-tool-look-6d61ea9cc260/game/.godot
python -m http.server 8078 --bind 127.0.0.1 --directory .cache
```

Helpers/diagnostics preserve existing result folders; choose a fresh name/path to
repeat. Standard engine checks remain registered in `tools/build.py`. Open the
isolated probe's `build/web/preview.html`, select each orientation, then press
Run DOM touch checks in the real game. At844x390 and390x844,27/0 each (54/0 total)
cover all six selections, held primary outside its button, exact40deg yaw/10deg
pitch, normal release, cancel, independent movement/LOOK, focus/menu and mirroring.
Restored live gameplay also moves4.363/3.858 units and fires2 shots in each run.
Both captured probe warning/error lists are empty. Saved portrait report/screenshot:
`.cache/previews/all-tool-look-portrait.{json,jpg}`.

Ordinary local export visibly enters the lab, enables mobile controls, exercises
rifle/spade/block/grenade Fire drag outside the button and rotates both axes.
An800ms held grenade press releases and visibly throws a projectile; local lab
unlimited stock remains3. Its captured warning/error list is empty; screenshot
`.cache/previews/all-tool-look-normal-local.jpg`. Physical-phone feel remains
untested; this does not promote full parity rows.

Published via the integrated grenade-feedback release:
source `d8e5ddb09d0ff63917d3312a758a2f9f4c584430`, Pages bundle
`2f786bedd3e1c33c41010f382b05b7b37e476ff0`, built/no error. Its MobileControls
source is byte-identical to checked6d. Independently fetched metadata and all six
export files match the integrated frozen export; report
`.cache/previews/all-tool-look-public.json`. Ordinary public lab entry and
spade/block/grenade Fire drags rotate yaw/pitch, with an empty captured warning/
error list. Screenshot `.cache/previews/all-tool-look-normal-public.jpg`.
Input file/engine leases are returned; the own HTTP helper and temporary tabs
are stopped. Full-row/physical-phone acceptance remain open.

## Mobile FPS validation

Godot4.7.2 import/parser passed (`.cache/logs/mobile-fps-import.log`). Actual
Main/Player/HUD integration passed144 assertions/0 failures
(`mobile-fps-look.log`): swipe normalization/event segmentation, own/spectator
camera permissions/pitch bounds, all three ADS zooms, independent desktop gain,
real ScreenTouch/Drag routing, settings/reset callbacks, reload of Main and exact
settings/servers restoration. Registered as `mobile-look` in `tools/build.py`.
Isolated production controls passed2381 assertions/0 failures
(`mobile-fps-controls-final.log`), actual HUD271/0 (`mobile-fps-ui.log`) and source
input35/0 (`mobile-fps-source-input.log`). The first transformed finger-reuse
expectation failed because float32 canvas round trips produced
`(2.000061035,0.999984741)` instead of ideal`(2,1)`, exactly matching the independent
transform calculation with two events. The fixture now checks both event count
and that calculation, with only0.0001px tolerance against the ideal displacement.
No production repair was needed for this fixture issue; initial/diagnostic logs
remain saved. Frozen3c408e818859 passed all79 behavioral/latency checks plus import,
runtime/server-launcher smoke and Web export, with clean engine diagnostics.
Logs/export: `.cache/release-3c408e818859`. Initial exported browser review at844×390,
390×844 and568×320 verified size80/140%, floating movement, look, fire-drag rotation,
tool selection, responsive toolbar/action rows and palette/map separation.
Those browser actions use desktop mouse preview, not physical touch.

Browser review found building feedback overlapping the lower action row at140%.
A placement-only HUD follow-up positions it above the action grid and the look
hint, with an actual HUD regression. Workspace repeat import/HUD272/0/touch-look144/0
and runtime smoke passed (`.cache/logs/mobile-hint-*.log`). Frozen8f04c2240a22 repeated
import/controls2381/0/HUD272/0/touch-look144/0/runtime/export for placement/fonts;
aa6f03e6e23a repeated import/controls/runtime/export for the caption-only follow-up.
Final31c513d0aa18 uses56CSSpx button targets for comfortable thumbs and full12CSSpx
captions. Its frozen import/controls2381/0/HUD272/0/touch-look144/0/runtime/Web export
passed with clean diagnostics and manifest `validation-chain.json`. World/network/
gameplay production files remain unchanged from full-tested3c. The rendered568×320
default-size view shows complete captions and usable hit areas. This chain does not
claim every suite ran again on31. Full fresh-checkout reproduction:

```text
python tools/release_checkpoint.py --revision 31c513d0aa182aaf42db51146b83a7aa22d1cd2c
```

## Current published artifact

[Pages](https://gordey328.github.io/Blockfield/) publishes clean source
`31c513d0aa182aaf42db51146b83a7aa22d1cd2c`, bundle
`e28bfddd165209defbc388e398c9fc35d5bfae84`. Independently downloaded metadata and
HTML match the tested export; PCK SHA256 is
`7be6d3864fe75fa089082d0b4ad4cf1c99f350940ff1284b9592af675a0356bd`
(16,167,776bytes). Report `.cache/previews/public-mobile-fps-31c513d0aa18.json`.
Public844×390/390×844 desktop-preview views exercise movement/look, fire-drag
rotation, block selection, palette/map separation and building feedback clear of
actions; no browser console warnings/errors. Physical-phone multitouch, thumb
feel, safe areas and hardware performance remain unverified.
On mode survived a public reload; public Auto and local touch defaults were
restored after testing. Browser report and landscape/portrait/small screenshots:
`.cache/previews/mobile-fps-31c513d0aa18-browser.json` and the corresponding JPEGs.
Temporary test tabs closed and viewport override reset.

## Previous checkpoint regression

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

## Previous public artifact96

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

Historical research before authorization: current contract/settings/evidence above
supersede its next-step proposal. Device traces and subjective phone acceptance
remain open.

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

## Open-source control candidates — 2026-10-11

The user requested examples and pros/cons before implementation. This is source/document
research against Blockfield HEAD `556c6dce324f1c33817cb182bb50118113195648`, Godot
`4.7.2.stable.official.ed1daf0bf`, and upstream OpenSpades
`dcf449c845d509bbde9d79239b32d201c1389961`. No addon was installed or executed.

| Candidate | Evidence and strengths | Blockfield limitations / suggested use |
| --- | --- | --- |
| [Built-in VirtualJoystick](https://docs.godotengine.org/en/stable/classes/class_virtualjoystick.html) + [TouchScreenButton](https://docs.godotengine.org/en/stable/classes/class_touchscreenbutton.html) | Open-source engine components, not a downloadable FPS template. Fixed/dynamic/following stick, action mapping, deadzone and theme customization; buttons support simultaneous touches. Existence independently confirmed in [the pinned engine source](https://github.com/godotengine/godot/blob/ed1daf0bf/doc/classes/VirtualJoystick.xml). | First component to compare if simplifying our movement UI. Swipe look, fire-and-look, permissions and focus cleanup still need our router. TouchScreenButton inherits Node2D and lacks Control anchors. Preserve separate movement sources instead of allowing stick release to clear keyboard intent. |
| [Virtual Joystick DX](https://github.com/Repechul/Virtual-Joystick-DX/blob/master/addons/virtual_joystick_DX/README.md), MIT | Rich third-party candidate: analog/D-pad, three modes, active regions, skins, configurable action triggers. [Asset entry](https://godotengine.org/asset-library/asset/5256) lists v1.1c, 2026-08-05, Godot4.6+ and author testing on4.7; repository README instead states4.3+. | Not a complete FPS swipe controller. [Core source](https://github.com/Repechul/Virtual-Joystick-DX/blob/master/addons/virtual_joystick_DX/vjdx_core_script.gd) uses simple position/scale conversion and global Input.action_press/release; our expanding canvas, action edges and lifecycle need an adapter. Dynamic base follows the finger rather than staying fixed after DOWN as ours does. Documented haptics are disabled on Web. Best third-party reference for configurable stick UX; browser/device compatibility remains untested here. |
| [MarcoFazio Virtual-Joystick-Godot](https://github.com/MarcoFazioRandom/Virtual-Joystick-Godot), MIT | Small GDScript component with fixed/dynamic/following modes, input actions, deadzone, textures and per-index touch ownership. Asset Library entry lists Godot4.2, v1.6 (2024-08-29). | Movement component only. [Source](https://github.com/MarcoFazioRandom/Virtual-Joystick-Godot/blob/Main/addons/virtual_joystick/virtual_joystick.gd) declares class_name VirtualJoystick, the same name as the pinned engine class: rename/adapt before evaluating on4.7. No integration/parser test was run. Useful simple reference, lower priority than native/DX for this project. |
| [Action Manager](https://github.com/Saulo-de-Souza/Action-Manager), MIT, Godot4.x | Joystick and TouchScreenButton bridge; held, toggle, long-press, repeat and double-press modes. Useful reference for optional sprint/crouch/ADS interaction preferences. | No FPS swipe camera. Mobile-only joystick visibility checks native Android/iOS names, so that option needs Web-aware adaptation. A second input manager could duplicate our HUD events or change weapon edges; take individual button ideas rather than replacing simulation/controller input. |

Additional references reviewed: [selgesel third-person controller](https://github.com/selgesel/godot4-third-person-controller)
(MIT, Godot4 touch movement/camera/buttons; third-person physics and pinch zoom are not
our FPS contract), [HubbleCommand mobile_controls](https://github.com/HubbleCommand/mobile_controls)
(MIT, pan/rotate/scale; floating stick activated by long press), and
[GodotTouchInputManager](https://github.com/Federico-Ciuffardi/GodotTouchInputManager)
(MIT, Godot4 release; global multi-finger gesture classification is unsuitable unmodified
for independent simultaneous move/look/fire roles).

Recommendation is provisional: keep Blockfield's per-ID absolute-position look and
fire-and-look ownership, compare native movement components and DX settings/skins,
and use Action Manager as a button-behavior reference. No architectural replacement
was accepted. All shortlisted alternatives require exported-browser and real-phone
multitouch checks; primary README claims and desktop previews do not establish these.
Research changes only this document and status.md; no parity status, engine, tests,
export, server or published artifact changed.

Camera-settings follow-up: the user clarified that camera rotation is the selection
target. Recommend the existing per-pointer swipe-look layer using native touch events;
DX is the movement-stick reference, not the camera choice. Current HUD already exposes
"Обзор пальцем"25–300%, "Обзор в прицеле"25–200%, Y inversion and fire-and-look.
PlayerController normalizes both axes by overlay width; at gain1 a30%-width swipe
rotates90 degrees before weapon zoom. Independent X/Y gains and optional smoothing
would be new preferences, not existing features. This clarification changed no code;
future physical-phone tuning still requires device evidence.

## Expanded camera reference search — 2026-10-11

The user reports that the current camera still feels poor and explicitly asked for
a refined, concrete reference and a broader search. The prior recommendation to
retain the existing handler is insufficient evidence of comfort and is superseded
by this comparative shortlist. Existing automated checks remain valid for their
recorded behaviors; they do not override this usability report. No defect cause or
comfortable sensitivity has been established on a physical phone in this turn.

Search expanded beyond Godot addons to released Android FPS clients and playable
Web FPS projects. Recommended external UX comparisons are
[Quad Touch](https://play.google.com/store/apps/details?hl=en&id=com.opentouchgaming.quadtouch)
/ [Delta Touch](https://play.google.com/store/apps/details?hl=en&id=com.opentouchgaming.deltatouch);
Xash3D FWGS is the clearest open camera implementation reference. These are research
recommendations, not an accepted replacement architecture or permission to copy assets.
The public [Psi_Touch submodules](https://github.com/emileb/Psi_Touch/blob/main/.gitmodules)
connect the touch library to the author's OpenTouch family; this does not establish
the exact source revision used in current Quad/Delta store binaries.

| Reference | Primary evidence / strengths | Limits for Blockfield |
| --- | --- | --- |
| [Open Touch Gaming / Delta Touch](https://opentouchgaming.com/delta-touch/) and [MobileTouchControls](https://github.com/emileb/MobileTouchControls) | Released mobile FPS applications from the library author; configurable touch HUD. Library revision `b2ea201ed29f84848b4256ad97d3e3bb7c85fa90` exposes relative touchpad and joystick outputs in [TouchJoy.cpp](https://github.com/emileb/MobileTouchControls/blob/b2ea201ed29f84848b4256ad97d3e3bb7c85fa90/TouchJoy.cpp), separate look/turn gains, inversion, movement deadzone, precision shooting and layout editing in [UI_TouchDefaultSettings.cpp](https://github.com/emileb/MobileTouchControls/blob/b2ea201ed29f84848b4256ad97d3e3bb7c85fa90/UI_TouchDefaultSettings.cpp). [License.txt](https://github.com/emileb/MobileTouchControls/blob/b2ea201ed29f84848b4256ad97d3e3bb7c85fa90/License.txt) explicitly states GPLv2. | Android/C++/OpenGL, paid applications, no Godot/Web drop-in. Exact equivalence of current app binaries and published library revision is unverified. TouchJoy contains legacy first-motion suppression, large-delta rejection and pointer-swap heuristics; default multitouch mode can replace an active pointer. Study app interaction and relative touchpad output, do not transplant those heuristics as a fix for Godot. |
| [Xash3D FWGS touch controls](https://github.com/FWGS/xash3d-fwgs/blob/51353ff8d65e58300eeb2bd014867673f1f367c6/Documentation/touch-controls.md) | Independent move/look fingers, separate yaw/pitch gains, optional nonlinear response and precise-look multiplier; editor for button positions/sizes, safe area and saved profiles. [Camera source](https://github.com/FWGS/xash3d-fwgs/blob/51353ff8d65e58300eeb2bd014867673f1f367c6/engine/client/input/in_touch.c#L1844) directly shows owned look displacement and separate axis gain. [Android continuous build](https://github.com/FWGS/xash3d-fwgs/releases/tag/continuous), build4209, published2026-10-09. | C engine / Android, not Web/Godot; Half-Life needs the user's own `valve` resources. Touch source GPL-3.0-or-later. Native normalized coordinates and gain values must be adapted to our coordinate contract. Documentation reverses yaw/pitch labels in one comment; source confirms yaw is horizontal, pitch vertical. Continuous release is a prerelease, not a claim of stable-phone acceptance. |
| [idTech4A++](https://github.com/glKarin/com.n0n3m4.diii4a/releases/tag/v1.1.0harmattan73) | Released Android FPS client, GPLv3, APK release2026-09-30. [Pointer router](https://github.com/glKarin/com.n0n3m4.diii4a/blob/ce49510f3b0c04969eab8ebe8238416e84e4f0bb/Q3E/src/main/java/com/n0n3m4/q3e/Q3EGameButtonHandler.java) keeps target ownership from DOWN to UP/CANCEL; [Button.java](https://github.com/glKarin/com.n0n3m4.diii4a/blob/ce49510f3b0c04969eab8ebe8238416e84e4f0bb/Q3E/src/main/java/com/n0n3m4/q3e/onscreen/Button.java) allows mouse-button drag to keep aiming while firing. In-game HUD editor documented in v71 release. | Requires chosen game resources; Java/C++/Android. Camera sensitivity is partly engine-specific: Doom3 has m_pitch/m_yaw, while Android touch layer sends displacement. Do not conflate gyro X/Y settings with shared touch-axis settings. Useful secondary reference for optional fire-and-look. |
| [Luanti5.17.0](https://github.com/luanti-org/luanti/releases/tag/5.17.0) | Released Android voxel platform, independent joystick/camera ownership, HUD editor, fixed/floating stick and density-normalized camera sensitivity. [Touch source](https://github.com/luanti-org/luanti/blob/5.17.0/src/gui/touchcontrols.cpp#L559) is LGPL-2.1-or-later. | C++/native, not a FPS template. Compare [buttons_crosshair](https://github.com/luanti-org/luanti/blob/5.17.0/builtin/settingtypes.txt#L377) mode for actions by the reticle; default tap/long-tap interactions do not match our weapons. Best secondary reference for block/tool interaction. |
| [NexQuake](https://kitty1.quake.nexus/) | Playable browser Quake with [documented touch controls](https://quake.nexus/controls/): left40% movement, right60% swipe look, separate touch sensitivity, inversion/left-handed layout and movable action slots. Public source inspected at `f9fd869074f13f3ad6aad55dca95427f8935027e`; [overlay/editor](https://github.com/0xBrsm/NexQuake/blob/f9fd869074f13f3ad6aad55dca95427f8935027e/client/shell/21-touch-controls.js). Client/server GPL-3.0-only; relay AGPL-3.0-only. | Useful Web comparison; younger project and no proven phone feel here. Root opened ENTER and observed the rendered multiplayer/server menu only. Overlay source is not the camera core; documented analog_speed must not be assumed equivalent to our displacement model. |
| [Ashworth Station](https://auaggy.github.io/ashworth-station/) | Immediately runnable Web FPS, MIT, [v1.0.0](https://github.com/AUAggy/ashworth-station/releases/tag/v1.0.0), source `132bbbe385986a9acf3c48fa328c67d6f6b5401d`. [Touch handlers](https://github.com/AUAggy/ashworth-station/blob/132bbbe385986a9acf3c48fa328c67d6f6b5401d/index.html#L3608) include floating movement, position-delta look, pointer capture, FIRE drag-look, safe-area CSS and lifecycle cleanup. Root launched DEPLOY and observed rendered gameplay. | No touch-sensitivity slider; FIRE ignores motion below2px per event, and separate LOOK/FIRE pointers may both turn the view. Author-reported playtests and [automated checks](https://github.com/AUAggy/ashworth-station/blob/132bbbe385986a9acf3c48fa328c67d6f6b5401d/docs/TESTING.md) do not establish polished phone aiming. Secondary runnable example, lower priority than released native FPS references. |

### Proposed comparison for Blockfield

- Use relative swipe-look with a stable camera finger, independent horizontal and
  vertical gain, and an explicitly tuned precision/ADS multiplier. Compare slow
  target tracking, a90/180-degree turn, and aiming while moving/firing on the same
  physical device. Existing Blockfield ownership/settings are a starting point;
  their presence does not establish successful feel or the cause of the complaint.
- Compare the Open Touch app's configurable layout and Xash3D's touch profiles before
  choosing baseline values. Keep nonlinear response and smoothing off for the first
  comparison; copied native sensitivity numbers have incompatible coordinate units.
- Compare a separate FIRE button and optional fire-and-look without letting a second
  camera pointer add motion. Prioritize buttons over the underlying look region.
- Godot-specific Pocket Godot, third-person/gesture controllers and joystick addons
  remain educational/component references. The search did not find convincing
  evidence that one is a released, phone-refined FPS camera replacement for Blockfield.

Root and both specialists performed source/document research only. Browser checks
used a desktop pointer and did not emulate coarse-pointer/multitouch or measure
camera response on Android/iPhone. Temporary browser tabs were closed; no viewport
override, app/addon installation, engine/parser/test execution, export or publication
was performed. Only this research document and status.md changed under root ownership.
