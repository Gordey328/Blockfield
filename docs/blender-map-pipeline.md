# Blender scenes to Blockfield maps — proposal

Researched 2026-10-11 (Europe/Moscow), against source
`26ea9883bdef9a7436bece87e36239857651dc8e`.
This is a proposal, not an adopted architecture decision or implemented converter.
No source map has been supplied, downloaded or converted in this research turn.

Follow-up: the user's GoldSrc Mirage was converted through a saved Blender scene
and verified in the local game/browser. See [conversion evidence](mirage-conversion.md)
and [ADR0024](decisions/0024-local-map-conversion.md). The general mesh/author-markup
approach below remains broader than that BSP-assisted importer.

## Recommendation

Use Blender as the source editor and a reproducible offline converter. Extract the
evaluated geometry and surface colors, then rasterize them into the existing voxel
model. A small amount of author markup should preserve rooms, passages and gameplay
intent. Ship the compiled map to the browser; rerun conversion when the source changes.

Three useful approaches have different goals:

| Approach | Result | Best use | Main limitation |
| --- | --- | --- | --- |
| Automatic geometric voxelization | Grid approximation of the source shapes/colors | Terrain, rocks, simple closed objects, quick previews | Does not infer usable doors, structural thickness or combat routes |
| Geometry plus author markup (recommended) | Mostly automatic conversion with explicit fill/carve/ignore rules and game markers | Repeatable production maps with recognizable source layout | Needs preparation of important structural objects and openings |
| Rebuild from reference | Extract layout/silhouettes, replace buildings, stairs and cover with authored block modules | Adapting an artistic scene to a balanced shooter map | Less literal fidelity and more level-design work |

The second approach can selectively use the third for stairs, narrow doors and
small details. A recognition/AI stage could suggest labels or replacements later;
geometry and reviewed rules should determine final collision and occupancy.

## Existing integration points and constraints

`game/world/voxel_data.gd` already owns dense packed cells: `0` is air and
`0x01RRGGBB` is a colored solid, including black. Dimensions are positive and at
most `(512,64,512)` in Godot `(x,y-up,z)` order. One world unit is one block.
The Y-fast index is `y + height * (x + width * z)`.

`VoxelData.load_snapshot_bytes` validates the dimensions, length and colors and
currently reads each canonical cell as four big-endian bytes. `VoxelWorld.set_map_data`
adopts validated writable data and prepares streaming, collision and presentation.
These are reusable building blocks, not an existing Blender/map-package importer.

`game/world/vxl_reader.gd` already reads/writes native VXL. This is the quickest
compatibility output for inspecting a conversion in the existing lab. However:

- A VXL load uses the full `(512,64,512)` grid, even for a small authored area.
- Hidden interior colors are not retained by VXL; reload reconstructs them with
  the existing earth-colored `DEFAULT_SOLID`. Walls can expose different colors
  after excavation. Preserve all cell colors in the authoring master.
- VXL carries no team spawns, objectives or bot routes. Export them separately.
- Bedrock/floor rules must remain valid, and source heights must fit 64 blocks.

Raw cell storage alone is 4 MiB for `(128,64,128)`, 16 MiB for `(256,64,256)` and
64 MiB for `(512,64,512)`. These smaller costs apply to compact native data, not
to the current fixed-size VXL loader. Meshes, collision, staging and effects add
memory. Browser timings cannot be inferred from these sizes or source triangle counts.

The current TDM arena is `(80,24,56)`. `game/ai/tdm_voxel_navigation.gd` chooses
one stand height per horizontal column, under a configured ceiling. Arbitrary
stacked floors, bridges above walkable tunnels and multi-storey routes need an
expanded navigation representation. Begin with a compact predominantly single-level map.

## Proposed conversion pipeline

1. Acquire a particular scene and preserve its archive, textures, linked resources,
   source URL, author, license, download date, source hash and Blender version.
   Store downloads under `.cache/map_sources/<id>/` and edit a separate working copy.
