# NexQuake mobile camera — 2026-10-11

This is a mobile input change for the existing Blockfield client. It does not
establish complete OpenSpades parity or physical-phone aiming acceptance.

## Result

The former upper-right look rectangle excluded the lower screen and left a gap
between movement and look. Floating movement now occupies the left40% and look
the right60%, at full height. Buttons take priority when a gesture starts. The
optional left-handed preference mirrors the whole control layout.

The reference is NexQuake `f9fd869074f13f3ad6aad55dca95427f8935027e`, specifically
[client/in_wasm.c](https://github.com/0xBrsm/NexQuake/blob/f9fd869074f13f3ad6aad55dca95427f8935027e/client/in_wasm.c).
Its default formula gives400degrees/full canvas width:180degrees over45% of the
width. `analog_speed=400` controls movement, not camera turn speed. Blockfield
uses displacement without frame-time gain or smoothing; touch multiplier1x
represents this baseline. Existing saved gains therefore turn33% farther than
the previous300degree baseline. See [ADR0014](decisions/0014-nexquake-mobile-camera.md).

Owned per-finger position deltas are queued and consumed once at the next render
or physics boundary, before command sampling. Normal UP keeps received motion;
cancel, focus/menu/chat/layout/reset clears it. Render consumption checks network
life identity and preserves the previously sampled explosion rotation. Existing
ADS/zoom, inversion, mouse gain, pitch limits and authority remain in their
existing paths. The fixed stick, deadzone and single camera owner are retained.

## Native evidence

Godot `4.7.2.stable.official.ed1daf0bf`, Compatibility; OpenSpades reference
`dcf449c845d509bbde9d79239b32d201c1389961`.

The managed branch started at556c6dce324f and incorporated concurrent optimization
commitsafbd05a andeef2225 without editing the shared Main/audio/world/model/build
files. Native validation temporarily set a unique custom userdata directory to
avoid concurrent tests touching the user's settings. Those two test-only project
keys were removed before freezing the production source; `game/project.godot`
has no final diff.

Import and eight affected suites passed on afbd05a plus the final mobile code:

| Suite | Assertions | Failures |
| --- | ---: | ---: |
| MobileControls | 3068 | 0 |
| Actual Main mobile look/settings/network command | 208 | 0 |
| Actual HUD | 284 | 0 |
| Source input | 35 | 0 |
| Network controller | 511 | 0 |
| Source camera effects | 45 | 0 |
| Spectator view | 47 | 0 |
| Epoch reset contract | 437 | 0 |

Total4635/0; logs in the worktree `.cache/logs/nexquake-final-*.log`. These are
affected checks, not a new run of all registered suites. The subsequenteef2225
changes Main's VXL job budget; import, actual mobile look/HUD and runtime are
rechecked after incorporating it:208/0,284/0, clean import and runtime smoke.

Reproduction with the pinned engine, using an isolated test userdata directory:

```powershell
<godot> --headless --path game --editor --import --quit
<godot> --headless --path game --fixed-fps 60 --script <absolute-suite-path>
```

Initial failures were harness errors: wrong handedness property name, exact
float equality after a global transform, and an old UI assertion expecting
immediate rather than next-frame look. The corresponding logs are retained.

## Exported-browser evidence

`tools/export_mobile_probe.py` copies the real game into a unique diagnostic
directory, imports/exports with the pinned engine and preserves existing runs.
The probe instantiates the actual Main/HUD/Player, routes synthetic ScreenTouch
and ScreenDrag through `Input.parse_input_event`, exercises movement/look/fire,
UP/cancel/focus/menu/mirroring and the restored real movement/weapon loop. Its
visible Run button publishes the result as readable DOM JSON. A bounded watchdog
reports incomplete runs.

The preview wrapper resizes only its own iframe; it does not alter a shared
browser viewport or the other chat's tab. Target sizes are844×390 and390×844.

```powershell
<python> tools/export_mobile_probe.py --source <checkout> --name nexquake-camera-5 --godot <absolute-godot> --import-cache <checkout>/game/.godot
<python> -m http.server 8876 --bind 127.0.0.1 --directory <checkout>/.cache/mobile-probe-nexquake-camera-5/build/web
```

Failed diagnostics1–4 remain saved. Run1 had a Node member-name collision; run2
did not flush buffered events, and run3 supplied viewport coordinates to the
window-coordinate input API. The corrected probe uses screen+canvas transforms
as in [Godot's custom-event example](https://docs.godotengine.org/en/stable/tutorials/2d/2d_transforms.html#feeding-custom-input-events).
Run4 gave the correct90degree camera result but expected an ordinary Fire action
to remain held outside its button while another finger owned look; re-entry now
tests the existing ordinary-action contract. These failures do not justify
changing the production canvas adapter or pointer ownership.

Run5 landscape844×390 passed15/0. It reported logical1038×480, yaw-90.000023°,
pitch-10.000005°, genuine movement4.109575 units and two weapon shots. Its DOM JSON
and screenshot are saved under `.cache/browser/nexquake-camera-5-landscape.*`.
Portrait390×844 passed15/0 with logical480×1038, yaw-89.999989°,
pitch-10.000051°, movement3.732950 units and two shots. Its DOM JSON and full-page
screenshot are saved under `.cache/browser/nexquake-camera-5-portrait.*`.
Normal-export outcomes are recorded after their actual run.
Physical Android/iPhone multitouch, aiming comfort, OS safe areas and sustained
device performance remain unverified.
