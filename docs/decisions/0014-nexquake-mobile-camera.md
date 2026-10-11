# ADR 0014 — NexQuake mobile camera reference

Accepted 2026-10-11 when the user selected NexQuake after reporting that the
existing mobile camera still felt poor. Device comfort remains an acceptance
check; selecting a reference does not establish that Blockfield already feels good.

## Reference and decision

Reference: [NexQuake client/in_wasm.c](https://github.com/0xBrsm/NexQuake/blob/f9fd869074f13f3ad6aad55dca95427f8935027e/client/in_wasm.c),
revision `f9fd869074f13f3ad6aad55dca95427f8935027e`, client GPL-3.0-only.
No engine, Quake resources, relay or JavaScript overlay is imported.

Use the canvas-relative40% movement /60% look partition. The look region covers
the full canvas height beneath action buttons; buttons win on DOWN. Floating
movement starts anywhere in the movement column. Fixed stick remains optional.
Mirror regions, buttons and stick for an optional persistent left-handed layout;
the movement vector and the direction of camera turning remain unchanged.

At NexQuake defaults, `look_units_per_pixel = 180 / (0.60 * canvas_width * 0.75 *
3 * 0.022)`, then mouse-angle coefficient0.022 and touch sensitivity3 cancel.
The resulting baseline is400degrees per full canvas width, or180degrees for a
45%-width swipe. Blockfield's touch sensitivity1x represents that baseline.
Both displacement and width use the overlay's same logical coordinate space.
This supersedes ADR0008's300degrees/full-width baseline. It is33% faster at the
same saved multiplier; values need comparison on the actual device, not a claim
that faster alone fixes the complaint.

Accumulate normalized owned-position displacement and consume it once before
offline movement or network-command sampling. An idle-frame consume also keeps
rendered camera response independent of physics/render frequency; neither path
multiplies displacement by frame time or integrates camera effects twice. Existing
weapon zoom, ADS multiplier, inversion, permission gates and OpenSpades pitch limits
remain in the controller. The immediate touch-motion API remains available for
explicit synchronous callers; the production HUD queues events.

Keep ADR0008's single camera owner, per-ID absolute-position history and optional
primary-fire/look. Do not copy NexQuake's additive multiple-look fingers, gestures
on every right-side action button, tap-to-fire/jump or cancellation behavior.
Ordinary UP keeps already received displacement until consumption. Cancel,
layout/resize, menu/chat, focus loss, disabled controls, respawn and session reset
clear pending view motion and release actions. Cancellation does not invent taps.

## Boundaries and verification

MobileControls owns regions and finger roles; HUD owns persistence and action
bridging; PlayerController owns gain, consumption and camera permissions. No new
offline/network simulation or authority path is added. Existing touch sensitivity,
ADS and inversion settings persist; `ui.left_handed_touch` defaults to false and
participates in the mobile reset.

Behavior checks cover region boundaries, button priority, mirrored ownership,
simultaneous movement/look/fire, event segmentation and corrupt engine-relative
motion, buffered UP/cancel behavior, lifecycle reset, settings round trips and
camera consumption before network intent. Exported-browser checks use the real
Main/HUD/controller and include a test-only synthetic-touch scene; these are
distinct from physical Android/iPhone multitouch and subjective aiming acceptance.

Concurrent optimization owns Main/audio/world/model/build files in the main
checkout. This change is developed in `codex/nexquake-mobile` worktree. Integration
must recheck its current checkpoint, preserve unrelated changes and validate the
combined source before publication. Exact outcomes belong in status/mobile evidence.

## iOS touch identifier boundary — 2026-10-11

Godot Web forwards signed32 DOM touch identifiers unchanged. WebKit's iOS
identifier generator starts from a random unsigned32 value, so valid native IDs
can be negative after conversion. MobileControls accepts the entire signed32
range and normalizes it to a nonnegative64 ownership key with `index & 0xffffffff`.
Internal mouse `-1` and no-owner `-2` markers remain separate. The browser fixture
dispatches authored DOM TouchEvents through JS/WASM rather than bypassing this
boundary with only `Input.parse_input_event`; physical phone acceptance is separate.
