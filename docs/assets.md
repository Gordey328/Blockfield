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

Validated import: 513 files; 34 GLB models (25,016 triangles), 146 Vorbis sounds,
296 PNG images, 1 VXL map, 17 locale descriptions, 16 original gettext PO catalogs,
1 gettext POT source template, 1 TTF and 1 bitmap font; 20,850,303 bytes.
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
  TGA orientation follows `Core/TargaReader.cpp`, which deliberately ignores origin
  flags. Pillow's spec-compliant origin adjustment is undone to match the source.
- Original bundled map: `res://assets/openspades/maps/Title.vxl`. Export presets must
  include `*.vxl` explicitly; maps are data read by `FileAccess`, not Godot scenes.
- Locale descriptions and original gettext messages are preserved under `locales/`.
  `OpenSpadesLocalization` installs the original PO catalogs through Godot's native
  loader with original message contexts and plural rules.
- Original fonts: `fonts/Gfx/Fonts/AlteDIN1451.ttf` and `100-unifont.fnt`. The official
  optional GNU Unifont pak supplies 57,085 original glyphs and a 4096² bitmap atlas.
  The importer converts its `.ospfont` descriptor to AngelCode BMFont, preserving
  coordinates/advances/offsets; the exact GPL/font-embedding-exception notice is included.

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
`CharacterView.set_intel_carrier(bool)` adds the original enemy-colored intel at the
source torso offset `(0, .6, .5)`, scale 0.1, for living standing/crouching carriers.
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

## Localization contract

`OpenSpadesLocalization.install()` registers 16 original PO catalogs plus the authored
Russian offline-lab catalog. English uses the original source strings. The 17 selectable
languages come from `get_languages()`: English, Russian, German, Greek, Spanish, French,
Hungarian, Indonesian, Japanese, Korean, Dutch, Polish, Brazilian Portuguese, Portuguese,
Ukrainian, Vietnamese and Chinese. Original `pt_br`, `pt_pt` and `en_us` identifiers map
to Godot `pt_BR`, `pt_PT` and `en_US`. Region variants select the available catalog.

`set_locale(id)` changes Godot's `TranslationServer` locale. Existing controls must refresh
on `NOTIFICATION_TRANSLATION_CHANGED`; `lab(original Russian label)` supplies authored
English/Russian lab text. Other languages use English for lab-only text. Original messages
use `text(message, context, arguments)` and `plural(message, plural, count, context, arguments)`.
Weapon names use context `Client`, language settings `StartupScreen`. Original positional
placeholders use `{0}`. New lab text is clearly separate from upstream catalogs; preserving
catalogs does not imply that every source screen has already been ported.

`godot --headless --path game --script ../tests/presentation/test_localization.gd`
passed 76 assertions: catalog installation, all language descriptions, normalization,
message contexts, original Russian 1/2/5 plural forms, numbered formatting, English/German
lookups, lab fallback, original Cyrillic/CJK bitmap glyphs and teardown. `get_ui_font()`
wraps the Godot default UI font with the original Unifont fallback; assign it to a parent
control's theme default font. This supplies browser glyphs without host-installed fonts.
Catalog bytes, provenance, checksums and GPL notices
are included in the asset manifest/distribution.

## Effects contract

`OpenSpadesEffects` is a scene-owned `Node3D`; call `setup(world, camera)` once. It owns visual
particles, casing contact audio and temporary lights, and never edits gameplay blocks.
Use `muzzle_fire`, `blood`, `block_hit`, `block_destroy`, `water_hit`, `grenade_explosion`,
`eject_shell`, `tracer` and `kick_camera` at the corresponding controller/session events.
`block_destroy` is for directly deleted cells; world-owned falling-cluster batches handle
collapsed components. `get_camera_rotation()` supplies a temporary pitch/yaw/roll offset
to add to the unshaken camera pose. `clear()` resets a lab/map and `stop_audio()` releases
stream/playback references before teardown.

All 17 original language names, including Japanese, Korean and Chinese, were reviewed
with the real OpenGL Compatibility renderer after matching the TGA atlas orientation.
The bitmap-font descriptor includes atlas provenance so Godot invalidates its embedded
font cache when the source atlas/orientation changes.

Emission counts, color/radius/growth/trajectory/lifetime/fade parameters and 32 m/s² particle
gravity are adapted from `Sources/Client/Client_LocalEnts.cpp` and `ParticleSpriteEntity.cpp`.
`SmokeSpriteEntity.cpp` supplies original 180-frame steady Smoke1 and 48-frame explosion
Smoke2 resources and playback rates. `GunCasing.cpp` supplies original KV6 casing scale 0.02,
velocity, weak bounce, first contact sounds and two-second ground lifetime. Source rifle/SMG
shells eject on firing; the source does not eject shotgun brass on firing (pump ejection is
an upstream FIXME). `Tracer.cpp` supplies `Gfx/Ball.png`, source velocities slowed by 0.5 and
moving 1/30-second streak segments. Local first-person tracers are suppressed as upstream.
`Client_Scene.cpp` supplies random/coherent angular shake and `Client_Update.cpp` its decay.

