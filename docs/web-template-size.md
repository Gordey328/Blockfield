# Reduced Godot Web template — accepted comparison

Verified on 2026-10-11. Both exports use frozen Blockfield source
`3d1199cb0251f1cfe9c13cbd66a553264a34c1e5`, including offline 3×3 combat.
Source archive SHA256: `6234ff5d43ea02cd996838e771c54ea7f145874f8dc9e721a16fd0e02bbabbf0`.
The shared live checkout and `build/web` were not used as mutable export targets.

## Measured sizes

MB below means 1,000,000 bytes. Gzip uses Python level9, mtime0, independently
for every file in both builds. These are comparable local compression estimates,
not observed GitHub Pages transfer sizes. Folder totals include notices/licenses.

| Item | Official | Reduced | Saved |
| --- | ---: | ---: | ---: |
| WASM, raw | 39,514,754 B | 31,835,587 B | 7,679,167 B / 19.434% |
| WASM, gzip | 10,054,758 B | 8,043,492 B | 2,011,266 B / 20.003% |
| Complete Web folder, raw | 63,855,150 B | 56,144,228 B | 7,710,922 B / 12.076% |
| Complete Web folder, gzip sum | 25,828,498 B | 23,811,261 B | 2,017,237 B / 7.810% |
| Game PCK, raw | 23,806,288 B | 23,806,288 B | Identical bytes |

Both game PCK hashes are
`71ef67d7b0681fdde5f5571b279bd9efeceff37d513c3f443b875649e31e6265`.
Fonts, audio, maps, game scripts and other packed resources are preserved.
The reduced engine still weighs 8.04MB with gzip; this accepted build does not
achieve a 5MB engine or a 5MB complete game.

## Engine and profile

Godot 4.7.2 commit `ed1daf0bf001b61586d9930840f2f1394092c079`;
Emscripten4.0.11 release `7033fec38817ec01909b044ea0193ddd5057255c`;
emsdk commit `35ff8a6d150541276abbc6bae512ca90bcfbe220`;
SCons4.9.1; Python3.12.14; Node24.19.0.
The full recorded command, tool identities, ZIP members and hashes are in
`build/templates/godot-4.7.2-web-blockfield.json`.

[Profile](../tools/web_template/blockfield.py) SHA256:
`17ac32fffba5b52fe9becd7c9e4313d79c3d53d6cd9e0c9d894a9aebcf5726c1`.
Generated `modules_enabled.gen.h` contains20 modules against46 standard eligible
modules. The [audit](../tools/web_template/module-audit.json) ties removed flags
to the pinned source and runtime contracts. Removed capability classes are absent
in the real reduced browser runtime. No individual class pruning is applied.
Keep Compatibility rendering, GodotPhysics3D, multilingual text/advanced GUI,
GLTF/ZIP, WAV/Ogg, RegEx/Noise, JavaScript bridge and WebSocket/TLS.
Bots use authored voxel navigation, allowing built-in navigation to be removed.
See [ADR0021](decisions/0021-reduced-web-template.md) for the boundaries.

Build uses -Os, thin LTO, single-thread wasm32 and no GDExtensions, jobs2/link2.
These optimization settings already apply to standard Web builds. The official
binary's compiler identity is unknown, so the measured difference compares two
concrete engine templates and cannot attribute every saved byte to module flags.
Successful SCons time was1:02:27 on this 8GB host.

```powershell
python tools/build_web_template.py --scons-dir .cache/template-python --jobs 2 --link-jobs 2 --output .cache/web-template-verification/template/blockfield-web-release-minimal.zip --log .cache/logs/web-template-verification-minimal-build.log
python tools/compare_web_builds.py --before .cache/web-template-verification/source-current/build/web --after .cache/web-template-verification/candidate/build/web --report .cache/web-template-verification/size-comparison.json
```

Both helpers preserve existing artifacts; choose new output/report paths for a
repeat. Prerequisites are the pinned Godot source and installed/activated SDK
under `.cache/godot-web-source` and `.cache/emsdk`, with SCons in the selected
Python or the supplied local target directory.

