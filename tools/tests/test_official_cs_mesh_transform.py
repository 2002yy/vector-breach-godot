"""Blender regression for native body morph/Basis coordinate preservation."""

from pathlib import Path
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "blender"))
from convert_official_cs_assets import transform_geometry


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
    print("OFFICIAL_MORPH_TRANSFORM_TEST_OK", flush=True)


if __name__ == "__main__":
    main()
