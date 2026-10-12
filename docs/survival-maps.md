# Downloaded community maps adapted for survival

Two additional levels use geometry from real, downloaded Teardown community archives. They are not newly authored imitations. Raw archives and extracted content stay in ignored `.cache/survival-map-sources`; the game receives only packed colored blocks and geometry-derived menu previews. Downloaded Lua and binaries are never executed.

## Sources and resources

| Catalog ID | Original map and author | Source archive | Converted X/Y/Z | Navigation columns | BFM bytes |
| --- | --- | --- | --- | --- | --- |
| `minecraft_chunk` | Small Minecraft Chunk — The_Wolfian | 405,799 bytes | 92 × 30 × 48 | 4,416 | 10,931 |
| `mira_hq` | [Alpha] Mira HQ (Among US) — CapnSoda202 | 759,258 bytes | 66 × 20 × 88 | 5,808 | 11,970 |

Minecraft source: [author Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=2652603687), [public download page](https://dlcfun.com/en/teardown/small-minecraft-chunk-mod). The author page supports the original map’s house/farm/mine description. The original, smaller version inside the archive is used.

Mira source: [Workshop identity recorded by the source archive](https://steamcommunity.com/sharedfiles/filedetails/?id=2905630454), [public download page](https://dlcfun.com/en/teardown/alpha-mira-hq-among-us-mod). The current Workshop page could not be read through the research tool; author/title are independently recorded in the downloaded `info.txt`, and the Workshop ID in `id.txt`. The archive contains an alpha static scene; its planned crewbot/airlock behavior is not imported or claimed.

The public mirror issued ordinary downloadable archive links. No Steam login, ownership check, anti-bot challenge or download restriction was bypassed. The Skeld candidate was abandoned after public download endpoints returned HTTP 403/challenge pages; Mira is an actual alternative map from Among Us. Download URLs have transient signed queries; reproducible records store page URLs and archive hashes, never those query strings.

| Map | Resource | Preview | Source/adaptation notice |
| --- | --- | --- | --- |
| Minecraft | `res://assets/maps/survival_minecraft_chunk.bfmap` | `res://assets/ui/menu/map_survival_minecraft_chunk.png` | [provenance](../game/assets/maps/survival_minecraft_chunk_provenance.md) |
| Mira HQ | `res://assets/maps/survival_mira_hq.bfmap` | `res://assets/ui/menu/map_survival_mira_hq.png` | [provenance](../game/assets/maps/survival_mira_hq_provenance.md) |

Archive pins:

- Minecraft: `b2db060c30f373ac78a3d32f27596f56245a34811b27a27e575affedb044b86a`.
- Mira HQ: `36f3b034af618adba80b1a1cc2697dd74108bcfd59533996c05bff2f7a58385d`.

No separate redistribution/adaptation license was found in these archives or the inspected source/download pages. Original author and underlying game rights remain; neither the BFM nor its geometry-derived preview is relicensed under repository MIT. Attribution and a public download are not represented as author-granted reuse permission. Minecraft rights belong to Mojang/Microsoft; Among Us rights belong to Innersloth. Each provenance notice retains every original archive member’s SHA-256.

## Adaptation and bounded navigation

`tools/prepare_survival_maps.py` is a new adapter using the existing `map_import.teardown`, `teardown_vox` and BFM writer without modifying them. It loads author XML transforms and actual occupied VOX cells. Voxbox brushes use the palette of the downloaded named VOX model, tiled into local axes; palette plurality coarsens each primitive, and later source primitives tint overlaps. Brush phase/offset/randomization, PBR, translucency and thin details are simplified. Voxagons/polygons, Lua, animation, missions, source AI, audio, lights, joints and ropes are omitted and counted. Source polygon walls are not replaced with invented lookalikes.

For Minecraft, 0.4 source meters become one game block. The upper original chunk retains the house, farm, grass, tree and other source objects. The huge outer ground, stone/cave/mine, and named plank roof are removed. Lower geometry is cropped below 11.2 source meters; upper foliage is clipped at 23.2 meters. A foundation fills the mine/farm depressions and a narrow exterior apron so the planner has one supported standing floor. The ground color of added foundation cells is an explicit adaptation, not a claim that those cells existed in the source.

For Mira, 0.6 source meters become one game block. The retained source bounds are X 25.2–62.4, Y 47.8–55.3 and Z 49.6–100.0 meters: cafeteria, janitor room, neighboring eastern corridor and balcony. The elevated station is translated to a local floor. A continuous foundation fills floor gaps and provides a narrow apron; station geometry outside that crop is omitted. XML rotation typos (two-component rotations and a trailing backslash) are normalized in derived XML and recorded in metadata. Subtractive `brush="hole"` helpers belong to the omitted greenhouse and are removed rather than misinterpreted as solid boxes.

The added foundation places feet at Y 4.01, with four complete support layers. Source walls, props and cover remain obstacles above that floor. Tall cover is not a second planned walking surface. The existing planner can choose detour or breach; single-floor data validation does not by itself prove AI movement in the engine.

| Map | Original primitives retained | Occupied source samples in crop | Samples using actual VOX brushes | Solid converted cells | Exposed cells | Connected clear floor columns |
| --- | --- | --- | --- | --- | --- | --- |
| Minecraft | 97 | 1,875,041 | 1,858,944 | 29,580 | 14,141 | 2,890 |
| Mira HQ | 2,233 | 868,019 | 139,672 | 28,608 | 15,468 | 3,864 |

Both maps fit the current 8,192-column navigation budget. `survival_arena` stores numeric JSON arrays for owner/supply/emergence positions, `floor_y=4`, navigation ceiling 27/17, eight emergence sectors, `supported=true`, `single_surface=true`, `stacked_surfaces=false`, walk speed 3.2 and the accepted breach timing/damage defaults. These flags describe this adaptation; they are not inherited source-map claims.

- Minecraft owner/supply: `[50.5, 4.01, 33.5]`.
- Mira owner/supply: `[39.5, 4.01, 42.5]`.
- All eight sectors per map have full 0.9 × 2.7 body clearance, corner support, at least 12 blocks of distance from owner and six blocks between sectors. A flood fill of clear floor columns reaches every sector from owner without destroying geometry.

## Reproduction and evidence

Run with a Python environment containing NumPy and Pillow:

```powershell
python tools/prepare_survival_maps.py --download
python tools/test_survival_maps.py
```

On this host, the bundled runtime is used:

```powershell
& 'C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' tools/prepare_survival_maps.py
& 'C:/Users/Gordey/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' tools/test_survival_maps.py
```

`--map minecraft_chunk` / `--map mira_hq` selects one source. Without `--download`, existing pinned ignored archives are required. With it, the adapter uses the public page-provided link and verifies the archive before extraction. Changed remote bytes fail the SHA pin and need source review. ZIP traversal/symlinks, member count (256), archive bytes (8 MB), total expanded bytes (16 MB) and primitive samples (8 million) are bounded. Conversion summaries are written to ignored `.cache/survival-map-sources/*-conversion.json`.

Data checks on 2026-10-12: **10 tests passed, 0 failures**. They cover source identity/member hashes, actual retained geometry and palettes, dimensions/budget, numeric metadata, safe body/support, connected distant sectors, preview resources, canonical solid-black byte order, unsafe tall spawn rejection, ZIP traversal rejection and public-page archive lookup without logging signed queries. Both sources were reconverted to a separate temporary output and reproduced the exact BFM/PNG bytes. No downloaded script was executed. The two PNG previews were visually inspected as renders of actual converted geometry; they are not engine screenshots.

This handoff does not run Godot, a browser or publication. Coordinator acceptance still needs native BFM load and real session/AI behavior on each map, local desktop rendering/input, and any wider regression/release checks. Browser, phone and publication are not claimed by these Python results.

## Handoff ownership

Changed files are only the new adapter, `tools/test_survival_maps.py`, this document, two new BFM packages, two matching provenance notices and two new menu PNGs. Existing map converters, game integration, catalog, Main and session behavior remain coordinator-owned. Raw downloads remain ignored. Next action: coordinator consumes the two trusted catalog IDs and validates each actual level in native/local play.