The accepted ZIP is `build/templates/godot-4.7.2-web-blockfield.zip`
(8,162,758B, SHA256 `a1ba66d55991c9dee57fda393cb3a8f5088fce527f931b204be51ed78693a922`).
For subsequent exports, explicitly select it in the Web preset's
`custom_template/release`, retaining disabled threads/extensions. The stock
installed templates and shared presets remain available; this task delivers an
isolated checked export rather than replacing another chat's release work.

## Verification

- Both private production parser/import and Web exports pass; PCK is identical.
- Existing isolated `release-3d1199cb0251` runs all92 registered test suites;
  its source archive is byte-identical and96 logs contain no parser/script/error
  or FAIL lines. Log SHA256s/summaries are recorded in the final report.
- Same frozen probe native47/0; headless explicitly skips browser framebuffer,
  real mixer and browser WebSocket evidence.
- Official and reduced engines each pass54/0 in the actual browser: all three
  firearms and finite ammo, movement, spade/block/grenade, 3D voxel collision,
  multilingual GUI/fonts, RegEx/Noise, real GLB432triangles, genuine ZIP overrides,
  nonzero finite WAV/Ogg mixer samples without overflow, real Unicode WebSocket
  handshake/echo, five moving bots, voxel paths and pause.
- Ordinary reduced export passes manual Russian menus/settings, original VXL
  loading, keyboard movement, tools1–4, map overlay, drag-to-look fallback and
  a normal TDM round reaching3:5 after25seconds. This verifies actual game UI,
  geometry, player input, soldiers, combat effects and HUD outside the probe.

```powershell
python tools/export_template_probe.py --source .cache/web-template-verification/source-current --name current-baseline5 --resume
python tools/export_template_probe.py --source .cache/web-template-verification/source-current --name current-reduced --template .cache/web-template-verification/template/blockfield-web-release-minimal.zip --resume
```

These are recorded commands for already prepared private probes; repeat with a
new name without `--resume`, optionally supplying an isolated import cache.
The baseline is at `.cache/template-probe-current-baseline5/build/web`; the
reduced probe at `.cache/template-probe-current-reduced/build/web`.
Fixture SHA256: `e9c89b401646ce285783b272d832a9150c4ae8ca68750f7bf8604da9c5dda9d8`.
Saved browser JSON/JPEG pairs are under `.cache/web-template-verification`.

Earlier failures remain preserved: SAMPLE audio bypassed capture, so the probe
now explicitly uses production's STREAM mode; .07s input timers could expire in
the same slow render frame, so short pulses span two actual physics frames and
a process boundary. Shot/ammo/block predicates were unchanged. The unmodified
native network-session fixture failed under compile load, then passed505/0 after
compilation. An events-delivery paced repeat passed105/0. Prior source/preference
and interrupted-build logs also remain; they are not relabeled as passes.
IAB Chromium rejects native pointer capture on both engines; ordinary game's
supported drag-to-look fallback was exercised successfully.

## Deliverables

`build/web-reduced-3d1199/` contains the checked production files.
`build/blockfield-web-reduced-3d1199.zip` is23,813,561B,
SHA256 `56278d0afabab9a6b723b04d25c83bb047f698236c0caa88673740f5b53a7abd`.
All copied and ZIP-extracted files were hash-checked against the measured export.
`build/web-template-report.json` contains sizes, file identities, native evidence,
both full browser results and manual verification. Publication evidence follows; the other chat owns current shared gameplay.

Published checked sibling: https://gordey328.github.io/Blockfield/reduced/.
Bundle c1a5d66e0793a0944cca725eed8398e1772bfbc3 built; public metadata/WASM/PCK
SHA256s match (build/reduced-public-verification.json). Public normal Russian
menu/TDM/keyboard movement passed. The user then approved default integration
with current main work; see ADR0021.

Default integration source20889b25bbd035639c88bc4b6cc63d2b57d8e90b passed93
test runs, import/parser/smokes and reduced export. Pages bundle
88bae197fcfed3aed1c33d7dcb1e1f2d21c1c6cf built; main site uses the reduced
engine with modern combat UI. Public WASM/PCK hashes match; sibling preserved.
Public normal TDM movement and rifle10-to8 work, captured warnings/errors empty.
Evidence: build/integrated-public-verification.json, integrated-public-browser.jpg.
