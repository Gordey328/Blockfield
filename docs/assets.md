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
`CharacterView.set_intel_carrier(bool,enemy_color_optional)` adds the original enemy-colored intel at the
source torso offset `(0, .6, .5)`, scale 0.1, for living standing/crouching carriers.
The optional color comes from team metadata; its value survives resource refresh.
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
`set_motion_state(forward_speed,strafe_speed,walk_progress)` uses the source gait:
`sin(progress*2*pi)*.6`, forward velocity factor 4 and strafe factor 3. Speeds are
world meters/second and are divided by 32 to obtain native velocity. The owner
supplies the source walk phase; `Player.cpp` advances horizontal distance by `.3`
only for grounded non-crouching/non-sneaking/non-ADS walking and exposes half that
distance plus half the footstep count. Legacy `animate_motion(speed,time)` remains
an explicit time-phase fallback. The view-equipment depth hack is adapted with
Godot materials, and room-dependent audio/reverb is owned elsewhere.

### Original third-person tool and corpse contract

`CharacterView.set_tool_action(action,progress,cook_time,ready_state,raise_state)`
accepts Idle=0, Bash=1, DigStart=2 and Dig=3. The original spade skin contributes
`-(1-progress)*.7` pitch for Bash; the body combines it with head pitch and sprint
`-.5`, then clamps/attenuates negative arm pitch by `.9`. Dig adds no pitch bias.
Original third-person grenade/block skins store cook/ready/raise state but do not
use it in their rendering functions; the default Godot view preserves that behavior.
`set_block_color(Color)` changes the held block independently of the uniform.
Gun/spade/grenade sentinel voxels retain `ModelRenderParam`'s original black default.
`set_ragdoll_enabled(true)` hides the static dead model when an external corpse is
spawned. The disabled-ragdoll `Dead.kv6` fallback retains source origin and has no
player yaw/pitch, as in `ClientPlayer.cpp`.

Live body model transforms now use explicit `W*native*S^-1`: source world vectors
map through `W=(x,-z,+y)`, while imported mesh vectors use `S=(x,-z,-y)`. Treating
these two conversions as identical mirrors the right-hand `.35` tool offset.
Original body scale `(.1,.1,.1)*(-1,-1,1)`, crouch offsets, head/arm pitch, two-axis
leg rotations and torso-attached enemy intel use the actual source matrices.