2. Select the playable region and included collections. Choose scale from player
   clearance, door heights and traversal distances; uniformly fitting an entire
   city into the bounds can make every building unusable. Keep the one-block game
   scale; adjust source-to-grid scale instead of changing player/weapon rules.
3. Use Blender's evaluated dependency graph for modifiers and world transforms.
   Explicitly realize/export instances and Geometry Nodes results; freeze the
   chosen frame/seed. Record unsupported object/material types and missing files.
4. Produce triangles with material IDs, UVs and/or vertex colors in a single
   documented grid transform. A proposed handedness-preserving Blender Z-up to
   Godot Y-up rotation is `(x,z,-y)`, followed by uniform scaling and translation.
   Transform marker positions and directions identically. The existing VXL
   `(x,y,z-down)` mapping is a different format conversion, not this Blender rotation.
5. Rasterize surface triangles with conservative triangle/cell intersection,
   bounded by per-object or per-chunk spatial indices. Filling only cells whose
   centers hit a surface can miss thin walls. Conservative occupancy can instead
   thicken walls and close narrow openings, requiring explicit gameplay corrections.
6. Apply object semantics, interior colors and explicit air masks; sample surface
   colors; validate structure and clearance. Generate a preview and diagnostics.
7. Emit the compiled map and gameplay metadata. Load them through the existing
   authority/world boundary and test the normal exported game.

Suggested author labels, using collections or custom object properties:

| Label | Conversion policy |
| --- | --- |
| `SOLID` | Fill the material volume of a closed wall, slab, rock or prop |
| `SHELL` | Rasterize an open surface with explicit block thickness |
| `CARVE_AIR` | Explicit empty room, doorway, tunnel or route; override prior solid fill |
| `TERRAIN` | Ground surface with explicit solid volume beneath it; use height columns only where no caves/overhangs are intended |
| `IGNORE` | Omit small decoration, cameras, lights and background content |
| `SPAWN_*`, objective/route markers | Export metadata rather than physical blocks |

Do not flood-fill the outside of a whole scene and assume every enclosed void is
material. A sealed room must remain empty; solid filling should be per structural
object or paired with explicit void masks. Gaps, non-manifold geometry and objects
with intersecting surfaces need a reported fallback or author correction.

Closed-mesh inside tests and conservative surface voxelization are a manageable
first implementation. OpenVDB is an optional later backend for demanding geometry,
with its own closure assumptions and deployment cost. Blender's Voxel Remesh can
prepare/preview geometry but returns a mesh, not Blockfield's packed colored cells.

## Color and destruction

Start with flat material/vertex colors; then support image textures via UV
sampling. Bake procedural base color in Blender before sampling it. Diffuse Color
without Direct/Indirect light is appropriate for compatible diffuse materials;
an explicit Base Color to Emission bake can cover materials such as metallic
surfaces whose diffuse pass is unsuitable. Define color-space conversion once.
Do not bake scene shadows into the canonical block colors: Blockfield adds its own
lighting and AO. Average multiple surface samples when a cell spans fine texture
detail, and provide an explicit fallback/report for unsupported materials.

Each occupied cell ultimately has one RGB value, so glass, reflectivity, normal
maps and multiple face textures cannot be reproduced directly. Decide whether
windows are carved openings or colored solid blocks. Assign sensible interior
colors per object/material so digging exposes wall or rock material rather than
arbitrary surface textures. Quantizing to a restrained palette is an optional
style/compression choice, not a requirement of the current data model.

## Proposed runtime output

A versioned compact package, tentatively `.bfmap`, could contain a validated header,
compressed canonical cells and a gameplay manifest. Reusing current snapshot byte
order/indexing avoids a second coordinate/color contract. Allocate a fresh authority
epoch/sequence on installation; source files should not set active match state.
The loader must enforce declared dimensions, uncompressed length and color values
before atomic adoption. Package format and loading UI still need implementation.

