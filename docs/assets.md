# OpenSpades asset pipeline

## Fixed provenance

Reference: OpenSpades `v0.1.3`, source commit `dcf449c845d509bbde9d79239b32d201c1389961`.
The official development package URL comes from `Resources/PakLocation.txt`:
`https://github.com/yvt/openspades-paks/releases/download/r33/OpenSpadesDevPackage-r33.zip`.
Package SHA-256: `0927dc323a0b3aba0ee8d1d68d6b544b00fe654740fead6d1faad37aac77a2ad`.

`tools/import_openspades.py` reads the source resources and the nested ZIP-format
`Nonfree/pak000-Nonfree.pak`; it does not execute upstream shell/PowerShell scripts.
The original pak overrides source `.weak` fallbacks, matching OpenSpades resource precedence.
Original archives and local conversion dependencies live in ignored `.cache/`.

## Rebuild and validation

Requirements: Python 3.10+, Pillow, and a local FFmpeg executable with `libvorbis`.
The importer's KV6 and GLB code uses only the Python standard library.
FFmpeg can be supplied through `--ffmpeg`; it is not installed globally by the importer.

```powershell
python tools/import_openspades.py --download --ffmpeg <local-ffmpeg-path> `
  --pack-sha256 0927dc323a0b3aba0ee8d1d68d6b544b00fe654740fead6d1faad37aac77a2ad
python tools/import_openspades.py --verify --ffmpeg <local-ffmpeg-path>
```

Outputs live in `game/assets/openspades/`. Its `manifest.json` maps each original
virtual resource path to its output path and records original/output SHA-256,
size, dimensions/pivot, geometry counts and unresolved placeholders.
Identical inputs preserve existing audio and produce an identical manifest.

Validated import: 494 files; 34 GLB models (25,016 triangles), 146 Vorbis sounds,
295 PNG images, 1 VXL map, 17 locale JSON files and 1 TTF font; 12,565,280 bytes.
Validation checks every output checksum, GLB buffer/accessor extents, finite values,
vertex/index counts, outward triangle winding, PNG decoding and every sound decoding.
Deterministic reimport was checked. Godot import and browser presentation remain separate checks.

## Model contract

Paths are `res://assets/openspades/models/<original path below Models>.glb`.
The importer preserves KV6 pivots and voxel dimensions in original model units.
Coordinate conversion is `(x - xpivot, -(z - zpivot), -(y - ypivot))`:
Y is up and source +Y forward becomes local -Z. Mesh winding/normals account for
the reflection. Enclosed air is treated as filled, matching `VoxelModel::HollowFill`.
Only exterior faces are emitted. Per-voxel sRGB colors are converted to linear glTF vertex colors.

Black voxels are OpenSpades' `customColor` sentinel. They use a separate material
named `TeamColor`; replace that surface material to change uniforms or block color.
Preserve the other `VoxelColors` surface to retain faces, boots and equipment colors.
The default team material is blue. There are no separate blue/green character files:
the original shared parts are recolored at runtime.

| Original group | Imported parts |
|---|---|
| `Player` | `Head`, `Torso`, `TorsoCrouch`, `Arms`, `Arm`, `UpperArm`, `Leg`, `LegCrouch`, `Dead` |
| `Weapons/Rifle` | `Weapon`, `WeaponNoMagazine`, `Magazine`, `Casing`, `Sight1`, `Sight2` |
| `Weapons/SMG` | `Weapon`, `WeaponNoMagazine`, `Magazine`, `Casing`, `Sight1`, `Sight2`, `Sight3` |
| `Weapons/Shotgun` | `Weapon`, `WeaponNoPump`, `Pump`, `Casing`, `Sight1`, `Sight2` |
| Other tools | `Weapons/Spade/Spade`, `Weapons/Block/Block`, `Weapons/Block/Block2`, `Weapons/Grenade/Grenade` |
| Map objectives | `MapObjects/Intel`, `MapObjects/CheckPoint` |

`ClientPlayer.cpp` uses player part scale 0.1 and view arm scale 0.05.
The original first-person skins use gun/tool scale 0.033 and third-person guns 0.05.
Rifle `WeaponNoMagazine` has twice the voxel resolution of `Weapon`: its view scale
is 0.033 * 0.5, plus the source half-voxel X correction. Sights have their own smaller
scales and original placements; reload magazines and shotgun pump are separate parts.

