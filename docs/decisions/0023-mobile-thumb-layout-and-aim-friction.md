# 0023 — Mobile thumb layout and aim friction

2026-10-11. The user requests improving mobile combat UX beyond uniform button
styling, and adding slight stickiness when aiming at an enemy.

Use an asymmetric thumb layout: largest primary fire, nearby ADS, smaller reload,
staggered jump/crouch, sprint above movement, and separate tool/utility bands.
Preserve the 40/60 movement/look split, pointer ownership, fire-and-look, mirrored
left-handed mode, control scaling and the 56 CSS-pixel minimum target. The bottom
52 logical pixels remain reserved for combat readouts. HUD clearance follows the
actual top-band height. The minimap mirrors the controls and reduces its small
preview size when needed to clear buttons. Touch reload prompts omit keyboard
bindings; a compact mobile feed prioritizes combat/objective messages over spawn/
team/mode notices while retaining the complete session journal. This supersedes
ADR0022's unchanged geometry decision.

TouchAimAssist is an input gain calculation. It uses the original firearm OBBs
of the nearest living actor under the unshaken reticle, within64 blocks, and the
source terrain ray. A foreground ally or wall prevents assistance. Public remote
health may be unknown; alive and known-health guards handle both session types.
Only the living local player's first-person firearm touch motion is eligible.
Mouse look and all server damage/spread rules retain their existing paths.

The minimum gain is0.82 (18% slowdown). Motion up to1 degree receives full
friction,1–4 degrees blends smoothly to normal, and4 degrees or more escapes.
Zero input never generates rotation. This is stateless slowdown: no snapping,
target attraction, automatic tracking or firing. The setting defaults on and
persists as input/touch_aim_assist; mobile reset restores it.

References reviewed2026-10-11:
- [COD Mobile controls](https://blog.activision.com/call-of-duty/2019-10/Getting-a-Grip-on-the-Call-of-Duty-Mobile-Controls): separately adjustable HUD position, size and opacity.
- [Warzone Mobile control customization](https://www.callofduty.com/uk/en/blog/2024/03/call-of-duty-warzone-mobile-complete-control-plus-customization-controller-options): thumb/control presets and optional aim assist. Our specific geometry and friction strength are authored choices.

Tests and browser evidence are recorded in docs/mobile-controls.md and status.md.
Browser emulation does not establish physical-phone comfort or safe-area support.