The manifest should include title, water settings, team spawn sets, objective/supply
positions, optional authored bot hints, conversion transform, source provenance and
converter settings/version. Existing `TdmArena.metadata()` shows useful fields such
as `team_spawns`, `cover_points`, `flank_routes` and `navigation_ceiling`, but a
general metadata validator/loader is still needed. VXL plus sidecar JSON remains
an optional compatibility export; it should not replace the full-color master.

## Sources to try

| Candidate | Verified listing | Suggested role |
| --- | --- | --- |
| [BlendSwap low-poly forest](https://blendswap.com/blend/27379) | GMRMarcVideos; CC0; Blender 2.9x; 2.67 MB | Small initial geometry/color example; add authored routes/spawns |
| [Official Classroom demo](https://www.blender.org/download/demo-files/) | Christophe Seux; CC0; 72 MB; updated for Blender 2.8x | Diagnostic for walls, cavities, doors and furniture; not a complete combat arena |
| [Poly Haven Pine Forest](https://polyhaven.com/collections/pine_forest) | Official Download the Scene link; [CC0 asset policy](https://polyhaven.com/license) | Later terrain/tree test using a small cropped region |

Listings/licenses were checked; archive contents and missing-resource behavior
were not tested. Poly Haven's [model standards](https://docs.polyhaven.com/en/technical-standards/models)
identify Blender as the primary model format. Other Blender demo files can use
different licenses. [Blendkit licenses](https://www.blendkit.com/docs/licenses/)
distinguish CC0 and Royalty Free; free access alone is not a CC0 designation.

## Smallest useful implementation milestone

Build an authored fixture with a flat floor, one building with an empty room and
door, stairs, one thin wall, a tree, black blocks and a two-color solid interior.
Add team spawn markers and a deliberately narrow/blocked opening. Convert it to
VXL for immediate lab inspection and a compact full-color artifact for round-trip
checks. Then adapt one downloaded scene into roughly 96–128 horizontal blocks.

Acceptance should cover geometry/axis/color goldens, solid black, empty cavities,
thin surfaces, deterministic reimport, interior colors after digging, valid
supported structures and floor rules, collision-aware spawn/route clearance, and
actual browser movement/shooting/building/grenade/collapse. A three-block-high
door and two-to-three-block-wide main passages are useful starting design targets,
not substitutes for the actual player/bot clearance checks. Measure loading,
visible faces/chunks, memory and destruction frame times on that specific map.
Do not claim balance, multi-floor bot support or performance before playtesting.

Primary technical references:

- [Blender command-line arguments](https://docs.blender.org/manual/sk/4.5/advanced/command_line/arguments.html): background Python conversion is supported.
- [Blender dependency graph API](https://docs.blender.org/api/3.6/bpy.types.Depsgraph.html): evaluated geometry and object instances.
- [Blender Remesh](https://docs.blender.org/manual/id/4.5/modeling/modifiers/generate/remesh.html): mesh reconstruction and thin/open-surface limitations.
- [OpenVDB MeshToVolume source](https://www.openvdb.org/documentation/doxygen/MeshToVolume_8h_source.html): closure assumptions for signed volume conversion.
- [Blender render baking](https://docs.blender.org/manual/de/4.5/render/cycles/baking.html): diffuse color and lighting contributions are separately selectable.
- [Blender Pack Resources](https://docs.blender.org/manual/ru/4.5/files/blend/packed_data.html): managing packed file dependencies.
- [Godot available 3D formats](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html): ordinary `.blend` import calls Blender's glTF export; it does not create destructive map cells.

No engine/import/browser/export/publication checks were run for this research-only proposal.
The subsequent user-supplied Mirage experiment completed the saved Blender → block
map pipeline, native package integration and local browser verification. See
[conversion evidence](mirage-conversion.md) and [ADR0024](decisions/0024-local-map-conversion.md)
for the adopted experiment contracts; general authored Blender volumes remain future work.
