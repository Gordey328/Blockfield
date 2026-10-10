# 0007 — Mobile input as a shared-controller adapter

Accepted 2026-10-10 for the user's mobile-controls request.

The touch overlay owns fingers and emits analog movement, look deltas and normal
action edges. It does not implement shooting, voxel edits or network authority.
The existing controller consumes the same intent offline and in multiplayer.
`InputEventAction` delivery preserves reload, ADS, grenade and block-line edges;
the stick is a separate finite, unit-bounded vector combined with keyboard movement.

HUD owns the saved Auto/On/Off setting. Auto detects native touch platforms and
coarse browser input, with first-touch fallback for unreported hybrid devices.
Touch play uses visible mouse mode and suppresses synthetic mouse delivery.
Physical mouse-button mappings are temporarily filtered while the overlay is
active, because consuming a GUI event does not undo Godot's global action state.
Menu/chat/scene exit restore the original mappings and GUI emulation.

Mobile logical resolution is 854×480 landscape or 480×854 portrait, expanding
to fit the viewport. Desktop mode restores the previous scale/aspect. Controls
use at least 60 logical pixels, independent stick/look owners, per-button owner
counts and a footer reserve. Focus loss, cancellation, resize, menu/chat, mode
changes and session resets release held input.

Browser tests at phone-sized viewports validate rendering and the mouse fallback;
production ScreenTouch tests validate simultaneous fingers and real local/network
handoff. A physical phone remains a distinct hardware/browser acceptance check.
See [contract and evidence](../mobile-controls.md).
