from __future__ import annotations

import math
from pathlib import Path
from typing import Iterable, Sequence

import bpy
from mathutils import Vector


def ensure_collection(name: str) -> bpy.types.Collection:
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(collection)
    return collection


def remove_collection(name: str) -> None:
    collection = bpy.data.collections.get(name)
    if collection is None:
        return
    for obj in list(collection.all_objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for child in list(collection.children):
        remove_collection(child.name)
    bpy.data.collections.remove(collection)


def remove_objects_with_prefix(prefix: str) -> None:
    for obj in list(bpy.data.objects):
        if obj.name.startswith(prefix):
            bpy.data.objects.remove(obj, do_unlink=True)


def move_to_collection(obj: bpy.types.Object, collection: bpy.types.Collection) -> None:
    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    collection.objects.link(obj)


def make_material(
    name: str,
    color: Sequence[float],
    *,
    metallic: float = 0.0,
    roughness: float = 0.7,
    emission: Sequence[float] | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    material = bpy.data.materials.get(name)
    if material is None:
        material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.diffuse_color = tuple(color)
    # Node display names are localized in Blender; node types are stable.
    principled = next(
        (node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED"),
        None,
    )
    if principled is not None:
        principled.inputs["Base Color"].default_value = tuple(color)
        principled.inputs["Metallic"].default_value = metallic
        principled.inputs["Roughness"].default_value = roughness
        emission_input = principled.inputs.get("Emission Color") or principled.inputs.get("Emission")
        if emission_input is not None:
            emission_input.default_value = tuple(emission or color)
        strength_input = principled.inputs.get("Emission Strength")
        if strength_input is not None:
            strength_input.default_value = emission_strength
    return material


def make_pbr_texture_material(
    name: str,
    base_color_path: Path,
    roughness_path: Path,
    normal_path: Path,
    *,
    base_color_factor: Sequence[float] = (1.0, 1.0, 1.0, 1.0),
    metallic: float = 0.0,
    normal_strength: float = 0.75,
) -> bpy.types.Material:
    texture_paths = (base_color_path, roughness_path, normal_path)
    missing = [str(path) for path in texture_paths if not path.is_file()]
    if missing:
        raise FileNotFoundError(f"Missing PBR textures for {name}: {missing}")

    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    output.location = (520.0, 0.0)
    principled = nodes.new("ShaderNodeBsdfPrincipled")
    principled.location = (260.0, 0.0)
    principled.inputs["Base Color"].default_value = tuple(base_color_factor)
    principled.inputs["Metallic"].default_value = metallic
    material.diffuse_color = tuple(base_color_factor)

    base_node = nodes.new("ShaderNodeTexImage")
    base_node.name = f"{name}_BaseColor"
    base_node.location = (-360.0, 180.0)
    base_node.image = bpy.data.images.load(str(base_color_path), check_existing=True)

    base_mix_node = nodes.new("ShaderNodeMix")
    base_mix_node.name = f"{name}_BaseColorFactor"
    base_mix_node.label = "glTF Base Color Factor"
    base_mix_node.location = (-40.0, 180.0)
    base_mix_node.data_type = "RGBA"
    base_mix_node.blend_type = "MULTIPLY"
    base_mix_node.inputs["Factor"].default_value = 1.0
    base_mix_node.inputs[7].default_value = tuple(base_color_factor)

    roughness_node = nodes.new("ShaderNodeTexImage")
    roughness_node.name = f"{name}_Roughness"
    roughness_node.location = (-360.0, -20.0)
    roughness_node.image = bpy.data.images.load(str(roughness_path), check_existing=True)
    roughness_node.image.colorspace_settings.name = "Non-Color"

    normal_texture_node = nodes.new("ShaderNodeTexImage")
    normal_texture_node.name = f"{name}_Normal"
    normal_texture_node.location = (-360.0, -240.0)
    normal_texture_node.image = bpy.data.images.load(str(normal_path), check_existing=True)
    normal_texture_node.image.colorspace_settings.name = "Non-Color"

    normal_map_node = nodes.new("ShaderNodeNormalMap")
    normal_map_node.location = (0.0, -220.0)
    normal_map_node.inputs["Strength"].default_value = normal_strength

    links = material.node_tree.links
    links.new(base_node.outputs["Color"], base_mix_node.inputs[6])
    links.new(base_mix_node.outputs[2], principled.inputs["Base Color"])
    links.new(roughness_node.outputs["Color"], principled.inputs["Roughness"])
    links.new(normal_texture_node.outputs["Color"], normal_map_node.inputs["Color"])
    links.new(normal_map_node.outputs["Normal"], principled.inputs["Normal"])
    links.new(principled.outputs["BSDF"], output.inputs["Surface"])
    return material


def assign_material(obj: bpy.types.Object, material: bpy.types.Material) -> None:
    if obj.type != "MESH":
        return
    obj.data.materials.clear()
    obj.data.materials.append(material)


def cube_project_uv(obj: bpy.types.Object, cube_size: float) -> None:
    if obj.type != "MESH" or cube_size <= 0.0:
        return
    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    bpy.ops.object.select_all(action="DESELECT")
    obj.hide_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.cube_project(cube_size=cube_size, correct_aspect=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.select_set(False)


def add_box(
    name: str,
    location: Sequence[float],
    dimensions: Sequence[float],
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    *,
    rotation: Sequence[float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign_material(obj, material)
    move_to_collection(obj, collection)
    return obj


def add_cylinder(
    name: str,
    location: Sequence[float],
    radius: float,
    depth: float,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    *,
    vertices: int = 12,
    rotation: Sequence[float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.active_object
    obj.name = name
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign_material(obj, material)
    move_to_collection(obj, collection)
    return obj


def add_torus(
    name: str,
    location: Sequence[float],
    major_radius: float,
    minor_radius: float,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    *,
    major_segments: int = 12,
    minor_segments: int = 6,
    rotation: Sequence[float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_segments=major_segments,
        minor_segments=minor_segments,
        major_radius=major_radius,
        minor_radius=minor_radius,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.active_object
    obj.name = name
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign_material(obj, material)
    move_to_collection(obj, collection)
    return obj


def add_ico_sphere(
    name: str,
    location: Sequence[float],
    scale: Sequence[float],
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    *,
    subdivisions: int = 1,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1.0, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign_material(obj, material)
    move_to_collection(obj, collection)
    return obj


def add_pipe(
    name: str,
    points: Sequence[Sequence[float]],
    radius: float,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
) -> bpy.types.Object:
    curve = bpy.data.curves.new(name=f"{name}_curve", type="CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 1
    curve.bevel_depth = radius
    curve.bevel_resolution = 0
    curve.resolution_u = 1
    curve.use_fill_caps = True
    spline = curve.splines.new(type="POLY")
    spline.points.add(len(points) - 1)
    for point, co in zip(spline.points, points):
        point.co = (*co, 1.0)
    obj = bpy.data.objects.new(name, curve)
    collection.objects.link(obj)
    obj.data.materials.append(material)
    return obj


def add_text(
    name: str,
    body: str,
    location: Sequence[float],
    size: float,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    *,
    rotation: Sequence[float] = (math.radians(90.0), 0.0, 0.0),
    extrude: float = 0.02,
) -> bpy.types.Object:
    curve = bpy.data.curves.new(name=f"{name}_font", type="FONT")
    curve.body = body
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    curve.size = size
    curve.extrude = extrude
    obj = bpy.data.objects.new(name, curve)
    obj.location = location
    obj.rotation_euler = rotation
    collection.objects.link(obj)
    obj.data.materials.append(material)
    return obj


def duplicate_single_user(
    source: bpy.types.Object,
    name: str,
    collection: bpy.types.Collection,
    *,
    location: Sequence[float] | None = None,
    rotation: Sequence[float] | None = None,
) -> bpy.types.Object:
    obj = source.copy()
    if source.data is not None:
        obj.data = source.data.copy()
    obj.name = name
    collection.objects.link(obj)
    if location is not None:
        obj.location = location
    if rotation is not None:
        obj.rotation_euler = rotation
    return obj


def join_mesh_objects(objects: Sequence[bpy.types.Object], name: str) -> bpy.types.Object:
    meshes = [obj for obj in objects if obj is not None and obj.type == "MESH"]
    if not meshes:
        raise ValueError(f"Cannot join empty mesh assembly: {name}")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    joined = bpy.context.active_object
    joined.name = name
    return joined


def collection_objects(collection: bpy.types.Collection) -> list[bpy.types.Object]:
    return [obj for obj in collection.all_objects if obj is not None]


def set_collection_hidden(collection: bpy.types.Collection, hidden: bool) -> None:
    collection.hide_viewport = hidden
    collection.hide_render = hidden
    for obj in collection_objects(collection):
        obj.hide_set(hidden)
        obj.hide_render = hidden


def select_collection(collection: bpy.types.Collection) -> list[bpy.types.Object]:
    bpy.ops.object.select_all(action="DESELECT")
    objects = [obj for obj in collection_objects(collection) if obj.type in {"MESH", "CURVE", "FONT", "EMPTY"}]
    for obj in objects:
        obj.hide_set(False)
        obj.select_set(True)
    if objects:
        bpy.context.view_layer.objects.active = objects[0]
    return objects


def export_collection_glb(collection_name: str, filepath: Path) -> int:
    collection = bpy.data.collections[collection_name]
    was_hidden_viewport = collection.hide_viewport
    was_hidden_render = collection.hide_render
    collection.hide_viewport = False
    collection.hide_render = False
    objects = select_collection(collection)
    filepath.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(filepath),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
    )
    collection.hide_viewport = was_hidden_viewport
    collection.hide_render = was_hidden_render
    return len(objects)


def look_at(obj: bpy.types.Object, target: Sequence[float]) -> None:
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def bounds_for_objects(objects: Iterable[bpy.types.Object]) -> tuple[Vector, Vector]:
    minimum = Vector((float("inf"), float("inf"), float("inf")))
    maximum = Vector((float("-inf"), float("-inf"), float("-inf")))
    found = False
    for obj in objects:
        if obj.type not in {"MESH", "CURVE", "FONT"}:
            continue
        found = True
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            minimum.x = min(minimum.x, world.x)
            minimum.y = min(minimum.y, world.y)
            minimum.z = min(minimum.z, world.z)
            maximum.x = max(maximum.x, world.x)
            maximum.y = max(maximum.y, world.y)
            maximum.z = max(maximum.z, world.z)
    if not found:
        return Vector(), Vector()
    return minimum, maximum


def validate_collection(collection_name: str) -> dict:
    collection = bpy.data.collections[collection_name]
    objects = collection_objects(collection)
    minimum, maximum = bounds_for_objects(objects)
    shared_meshes = []
    for obj in objects:
        if obj.type == "MESH" and obj.data.users > 1:
            shared_meshes.append(obj.name)
    return {
        "collection": collection_name,
        "object_count": len(objects),
        "bounds_min": [round(value, 4) for value in minimum],
        "bounds_max": [round(value, 4) for value in maximum],
        "shared_mesh_objects": shared_meshes,
    }