Four upstream `.weak` models remain unresolved even with the official pack:
Rifle/SMG/Shotgun `Tracer`, and SMG `WeaponNoMagazine-old`. They are excluded and
listed in the manifest, not silently represented as real models. Tracers require a
presentation implementation; the old SMG part is unused by the current skin.

## Audio, UI and map paths

Godot does not import the original Opus format as its normal audio stream. The
pipeline transcodes to Ogg Vorbis for native and browser imports; source hashes
remain recorded. Resource playback and spatial mixing still require game code.

- Rifle: `res://assets/openspades/sounds/Weapons/Rifle/FireLocal.ogg`.
- SMG: `sounds/Weapons/SMG/V2Local1.ogg` through `V2Local4.ogg`.
- Shotgun: `sounds/Weapons/Shotgun/FireLocal.ogg`, `CockLocal.ogg` and `ReloadLocal.ogg`.
- Other resources preserve paths under `sounds/Player`, `sounds/Weapons/Impacts`,
  `sounds/Weapons/Grenade`, `sounds/Feedback` and `sounds/Misc`.
- UI/effects preserve names under `images/Gfx` and `images/Textures`. Original TGA/JPEG
  resources become PNG, so `Gfx/Sight.tga` maps to `images/Gfx/Sight.png`.
- Original bundled map: `res://assets/openspades/maps/Title.vxl`. Export presets must
  include `*.vxl` explicitly; maps are data read by `FileAccess`, not Godot scenes.
- Locale dictionaries are preserved under `locales/`; they need adaptation into
  Godot translation messages before claiming localization parity.
- Original font: `fonts/Gfx/Fonts/AlteDIN1451.ttf`. Its coverage does not imply all
  original language glyphs are available. The optional Unifont pak is not imported.

## Distribution notices

All supplied upstream license/credit notices are copied byte-for-byte to `licenses/`.
OpenSpades source assets carry GPL-3.0-or-later notices. The official nonfree pack's
outer `Nonfree/LICENSE.md` permits bundling with derived free-download, free-of-charge,
noncommercial open-source projects and requires its license notice in every copy.
It forbids redistributing its audio separately. The pack's inner credits retain
older official-release wording; both notices are preserved, including font credits.
These assets are part of the complete Blockfield game/source distribution, not an
independent audio pack. Transcoding does not change authorship or license attribution.

## Presentation implementation and remaining checks

`game/presentation/character_view.gd` and `weapon_view.gd` assemble imported original
parts. Source references are `Sources/Client/ClientPlayer.cpp` and
`Resources/Scripts/Skin/{BasicViewWeapon,Rifle,SMG,Shotgun,Spade,Block,Grenade}`.
Walk/crouch/head poses, original view scales, separate sights/magazines/pump,
source-stage reload hand targets and two-segment view arms are implemented there.
Input timing, recoil state, server state and camera behavior come from the owning
controller/session; those must be verified with the full build. Matching imported
resource counts alone does not verify gameplay or visual parity.

Presentation checks: `godot --headless --path game --script ../tests/presentation/test_presentation.gd`.
Godot 4.7.2 passed 504 pose/resource combinations, including both teams, all
weapon/tool combinations, reload stages, aiming, sprinting, crouching, corpse and
spectator visibility. Independent team-color changes and finite/nondegenerate
transforms are checked. The real OpenGL Compatibility renderer also produced
character and hip/ADS gun previews for review, with no renderer errors after caching
immutable model/material resources. Preview images remain in ignored `.cache/`.

Optional GPU preview command:
`godot --path game --rendering-method gl_compatibility --script ../tests/presentation/render_presentation.gd -- --output=<absolute output directory>`.

Body coordinates at feet anchor: standing head center 2.35, torso center 1.6,
legs center 0.6, arms center 1.75; crouching head center 1.5, torso center 0.95,
legs center 0.4, arms center 1.4. Hit zones must follow the same crouch state.
Walking is a source-amplitude procedural approximation from speed/time; strafing
gait input is not provided by the current API. The view-equipment depth hack is
adapted with Godot materials, and room-dependent audio/reverb is owned elsewhere.
