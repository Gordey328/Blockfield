# Mobile controls

Touch controls are an input presentation layer for the existing source movement/tool rules. `game/ui/mobile_controls.gd` owns finger claims and emits action, movement, look and menu signals; `LabHUD` owns their connection to the player and global Godot input. Neither the overlay nor its buttons grant local authority in a network session.

Settings → Mobile controls offers Auto/On/Off, saved as `[ui] touch_controls` in
`user://settings.cfg`. Auto detects native touch availability/platforms, coarse
browser pointers and small touch screens, with first-touch fallback. On also
enables a desktop mouse preview; Off restores the desktop scale and mouse input.
The mobile canvas expands from 854×480 landscape or 480×854 portrait to fill the
actual viewport. Menus use larger buttons/dropdown rows, wrapping text and two
columns in portrait; HP/ammo remain in the footer and the minimap clears both
toolbar rows. [ADR0007](decisions/0007-mobile-controls.md) records the decision.

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

The separate actual Main/HUD suite in `tests/ui/test_ui.gd` passed267/0: real
overlay mouse dispatch, Jump without accidental primary input, action/stick/look
bridges, saved mode, menu/chat/focus cleanup and desktop scale/mapping restoration.
That fixture preserves preferences byte-for-byte on normal completion.

Local exported Web views at844×390 and390×844 displayed the overlay/menu and
retained forced-On mode after reload. The left stick moved the rendered player,
the right drag rotated the view, and footer/portrait minimap placement was checked.
Final frozen/public artifact evidence will be appended after publication.
These browser gestures use the desktop mouse fallback. Physical phone touch,
OS keyboard/safe-area behavior and hardware performance remain unverified.
