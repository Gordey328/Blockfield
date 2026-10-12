"""Conservative Godot 4.7.2 Web release profile for Blockfield.

Load with SCons profile=<this file>. The build helper owns platform, target,
architecture, thread/extension variants and toolchain. Audited module contracts
and pinned source evidence are recorded in the adjacent module-audit.json.
"""

# Keep normal engine defaults for anything not explicitly audited below.
modules_enabled_by_default = True
optimize = "size"

# The project is 3D with a full Control UI and the default GodotPhysics3D server.
disable_3d = False
disable_advanced_gui = False
disable_physics_3d = False
opengl3 = True
javascript_eval = True
minizip = True

# Control/Canvas rendering remains available; only the unused physics server
# and engine navigation servers are removed. Bots query VoxelData themselves.
disable_physics_2d = True
disable_navigation_2d = True
disable_navigation_3d = True
disable_xr = True

# Alternate geometry/physics/import authoring paths are outside the supported
# static PNG/GLB resource-pack contract. Runtime GLTF loading remains enabled.
module_csg_enabled = False
module_gridmap_enabled = False
module_fbx_enabled = False
module_jolt_physics_enabled = False
module_vhacd_enabled = False
module_visual_shader_enabled = False

# Offline gameplay does not use these transport modules.
module_enet_enabled = False
module_webrtc_enabled = False
module_upnp_enabled = False
module_websocket_enabled = False
# GDScript LSP is editor-only; offline gameplay uses no JSONRPC or SceneMultiplayer.
# SceneTree retains the core MultiplayerAPIExtension fallback interface.
module_jsonrpc_enabled = False
module_multiplayer_enabled = False

# Bundled CTEX textures use lossless mode, resource packs require PNG, and
# runtime GLBs permit embedded PNGs. Keep PNG/WebP/JPG/BC/ETC/ASTC and the full
# SVG/text stack; remove unrelated source-image/container decoders.
module_basis_universal_enabled = False
module_ktx_enabled = False
module_bmp_enabled = False
module_dds_enabled = False
module_hdr_enabled = False
module_tga_enabled = False
module_tinyexr_enabled = False

# All accepted sounds are WAV or Ogg Vorbis; there is no video/music graph.
module_mp3_enabled = False
module_theora_enabled = False
module_interactive_music_enabled = False

# Explicitly protect dynamic dependencies that static class pruning misses.
module_gdscript_enabled = True
module_godot_physics_3d_enabled = True
module_gltf_enabled = True
module_zip_enabled = True
module_regex_enabled = True
module_noise_enabled = True
module_ogg_enabled = True
module_vorbis_enabled = True
module_webp_enabled = True
module_jpg_enabled = True
module_svg_enabled = True
module_freetype_enabled = True
module_msdfgen_enabled = True
module_text_server_adv_enabled = True
module_mbedtls_enabled = True
module_meshoptimizer_enabled = True

# Core disabling is sufficient, but pin their module state too for review.
module_godot_physics_2d_enabled = False
module_navigation_2d_enabled = False
module_navigation_3d_enabled = False
module_mobile_vr_enabled = False
module_openxr_enabled = False
module_webxr_enabled = False
