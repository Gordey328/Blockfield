# Local Mirage conversion — 2026-10-11

The supplied directory was converted to a saved Blender scene, then reopened in
Blender to create a playable colored block map. This is a local static geometry
conversion experiment. It does not establish Counter-Strike behavior, complete
map connectivity, bot routing or the OpenSpades port acceptance gate.

## Input and outputs

Actual input is GoldSrc BSP30, WAD3 and IDST10 models, under
`C:/Users/Gordey/Downloads/csgo_mirage/csgo_mirage`. The folder name does not imply
that this is a Source/CS:GO BSP. Original BSP SHA256:
`13ded0fee37ae9e9ccb2c50d798fe7c008503edba3a7f41cbb54ea012386b2b8`.
Independent format decoding uses the Valve SDK headers at
`b1b5cf5892918535619b2937bb927e46cb097ba1`; no SDK parser code is copied.

All extracted/generated map assets are local under
`C:/Users/Gordey/Downloads/csgo_mirage_converted/`.

| Artifact | Result |
| --- | --- |
| `extracted/scene.json` | 176 BSP models, 12,242 faces, all301 placed props from64 MDL files, 281 textures/materials, 646 entities; no missing textures or used models |
| `csgo_mirage.blend` | 59,018,636 bytes; 472 mesh objects, 129,796 polygons, 281 packed images; embedded collision/entity/provenance metadata |
| `csgo_mirage.bfmap` | 327,461 bytes; 171×61×165, 1,721,115 cells, raw6,884,460 bytes; 298,384 solids, 112,280 surface cells, 95,946 UV-colored cells |
| `csgo_mirage.report.json` | Transform, source hashes, selected spawns, exclusions, counts and explicit limitations |
| `source-overview.png`, `source-spawn.png` | Actual Blender source renders; reviewed visually |
| `voxel-topdown.png`, `voxel-first-person.png`, `voxel-overview.png` | Converter topdown and actual Compatibility game renders; reviewed visually |
| `browser-mirage.png`, `browser-destruction.png`, `browser-block-edits.png` | Real final Web game captures of loaded map, spade digging and block construction |

Final hashes:

```text
blend d3d86443f0ec58c45147dee3cf04a8d7d0cf31e5a5deaa69f92c49a19123e208
bfmap 08b69203a2dde4d276053647312dbcdd5bf20f0730203ee24c4c293934e35d3a
```

## Conversion policy

Source axes rotate to `(x,z,-y)` and use28 source units per game block. Full
height fits61 cells without cropping. The standing player's2.7-block body needs
more clearance than the first32-unit attempt supplied in some source passages.
Forty source team spawns are retained:20 per team, with full0.9×2.7 clearance and
all four support corners verified. Maximum source-spawn correction is1.0344
blocks; initial feet are`[124.5,6.025,118.5]`, yaw`-4.71238898038469`.
The converter finds32,232 supported standing cells; this is not a route graph.

Original BSP queries preserve room air. Entirely technical/faceless submodels
are excluded:57 total,52 originally solid. A finite visible structural envelope
from roofs/floors/wall silhouettes, with a conservative one-cell margin,
intersects BSP solids. This removes544,027 unbounded exterior/sky cells and never
fills original room air. Static prop and illusionary-brush shells add9,387 cells
afterward. Two continuous bottom support layers accommodate voxel collapse rules.
Evaluated geometry and UV colors are read from the actual saved `.blend`.

QA first found an enormous `nowallshot` checker tool overlay in Blender. It stays
hidden in a source-tools collection and is excluded from surface coloring.
Subsequent game QA identified the unbounded BSP exterior fill, leading to the
finite envelope. Remaining thick black lines include actual telephone-wire/pole
MDL decorations quantized into blocks.

## Reproduce

Run from the repository root in PowerShell with the bundled Python or a normal
Python3 installation. Portable Blender is pinned to4.5.14LTS, build62c1db4208e8;
official ZIP SHA256
`b9533d2397ac1984db4466fb23a7a4649391cca93f6e84209f9bcc60d071c8b9`.

```powershell
python tools/bootstrap_blender.py
python tools/map_import/goldsrc.py --source C:/Users/Gordey/Downloads/csgo_mirage/csgo_mirage --output C:/Users/Gordey/Downloads/csgo_mirage_converted/extracted

$mapBlender = 'C:/Users/Gordey/Documents/ChatGPT/Blockfield/.tools/blender/blender-4.5.14-windows-x64/blender.exe'
& $mapBlender --background --python tools/map_import/blender_scene.py -- --scene C:/Users/Gordey/Downloads/csgo_mirage_converted/extracted/scene.json --output C:/Users/Gordey/Downloads/csgo_mirage_converted/csgo_mirage.blend --render-overview C:/Users/Gordey/Downloads/csgo_mirage_converted/source-overview.png
& $mapBlender --background C:/Users/Gordey/Downloads/csgo_mirage_converted/csgo_mirage.blend --python tools/map_import/blender_voxelize.py -- --output C:/Users/Gordey/Downloads/csgo_mirage_converted/csgo_mirage.bfmap --units-per-block 28 --render-spawn C:/Users/Gordey/Downloads/csgo_mirage_converted/source-spawn.png
```

The final policy update reused the validated geometry and packed images with
`blender_scene.py --refresh-metadata`, saving in7.8s. The next separate invocation
reopened that file and voxelized in116.97s. Indented embedded JSON avoids Blender
Text insertion taking minutes for one huge line. Two slow unsaved rebuilds were
stopped before this successful update.

