# Source-compatible voxel rays

`VoxelData` and `VoxelWorld` provide the two distinct OpenSpades ray algorithms
alongside the existing bounded, Euclidean `cast_voxel` query. Ray queries do not
edit terrain, advance simulation, allocate scene nodes or apply transactions.

## Public contract

```gdscript
cast_source_ray(origin: Vector3, direction: Vector3, max_steps: int = 500) -> Dictionary
cast_source_ray_legacy(origin: Vector3, direction: Vector3, length: float = 256.0) -> Dictionary
```

Both return the following explicit dictionary:

| Field | Meaning |
| --- | --- |
| `hit` | Solid voxel or native virtual floor was reached |
| `start_solid` | CastRay2 began in a solid voxel; always false for legacy CastRay |
| `cell` | Unwrapped traversed cell in Godot axes |
| `normal` | CastRay2 outward face normal; zero for start-solid or legacy |
| `position` | CastRay2 face intersection, legacy source integer corner, or original origin on a miss |
| `steps` | Actual crossed grid planes, including the successful crossing |
| `valid`, `error` | Defined input/budget result, independent of whether anything was hit |

Check `valid` before consuming a query result. A miss is valid and is not an
input failure. The wrappers forward the complete result from World's current
Data object; they do not consult delayed meshes or physics colliders.

### CastRay2

`cast_source_ray` ports pinned OpenSpades v0.1.3 `GameMap.cpp:361–506` and
`Math.h:359–374`. It normalizes direction using the source's binary32 products,
left-associated sums, square root and reciprocal. Each component of the native
fractional-distance updates and reconstructed hit position also rounds to
binary32. The step budget counts **grid-plane crossings**, not metres. A diagonal
ray can exhaust twelve steps before travelling twelve metres.

The implementation executes in native axes so strict `<` comparisons preserve
source tie priority X, Y, Z. In Godot axes that is X, Z, Y. Equal-time crossings
are separate steps. A hit reports the face just crossed, including a zero-time
crossing from an exact grid boundary. The initial cell is sampled before the
first crossing. Starting in solid returns the original origin, zero normal,
zero steps and `start_solid=true` even with a zero budget or zero direction.

As in source, a nonzero-budget miss reports the last traversed cell and face
normal while `position` remains the original origin. Native zero-budget miss
cell/normal were uninitialized; this port defines them as the initial cell and
zero normal. Native zero-direction traversal asserts because there is no next
plane. This port returns `valid=false` for that case, while a zero-budget empty
query remains a defined miss.

### Legacy CastRay

`cast_source_ray_legacy` ports the active faster `#if 1` branch of
`GameMap.cpp:208–358`. It intentionally does **not** normalize direction. It
forms the endpoint with binary32 `origin + direction * length`, quantizes the
1024-scaled cross-product decision values with native floor operations, and
limits the number of steps to the smaller of endpoint Manhattan distance and
the integer truncation of binary32 length. This is not an alias for CastRay2.

Legacy returns only native integer block coordinates. Its `position` therefore
uses that integer corner converted as a geometric point, not a center or
reconstructed face. This matters to source room-distance probes in
`ALDevice.cpp:654–664` and `ClientPlayer.cpp:1110–1119`. In Godot coordinates the
legacy corner is `(cell.x, cell.y + 1, cell.z)`. Normal stays zero, and the initial
solid voxel is not tested. Starting below the native virtual floor is an
immediate hit regardless of direction or budget.

The source faster branch also skips checking the first entered native z=0 cell
when arriving from the sky. Its cached horizontal column is not updated during
the sky loop. A subsequent vertical hit can therefore use the old column while
reporting the newly traversed cell. These observable source quirks are retained
and have distinct fixtures. The native output coordinate is undefined on a
miss; the port supplies the last traversed cell only as a diagnostic, with the
original origin as `position`.

### Axes, edges and safety bounds

Native geometric points `(x,y,z)` map to Godot `(x,64-z,y)`; integer native cells
map to `(x,63-z,y)` and directions/normals to `(x,-z,y)`. Point and cell conversion
cannot share the same vertical offset at exact faces. Above the map is air;
Godot cells below y=0 are the native virtual solid floor.

