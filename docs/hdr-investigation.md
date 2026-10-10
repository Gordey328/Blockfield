# HDR scene washout: investigation and boundary correction

Investigated on 2026-10-10 with Godot 4.7.2 `ed1daf0bf`, Compatibility,
Intel UHD Graphics. Native reference: OpenSpades v0.1.3,
`dcf449c845d509bbde9d79239b32d201c1389961`.

## Finding

The HDR filters received nonlinear Godot 3D scene colors as though they were
linear radiance. `hdr_present.gdshader` then applied native gamma correction
again. Bloom and the brightness meter also consumed the wrong encoding. The
result raised dark colors and compressed differences between bright channels,
visually washing the laboratory toward gray.

The original actual-Main captures `01-main-ldr.png` and `02-main-hdr.png` used
gain 1, `hdr_speed=0`, and automatic exposure disabled. Auto-exposure adaptation
therefore cannot explain their initial difference. The later LDR correction
was already disabled by `OpenSpadesPostEffects.set_hdr_active`; it was not a
second ACES pass.

Generic [ViewportTexture documentation](https://docs.godotengine.org/en/4.7/classes/class_viewporttexture.html)
describes HDR textures as linear. The pinned Compatibility 3D path is decisive
for this project: [scene.glsl](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/scene.glsl#L2203)
converts authored albedo/emission to linear, shades them, then explicitly calls
`linear_to_srgb` before writing the scene at line 2570. The HDR float storage
preserves range but does not remove that transfer. The engine's
[tonemap_inc.glsl](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/tonemap_inc.glsl#L12)
uses a polynomial albedo decode and a power-law output approximation.

## Native contract

OpenSpades `BasicBlock.vs:62` squares palette RGB. `BasicBlock.fs:45–65` shades
linear colors and omits its final square root when `LINEAR_FRAMEBUFFER` is set.
`GLRenderer.cpp:965–982` orders auto-exposure, nonlinearization, then color
correction. `AutoExposurePreprocess.fs:31–46` meters max RGB in linear input,
rejects brightness outside 0..16, clamps to .05..1.3 and raises it to the fourth
power. `Nonlinearize.fs:36–37` applies `pow(color,1/r_hdrGamma)`;
`ColorCorrection.fs:49–68` adjusts device-space tint/saturation before its
square → ACES(.8 × color) → square-root operation.

These filter formulas are unchanged. Reconstructed Godot scene radiance is
still the Godot renderer's result. Its albedo decode, shading, fog, reflections
and lights are not identical to native OpenSpades. Removing duplicate gamma
does not establish complete visual parity.

## Isolated GPU evidence

`tests/presentation/probe_hdr_color_space.gd` creates a real unshaded 3D scene
and a separate float 2D canvas containing the same six authored RGB swatches.
It never instantiates Main or accesses preferences. Both presentation paths
use the production HDR shader with gain 1, no bloom, white tint and saturation
1. The intentionally incorrect control treats encoded 3D input as linear.

Final native result: **79 assertions, 0 failures**. Readback shows the 2D
canvas preserves its supplied linear values while the 3D capture follows the
pinned engine's nonlinear transfer. Selected display values:

| Authored ALBEDO | Incorrect encoded input | Correct linear boundary | Filter reference |
|---|---|---|---|
| (.18,.18,.18) | (.49020,.49020,.49020) | (.13725,.13725,.13725) | (.13731,.13731,.13731) |
| (.05,.2,.8) | (.15294,.52157,.83529) | (.02745,.16078,.78824) | (.02975,.15962,.78713) |
| (.4,.7,.1) | (.70196,.81176,.32549) | (.41961,.72549,.06275) | (.42055,.72644,.06293) |

The neutral .18 albedo produces pre-transfer scene radiance approximately
.026137, not .18. The corrected blue swatch increases its blue-minus-red
chroma by .0784. Across this fixture the meter's final fourth-power value
changes from .74756 to .19922. These observations explain why changing only
manual exposure cannot fix the input contract.

Probe artifacts: `.cache/previews/hdr-color-space/metrics.json`,
`01-current-encoded-input.png`, `02-decoded-linear-input.png`.
Original Main captures were preserved in
`.cache/previews/hdr-lab-before-normalization/` before recapture.

## Applied correction and API

`HdrExposure.setup(texture, compatibility_encoded=false)` now accepts an
explicit encoding flag. The two `HdrSceneViewport` setup call sites pass true.
Already-linear 2D callers retain the default and allocate no normalization
target. The encoded path creates one full-size float 2D viewport using
`hdr_normalize.gdshader`. It reverses the pinned output transfer exactly once:

```
encoded > 0 ? pow((encoded + .055) / 1.055, 2.4) : 0
```

It does not clamp highlights to one, use an authored-texture `source_color`
hint, or decode intermediate HDR targets again. Meter, bloom and direct
presentation share this one linear texture. `get_linear_texture()` exposes
it for diagnostics. Disabling HDR pauses normalization and restores the raw
encoded presentation input. Resizing reuses the normalization viewport while
updating its dimensions and dependent filter targets.

`get_stats()` reports `input_encoding`, `normalization_size` and
`normalization_color_bytes`. Its aggregate color-texture estimate includes
normalization. This costs one RGBA16F target: 4,147,200 bytes at 960×540,
7,372,800 bytes at 1280×720, plus one full-screen GPU pass while enabled.
Framebuffer overhead and timing are unmeasured; no frame-rate claim follows.

## Regression coverage and remaining acceptance

`test_hdr_exposure.gd`: **47/0**, including shared input bindings, explicit
encoding, allocation accounting, disabled raw input, target reuse and removal
when switching to a linear caller.

`render_hdr_exposure.gd`: **32/0** native GPU. Existing linear 2D exposure,
gamma, tone, bloom and temporal tests retain their original expectations. The
3D fixture now uses ALBEDO (1.5,1,.5), whose actual linear radiance is
(2.584077,1,.214967). Its previous ALBEDO (4,2,.5) implied approximately
(30.5044,5.19618,.214967), outside the native meter's <=16 valid range; it was
an encoded-albedo test, not a known-radiance test. Raw 3D capture and normalized
radiance are now recorded separately.

`render_hdr_lab.gd`: **63/0** native actual-Main checks after correction,
with empty error log and original preferences restored byte for byte. Visual
inspection of the before/after captures shows restored green ground, blue
forearms, orange skin, dark rifle and distinct team colors. Corrected HDR is
close to the same-run LDR scene, with the intended tone/saturation differences.
The sampled average Main LDR/HDR difference changes from .11545 before the
fix to .03593 after it; difference alone is not a quality criterion. HUD,
equipment, bloom, depth effects, MSAA, resize and disable/re-enable checks pass.
Evidence: `.cache/logs/hdr-lab-normalized.log` and
`.cache/previews/hdr-lab/`. The legacy metric `actual_world_radiance` still
describes the raw encoded fixture readback; its values are not linear units.
Raw-capture expectations remain valid because normalization happens after
that capture.

The updated exporter includes `hdr_normalize.gdshader`. Actual exported
exposure32/0 and color-space79/0 probes ran through WebGL; their visible DOM
reports renderer `WebKit WebGL` and `EXT_color_buffer_float=true`. This is the
driver's reported string, not an identification of the browser engine.
Actual full-client Web/Title-map visual and sustained performance acceptance
remain required. ADR0004 now records the corrected encoding boundary and
assertion counts; the isolated probes do not accept the whole game.

The near-black clamp in the engine's output approximation loses information
before this boundary; the normalization shader preserves zero rather than
inventing a light floor. A future Godot renderer/engine change must recheck
this encoding contract. The flag is specific to the pinned Compatibility
path; applying it to an already-linear Forward+ texture would be incorrect.
