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
The normal development export froze clean source
`4af719a9543747f521fa8cee3857562511a1e7e1`; production import/export passed with
unchanged project config. SHA-256 for all three input scripts matches the tested
probe. Served at `http://127.0.0.1:8877/index.html`, the normal game rendered,
accepted Mobile On and mirrored controls from its actual settings menu, and
responded to mouse-preview horizontal/vertical look and primary-fire drag.
Mobile On and the mirrored layout survived a real browser reload. Engine/browser
error/warning capture for that tab was empty. Screenshots are retained in
`.cache/browser/nexquake-normal-*.jpg`; this remains desktop preview evidence.

## Integration with completed optimization work — 2026-10-11

The user requested checking the other chat, preserving its changes, merging main
and publishing for phone testing. The optimization chat completed and returned all
leases. Merge1c046655fef23dcf46257dc10649d345ec4256d0 contains every main commit
through922f23072afdee7552e0ed9653fca277ab92e529, including browser VXL staging774e506
and audio-fixture correction66e4b5b. Git ancestry and the changed-path allowlist
confirm every other production game file is identical to that completed main;
only PlayerController, MobileControls and LabHUD differ. No protocol/authority,
world, audio, material-cache or export-pipeline change was overwritten.

A clean git archive of1c04665 passed all85 registered native behavioral/latency
invocations, parser/import, runtime/server-launcher smoke and normal Web export
on Godot4.7.2.stable.official.ed1daf0bf. Controls3068/0, actual mobile look209/0,
UI284/0, network controller511/0, camera45/0, epoch437/0, VXL62/0, actual Main
VXL15/0, bounded materials1555/0 and latency465/0 are included in that full run.
Headless effects explicitly skip three GPU readback assertions; browser rendering
is checked separately. Logs: `.cache/release-1c046655fef2/.cache/logs/`.

