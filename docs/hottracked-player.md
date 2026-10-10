# Native hottracked player outlines

`game/presentation/hottracked_player.gd` implements the five wire boxes drawn by
OpenSpades v0.1.3 `Client_Scene.cpp:783–800`. This helper is presentation only: it
does not select a player, inspect health, cast a ray, or change authority state.
Main/HUD integration belongs to the caller. Standalone native evidence below does
not establish exported-browser or full-scene acceptance.

## Source contract

- `Client_LocalEnts.cpp:114–135` selects only first-person camera modes, excludes
  the camera-target player and rejects enemies while the viewed player is on a
  playing team. A spectator target permits both teams. Dead/spectator candidates
  and nearer terrain are excluded by `World::WeaponRayCast`.
- `World.cpp:439–522` tests head, torso, left leg, right leg and broad arms in that
  order. When a later part of the same actor is nearer, its flag is accumulated
  without clearing earlier flags. Switching to a nearer different actor clears
  flags. This is why callers must pass `parts:Array[String]`, not just the nearest
  part. The two leg boxes share `legs` and therefore become white together.
- `Player.cpp:1316–1385` supplies the exact oriented boxes. The helper uses
  `LabHitVolumes.volumes(crouching,pitch)` and the same feet/yaw convention as ray
  tests; it does not approximate the visual model with a capsule or axis-aligned
  world box. The mapped native axes are `(X,Y,Z-down) → (X,-Z,Y)`.
- `Client_Scene.cpp:514–539` emits twelve edges per box: four along native X,
  then four along Y, then four along Z. Head/torso/two-leg/arms order is retained.
  Flagged parts use opaque white; all other parts use the supplied team RGB/255.
  Name-display settings do not disable the scene outline.
- `GLRenderer.cpp:559–599,677–683` uses basic vertex colors, `GL_LINES`, no
  blending and depth testing with `LESS`. `Basic.vs/fs` apply no lighting or fog.
  Software rendering also tests lines against scene depth.

The native local AABBs retained by `LabHitVolumes` are:

| Part | Standing min / size | Crouching min / size |
| --- | --- | --- |
| Head | `(-.3,-.3,-.5) / (.6,.6,.6)` | `(-.3,-.3,-.45) / (.6,.6,.6)` |
| Torso | `(-.4,-.15,.1) / (.8,.3,.9)` | `(-.4,-.15,.1) / (.8,.8,.6)` |
| Left leg | `(-.4,-.15,0) / (.3,.3,1)` | `(-.4,-.15,.5) / (.3,.3,.5)` |
| Right leg | `(.1,-.15,0) / (.3,.3,1)` | `(.1,-.15,.5) / (.3,.3,.5)` |
| Arms | `(-.6,-.15,.1) / (1.2,.3,.9)` | `(-.6,-.15,.1) / (1.2,.3,.6)` |

These are local native coordinates before the lower/torso/head transforms. Head
pitch pivots at native Z `.1` standing and `.15` crouching. Geometry is a source
reimplementation under the repository's GPL-3.0 terms; no new asset pack is used.

## Integration API

```gdscript
var outline = preload("res://presentation/hottracked_player.gd").new()
add_child(outline)
outline.show_pose(feet, yaw, crouching, pitch, hit.parts, team_color)
# When no eligible target remains:
outline.hide_target()
# Map/epoch reset:
outline.clear()
```

`OpenSpadesHottrackedPlayer` extends `Node3D` and starts hidden.

- `show_pose(feet:Vector3,yaw:float,crouching:bool,pitch:float,
  hit_parts:Array[String],team_color:Color)->bool` builds the original direct
  matrices. It is the preferred path when the caller already has the actor pose.
- `show_prepared(pose:LabHitVolumes.PreparedPose,hit_parts:Array[String],
  team_color:Color)->bool` accepts an existing prepared ray-test pose. It copies
  its boxes/inverses and reverses the inverses once; standalone tests bound that
  float round-trip difference to `<.00001` for the sampled poses.
- `hide_target()` hides retained bounded geometry. `clear()` hides and removes
  the current surface, retaining the one renderer node for later reuse.
- `get_line_vertices()/get_line_colors()` return independent value copies for
  diagnostics. Tree exit releases mesh/material bindings; re-entry recreates
  those resources without accumulating child nodes.

Parts are `head`, `torso`, `legs`, `arms`, at most four entries. Team RGB must be
finite and within0..1; alpha is forced to1. Invalid/null/nonfinite input clears
and hides the result. Vertices are world-space: the helper is `top_level` and uses
an identity transform, including beneath transformed parents. Do not move/scale
the helper to pose it; pass the actual feet/yaw/crouch/pitch instead.

The caller must update or hide it every relevant frame, including camera changes,
target death/loss, menu/reset and leaving first person. It must apply native
camera/team/terrain eligibility independently of any HUD name setting.

## Rendering and bounded lifetime

Each helper has at most one `MeshInstance3D`, one `ArrayMesh`, one material and one
opaque line surface: **60 segments /120 endpoints**. Repeated updates replace that
surface rather than adding nodes or surfaces. Lines use normal world layer1,
unshaded vertex RGB, fog disabled, no shadows/GI, no transparency, depth offset or
xray mode. Main's ordinary scene postprocessing can still affect their final image.

Compatibility's normal depth test uses reversed-Z `GEQUAL`, while native used
strict `LESS`; an exact coplanar equality can therefore differ by a pixel. This
is an explicit engine rasterization adaptation, not an intentional through-wall
outline. Godot exposes the normal test rather than a separate strict-inequality
Compatibility mode. See the [spatial shader depth modes](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html)
and [pinned4.7.2 GLES3 depth implementation](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/rasterizer_scene_gles3.cpp).
Native-width hardware lines retain backend/MSAA pixel-coverage differences;
pixel-identical rasterization with OpenSpades is not claimed.

## Standalone evidence

Godot4.7.2 `ed1daf0bf` headless passed **6216 checks,0 failures**, clean teardown.
Checks include independent standing/crouching box-bound goldens, source edge
ordering, an independent trigonometric head pivot/yaw/pitch golden, white/team
colors and both-leg flags, direct/prepared pose comparisons across48 poses,
copied inspection data,200-frame bounded reuse, hide/clear, nonfinite/unknown
input rejection and resource release/re-entry. The fixture loads neither Main
nor preferences/audio.

Actual offscreen native Compatibility on **Intel UHD Graphics/OpenGL3.3** passed
**6221 checks,0 failures**, empty stderr and no leaked objects/resources. Its five
additional image checks show team body/white head edges, crouch/yaw/pitch changes,
complete opaque-wall occlusion, foreground outline preservation when the wall is
behind, and hidden-target disappearance. Standing/foreground frames each had
1197 green and310 white pixels; occluded/hidden frames had0/0. PNGs were inspected.

```powershell
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script ../tests/presentation/test_hottracked_player.gd
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --path game --rendering-method gl_compatibility --position -3000,-3000 --script ../tests/presentation/test_hottracked_player.gd -- --gpu --output=C:/Users/Gordey/Documents/ChatGPT/Blockfield/.cache/previews/hottracked-player
```

Logs: `.cache/logs/test-hottracked-player.log` and
`.cache/logs/test-hottracked-player-gpu.log/.err`. Review outputs are untracked
under `.cache/previews/hottracked-player/`, including `report.json` and five PNGs.
Main/HUD camera eligibility, exported WebGL and browser interaction remain
separate integration/acceptance checks. No parity row is promoted by this helper.
