"""Render real acquired weapon models for the optional local buy-page previews."""

import argparse
from pathlib import Path
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import convert_official_cs_assets as assets


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1 :])
    if args.output.resolve().parts[-4:] != (
        "assets",
        "local_reference",
        "cs_official",
        "ui",
    ):
        raise ValueError("Output must end in assets/local_reference/cs_official/ui")
    args.output.mkdir(parents=True, exist_ok=True)
    for key, source in {
        "rifle-ct": "weapon_rif_m4a1_silencer",
        "rifle-t": "weapon_rif_ak47",
        "pistol": "weapon_pist_glock18",
    }.items():
        target = args.output / (key + ".png")
        if target.exists():
            raise FileExistsError("Preserve existing preview: " + str(target))
        arm, meshes = assets.imported(args.source / (source + ".gltf"))
        meshes = [o for o in meshes if o.name.endswith(".body_hd")]
        if not meshes:
            raise ValueError("Missing native HD group")
        for obj in list(bpy.data.objects):
            if obj != arm and obj not in meshes:
                bpy.data.objects.remove(obj, do_unlink=True)
        bpy.context.view_layer.update()
        graph = bpy.context.evaluated_depsgraph_get()
        points = [
            o.matrix_world @ v.co
            for obj in meshes
            for o in [obj.evaluated_get(graph)]
            for v in o.data.vertices
        ]
        low = Vector(tuple(min(p[k] for p in points) for k in range(3)))
        high = Vector(tuple(max(p[k] for p in points) for k in range(3)))
        center = (low + high) / 2
        extent = (high - low).length
        scene = bpy.context.scene
        scene.render.engine = "CYCLES"
        scene.cycles.samples = 24
        scene.render.resolution_x = 900
        scene.render.resolution_y = 360
        scene.render.resolution_percentage = 100
        scene.render.film_transparent = True
        scene.world = bpy.data.worlds.new("PreviewWorld")
        scene.world.color = (0.35, 0.35, 0.35)
        scene.view_settings.view_transform = "AgX"
        for offset, energy in [((1, -1, 2), 450), ((-1, 0.5, 1.2), 220)]:
            bpy.ops.object.light_add(
                type="AREA", location=center + Vector(offset) * extent
            )
            light = bpy.context.object
            # Camera and light distance scale with the model; power must scale
            # with area too, or a small pistol is vastly brighter than a rifle.
            light.data.energy = energy * extent * extent
            light.data.size = extent * 2
            light.rotation_euler = (
                (center - light.location).to_track_quat("-Z", "Y").to_euler()
            )
        bpy.ops.object.camera_add(location=center + Vector((2, -0.25, 0.65)) * extent)
        camera = bpy.context.object
        camera.rotation_euler = (
            (center - camera.location).to_track_quat("-Z", "Y").to_euler()
        )
        camera.data.type = "ORTHO"
        rotation = camera.rotation_euler.to_matrix()
        right, up = rotation.col[0], rotation.col[1]
        width = 2 * max(abs((p - center).dot(right)) for p in points)
        height = 2 * max(abs((p - center).dot(up)) for p in points)
        aspect = scene.render.resolution_x / scene.render.resolution_y
        camera.data.ortho_scale = max(width, height * aspect) * 1.12
        scene.camera = camera
        scene.render.image_settings.file_format = "PNG"
        scene.render.image_settings.color_mode = "RGBA"
        scene.render.filepath = str(target)
        bpy.ops.render.render(write_still=True)
        print("OFFICIAL_PREVIEW_RENDERED", key, flush=True)


if __name__ == "__main__":
    main()
