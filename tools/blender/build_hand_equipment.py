"""Original presentation assets; meters, Godot +Y equipment axis, no collision.

Anatomy: shaped glove palm / sewn dorsal panels / padded finger module; full-tang
knife with bevel cross-section and contoured scales; three distinct utility shells.
All interfaces derive from shared dimensions. Safety rings/levers stay separable.
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from blender_build_utils import (  # noqa: E402 - Blender adds script directory explicitly.
    ensure_collection,
    export_collection_glb,
    make_material,
    move_to_collection,
    validate_collection,
)

COLLECTION = "VB_HAND_EQUIPMENT"
COL = None
MATS = {}
CONTACTS = []


def xyz(p):
    return (p[0], -p[2], p[1])


def mesh(name, vertices, faces, material, parent=None):
    data = bpy.data.meshes.new(name + "Mesh")
    data.from_pydata([xyz(p) for p in vertices], [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    COL.objects.link(obj)
    obj.data.materials.append(MATS[material])
    obj.parent = parent
    return obj


def empty(name):
    obj = bpy.data.objects.new(name, None)
    COL.objects.link(obj)
    return obj


def box(name, at, size, material, parent):
    bpy.ops.mesh.primitive_cube_add(size=1, location=xyz(at))
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    move_to_collection(obj, COL)
    obj.data.materials.append(MATS[material])
    obj.parent = parent
    return obj


def lathe(name, profile, material, parent, segments=32, x=0, z=0):
    verts = [
        (
            x + r * math.cos(i * math.tau / segments),
            y,
            z + r * math.sin(i * math.tau / segments),
        )
        for y, r in profile
        for i in range(segments)
    ]
    faces = []
    for ring in range(len(profile) - 1):
        for i in range(segments):
            j = (i + 1) % segments
            a, b = ring * segments + i, ring * segments + j
            faces.append((a, b, b + segments, a + segments))
    faces += [
        tuple(reversed(range(segments))),
        tuple((len(profile) - 1) * segments + i for i in range(segments)),
    ]
    # Godot coordinates become a right-handed Blender system; lathe outward faces.
    obj = mesh(name, verts, faces, material, parent)
    for poly in obj.data.polygons:
        poly.use_smooth = len(poly.vertices) == 4
    return obj


def torus(name, at, radius, tube, material, parent, vertical=False):
    verts, faces = [], []
    for i in range(32):
        a = i * math.tau / 32
        for j in range(8):
            b = j * math.tau / 8
            r = radius + tube * math.cos(b)
            p = (r * math.cos(a), tube * math.sin(b), r * math.sin(a))
            if vertical:
                p = (p[0], p[2], p[1])
            verts.append(tuple(at[k] + p[k] for k in range(3)))
    for i in range(32):
        for j in range(8):
            faces.append(
                (
                    i * 8 + j,
                    ((i + 1) % 32) * 8 + j,
                    ((i + 1) % 32) * 8 + (j + 1) % 8,
                    i * 8 + (j + 1) % 8,
                )
            )
    return mesh(name, verts, faces, material, parent)


def loft(name, sections, material, parent):
    # Each cross-section is a chamfered rectangle: crisp center and bevel planes.
    verts = []
    for y, w, d, offset in sections:
        verts += [
            (offset + x * w, y, z * d)
            for x, z in [
                (-1, -0.45),
                (-0.72, -1),
                (0.72, -1),
                (1, -0.45),
                (1, 0.45),
                (0.72, 1),
                (-0.72, 1),
                (-1, 0.45),
            ]
        ]
    faces = [tuple(reversed(range(8)))]
    for j in range(len(sections) - 1):
        for i in range(8):
            faces.append(
                (
                    j * 8 + i,
                    j * 8 + (i + 1) % 8,
                    (j + 1) * 8 + (i + 1) % 8,
                    (j + 1) * 8 + i,
                )
            )
    faces.append(tuple((len(sections) - 1) * 8 + i for i in range(8)))
    return mesh(name, verts, faces, material, parent)


def knife():
    root = empty("knife")
    loft(
        "KnifeFullTang",
        [
            (-0.139, 0.020, 0.009, 0),
            (-0.125, 0.021, 0.009, 0),
            (-0.015, 0.022, 0.009, 0),
            (0.002, 0.022, 0.009, 0),
        ],
        "steel",
        root,
    )
    loft(
        "KnifeGripScales",
        [
            (-0.131, 0.020, 0.014, 0),
            (-0.118, 0.022, 0.016, 0),
            (-0.096, 0.019, 0.016, 0),
            (-0.077, 0.023, 0.016, 0),
            (-0.056, 0.020, 0.016, 0),
            (-0.036, 0.024, 0.016, 0),
            (-0.014, 0.021, 0.014, 0),
        ],
        "rubber",
        root,
    )
    loft(
        "KnifeGuard",
        [
            (-0.014, 0.050, 0.023, 0),
            (-0.010, 0.054, 0.024, 0),
            (-0.003, 0.054, 0.024, 0),
            (0.001, 0.050, 0.023, 0),
        ],
        "darkmetal",
        root,
    )
    # Guard top=0.001, blade root=0: explicit 1mm seating overlap.
    CONTACTS.append({"interface": "blade_guard", "overlap_m": 0.001})
    loft(
        "KnifeBlade",
        [
            (0, 0.022, 0.003, 0),
            (0.018, 0.025, 0.004, 0),
            (0.155, 0.021, 0.003, 0),
            (0.204, 0.012, 0.002, -0.006),
            (0.235, 0.0003, 0.0003, -0.014),
        ],
        "steel",
        root,
    )
    for y in [-0.035, -0.077, -0.118]:
        for side in [-1, 1]:
            box(
                "GripInset",
                (side * 0.020, y, 0.0147),
                (0.003, 0.012, 0.002),
                "ochre",
                root,
            )
    for y in [-0.036, -0.108]:
        torus(
            "GripFastener",
            (0, y, 0.017),
            0.003,
            0.001,
            "darkmetal",
            root,
            vertical=True,
        )
    for y in [-0.022, -0.048, -0.074, -0.100, -0.124]:
        box("GripTraction", (0, y, -0.0161), (0.029, 0.0012, 0.001), "fabric", root)


def utility(kind):
    root = empty(kind)
    he = kind == "he_grenade"
    flash = kind == "flash_grenade"
    height = 0.14 if he else 0.19
    body = "silver" if flash else "olive"
    if he:
        profile = [
            (-0.074, 0.028),
            (-0.069, 0.041),
            (-0.053, 0.050),
            (-0.025, 0.054),
            (0.025, 0.054),
            (0.053, 0.047),
            (0.070, 0.030),
        ]
    else:
        profile = [
            (-height / 2, 0.045),
            (-height / 2 + 0.006, 0.052),
            (height / 2 - 0.012, 0.052),
            (height / 2, 0.043),
        ]
    lathe("UtilityShell", profile, body, root)
    for y in [-height * 0.37, height * 0.34]:
        lathe(
            "RolledBand",
            [
                (y - 0.006, 0.051),
                (y - 0.004, 0.055),
                (y + 0.004, 0.055),
                (y + 0.006, 0.051),
            ],
            "ochre" if he else ("darkmetal" if flash else "ivory"),
            root,
        )
    if he:
        for i in range(12):
            a = i * math.tau / 12
            # A narrow shell seam, shallow overlap with the body surface.
            obj = box(
                "ShellRib",
                (0.052 * math.cos(a), 0, 0.052 * math.sin(a)),
                (0.004, 0.092, 0.006),
                "olive",
                root,
            )
            obj.rotation_euler.z = -a
    elif flash:
        for i in range(12):
            a = i * math.tau / 12
            obj = box(
                "VentInset",
                (0.051 * math.cos(a), 0, 0.051 * math.sin(a)),
                (0.007, 0.055, 0.002),
                "darkmetal",
                root,
            )
            obj.rotation_euler.z = -a
    else:
        box("SmokeIDPanel", (0, 0, 0.052), (0.048, 0.050, 0.001), "ivory", root)
        for y in [-0.014, 0, 0.014]:
            box("SmokeIDMark", (0, y, 0.053), (0.032, 0.003, 0.001), "olive", root)
    top = height * 0.5
    lathe(
        "SafetyCap",
        [(top - 0.003, 0.028), (top + 0.009, 0.028), (top + 0.018, 0.021)],
        "darkmetal",
        root,
    )
    # Connected bent external spoon as one continuous loft, not disconnected bars.
    loft(
        "SafetyLever",
        [
            (top + 0.022, 0.017, 0.004, 0.010),
            (top + 0.014, 0.017, 0.004, 0.042),
            (top - 0.010, 0.014, 0.004, 0.054),
            (-top - 0.010, 0.014, 0.004, 0.054),
        ],
        "silver",
        root,
    )
    torus(
        "SafetyRing",
        (-0.034, top + 0.017, 0),
        0.016,
        0.0023,
        "steel",
        root,
        vertical=True,
    )
    CONTACTS.append({"interface": kind + "_cap_shell", "overlap_m": 0.003})


def glove():
    palm = empty("GlovePalm")
    # Palm length 92mm / width 86mm; broad metacarpal mass with tapered wrist.
    verts = []
    sections = [
        (-0.045, 0.032, 0.016),
        (-0.025, 0.042, 0.021),
        (0.015, 0.040, 0.022),
        (0.048, 0.028, 0.017),
    ]
    for z, w, d in sections:
        verts += [
            (x * w, y * d, z)
            for x, y in [
                (-1, -0.45),
                (-0.72, -1),
                (0.72, -1),
                (1, -0.45),
                (1, 0.45),
                (0.72, 1),
                (-0.72, 1),
                (-1, 0.45),
            ]
        ]
    faces = [tuple(reversed(range(8)))]
    for j in range(3):
        faces.extend(
            [
                (
                    j * 8 + i,
                    j * 8 + (i + 1) % 8,
                    (j + 1) * 8 + (i + 1) % 8,
                    (j + 1) * 8 + i,
                )
                for i in range(8)
            ]
        )
    faces.append(tuple(24 + i for i in range(8)))
    mesh("GloveLeather", verts, faces, "rubber", palm)
    for x in [-0.029, -0.009, 0.011, 0.031]:
        box("DorsalKnuckle", (x, 0.022, -0.021), (0.016, 0.011, 0.023), "fabric", palm)
    box("DorsalPanel", (0, 0.022, 0.014), (0.062, 0.006, 0.030), "olive", palm)
    for side in [-1, 1]:
        for z in [-0.028, -0.018, -0.008, 0.002, 0.012, 0.022, 0.032]:
            box(
                "GloveStitch",
                (side * 0.033, 0.022, z),
                (0.001, 0.001, 0.003),
                "ochre",
                palm,
            )
    box("PalmReinforcement", (0, -0.021, 0), (0.057, 0.004, 0.057), "fabric", palm)
    finger = empty("GloveFinger")
    # One 31mm phalange; runtime's existing joint chain bends these modules.
    loft(
        "FingerLeather",
        [
            (-0.015, 0.0075, 0.008, 0),
            (-0.011, 0.0095, 0.010, 0),
            (0.009, 0.009, 0.0095, 0),
            (0.015, 0.0065, 0.007, 0),
        ],
        "rubber",
        finger,
    )
    # Convert this module from +Y length to runtime -Z length at origin.
    for child in list(finger.children):
        for v in child.data.vertices:
            # Blender Z axis is Godot Y; Blender Y axis is Godot -Z.
            v.co.y, v.co.z = -v.co.z, v.co.y
    box("FingerPad", (0, 0.010, 0), (0.014, 0.004, 0.016), "fabric", finger)
    box("FingerSeam", (0, 0.012, 0.008), (0.014, 0.001, 0.001), "ochre", finger)
    cuff = empty("GloveCuff")
    box("CuffWrap", (0, -0.004, 0.055), (0.064, 0.040, 0.024), "olive", cuff)
    box("CuffStrap", (0, 0.019, 0.055), (0.061, 0.008, 0.014), "rubber", cuff)
    box("CuffPatch", (0.017, 0.024, 0.055), (0.016, 0.003, 0.010), "ochre", cuff)


def build_all():
    global COL, MATS
    bpy.ops.wm.read_factory_settings(use_empty=True)
    COL = ensure_collection(COLLECTION)
    specs = {
        "steel": ((0.42, 0.48, 0.51, 1), 0.90, 0.24),
        "darkmetal": ((0.055, 0.065, 0.07, 1), 0.75, 0.34),
        "rubber": ((0.028, 0.035, 0.038, 1), 0, 0.78),
        "fabric": ((0.095, 0.115, 0.11, 1), 0, 0.91),
        "olive": ((0.12, 0.17, 0.10, 1), 0.18, 0.62),
        "silver": ((0.40, 0.44, 0.46, 1), 0.8, 0.32),
        "ochre": ((0.64, 0.36, 0.065, 1), 0.15, 0.55),
        "ivory": ((0.68, 0.70, 0.60, 1), 0, 0.73),
    }
    MATS = {
        key: make_material("MAT_equipment_" + key, c, metallic=m, roughness=r)
        for key, (c, m, r) in specs.items()
    }
    knife()
    for kind in ["he_grenade", "flash_grenade", "smoke_grenade"]:
        utility(kind)
    glove()
    # Recalculate outward normals for every closed part; no negative mesh scales.
    for obj in list(COL.all_objects):
        if obj.type != "MESH":
            continue
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.normals_make_consistent(inside=False)
        bpy.ops.uv.smart_project(angle_limit=1.1519, island_margin=0.02)
        bpy.ops.object.mode_set(mode="OBJECT")
    result = validate_collection(COLLECTION)
    output = ROOT / "assets/models/equipment/hand_equipment.glb"
    export_collection_glb(COLLECTION, output)
    source = ROOT / "assets-source/blender/equipment/hand_equipment_source.blend"
    source.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(source))
    return {"validation": result, "contacts": CONTACTS, "output": str(output)}


if __name__ == "__main__":
    print(json.dumps(build_all(), indent=2))