Reproduction uses the pinned engine and frozen helper (absolute Python/Godot paths
from this machine's status). In a worktree lacking its own .tools engine cache:

```python
import sys
from pathlib import Path
sys.path.insert(0, "tools")
import build, release_checkpoint
build.engine = lambda: Path("C:/Users/Gordey/Documents/ChatGPT/Blockfield/.tools/godot/Godot_v4.7.2-stable_win64_console.exe")
sys.argv = ["release_checkpoint.py", "--revision", "1c046655fef23dcf46257dc10649d345ec4256d0"]
release_checkpoint.main()
```

The integrated test-only probe was exported from the same frozen source using
`--name nexquake-integrated-1` and that source's imported cache. At844x390 it
passed15/0, yaw-90.000023deg/pitch-10.000005deg, movement3.732916 and two real shots.
At390x844 it passed15/0, yaw-89.999989deg/pitch-10.000051deg, movement4.109588 and
 two shots. DOM JSON/screenshots: `.cache/browser/nexquake-integrated-{landscape,portrait}.*`.
The probe tab captured one unattributed MutationObserver exception with no source
URL; there were no captured Godot script errors and all checks completed. This
exception is retained as diagnostic evidence rather than attributed to game code.
The separate normal export rendered the real lab, retained Mobile On/mirrored
settings, and accepted horizontal/vertical look and fire-drag; its warning/error
capture was empty. Screenshot: `.cache/browser/nexquake-integrated-normal.jpg`.
All three input script hashes match between the probe and frozen normal source.

The separate active chat "Сравнить Ace of Spades и OpenSpades" owns its evolving
inspection helper and research; those pending files are not included or modified
by the mobile release. Earlier mobile research bytes are preserved in the main
checkout's `.cache/nexquake-integration-backup-20261011`, and their substantive
records are included in this branch. Subsequent documentation-only commits do not
change the tested game bytes. PR1 merged as0fd90e75e508e83adbab410628940ca689d00da0.

Publication is complete (evidence below). Physical Android/iPhone
multitouch, aiming comfort, OS safe areas and sustained performance remain pending.
The existing66e4b5b dedicated-server package stays compatible: wire/authority files
are byte-identical. No new hosted server or complete-port acceptance is claimed.

## Published phone-test checkpoint

`tools/publish_pages.py` published the checked source1c04665 as bundle
83ce7fa206d7f4e602fff2a01dfe0071e32d6b11. GitHub Pages reports built with no error.
Independent HTTPS requests confirm the clean source metadata and exact SHA256 for
HTML, JS, WASM, PCK and both audio worklets. PCK16,202,560bytes:
`c098fb35b23d33d771dfc4d669bf117cf6735b5560359fc1d039db88e1573289`.
Report in the main checkout: `.cache/browser/nexquake-public-hashes.json`.

The actual public site rendered and accepted Mobile On from the real menu,
movement-stick drag, horizontal/vertical swipe and fire-and-look with100% gain.
Public normal-game error/warning capture was empty. Screenshot in main:
`.cache/browser/nexquake-public-mobile.jpg`. The original public Auto mode was
restored after checking. This remains desktop input-preview evidence, alongside
synthetic multitouch checks; the user's physical-phone feel check is next.

The main checkout fast-forward preserved the concurrent AoS research's complete
pending status insertion and left its helper/documents untouched. That insertion
remains pending under its owning chat rather than being committed into this release.
All own diagnostic/normal/public browser tabs and preview servers8877/8878 closed;
other chats' tabs/processes were retained. Engine/release leases are returned.

## iPhone combat input failure — 2026-10-11

The user reports that Chrome on iPhone accepts main-menu taps but every combat
control is dead. The prior positive-ID `Input.parse_input_event` probe and desktop
preview did not cover native browser identifiers. The production public touch
handlers rejected all negative indices. WebKit's iOS identifier generator seeds
an unsigned32 counter with `arc4random()`, and DOM Touch/Godot Web carry signed32
identifiers. High-bit IDs therefore hit that rejection. This is a proved input
compatibility defect and a concrete explanation of the report; matching the
individual phone still requires the user's retry.

Primary source chain:

- [WebKit random identifier seed](https://github.com/WebKit/WebKit/blob/5366911032cc8110a316535db51be0c961f9a708/Source/WebKit/UIProcess/ios/WKTouchEventsGestureRecognizer.mm#L67).
- [Signed DOM Touch IDL](https://github.com/WebKit/WebKit/blob/5366911032cc8110a316535db51be0c961f9a708/Source/WebCore/dom/Touch.idl#L40).
- [Pinned Godot JS i32 write](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/platform/web/js/libs/library_godot_input.js#L593)
  and [ScreenTouch index assignment](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/platform/web/display_server_web.cpp#L713).

The fix accepts signed32 IDs and maps each to its unsigned32 value in a Godot64-bit
integer before owner lookup. Real IDs `-1/-2` cannot collide with internal mouse
and no-owner markers. Finite-coordinate validation and immutable gesture roles
remain intact. Only MobileControls changes in production; HUD, PlayerController,
authority, world, audio and all completed optimization work retain their bytes.
The browser fixture now dispatches DOM TouchEvents with IDs `-1`, `-2`, INT_MIN,
INT_MAX and0 through the actual JS/WASM boundary. Engine-native cancellation and
DOM cancellation are distinguished because pinned Godot maps DOM cancel to UP.

Frozen source2d60434b7534ff75c2a1b3863d235b643d0ea0b8 passed parser/import,
controls3090/0, actual Main mobile-look209/0, UI284/0, source-input35/0,
network-controller514/0, camera-target-rays11/0, runtime smoke and normal Web
export on pinned Godot4.7.2. This is focused validation of the one production
file changed since26bdf7d, with all85-check baseline evidence retained; it is
not a claim that all85 suites reran on this fix. Frozen logs:
`.cache/release-2d60434b7534/.cache/logs/`.

The same DOM fixture failed15/5 on the prior game bytes (movement0/shots0)
and passed15/0 on the fixed bytes at844x390 and390x844. Landscape movement
3.732885/two genuine shots; portrait3.732935/two shots. Owned swipe yaw is
-90deg/pitch-10deg in both. Input script hashes match the frozen normal source.
Reports/screenshots: `.cache/browser/iphone-dom-{red,landscape,portrait}.*`.
The probe captured the same unattributed MutationObserver exception without a
source URL as the prior diagnostic; no Godot script errors were captured. This
exception is recorded without attribution, and does not negate the completed
assertions. Normal public rendering/input is checked separately after publication.
Native RED3090/13 log: `.cache/logs/nexquake-signed-touch-red.log`.

Reproduce the focused native checks with the pinned executable:
`Godot_v4.7.2-stable_win64_console.exe --headless --path <frozen>/game
--fixed-fps 60 --script <frozen>/tests/ui/test_mobile_controls.gd`, substituting
`tests/integration/test_mobile_look.gd`, `tests/ui/test_ui.gd`,
`tests/integration/test_source_input.gd`, `tests/network/test_network_controller.gd`
and `tests/gameplay/test_camera_target_rays.gd` for the remaining fixtures.
Import uses `--editor --import --quit`, runtime uses `--quit-after 120`, export
uses `--export-release Web <output>/index.html`. Freeze with `git archive` of
2d60434 first. `tools/export_mobile_probe.py --source <frozen> --name <unique>
--godot <absolute executable> --import-cache <frozen>/game/.godot` creates the
separate DOM diagnostic; serve its build/web and use the visible run/size buttons.

Native-fixture specialist and read-only upstream reviewer have returned their
leases. Root owns only integration/publication; concurrent AoS research remains
untouched. Physical iPhone retry remains pending.