For an in-game local shortcut, copy the package to ignored
`game/assets/local_maps/csgo_mirage.bfmap`. The lab's World/modes tab includes
“Открыть csgo_mirage”; native/browser file selection also accepts`.bfmap`.

```powershell
python tools/freeze_local_map.py --output .cache/mirage-inspection-new
python tools/export_local_maps.py --source .cache/mirage-inspection-new --output build/mirage-web
python tools/serve.py --directory build/mirage-web --port 8091
```

The freeze takes HEAD plus an explicit list of map-conversion files, excluding
unrelated concurrent gameplay edits. Actual validated base is
`26ea9883bdef9a7436bece87e36239857651dc8e`; source overlays are hashed in
`.cache/mirage-inspection/map-overlay.json`, with the final map hash included.
Final overlay manifest SHA256:
`4a102e6020bd39837309c54ffe0144b6907d9b4dff361e80938ac3e30627af4b`.
Local Web metadata identifies the source snapshot and reduced template SHA256
`a1ba66d55991c9dee57fda393cb3a8f5088fce527f931b204be51ed78693a922`.
The default public export preset excludes local map assets and is restored
byte-for-byte by the local exporter. No map assets or build were published.

## Verification

Godot is4.7.2.stable.official.ed1daf0bf; OpenSpades reference remains
`dcf449c845d509bbde9d79239b32d201c1389961`.

| Check | Evidence |
| --- | --- |
| GoldSrc decoder | Python9/9, including actual all-used-model/texture extraction and40 source spawns in BSP air |
| Voxel helper policies | 7 original helper checks plus7 finite-envelope/tool checks; all40 final binary spawns validated |
| Native map format | 95/0 including final real package, exact framing, malformed input, canonical solid black and supported spawn |
| Actual Main lifecycle | 21/0: signature load, request cancellation, native color/reset, source view, dry water, save-spawn fallback, lab restoration |
| Existing VXL path | 15/0 after native Main changes;126 yielded load frames in isolated repeat |
| World/adapter/motion/UI/TDM regressions | Earlier affected runs30/0,25/0,128/0,284/0,62/0; runtime smoke and parser/import passed |
| Final normal Compatibility scene | GPU6/0: adopts real map, actual input walks source lane and rifle destroys terrain, reset restores baseline, both PNGs saved |
| Local final Web | Export passed; real browser opens Mirage, walks toward stairs, fires, spade removes floor, block input places new blocks; current-map reset restores spawn/view/baseline |

Final isolated logs are under`.cache/mirage-inspection/.cache/logs/`:
`mirage-isolated-import`, `mirage-isolated-main`, `mirage-isolated-vxl`,
`mirage-final-real-loader`, `mirage-final-gpu-capture`, `export-local-maps`.
The normal graphics inspection command is:

```powershell
& '.tools/godot/Godot_v4.7.2-stable_win64_console.exe' --path .cache/mirage-inspection/game --rendering-method gl_compatibility --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 60 --script .cache/mirage-inspection/tools/render_local_map.gd -- C:/Users/Gordey/Downloads/csgo_mirage_converted/csgo_mirage.bfmap C:/Users/Gordey/Downloads/csgo_mirage_converted
```

The overhead inspection alone disables fog and chunk distance fading to expose
the whole map. First-person and browser checks use normal game presentation.
Codex's in-app browser does not supply pointer lock here; drag-look fallback
works. Its console records Chromium`UnknownError` on pointer-lock attempts; no
Godot script/runtime error was observed in the final browser check. Tests of
invalid UTF-8 intentionally print one Unicode diagnostic. The first save-spawn
fixture compared float arrays exactly; it was corrected to approximate Vector3
comparison and all21 checks passed.

The shared workspace temporarily contained incomplete particle scripts from a
separately owned concurrent task. One intervening Main run failed on those
unrelated parser errors; the final checks/export use the explicit isolated
overlay and preserve the other task's changes.

Final sanity checks pass: all16 explicit overlay files match the frozen source
and workspace, all three map copies match the final hash, and the Blender hash
matches. All9 conversion/export/server Python files compile;17 owned new/helper
files have no trailing whitespace. `git diff --check` passes for affected tracked
files. The live local HTTP build metadata matches the frozen manifest, both public
and private presets retain local-map exclusion, and all six retained visual
captures exist. No runtime source changed after the final export/browser check.

## Limits

Fifteen sprites,58 decals, source lightmaps, scripts, moving doors, functional
ladders, animations and original objectives are not reproduced. Original
non-solid decoration becomes solid destructible shells. Thin details, stairs
and openings are quantized; only the spawn lane was walked interactively,
not every route. TDM bots use the existing authored arena and have no verified
multi-floor navigation for Mirage. Source texture colors cover exposed cells
and one inner band; deeper solids use base material colors.

Arbitrary wall edits in Blender do not regenerate BSP occupancy metadata; this
converter combines visible geometry with the original collision tree. General
authored Blender-map volume/markup conversion remains future work described in
[the pipeline proposal](blender-map-pipeline.md). Package and integration contracts
are in[ADR0024](decisions/0024-local-map-conversion.md). Original parity rows are
not promoted by this experiment.

Follow-up: the user subsequently authorized combining this map with the finished
effects task and publishing Pages. The unchanged compiled map is bundled under
`game/assets/maps`; see [ADR0026](decisions/0026-bundled-map-publication.md) and
[combined release evidence](combined-mirage-release.md) for the frozen96-test run,
public hashes and actual published movement/destruction/build/reset checks.
