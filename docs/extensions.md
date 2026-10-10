# Resource packs and Godot skin extensions

OpenSpades v0.1.3 prepends resource filesystems and selects tool skins through
`CreateView*Skin` / `CreateThirdPerson*Skin` AngelScript functions. The relevant source is
`Sources/Core/FileManager.cpp`, `Sources/Gui/Main.cpp`, `Sources/Client/ClientPlayer.cpp`
and `Resources/Scripts/Reference/Skin/`.

Blockfield replaces that runtime with two explicit mechanisms: data-only ZIP overrides
and trusted Godot factories compiled into the game. Uploaded packs do not execute
AngelScript, GDScript, scenes, shaders or native extensions. Raw OpenSpades `.pak`/KV6/Opus
files need offline conversion; they cannot be loaded directly by this API.

## Pack format

A ZIP contains `blockfield-pack.json`, declared static GLB models, PNG textures and Ogg
Vorbis audio. Optional `.txt`/`.md` attribution files are accepted. Directory entries are
not needed. Use original virtual paths from `game/assets/openspades/manifest.json` as
targets, even when the replacement has a converted extension:

```json
{
  "version": 1,
  "id": "my-equipment",
  "title": "My equipment pack",
  "authors": ["Author name"],
  "license": "License name, required notices, and attribution",
  "assets": {
    "Models/Weapons/Rifle/WeaponNoMagazine.kv6": {
      "file": "rifle.glb",
      "type": "model",
      "sha256": "<SHA-256 of exact rifle.glb bytes>"
    },
    "Gfx/AlertIcon.png": {
      "file": "alert.png",
      "type": "texture",
      "sha256": "<SHA-256 of exact alert.png bytes>"
    },
    "Sounds/Feedback/Alert.opus": {
      "file": "alert.ogg",
      "type": "sound",
      "sha256": "<SHA-256 of exact alert.ogg bytes>"
    }
  }
}
```

Compute a digest with Python `hashlib.sha256(Path(path).read_bytes()).hexdigest()`.
The hash verifies declared bytes; it is not an author signature or a license check.
Authors must have permission to distribute every replacement. Include the exact
notices for derivatives of original assets; the original notices are under
`game/assets/openspades/licenses/`. Transcoding does not change asset authorship.

Model coordinates, pivots and material groups must match the replaced part. The
offline KV6 importer maps source coordinates to Godot `(x, -z, -y)` and preserves raw
voxel units; view code applies original scales. A material named `TeamColor` receives
the player's team/block tint. Other PBR materials and vertex colors are preserved.
GLBs must embed one binary buffer and any PNG textures; external URI resources,
animations, skeletal skins, cameras and required extensions are rejected. Parts are
static meshes animated by the owning Godot skin.

Limits are enforced before ZIP extraction: 32 MiB archive, 64 MiB decoded entries,
16 MiB per entry, 512 files, 128 overrides per pack and four active packs. Encrypted,
multidisk and ZIP64 archives are unsupported. Traversal, absolute paths, drive/URI
paths, backslashes, duplicate names and undeclared executable files are rejected.
PNG images are limited to four megapixels and 4096 pixels per side. Audio is Vorbis
and at most 60 seconds. GLBs have bounded object/accessor counts and embedded-buffer
checks; resource memory estimates are limited to 64 MiB per pack. These limits also
apply to embedded model textures. Fonts and new virtual resource names are currently
unsupported; the bundled Unicode fallback font remains active.

## Loader and refresh contract

`OpenSpadesExtensions` exposes static methods:

- `load_pack_file(path)` on desktop; `load_pack_bytes(PackedByteArray)` on desktop/web.
- Result: `{ok:false,error:String}` or `{ok:true,id,resources,archive_sha256}`.
- `get_packs()` returns attribution and digest metadata; `remove_pack(id)` and `clear()`
  release active overrides. `get_generation()` changes after each successful mutation.
- `texture(original_virtual_path_or_converted_res_path)` and `sound(...)` resolve the
  newest active override, then the original resource. `model_override(relative_path)`
  returns a `PackedScene` override or null. Model names omit `Models/` and `.kv6`.

The loader stages uploaded bytes in `user://`, reads a ZIP without extracting paths,
decodes allowed data, then removes the temporary archive. Successful imports are
atomic: validation failure leaves active resources unchanged. Reloading an existing
pack id replaces it; otherwise the newest pack wins. Removing it reveals the previous
override or the original. Active packs are session data; this helper does not persist
uploaded bytes across a browser reload.