Adaptations requiring visual comparison: sprites use Godot's alpha blending rather than the
original renderer's premultiplied pipeline; tracer streaks use one textured quad rather than
11 layered long sprites; coherent shake uses Godot noise and omits source FOV shake.
The postprocess below adds hurt/rotation blur; explicit local-fire and explosion radial
shake inputs still need to be connected for identical source behavior. Terrain/light
response is owned by the world renderer. Particle, shell,
tracer and light budgets (defaults 512/48/64/8) keep repeated lab events bounded in browsers.
Casing collision uses the world voxel sampler and 60 Hz substeps; a 15-second flight limit
also bounds shells falling beyond a map. Spatial impact/weapon audio remains controller-owned.

`godot --headless --path game --script ../tests/presentation/test_effects.gd`
checks source emission groups, shell/contact/lifetime behavior, all tracer velocity profiles,
first-person suppression, budgets, finite transforms, animated frame updates, gravity and
cleanup. `render_effects.gd` can capture the real OpenGL Compatibility renderer using the same
`--output=<absolute dir>` convention as the model preview. Screenshots stay in ignored `.cache/`.

## Compatibility renderer effects

`OpenSpadesPostEffects.setup(camera,world_environment)` creates one world color pass
and an optional opaque-depth pass. `set_options(Dictionary)` validates updates atomically;
`preset("low"/"medium"/"high")` and `get_options()` support UI/settings storage. Unknown
native `hdr`/`gi` switches are rejected. The selected replacements are explicitly
`tone_map` and `ambient_energy`, whose effects are real and separately adjustable.

Call `update_state(delta,health,hurt_age,sprinting,aiming_float,focus_distance)` with ADS
state 0..1; `damage(amount,direction_angle)` can start autonomous hurt decay. Normal main
UI owns red flash, edge sprites and directional ring. Post overlays default disabled;
`set_hurt_overlay_enabled(true)` is only for isolated previews. PostEffects handles source
scene desaturation/radial blur without drawing the HUD's hurt overlay a second time.
`set_flare_sources([{position_or_direction,color,energy,radius,visible},...])` accepts at
most four lights; the owning world ray determines visibility/occlusion. `reset()` clears
damage/motion state. Environment energy changes only on option updates, not every frame.

| Setting | Implemented behavior and source adaptation |
| --- | --- |
| `fxaa`, `msaa` 0/2/4 | Screen-space FXAA and actual viewport geometry MSAA. |
| `bloom` | Bounded screen mip/downsample blur, threshold and original LensDustTexture; LDR rather than native HDR bright-pass pyramid. |
| `lens` | Source radial chromatic separation (.008) and mild corner shading. |
| `lens_flare` | Original flare images with halo and mirrored ghost, four world-visible lights; owner ray replaces native depth-scanner mask. |
| `color_correction`, `saturation`, `exposure` | Source equal-channel grayscale, fog tint, smoothstep enhancement and `2^(exposure*.5)` adjustment. |
| `tone_map` | Source ACES curve applied to LDR squared color; no true HDR render buffer or native automatic exposure. |
| `camera_blur` | Five bounded radial/rotation samples, source .15-second hurt blur decay; no depth-aware velocity blur or retained previous-frame image. |
| `dof`, `dof_strength` | Actual opaque depth, source automatic focal range `.054 + 13*ADS^3`, near-only CoC `1-depth/focalRange`; bounded 6/12 disk samples replace native hexagonal multi-pass bokeh. |
| `manual_focus` | Near and far blur at half strength, using the provided focus distance; the owner supplies manual focus input. |
| `ssao`, `ssao_strength` | Actual reconstructed opaque depth and derivative normals, bounded 6/12 neighbor samples; no native radiosity or temporal AO denoising. |
| `ambient_energy` | Changes actual environment fill lighting. This is an explicit radiosity/GI visual replacement, without indirect light transport. |
| `quality` 0/1/2 | Selects bloom mip scale and depth sample budget; HUD stays above postprocessing. |

Source references: `Sources/Draw/GLSettings.cpp`, `GLRenderer.cpp`,
`GLDepthOfFieldFilter.cpp`, `GLLensDustFilter.cpp`, `GLLensFlareFilter.cpp`,
`Resources/Shaders/PostFilters/{ColorCorrection,Lens,DoFCoCGen,SSAO}.fs` and
`Sources/Client/{Client_Scene,Client_Draw,HurtRingView}.cpp`. The shader integration uses
Godot's documented [Compatibility depth reconstruction](https://docs.godotengine.org/en/stable/tutorials/shaders/advanced_postprocessing.html).
The depth pass runs before transparent sprites and depth-hacked first-person equipment,
so it cannot erase the weapon. The later color pass includes those transparent objects.

Headless `test_post_effects.gd`: 79 assertions, zero failures. Real Intel UHD OpenGL
Compatibility `render_post_effects.gd`: separate on/off image pairs for 13 visible
effects, plus a first-person weapon preservation check, zero failures and clean logs.
FXAA/MSAA, bloom, lens/flare, correction/tone map, blur, auto/manual DoF, SSAO,
environment lighting and standalone hurt differences were all nonzero. The images were
visually reviewed, including bounded smooth bloom and clear view equipment with depth
effects enabled. This is adaptation evidence, not acceptance of exact native-renderer
parity or browser performance. Screenshots stay in ignored `.cache/`.

Resource override and first/third-person Godot skin entrypoints are documented in
[extensions.md](extensions.md). Remaining character parity includes native third-person
spade bash PitchBias, tool raise/cook action state and `Corpse.cpp` physical ragdoll
behavior; the current dead model is a pose, not that physics simulation.
