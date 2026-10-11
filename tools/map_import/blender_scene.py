"""Save an extracted GoldSrc scene as a self-contained, textured .blend.

Usage: blender --background --python tools/map_import/blender_scene.py --
       --scene extracted/scene.json --output csgo_mirage.blend
The resulting .blend must then be loaded by blender_voxelize.py in another run.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from voxelize_helpers import is_tool_material


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scene", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--render-overview", type=Path)
    parser.add_argument("--render-spawn", type=Path)
    parser.add_argument("--refresh-metadata", action="store_true", help="Refresh embedded collision policy in an already loaded saved .blend")
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])


def source_metadata(source, source_file):
    metadata = {key: value for key, value in source.items() if key != "meshes"}
    tool_only_models = {}
    for mesh_entry in source["meshes"]:
        if mesh_entry.get("kind") != "bsp" or not mesh_entry.get("model_index"):
            continue
        if all(is_tool_material(source["materials"][face["material"]]) for face in mesh_entry["faces"]):
            tool_only_models[int(mesh_entry["model_index"])] = sorted({source["materials"][face["material"]]["name"] for face in mesh_entry["faces"]})
    for model in metadata["collision"]["models"]:
        model["voxel_excluded"] = int(model["model_index"]) in tool_only_models
    metadata["tool_only_models"] = [{"model_index": model["model_index"], "classname": model["classname"],
                                     "materials": tool_only_models[model["model_index"]], "originally_solid": model["solid"]}
                                    for model in metadata["collision"]["models"] if model["voxel_excluded"]]
    metadata["source_scene_file"] = str(source_file.resolve())
    return metadata


def main():
    args = arguments()
    source = json.loads(args.scene.read_text(encoding="utf-8"))
    if source.get("format") != 1:
        raise ValueError("Unsupported extracted scene format")
    if args.refresh_metadata:
        if not bpy.data.filepath:
            raise ValueError("Refresh requires the previously saved .blend to be loaded")
        text = bpy.data.texts.get("BLOCKFIELD_SOURCE_METADATA.json")
        if not text:
            raise ValueError("Loaded .blend is missing conversion metadata")
        print(json.dumps({"stage": "refreshing_metadata"}), flush=True)
        text.clear()
        # Blender text insertion becomes very slow for a megabyte-sized single
        # line. Ordinary indented JSON keeps line operations bounded.
        text.write(json.dumps(source_metadata(source, args.scene), ensure_ascii=False, indent=2))
        print(json.dumps({"stage": "saving_refreshed_blend"}), flush=True)
        bpy.ops.wm.save_as_mainfile(filepath=str(args.output.resolve()))
        print(json.dumps({"stage": "saved_refreshed_metadata", "blend": str(args.output.resolve()), "blender_version": bpy.app.version_string}), flush=True)
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    visible = bpy.data.collections.new("Mirage — visible geometry")
    tools = bpy.data.collections.new("Source tools and sky — excluded from blocks")
    bpy.context.scene.collection.children.link(visible)
    bpy.context.scene.collection.children.link(tools)
    materials = []
    for entry in source["materials"]:
        material = bpy.data.materials.new(entry["name"])
        material.use_nodes = True
        material["blockfield_source"] = json.dumps(entry, ensure_ascii=False)
        material["blockfield_excluded"] = is_tool_material(entry)
        shader = material.node_tree.nodes.get("Principled BSDF")
        shader.inputs["Roughness"].default_value = 1
        texture_path = args.scene.parent / entry.get("texture", "")
        if texture_path.is_file():
            image = bpy.data.images.load(str(texture_path), check_existing=True)
            image.pack()
            node = material.node_tree.nodes.new("ShaderNodeTexImage")
            node.image = image
            node.interpolation = "Closest"
            material.node_tree.links.new(node.outputs["Color"], shader.inputs["Base Color"])
            if entry.get("masked"):
                material.node_tree.links.new(node.outputs["Alpha"], shader.inputs["Alpha"])
                if hasattr(material, "surface_render_method"):
                    material.surface_render_method = "DITHERED"
                elif hasattr(material, "blend_method"):
                    material.blend_method = "CLIP"
        else:
            shader.inputs["Base Color"].default_value = (.57, .5, .38, 1)
        materials.append(material)
    mesh_count, face_count = 0, 0
    for entry in source["meshes"]:
        for excluded in (False, True):
            faces = [face for face in entry["faces"] if bool(materials[int(face["material"])]["blockfield_excluded"]) == excluded]
            if not faces:
                continue
            mesh = bpy.data.meshes.new(entry["name"] + ("_tools" if excluded else ""))
            mesh.from_pydata(entry["vertices"], [], [face["indices"] for face in faces])
            mesh.update()
            used_materials = sorted({int(face["material"]) for face in faces})
            material_indices = {source_id: index for index, source_id in enumerate(used_materials)}
            for source_id in used_materials:
                mesh.materials.append(materials[source_id])
            uv = mesh.uv_layers.new(name="Source UV")
            for polygon, face in zip(mesh.polygons, faces):
                polygon.material_index = material_indices[int(face["material"])]
                for loop_index, source_uv in zip(polygon.loop_indices, face["uv"]):
                    uv.data[loop_index].uv = source_uv
            obj = bpy.data.objects.new(mesh.name, mesh)
            (tools if excluded else visible).objects.link(obj)
            obj["blockfield_kind"] = entry.get("kind", "bsp")
            obj["blockfield_solid"] = bool(entry.get("solid", True))
            obj["blockfield_excluded"] = excluded
            obj["blockfield_model_index"] = -1 if entry.get("model_index") is None else int(entry["model_index"])
            obj["blockfield_classname"] = entry.get("classname", "")
            if excluded:
                obj.hide_render = True
                obj.hide_set(True)
            mesh_count += 1
            face_count += len(faces)
            if mesh_count % 50 == 0:
                print(json.dumps({"stage": "building_blender_scene", "meshes": mesh_count, "polygons": face_count}), flush=True)
    metadata = source_metadata(source, args.scene)
    text = bpy.data.texts.new("BLOCKFIELD_SOURCE_METADATA.json")
    text.write(json.dumps(metadata, ensure_ascii=False, indent=2))
    scene = bpy.context.scene
    scene["blockfield_pipeline"] = "GoldSrc extraction → saved Blender → Blockfield voxel map"
    scene["blockfield_coordinates"] = "GoldSrc source units, Z-up; conversion maps (x,y,z) to (x,z,-y)"
    scene.unit_settings.system = "NONE"
    world = bpy.data.worlds.new("Mirage daylight")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (.65, .75, .9, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = .65
    scene.world = world
    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 2
    sun = bpy.data.objects.new("Sun", sun_data)
    scene.collection.objects.link(sun)
    sun.rotation_euler = (.6, -.3, -.5)
    camera_data = bpy.data.cameras.new("Mirage overview")
    camera = bpy.data.objects.new("Mirage overview", camera_data)
    scene.collection.objects.link(camera)
    model = source["collision"]["models"][0]
    center = (Vector(model["mins"]) + Vector(model["maxs"])) / 2
    center.z = 150
    camera.location = center + Vector((2500, -3400, 3100))
    camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera_data.clip_end = 20000
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 6100
    scene.camera = camera
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1100
    scene.render.resolution_percentage = 100
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(args.output.resolve()))
    print(json.dumps({"blend": str(args.output.resolve()), "meshes": mesh_count, "polygons": face_count, "materials": len(materials), "packed_images": len(bpy.data.images), "blender_version": bpy.app.version_string}, ensure_ascii=False), flush=True)
    if args.render_overview:
        args.render_overview.parent.mkdir(parents=True, exist_ok=True)
        scene.render.filepath = str(args.render_overview.resolve())
        scene.render.image_settings.file_format = "PNG"
        scene.render.resolution_x, scene.render.resolution_y = 1400, 1000
        scene.eevee.taa_render_samples = 16
        bpy.ops.render.render(write_still=True)
    if args.render_spawn:
        args.render_spawn.parent.mkdir(parents=True, exist_ok=True)
        spawn = next((entry for entry in source["entities"] if entry.get("classname") == "info_player_start"), None)
        if spawn:
            position = [float(value) for value in spawn["origin"].split()]
            angles = [float(value) for value in spawn.get("angles", "0 0 0").split()]
            camera.location = Vector(position) + Vector((0, 0, 28))
            direction = Vector((math.cos(math.radians(angles[1])), math.sin(math.radians(angles[1])), -.035))
            camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
            camera_data.type = "PERSP"
            camera_data.lens = 23
            camera_data.clip_start = 1
            scene.render.resolution_x, scene.render.resolution_y = 1400, 900
            scene.render.filepath = str(args.render_spawn.resolve())
            scene.eevee.taa_render_samples = 16
            bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