`OpenSpadesModels.create()` detects the generation and invalidates its scene/material
caches automatically. Existing objects hold their old resources until refreshed:

- `WeaponView.refresh_resources()` preserves selection/team/animation state and reload.
- `CharacterView.refresh_resources()` preserves weapon/tool/team/pose/intel state.
- `OpenSpadesEffects.reload_resources()` clears current cosmetic particles/casings and
  audio, then drops texture/tracer caches; later effects use the pack.
- `OpenSpadesPostEffects.reload_resources()` rebinds dust/flare/hurt image resources.
- The owning main/controller refreshes objective/grenade model instances and audio;
  the HUD refreshes its texture bindings through the resolver.

The main UI supplies the desktop file picker or browser `File.arrayBuffer()` bridge.
It must show the result/error and call these refresh methods only after `ok:true`.
Browser WebGL runtime import still needs browser acceptance in the full exported game;
native GPU checks alone do not establish web compatibility.

## Trusted Godot skin entrypoints

`register_skin(id, first_person_factory:Callable, third_person_factory:Callable)` is
called only by code already compiled into the project. Factories receive a copied
context dictionary and return an unattached `Node3D`. `get_skins()` includes `original`.
Create a view with `create_first_person_skin(id,context)` or
`create_third_person_skin(id,context)`. Missing contract methods reject the factory result.

The first-person contract is `set_selection`, `is_changing_tool`, `update_pose`, `fire`, `reload`, `set_team`,
`set_block_color`, `set_ammo`, `set_grenade_cook`, `set_spade_action`, `cancel_reload`,
`reload_completed`, `get_muzzle_transform`, `refresh_resources`. The original
`WeaponView` implements it. The third-person contract is `set_team`, `set_pose`,
`set_weapon`, `animate_motion`, `set_aim`, `set_intel_carrier`, `refresh_resources`;
the original `CharacterView` implements it. Derive from these classes to retain the
current controller's static types and method signatures. The tool/weapon id convention
remains tools 0 spade / 1 block / 2 gun / 3 grenade and guns 0 rifle / 1 SMG / 2 shotgun.

This is a Godot extension contract, not binary compatibility with AngelScript interfaces.
Uploaded packs change resources of existing animations. Custom animation logic requires
reviewed project code, registration and a new exported game build. First-person hand IK,
eye-local positioning, third-person origins, pitch and source action state are owned by
the corresponding skin rather than by an uploaded executable asset.

Current callers pass `set_team(index, Color)` and third-person
`set_intel_carrier(enabled, enemy_team_color)`. Factories must preserve these signatures.
Optional first-person hooks are `initialize_selection(tool,weapon)` (immediate first
attachment, no raise event), `set_tool_action(type,progress,ready_state)` and
`set_motion_state(camera_local_velocity,walk_progress,front_delta,manual_offset=ZERO)`.
Readiness can exceed1 after a grenade throw or firearm delay; do not clamp it globally.
The optional `tool_raised(tool,weapon)` signal fires at the actual animated swap.
Optional third-person hooks are `set_motion_state(forward_speed,strafe_speed,walk_progress)`,
`set_tool_action(type,progress,cook_time,ready_state,raise_state=1)`,
`set_block_color(Color)` and `set_ragdoll_enabled(bool)`.

First-person visuals occupy layer19 (`1<<18`) so reflected-world cameras can exclude
hands/equipment. Spectator factories receive a copied `snapshot`, `target_id`,
`spectator:true` and `local_audio:false`; they must not fire authority actions or local
player sounds. Snapshot presentation fields are documented in assets.md.

## Verification

`godot --headless --path game --script ../tests/presentation/test_extensions.gd` passed
67 assertions on Godot 4.7.2: original GLB/PNG/Vorbis import, aliases, cache generation,
attribution, failure atomicity, traversal/hash/type/executable/size rejection, malformed
and external-reference GLBs, both skin contracts and state-preserving resource refresh.

`godot --path game --rendering-method gl_compatibility --script
../tests/presentation/render_extensions.gd -- --output=<absolute directory>` separately
checks real runtime GLB and PNG replacements. Intel UHD Compatibility rendering produced
normalized RGB differences 0.00162044 for the model and 0.00214572 for the texture, with
zero failures and clean logs. The original/overridden frames were visually reviewed;
test screenshots and generated packs remain in ignored `.cache/`/`user://`.
