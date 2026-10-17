"""Blender regression for native body morph/Basis coordinate preservation."""

from pathlib import Path
import sys
import tempfile

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "blender"))
from convert_official_cs_assets import transform_geometry
import convert_local_cs_characters as shared


def arm_export_regression():
    """Exercise trimming, copied shape keys, wrist conversion and real GLB export."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.object.armature_add()
    arm = bpy.context.object
    bpy.ops.object.mode_set(mode="EDIT")
    arm.data.edit_bones.remove(arm.data.edit_bones[0])
    positions = {
        "arm_lower_L": ((1, 2, 2), (1, 2, 3)),
        "hand_L": ((1, 2, 3), (1, 2, 3.2)),
        "finger_middle_0_L": ((1, 2, 3.2), (1, 2, 3.3)),
        "finger_index_0_L": ((0.9, 2, 3.2), (0.9, 2, 3.3)),
        "finger_pinky_0_L": ((1.1, 2, 3.2), (1.1, 2, 3.3)),
    }
    for name, (head, tail) in positions.items():
        bone = arm.data.edit_bones.new(name)
        bone.head, bone.tail = head, tail
        if name != "arm_lower_L":
            bone.parent = arm.data.edit_bones["arm_lower_L"]
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.mesh.primitive_cube_add(size=0.1, location=(0, 0, 0))
    obj = bpy.context.object
    obj.shape_key_add(name="Basis")
    corrective = obj.shape_key_add(name="Corrective")
    corrective.data[0].co += Vector((0.01, 0.02, 0.03))
    group = obj.vertex_groups.new(name="arm_lower_L")
    group.add(list(range(8)), 1, "REPLACE")
    obj.modifiers.new("Armature", "ARMATURE").object = arm
    before = {
        key.name: [point.co.copy() for point in key.data]
        for key in obj.data.shape_keys.key_blocks
    }
    # Anatomical wrist axes are +X, -Y, -Z with a nonzero translation.
    inverse = Matrix.Diagonal((1, -1, -1, 1)) @ Matrix.Translation((-1, -2, -3))
    original_export = shared.export
    checked = []

    def checked_export(path, objects, animated):
        for mesh in (o for o in objects if o.type == "MESH"):
            for key in mesh.data.shape_keys.key_blocks:
                for point, source in zip(key.data, before[key.name]):
                    assert (point.co - inverse @ source).length < 0.00001, key.name
            checked.append(mesh.name)
        original_export(path, objects, animated)

    shared.export = checked_export
    try:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "arm.glb"
            record = shared.arm_asset(arm, [obj], "L", target)
            assert checked and record["vertices"] == 8 and target.stat().st_size > 0
            bpy.ops.import_scene.gltf(filepath=str(target))
            imported = bpy.context.selected_objects
            assert any(
                o.type == "MESH"
                and o.data.shape_keys
                and "Corrective" in o.data.shape_keys.key_blocks
                for o in imported
            ), "Export must preserve the corrective morph target"
    finally:
        shared.export = original_export
    print("OFFICIAL_ARM_EXPORT_MORPH_TEST_OK", flush=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.mesh.primitive_cube_add()
    obj = bpy.context.object
    obj.shape_key_add(name="Basis")
    corrective = obj.shape_key_add(name="Corrective")
    corrective.data[0].co += Vector((0.1, 0.2, 0.3))
    keys = obj.data.shape_keys.key_blocks
    before = {key.name: [p.co.copy() for p in key.data] for key in keys}
    transform = (
        Matrix.Translation((0.2, -0.4, 0.8))
        @ Matrix.Rotation(1.7, 4, "Z")
        @ Matrix.Scale(0.9, 4)
    )
    transform_geometry(obj, transform)
    for key in keys:
        for point, original in zip(key.data, before[key.name]):
            assert (point.co - transform @ original).length < 0.00001, key.name
    expected_delta = transform.to_3x3() @ (before["Corrective"][0] - before["Basis"][0])
    actual_delta = corrective.data[0].co - keys["Basis"].data[0].co
    assert (actual_delta - expected_delta).length < 0.00001
    arm_export_regression()
    print("OFFICIAL_MORPH_TRANSFORM_TEST_OK", flush=True)


if __name__ == "__main__":
    main()
