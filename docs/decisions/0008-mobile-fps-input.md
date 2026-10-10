# ADR 0008 — mobile FPS gestures and camera gain

Accepted 2026-10-10 after the user authorized the researched fix and requested
comfortable mobile game controls in addition to the jitter repair.

## Decision

Keep pointer roles fixed from DOWN to UP/cancel. Store the previous absolute
position per accepted pointer ID and derive look delta from that position.
The pinned Godot Web implementation derives relative motion from the slot in
`changedTouches`, which can represent another finger on the next event; see
[research](../mobile-controls.md#research-2026-10-10). Do not substitute one engine
relative field for another or smooth contaminated deltas.

The left thumb gets a floating joystick by default: its accepted DOWN is neutral,
the base remains fixed for the gesture, and a radial deadzone of 0.12 is remapped
once. A fixed joystick remains selectable. Primary fire can also claim the free
look role on DOWN for a living player with a firearm, allowing fire and aim with
one thumb. It keeps firing outside its button until UP/cancel. When another finger
already owns look, primary retains ordinary button behavior. Roles never transfer
mid-gesture. Spectator target selection retains its original action behavior.

Touch camera gain is linear and independent of desktop mouse sensitivity,
exponent and inversion. Both axes use the full overlay width as the denominator:
at 100%, a 30%-width swipe rotates 90 degrees before weapon zoom. No frame-time
multiplier, acceleration, filtering delay or CSS/device-pixel multiplier is added.
The existing weapon zoom and camera-mode permission/pitch limits still apply.

Persist touch look gain (25–300%), ADS gain (25–200%), inversion, floating/fixed
stick, fire-and-look and control size (80–140%). Provide a mobile-only reset.
Buttons retain a 56 CSS-pixel floor in Web, measured against the canvas bounds;
their captions/hints retain a 12 CSS-pixel floor, calculated at layout time.
Headless/native checks use a logical-pixel floor without claiming CSS equivalence.
Desktop mouse preview is disabled when genuine touch is detected.

## Consequences and verification

Offline and network sessions retain the same movement/tool rules and authority.
The pointer adapter, HUD and player camera each have behavioral regressions,
including malformed relative motion, simultaneous movement/look/fire, cancellation,
settings round trips and independent desktop gain. Exported landscape and portrait
views must also be checked interactively. Native fixtures and desktop browser
preview do not establish physical-phone feel, OS safe areas or device performance.
Device feedback remains necessary to tune the defaults further.
