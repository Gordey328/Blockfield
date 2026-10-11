# 0021 — Reduced Godot Web export template

Date: 2026-10-11. Status: accepted for the checked isolated export.

The official single-thread Godot 4.7.2 Web engine is 39,514,754 bytes before
HTTP compression. Blockfield does not use all of its modules. Compile a separate
release template from the exact installed engine revision rather than removing
resource files or changing gameplay to fit a smaller engine.

The reproducible profile is [blockfield.py](../../tools/web_template/blockfield.py).
Its [module audit](../../tools/web_template/module-audit.json) records each flag
against the pinned source and runtime contracts. Keep standard module defaults
and remove only explicitly audited capabilities; do not prune individual classes.
The generated module list contains 20 modules instead of 46 eligible modules.

Disable 2D physics, built-in navigation, XR, alternate Jolt physics, CSG, GridMap,
FBX, VHACD, VisualShader, ENet, WebRTC, UPnP, unused texture import formats and
MP3/Theora/interactive music, JSON-RPC and high-level scene multiplayer. WebSocket remains the browser multiplayer transport.
Bots use TdmVoxelNavigation and voxel queries rather than Godot navigation servers.

Keep Compatibility rendering, GodotPhysics3D, the advanced GUI, full multilingual
text and fallback fonts, WAV/Ogg, RegEx, FastNoiseLite, JavaScript bridge, TLS,
GLTF and ZIP. Custom packs retain the existing validation contract: static GLB
meshes with embedded PNG images plus allowed texture and sound overrides.
The renderer's compressed texture decoders remain available.

The compiler inputs are Godot `ed1daf0bf001b61586d9930840f2f1394092c079`,
Emscripten 4.0.11, SCons 4.9.1 and a recorded Node executable. Use the standard
Web size optimization and thin LTO, single-thread wasm32, no GDExtensions,
two compilation jobs and two link jobs on this 8 GB host. Those optimization
settings already apply to the standard Web configuration; they are not new
module-removal gains. The official binary's exact compiler identity is unknown,
so its measured size difference is a comparison of two concrete templates.

Use an explicit custom release ZIP when exporting an isolated frozen project.
Keep the globally installed templates and shared presets available for fallback.
The build helper records the source/profile/toolchain identities and validates
the output ZIP. Store the accepted binary separately from source control.

Acceptance requires identical game PCK hashes in the standard and reduced
exports, native regression checks on that frozen source, and real browser checks
for rendering, controller/tool behavior, audio, multilingual GUI, runtime GLTF,
ZIP overrides, WebSocket and actual five-bot TDM/navigation/pause behavior.
Record original failures and any repaired attempts. Gzip measurements use the
same settings for both builds and are estimates, not observed HTTP traffic.
Future use of a removed capability requires updating this profile and repeating
the relevant browser acceptance before publication.

The accepted build contains20 modules, passes identical54/0 browser probes on
both engines, and preserves the exact game PCK. WASM39514754→31835587bytes
(19.434% saved), gzip10054758→8043492bytes (20.003%). Complete Web folder
63855150→56144228bytes; local gzip sum25828498→23811261bytes.
The reproducible profile, toolchain, commands, failed attempts and final
artifacts are recorded in [size and verification evidence](../web-template-size.md).
Keep the shared default export/release separate from this comparison while the
other chat owns ongoing gameplay and publication integration.

## Accepted default integration — 2026-10-11

User approved merging the checked reduced engine with the other work. Release
exports now use tools/web_release_template.py to select the hash-pinned ZIP at
build/templates/godot-4.7.2-web-blockfield.zip. Missing or changed binaries fail
explicitly; rebuild using the pinned instructions on another machine. The preset
is restored byte-for-byte and metadata records the template hash. Installed
stock templates remain available. The Pages publisher rebases before push to
preserve separately published sibling folders.
