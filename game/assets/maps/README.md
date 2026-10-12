# Bundled voxel conversions

The user supplied the `csgo_mirage` GoldSrc map archive and explicitly requested
publishing its converted map with Blockfield on GitHub Pages on 2026-10-11.
The supplied archive includes an ALL-CS.RU download-site page. Original map/model/
texture assets belong to their respective authors; no original author or separate
map license was identified in the supplied archive. This conversion does not
relicense those assets under Blockfield's source-code license.

`csgo_mirage.bfmap` is the compiled colored voxel adaptation, with source hashes
retained in its provenance metadata. Original BSP SHA256:
`13ded0fee37ae9e9ccb2c50d798fe7c008503edba3a7f41cbb54ea012386b2b8`.
Compiled map SHA256:
`08b69203a2dde4d276053647312dbcdd5bf20f0730203ee24c4c293934e35d3a`.

Conversion: GoldSrc BSP/WAD/MDL → saved Blender4.5.14LTS scene → BFM1 map,
28 source units per block; dimensions171×61×165,298,384 occupied cells.
Source scripts, moving doors, animation, lightmaps, sprites and decals are omitted;
static decoration becomes destructible block shells. Mirage bot navigation and
full-map connectivity are not verified. The original archive, extracted textures,
models and Blender scene are retained locally, outside this release.

The offline lab's World/modes menu exposes “Open csgo_mirage”. The public `maps/`
directory also provides the identical package for manual import/download.

## Dust2 from Teardown

The user supplied `C:/Users/Gordey/Desktop/dust2csgo` and explicitly requested
immediate publication on2026-10-12. Source author: CleverGrief; source info.txt
contains `[noupload]`, retained in the compiled package's provenance. This
conversion does not relicense original map assets under Blockfield's code license.
Only the compiled `dust2.bfmap` is bundled; raw XML/VOX/images/Lua stay local.

Teardown XML/MagicaVoxel150 → BFM1,0.6meters/block,220×44×189,392,015solid cells.
SHA256:`d9d8e1f6f7e7d14719242def88c306f3af0dda681c765c3a41222bf91bcaab61`.
Static geometry and supplied heightmap ground are retained; reserved255 helper
markers are excluded. Thin details are quantized. Original scripts, moving
vehicles/doors, source lighting/material physics, ropes and water are omitted.
The World/modes menu exposes “Open dust2”; maps/dust2.bfmap is the same download.
See docs/teardown-dust2-conversion.md for evidence and explicit limits.
