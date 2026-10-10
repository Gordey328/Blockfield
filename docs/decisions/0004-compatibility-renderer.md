# 0004 — Browser renderer and extension adaptations

Date: 2026-10-10. Status: implementation decision within the authorized Godot browser port; full parity acceptance remains pending.

Godot Compatibility/WebGL2 replaces the original custom OpenGL renderer. Original voxel colors, AO data, models, textures and effect formulas remain source references. Engine-specific substitutions require numeric, GPU and exported-browser checks; exposing a checkbox is not acceptance.

Current direct lighting/shadows use Godot lights. The native flashlight projector is unavailable in Compatibility; a warm spot plus a 30% local fill reproduce its cone/color/rise behavior. Vertex corner AO is an intermediate step toward sampling the original per-pixel atlas. Water currently has an analytic animated surface; source-shaped spectral waves, screen refraction and optional reflection are next.

The current post chain supplies FXAA/MSAA, LDR bloom, original lens textures/flares, color correction, camera/hurt blur, depth-of-field and SSAO. Native floating-point HDR adaptation and brightness-pyramid bloom are not reproduced by LDR tone mapping. An ambient-energy slider is a fill-light choice and does not implement native palette radiosity. A bounded source-based single-bounce probe implementation is planned separately. Full native irradiance volumes, soft shadows, complete FFT and mirrored/raymarched water remain distinct fidelity requirements until explicitly resolved.

Native AngelScript extensions are replaced by trusted GDScript first/third-person skin factories and validated data-only ZIP resource packs. Uploaded scripts/PCK files are not executed. The runtime pack API validates paths, hashes, types and budgets and refreshes cached resources. Native script source/API compatibility, uploaded fonts and all native cvars remain unported; see ../extensions.md.

These documented substitutions do not by themselves mark U14/U15/U18 or iteration 1 complete. Record the actual implemented behavior and evidence in ../parity.md; keep unresolved native features visible there.
