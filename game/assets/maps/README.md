# Bundled Mirage voxel conversion

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
