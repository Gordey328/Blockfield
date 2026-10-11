# 0024 — Offline map conversion and compact local map packages

Date: 2026-10-11. Status: accepted implementation direction for the user's local
Mirage conversion experiment; no complete-map fidelity or public-release claim.

## Context

The user supplies `C:/Users/Gordey/Downloads/csgo_mirage` and requests conversion
to Blender first, then playable Blockfield blocks. Its actual format is GoldSrc
BSP30 with WAD3 textures and IDST10 studio models. Source-unit layout and rooms
must survive the conversion. Native VXL's fixed size and missing hidden colors
make it unsuitable as the only master for this local experiment.

## Decision

Use an independent, validated GoldSrc extractor, save a self-contained `.blend`,
then reopen that file in pinned portable Blender4.5.14LTS for block conversion.
Blender is a build-time dependency. Source collision planes/trees/entities are
stored with the scene. This first converter uses original BSP solid/air queries
for volume filling and evaluated Blender geometry/UVs for appearance. Arbitrary
edits to Blender geometry do not regenerate the original BSP occupancy tree;
a general mesh-volume importer remains future work.

Exclude entirely technical brush submodels from occupancy. Intersect original
BSP solids with a finite per-column envelope from visible structural roofs,
floors and wall silhouettes, then add decorative shells separately. This removes
unbounded exterior/sky solids without filling original room air. Mirage uses
28 source units per block; its full height fits61 cells and passage clearance is
closer to the actual2.7-block standing player than the first32-unit attempt.

Canonical axes rotate source `(x,y,z-up)` to Godot `(x,z,-y)`, then apply one
uniform source-units-per-block scale and translation to both geometry and markers.
Keep the existing one-unit block/game rules and packed `0/0x01RRGGBB` cells.
Static decorative models/some visible non-solid brushes become block surfaces,
with the resulting collision adaptation reported. Preserve air inside rooms using
the BSP tree rather than global hole filling.

BFM1 is a versioned local file format: four-byte ASCII magic; little-endian uint32
JSON byte length, uncompressed cell length and compressed cell length; UTF-8 JSON;
one zlib DEFLATE stream. Cells are four-byte big-endian values in Y-fast order,
matching `VoxelData.snapshot_bytes`. Required metadata: format1, dimensions,
title, safe feet spawn. A fresh authority epoch/sequence is allocated on adoption.
Loader limits metadata to1MiB, cells/compressed data to64MiB, validates exact file
framing, dimensions, canonical colors and actual0.9×2.7 standing space/support.
Failed/cancelled imports retain the installed world and reset baseline.

Main supports native file selection and detects BFM1 by signature or `.bfmap`
extension. Reset restores the imported file; native saves retain full colors and
metadata. If edits destroy the original spawn support, saving tries the current
player feet and bounded source team spawn candidates without changing the reset
baseline. Source yaw restores a level view when loading/resetting a native map.
World accepts an optional prevalidated feet spawn during data adoption,
so respawn and streaming use the imported spawn. Imported maps do not receive
the test-ground's automatically positioned soldier roster. Existing VXL and
offline TDM/network paths keep their own authority and lifecycle.

Source/generated assets stay outside version control in the user's conversion
directory and ignored `game/assets/local_maps`. Default Web exports exclude this
local asset directory. A local inspection export can explicitly include it; source
map assets are not published by this experiment.

Follow-up: after local verification, the user explicitly requested a combined
Pages publication. ADR0026 extends this policy for the single reviewed compiled
Mirage package; raw assets and other local maps retain this exclusion.

## Consequences and verification

Small maps retain compact dimensions and hidden interior colors. Conversion is
reproducible with original source hashes and engine/Blender pins. Detailed commands,
source/voxel counts, omissions, previews and checks belong in the map-conversion
evidence document/status. All original parity rows retain their existing status.
Sprite/decal/lightmap/script behavior and full multi-floor bot routing are separate
from static map geometry; they must not be inferred from a successful import.
