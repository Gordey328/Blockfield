# Local Teardown Dust2 conversion — 2026-10-12

User input: `C:/Users/Gordey/Desktop/dust2csgo`. Current map: `de_dust2.xml`,
Teardown scene0.9.2 and MagicaVoxel150. `main.xml` is the mod's menu; the legacy
map is an alternative source, not selected. Author: CleverGrief. Original
`info.txt` includes `[noupload]`, retained as provenance. The initial conversion
was local; the user subsequently explicitly requested immediate upload without
more map checks. The compiled package is now being bundled for Pages; raw sources
and local alternatives remain excluded.

## Source and contract

Independent inventory:385files/47,276,606bytes, including347VOX files,
457models and9,055,974stored voxels. The active scene has795VOX references and
233prefab instances.257VOX files contain IMAP. XML composes parent/instance
transforms and selects individual named VOX objects. Material physics, opacity,
emission, scripts and animations are not encoded in Blockfield's RGB occupancy.

Terrain is not contained in the building VOX files. The actual supplied
`ground.lua` builds sand columns from the image's red-byte height and top colors
from its blue-byte material code. It uses0.1m source voxels. Interpret these known
operations directly; do not execute arbitrary source Lua. Source T feet marker is
`[4.36998,5.88,30.99999]`, CT is`[17.16998,2.58,-23.60001]` (inactive source layer).

Source SHA256:

```text
de_dust2.xml d6461bfeac7c770dac963b6a9f909d6dbb1c6f94073afcfbb49cc557e4123700
ground.lua 44070d85fc08309a745de72a3abd0f162c1c4c44d5aca011d28cb3e803d70467
heightmap_full.png 5adc173d3889b5499770c68ddbcab164b464702a3d80e00b6b4c40b13b07ecff
```

Output uses existing BFM1/Y-fast `(z,x,y)` storage, air0 and solid0x01RRGGBB.
Required dimensions stay within512×64×512. Safe feet spawn needs actual0.9×2.7
standing space and four supported corners. A uniform meters-per-block scale and
translation apply to geometry and markers. See[ADR0029](decisions/0029-local-teardown-map-conversion.md).

## Handoff and checks in progress

Source runtime:dee5603618ae237172b19a1156ff00543157986c, identical dev and current
branch heads. Godot4.7.2.stable.official.ed1daf0bf, OpenSpades
dcf449c845d509bbde9d79239b32d201c1389961, Compatibility Web renderer.
Root owns docs, frozen source and serial engine/browser checks. Converter
specialist owns only new tools/map_import/teardown.py/teardown_vox.py;
independent QA owns only tests/tools/test_teardown_import.py. The first QA agent's
capacity failures were replaced without handing over additional file ownership.
Unrelated optimization-plan/Steam edits remain untouched.

Bundled Python is
`C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe`
with numpy2.3.5 and Pillow12.3.0. The Windows Store `python` alias does not execute
the scripts. Existing freeze helper created`.cache/dust2-inspection`; parser/import
passes, actual native Main25checks/0failures and120-frame smoke pass there.
Logs:`.cache/dust2-inspection/.cache/logs/dust2-import.log`,
`dust2-native-main.log`, `dust2-smoke.log`.

Final map:220×44×189 at0.6m/block,392,015solids,261,132surface cells,
99,193bytes (7,318,080raw). SHA256:
`d9d8e1f6f7e7d14719242def88c306f3af0dda681c765c3a41222bf91bcaab61`.
5,257placed reserved255 helper samples are excluded, preserving real red/black.
Final-code reproduction is byte-identical; all385input hashes are unchanged.
Thirty enabled Python checks pass with actual source/package and zero skips;
logs:`.cache/dust2-inspection/qa-final.log`, `qa-route.json`.
Independent geometry diagnostic finds61,307standing nodes and a138step T-to-CT
supported/swept-body route; nearest CT point is0.775m from its source marker.
This diagnostic does not validate actual engine motion along every route.

Final BFM95/0 and actual Compatibility GPU6/0 pass, including movement, rifle
terrain destruction and full reset; normal first-person and overhead PNGs saved
under`C:/Users/Gordey/Desktop/dust2csgo_converted/`. Local export passes and actual
browser opens Dust2 through its menu, moves and supports drag look. Further local
map checks stop when the user requests immediate publication. Draft captures with
red source helper markers are preserved under`draft-with-source-helpers`.
No full map fidelity, all-route connectivity, bot navigation, source simulation
or original parity acceptance is claimed.

## Publication requested by the user

The user stops further map checks and requests immediate upload. Source
`021122bf0adeedece3016de8b7a6eb84c6b34581` is pushed on`codex/teardown-dust2`.
It contains the compiled Dust2 package, converter/fixtures and provenance docs;
the runtime inherits the accepted optimized dev source. Unrelated UI-plan,
optimization-plan and Steam edits are excluded. Normal bundled-map export uses
the accepted reduced single-thread template SHA256
`a1ba66d55991c9dee57fda393cb3a8f5088fce527f931b204be51ed78693a922` and excludes
ignored local maps. Output:`.cache/dust2-inspection/build/web`.

Publication preserves the existing optimized/reduced sibling builds. Bundle
`6988cef85a3a9d75aaf595f1ead4c33e89ca0d87` changes only root build-info.json,
index.html/index.pck and maps/README.md/maps/dust2.bfmap. The engine JS/WASM are
unchanged. Repeatable upload:
`tools/publish_pages.py --directory .cache/dust2-pages`; Pages reports queued,
then building. URL:https://gordey328.github.io/Blockfield/?v=021122b .
World/modes → Open dust2. Temporary local HTTP helper is stopped after upload.
Pages reports built for the exact bundle. Actual public build-info.json identifies
source021122bf0adeedece3016de8b7a6eb84c6b34581 and both map hashes; downloaded
public maps/dust2.bfmap is99,193bytes with the exact d9d8e1f6…ab61 hash.
This is publication/availability confirmation, not another gameplay suite.

## Reproduce conversion

```powershell
$dustPython = 'C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
& $dustPython tools/map_import/teardown.py C:/Users/Gordey/Desktop/dust2csgo --scene de_dust2.xml --output C:/Users/Gordey/Desktop/dust2csgo_converted/dust2.bfmap --meters-per-block 0.6
```

Final converter code hashes:
`teardown.py=4da42e98484b9ef2d512d01426068008c34a190f776d55ce3bca68b7ce515ea4`,
`teardown_vox.py=73e1e0ac9598d3c4e76c23093524ac565c33ebd5d943e14e7cc414c097aa0f01`.
Hidden/disconnected malformed VOX graphs and output inside the source directory
are rejected. Actual reports include all385source hashes and explicit omissions.
Author-format references: [Teardown modding](https://teardowngame.com/modding/),
[Euler API](https://teardowngame.com/modding/api.html#QuatEuler),
[voxscript API](https://teardowngame.com/modding/voxscript.html),
[MagicaVoxel format](https://github.com/ephtracy/voxel-model).