`OpenSpadesCorpse` in `game/presentation/corpse.gd` adapts the original
[nine-node spring simulation](https://github.com/yvt/openspades/blob/v0.1.3/Sources/Client/Corpse.cpp#L36)
and its [six original mesh transforms](https://github.com/yvt/openspades/blob/v0.1.3/Sources/Client/Corpse.cpp#L620).
It is scene-owned and never changes gameplay, voxel terrain or the owning player.

```gdscript
corpse.setup(world, {
    "feet_position": feet, "yaw": yaw, "crouch": crouching,
    "team": team, "color": team_color, "player_id": id,
    "velocity": world_velocity, "impulse": kill_impulse, "seed": optional_seed
})
corpse.step(delta)
corpse.add_impulse(world_impulse)
corpse.get_center()
corpse.is_visible_from(camera_position)
corpse.refresh_resources()
corpse.clear()
```

`feet_position`, velocity and impulses use Godot world coordinates and meters/second;
yaw rotates around Godot +Y. Capture crouch, feet and velocity before respawn/reset.
The nine points are four torso corners, two arms, two legs and head. Initial random
horizontal velocities, `.8/.9/1.204/1` pair springs, arm/leg angle constraints, head
spring, angular momentum, source gravity 32, submerged buoyancy 6, `.371` vertical
damping, axis collision order/bounce/friction and line constraints are implemented.
The owner supplies `world.clip_box(point)`, `get_block(cell)`, `dimensions` and
`water_level`. Bodies use separate original `Torso/Head/Arm/Leg` meshes; carried
equipment/intel is omitted as in upstream. Resource refresh keeps physics state.

Native [kill impulses](https://github.com/yvt/openspades/blob/v0.1.3/Sources/Client/Client_Update.cpp#L823)
are normalized victim-minus-killer direction times rifle 3.5, SMG 2.8, shotgun 4.5
or melee 6, plus victim world velocity. Grenades use upward random 4..8 instead of
that direction, including self kills. Other self kills add no directional impulse.
The owner maintains original soft/hard list limits 6/16 and removes invisible bodies
over the soft limit; no automatic 30-second expiry is added because the source's
TTL field is unused. Clear bodies on map/lab reset and release their scene nodes.

Explicit adapters: native four substeps per render frame are preserved at 60 Hz or
faster; slower frames add substeps to retain at least 240 Hz and a paused browser
resume processes at most `.25` seconds of cosmetic simulation. Zero-length/parallel
bases retain the last valid render transform instead of producing NaNs. Horizontal
voxel addressing wraps map dimensions. Native `LineCollision`/`IsVisibleFrom` pass
an endpoint to the old direction-based `CastRay` prefilter, and visibility returns
the hit rather than unobstructed state; that legacy inconsistency is replaced by
finite-segment voxel DDA and intended any-unoccluded-point visibility (150 m limit).
Line queries retain the source eight-cell budget, escape order and force/friction.
This source adaptation is documented rather than claiming identical native bugs.

Validation commands:

```powershell
godot --headless --path game --script ../tests/presentation/test_character_actions.gd
godot --headless --path game --script ../tests/presentation/test_corpse.gd
godot --path game --rendering-method gl_compatibility `
  --script ../tests/presentation/render_character_corpse.gd -- --output=<absolute dir>
```

Behavior checks include literal source-formula first-frame point/mesh fixtures,
crouch/yaw, black tool colors and independent block tint, Bash/sprint/head separation,
forward/backward/strafe gait, velocity/impulse, gravity/buoyancy, floor and line
collisions, occlusion, resource refresh, cleanup and 10-second finite-body stability.
Headless character/corpse checks passed 30/9,046 assertions respectively, zero failures.
Godot 4.7.2 real Intel UHD OpenGL Compatibility preview passed seven image-difference
checks, with clean logs. Standing/crouching death frames, impulse/falling/settled
bodies, forward/strafe poses, spade Bash and colored-block/intel previews were visually
reviewed. These fixtures/renderer checks are module evidence; full-build event timing,
death-camera following, corpse pruning and browser acceptance require full-build checks.

### Original first-person skin contract

`WeaponView` adapts the source
[tool/ADS/sprint state](https://github.com/yvt/openspades/blob/v0.1.3/Sources/Client/ClientPlayer.cpp#L318),
[view movement and two-segment arm IK](https://github.com/yvt/openspades/blob/v0.1.3/Sources/Client/ClientPlayer.cpp#L650)
and all six original `Resources/Scripts/Skin/<tool>/View.as` renderers.
The source eye matrix maps view coordinates through `E=(-x,-z,-y)`, rather than
the imported-mesh conversion `S=(x,-z,-y)`. A single `SourceViewAxes` parent preserves
this distinction: hip equipment sits on screen right, the source left/right shoulder
anchors sit on their corresponding sides, and ADS centers the original front sight.
Original weapon subpart pivots/scales, rifle half-resolution correction and source
matrix multiplication order remain explicit.

```gdscript
view.set_selection(tool,weapon) # tool 0..3; weapon 0..2
view.set_team(team,team_color_optional)
view.set_ammo(ammo,clip_size)
view.set_tool_action(action,progress,ready_state)
view.set_motion_state(camera_local_velocity,walk_progress,front_delta,manual_offset)
view.set_grenade_cook(seconds)
view.update_pose(delta,aiming,sprinting,crouching,speed,reload_progress)
view.fire()
view.reload()
view.reload_completed()
view.cancel_reload()
view.get_muzzle_transform()
view.get_sprint_state()
view.is_changing_tool()
view.get_eye_bob()
```

Action values are Idle=0, Bash=1, DigStart=2 and Dig=3. First DigStart has the source
quadratic preparation; repeated Dig begins in its ready pose. Block readiness hides
the block and restores the source hand targets. Grenade readiness is normalized to
the `.5` second cooldown, including the source throw arc, pin pull and bring-up.
**Do not clamp ReadyState to one**: gun/grenade states may exceed one after cooldown;
the grenade bring-up and completed shotgun reload depend on that source behavior.
Gun state is `1-TimeToNextFire/GetDelay`, grenade state is `1-TimeToNextGrenade/.5`.
For gun reloads, call `reload_completed()` on completion; shotgun progress continues
above one for the source final pump, without simulating an extra shot. Per-shell
ammo/clip values determine intermediate versus last-shell pump blending.

Rifle/SMG resting and bolt/reach hand targets are calculated before sight alignment;
magazine attachment targets are calculated after it. Shotgun reload reach/insert
targets use the former transform, while pump/rest targets use the latter. The pump
on firing uses remaining cooldown fraction, rather than elapsed cooldown fraction.
Arm IK retains the source equal-length segments and bend side, with finite guards
for degenerate segments. Original gun/spade/grenade custom color defaults to black;
held blocks use their separate selected color and arm sentinels use team metadata.
Original gun surfaces themselves have fixed vertex colors and no team-color faces.

Raw sprint rises at `4/s` and falls at `3/s`; source smoothstep, squared skin input
and `.001^delta` rising smoothing remain separate stages. ADS rises at `8/s` and
falls at `3/s`. Tools lower before replacement, then raise at `4/s` through the
source squared/clamped curve. `tool_raised(tool,weapon)` emits once at actual replacement,
so the owner can play `RaiseLocal` then. Selecting another gun class in the offline
lab has no native live-switch equivalent; it immediately replaces that class and
uses the same raising curve. Ammunition remains authority-owned.

`is_changing_tool()` is a required compiled skin contract for the owner's source tool-use
gate: it compares displayed versus requested tool and the raw raise counter against
`.999`, not the eased visual raise value. Original `Client::CanLocalPlayerUseToolNow`
also rejects actions while `get_sprint_state()>0`, including sprint decay after the
key is released. The controller applies those gates before committing an action.

Movement velocity uses camera-local Godot meters/second and is divided by 32.
`front_delta` is camera-local change of the owner's unshaken forward vector.
The source inertia, decay, soft limits, gait bob and heartbeat pulse are retained.
`manual_offset` retains native `cg_viewWeaponX/Y/Z` units: X screen-left, Y forward,
Z down. The optional eye-bob getter returns the source positive camera-Y sprint bob;
the owner applies it according to its shake setting. The muzzle getter preserves
`ClientPlayer::FiredWeapon`'s fixed eye-local point `(-.13,1.5,.2)`, independent of
weapon/ADS/reload. It is an effects origin rather than the animated mesh barrel.
All FP equipment/arm meshes occupy render layer 19 (`1 << 18`), also after resource
refresh; world reflection cameras exclude that layer, while the main camera sees it.

`test_weapon_native.gd` passed 65 assertions with literal native pose/hand fixtures,
all reload hand stages, final shotgun pump lifecycle, dig/grenade timing, source
state rates, delayed tool-swap signal, custom uniform tint, reflection layer and refresh.
`render_weapon_native.gd` passed ten actual Intel UHD OpenGL Compatibility image
checks with clean logs: three hip/ADS pairs, first/repeated dig, ready/unready block,
pin/throw movement. All three weapons' reload stage images, pump and custom-color
arms were also captured and visually reviewed. Screenshots stay in ignored `.cache/`.
Run both scripts with the same headless/GPU commands above, substituting their names.
These tests establish source-formula/module rendering evidence; full controller event
timing, native-renderer comparison and browser performance remain acceptance work.

### Observed first-person soldiers

`OpenSpadesSpectatorView` in `game/presentation/spectator_view.gd` supplies equipment
for the live soldier selected by a first-person follow camera. This follows
[ClientPlayer::AddToScene and ShouldRenderInThirdPersonView](https://github.com/yvt/openspades/blob/v0.1.3/Sources/Client/ClientPlayer.cpp#L992):
the camera target receives a view skin regardless of whether it is the local player.
The owning controller positions/rotates the camera and suppresses the followed
soldier's third-person body as required by that camera mode.

```gdscript
camera.add_child(observed_view) # Identity transform; the camera owns its pose.
observed_view.setup(camera,session,skin_id)
# Each frame, after the owner updates the follow-camera transform:
observed_view.show_target(followed_id,is_first_person_follow)
observed_view.update_view(delta)
observed_view.refresh_resources()
observed_view.set_skin(id)
observed_view.clear()
```

Updates are manual; there is no independent `_process` ordering to race the camera.
Repeated `show_target` calls with unchanged arguments preserve motion samples.
Missing, dead, zero-health, invalid-position and spectator-team targets hide the
equipment. Changing target or respawning creates a fresh skin; `clear()` frees it
and retains setup references for a subsequent follow. The original
`WeaponView.initialize_selection(tool,weapon)` immediately selects the starting
tool for a new view, without a live tool-change delay or `tool_raised` signal.
Trusted skins may implement this optional API; otherwise their ordinary initial
`set_selection` behavior applies. Later live tool changes retain native lowering.
Every observed visual mesh is assigned layer 19, including custom skins and refresh.

The adapter only queries `get_target(id)` and optional `get_team_info(team)` from
the session. It never reads the local player's ammo/weapon, invokes game authority,
changes the camera/snapshot, or attaches own-local audio. A trusted first-person
factory receives `{target_id,snapshot,spectator:true,local_audio:false}`; the snapshot
is copied and no live session reference is provided. Custom skins must honor that
context and keep their presentation methods free of own-local sounds/game actions.

Target fields are `position`, `team`, `weapon`, `tool` and optional `alive`, `health`,
`state`, `pitch`, `yaw`. Explicit `team_color`/`color` overrides team metadata.
The following optional snapshot fields drive the existing view-skin API:

| Fields | Presentation behavior |
| --- | --- |
| `crouching`, `sprinting`, `aiming` | State booleans; corresponding `state` strings are fallbacks. |
| `velocity`, `walk_progress` | World meters/second and native walk phase. Otherwise velocity comes from previous position and phase advances by horizontal distance times `.15`, when grounded/non-crouching/non-sneaking/non-ADS. Pitch/yaw convert motion and front changes to observed camera-local axes. |
| `profile`, `clip_size`, `ammo`/`magazine` | Target profile overrides current session profile; absent ammo uses the full selected profile clip. |
| `block_color`, `grenade_cook_time`/`cook_time` | Held resource color and original grenade pin/cook animation. |
| `action_type`, `action_progress`, `ready_state` | Original tool action and unbounded readiness; alternatively `action:{type,progress,ready}`. Missing action is idle and readiness is fully ready. |
| `is_reloading`/`reloading`, `reload_progress`, `reload_cancelled` | Source reload stages, repeated shell-cycle resets and completion/cancellation. |
| `shot_sequence` | A changed sequence triggers only the skin's visual recoil; first observation establishes a baseline. |

Absent remote action data deliberately produces an idle full-clip view rather than
inventing remote gameplay. Animation steps are capped at `.25` seconds after a
paused/slow frame. This module does not add multiplayer snapshots or remote firing
to offline targets; supplying those fields is the owning session's responsibility.
Headless `test_spectator_view.gd` passed 43 assertions, zero failures, including
read-only authority, profile changes, optional states, motion, skin isolation,
death/respawn/invalid hiding, reflection layers and cleanup. Actual Intel UHD OpenGL
Compatibility `render_spectator_view.gd` passed 11 image checks with clean logs.
Three observed hip/ADS weapons, grenade pin and spade actions were captured and
visually reviewed; dead/missing targets matched the empty frame. Full follow-camera
integration and browser acceptance remain separate checks.

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
[extensions.md](extensions.md). The source character/action and physical-corpse modules
are implemented as above. Full character parity still requires full-build checks of
walk/action timing, pre-reset death state/impulses, list pruning, local death-camera
following and browser acceptance. Original third-person grenade/block cook/raise values
are intentionally stored without adding an animation absent from those source skins.

## Source camera effects

`SourceCameraEffects` in `presentation/source_camera_effects.gd` ports
`Client_Scene.cpp:111..119,201..247,384..440`, `NoiseSampler.cpp:29..83` and
`Client_Update.cpp:248..258` from the pinned v0.1.3 source. It is a scene-independent
`RefCounted` helper. It samples presentation effects without editing camera targets,
authoritative aiming rays, movement, ADS state or gameplay RNG.

`sample(input,time,dt)` accepts `shake_level`0/1/2, `first_person`, raw normalized
`raw_ads`/`raw_sprint`, `walk_phase` in native cycles, `last_fire_time` on the same
clock as `time`, native `tool`0=spade, `ads_zoom_scale` from the current local/follow
camera target, and `grenade_fast`/`grenade_slow` intensities. Those intensities are
already decayed by the owner; `sample` does not decay them again or mutate `input`.
An optional separate `decay_intensities(input,dt)` returns the native subtract-dt,
clamp-at-zero result. Use that helper or the existing effects-manager decay once.

The100 ms fire envelope is squared before the spade0.4 multiplier. Shake level1
adds its native random roll/FOV, pitch/yaw and radial blur, plus sine/cosine sprint
angles. Sprint pitch uses cos^8; the separate view-skin eye bob uses cos^16.
Level2 adds source coherent sprint angles and SmoothStep(sprint)*0.1 FOV widening.
Fast grenade intensity multiplies10 and clamps at1, adding random angles/FOV and
radial blur. Slow intensity multiplies4, clamps at1 then squares, adding coherent
angles at time rates8/12/11. Grenade effects apply to all camera modes; fire/sprint
effects require `first_person`. Level0 disables all these shake channels.

The canonical result is `basis_delta`, a local proper rotation preserving native
roll→pitch→yaw order and source-axis conversion. `rotation_delta` is its diagnostic
Godot YXZ Euler decomposition in radians; it is not an additive world-space rotation.
`fov_scale` multiplies **tan(current already-ADS FOV/2)**, not FOV degrees. Native fire
and sprint modify scale before dividing by ADS zoom, while fast grenade modifies it
afterwards. Therefore the relative result includes that grenade delta times the
owner's zoom. `native_fov_scale` is the diagnostic complete multiplier for unzoomed
FOV. This preserves ADS ownership and prevents duplicate zoom in local/follow views.

```gdscript
var sample := camera_effects.sample(camera_inputs, session_time, delta)
camera.basis = unshaken_basis * sample.basis_delta
camera.fov = SourceCameraEffects.apply_fov_degrees(zoomed_fov, sample.fov_scale)
# Send sample.radial_blur_strength to the owning post chain; do not also add
# the legacy OpenSpadesEffects.get_camera_rotation() offset.
```

The source coherent sampler uses three1024-entry value/gradient pairs, smooth cubic
interpolation plus the native gradient polynomial, and1024-period wrapping including
negative coordinates:24 KiB of packed float32 table data. Its private Godot RNG
preserves source distributions but not native `std::uniform_real_distribution`
seed sequences. `reset_noise(seed)` makes this stream reproducible and independent
of gameplay. `set_noise_tables(axis,values,derivatives)` and sample inputs
`random_values`, `sprint_noise`, `grenade_noise` permit fixed native fixtures without
global RNG changes. Source formulas are checked within floating-point tolerance;
bit-identical C++ float arithmetic is not claimed.

Godot4.7.2 `ed1daf0bf`: `test_camera_effects.gd` passed45 numeric checks, including
native combined angles(.021039,.007841016,.060663492), radial strength.0525 and
base68°/ADS2.4 FOV34.857015°. `render_camera_effects.gd` passed7 real Intel UHD
Compatibility GPU checks: tangent-FOV image difference.002852, independent angular
difference.006013, rendered/projected marker agreement within2 pixels, and exact
image restoration at shake level0. The PNGs were visually inspected. This demo
verifies camera pose/FOV integration; actual radial-post integration and exported
browser behavior are acceptance checks owned by the full client. Run the usual
headless script command for numeric tests and graphics-enabled Compatibility with
`-- --output=<absolute evidence directory>` for the GPU demo. Godot's Euler
conventions are documented in [Basis](https://docs.godotengine.org/en/4.7/classes/class_basis.html).