On an original-size `(512,64,512)` map, occupancy samples wrap native X/Y with
`&511`, as `GameMap.h:83–95` does. Returned cell and hit position remain
**unwrapped**. Gameplay must retain native bounds checks before editing terrain;
a wrapped occupancy sample does not authorize an out-of-bounds mutation. The
authored smaller Lab maps keep bounded horizontal sampling and air above their
own height. This is an explicit arena adaptation, not native periodic wrapping.

Budgets are bounded to 8,192 steps/length. Inputs must be finite; origin and
legacy endpoint coordinates are bounded to one million. Unsafe float32
normalization/reciprocal or legacy integer decision ranges return invalid
results instead of reaching native assertions or undefined integer conversion.
Ordinary source gameplay budgets are 12, 256 and 500.

The existing `cast_voxel` metre budget, Godot tie ordering, bounded sampling and
miss endpoint remain unchanged. Generic grenade visibility, renderer and other
metric-distance consumers can continue using that contract.

## Integration routes

The helper change itself does not reroute gameplay. Source call sites identify
which contract each consumer needs:

| Native use | Required query |
| --- | --- |
| `Player.cpp:406,479,483` block cursor/fallback | CastRay2, including last miss cell and face normal; 12-step budget/fallbacks |
| `Player.cpp:581` firearm terrain clipping | CastRay2, 500 steps; check native bounds before block damage |
| `Player.cpp:826,868` dig/spade terrain clipping | CastRay2, 256 steps, followed by source reach rules |
| `World.cpp:501` general world terrain cast | CastRay2, 256 steps |
| `Client_Update.cpp:133` eyedropper | Legacy 256, wrapped color sample after a valid hit |
| `ALDevice.cpp:323,654,664`, `ClientPlayer.cpp:1110,1119` audio occlusion/room probes | Legacy, source integer corner distance |
| `Client_Update.cpp:1201` downward sound placement | Legacy, length 8 |

Source ray occupancy dispatches through virtual `get_block`, allowing a pure
historical query to read its captured frame without packed storage. Such a
leased query must still override these entry points to reject an expired lease
before calling the inherited helper: a virtual-floor hit can return before
`get_block`. HitHistory lifecycle integration is owned separately.

## Deferred VXL presentation

```gdscript
load_vxl(path: String, deferred_visuals: bool = false) -> Error
load_vxl_bytes(bytes: PackedByteArray, title: String = "Imported VXL", deferred_visuals: bool = false) -> Error
```

Both retain synchronous decoding and error returns. The opt-in flag only queues
the same incremental mesh/water presentation used by `set_map_data`; the decoded
Data, spawn and source queries are available immediately. Defaults preserve the
original synchronous behavior. Decode remains a whole-file CPU operation; this
flag does not claim incremental VXL decoding or eliminate its allocation cost.
Failed imports leave the installed Data and pending visual preparation intact.
See [world preparation](world-preparation.md) for budgets, pending images and
epoch cancellation.

## Verification

`tests/world/test_source_rays.gd` uses committed literal fixtures derived from
an independent scalar reference transcription of the pinned native arithmetic,
rounding each float operation through IEEE754 binary32. CI does not need a native
OpenSpades checkout or a C++ compiler. These are source-math differential
goldens, not a claim that the native OpenSpades executable was built or run.

Fixtures cover cardinal/negative boundary hits, equal-time axis priority,
three-axis ties, step-versus-metre budgets, original-size wrapping, sky entry,
cached sky columns, virtual floor, binary32 slopes/hit positions, near-axis rays,
legacy unnormalized input and fractional lengths, 1024 quantization differences,
zero/start-solid/miss cases, query-only subclasses, maximum budgets and invalid
inputs. World wrappers and deferred byte/path imports use an authored original
VXL floor fixture, distinct from the committed Title map. No Main, settings,
GPU or browser run is part of this helper suite.

Run from the repository root:

```powershell
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/world/test_source_rays.gd
```

Godot 4.7.2 `ed1daf0bf` passed **377 assertions / 0 failures** with clean stderr.
Exact Vector3 equality, rather than an adjustable position tolerance, verifies
the literal binary32 hit-position goldens. This establishes native headless
data behavior; browser execution, final consumer routing and gameplay acceptance
are separate checks.
