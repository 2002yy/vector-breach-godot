"""Extract private native reflection blocks and spatial inputs from matching VPK."""

import argparse
import hashlib
import json
import math
import os
import subprocess
import tempfile
from pathlib import Path

from source_reflection import box_direction, reflection_record, validate_blocks


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def run(args, env=None):
    result = subprocess.run(
        [str(arg) for arg in args],
        check=False,
        env=env,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=180,
    )
    if result.returncode:
        raise RuntimeError(result.stderr[-2000:] + result.stdout[-2000:])
    return result.stdout


def recover(cli, bridge, entity_bridge, level, vpk, output):
    config = json.loads(level.read_text(encoding="utf-8"))
    trace = config["sourceTrace"]
    if sha(vpk) != trace["vpkSha256"] or vpk.stem != trace["referenceMap"]:
        raise ValueError("VPK differs from authoritative level")
    if output.exists():
        raise FileExistsError("Existing reflection evidence preserved")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        dir=output.parent, prefix=output.name + ".partial-"
    ) as folder:
        stage = Path(folder)
        native = stage / "native"
        native.mkdir()
        name = "maps/" + vpk.stem
        texture_name = name + "/cubemaps/env_cubemap_array.vtex"
        compiled = native / "env_cubemap_array.vtex_c"
        entities = native / "default_ents.vents_c"
        run([cli, "-i", vpk, "-f", texture_name + "_c", "-o", compiled])
        run(
            [
                cli,
                "-i",
                vpk,
                "-f",
                name + "/entities/default_ents.vents_c",
                "-o",
                entities,
            ]
        )
        env = os.environ.copy()
        env.pop("VB_RESOURCE_RGBA", None)
        env.update(
            DOTNET_STARTUP_HOOKS=str(entity_bridge), VB_RESOURCE_INPUT=str(entities)
        )
        lump = json.loads(run([cli, "--help"], env))
        env.update(
            DOTNET_STARTUP_HOOKS=str(bridge),
            VB_RESOURCE_INPUT=str(compiled),
            VB_REFLECTION_OUTPUT=str(stage / "blocks"),
        )
        blocks = json.loads(run([cli, "--help"], env))
        payload = stage / "blocks/reflection.bc6h"
        validate_blocks(blocks, payload.read_bytes())
        selected = [e for e in lump["entities"] if e.get("cubemaptexture")]
        if any(
            e.get("classname") != "env_combined_light_probe_volume"
            or e["cubemaptexture"] != texture_name
            for e in selected
        ):
            raise ValueError(
                "Separate reflection class/texture requires explicit handling"
            )
        probes = [reflection_record(entity, blocks["cubes"]) for entity in selected]
        if sorted(p["cube_index"] for p in probes) != list(range(blocks["cubes"])):
            raise ValueError("Probe index coverage differs from native cube array")
        cases = []
        for probe in probes:
            if not probe["sample_supported"] or not probe["enabled"]:
                continue
            yaw = math.radians(probe["yaw_degrees"])
            c, s = math.cos(yaw), math.sin(yaw)
            for fraction in [0.15, 0.5, 0.83]:
                local = [
                    a + b * fraction
                    for a, b in zip(probe["bounds_min"], probe["bounds_size"])
                ]
                point = [
                    c * local[0] - s * local[1],
                    s * local[0] + c * local[1],
                    local[2],
                ]
                point = [p + o for p, o in zip(point, probe["origin"])]
                for direction in [[1, 0, 0], [0, -1, 1], [1, -2, 3]]:
                    cases.append(
                        {
                            "cube_index": probe["cube_index"],
                            "position": point,
                            "ray": direction,
                            "origin_yaw": probe["origin"] + [yaw],
                            "minimum": probe["bounds_min"],
                            "size": probe["bounds_size"],
                            "expected": box_direction(probe, point, direction),
                        }
                    )
        data = dict(
            blocks,
            level=config["id"],
            source_trace=trace,
            file="blocks/reflection.bc6h",
            sha256=sha(payload),
            compiled_sha256=sha(compiled),
            entity_sha256=sha(entities),
            probes=probes,
            projection_cases=cases,
            limits=[
                "raw reflection input diagnostic; no BRDF or hair lobe",
                "default entity lump only; child transforms not instantiated",
            ],
        )
        (stage / "reflection.json").write_text(
            json.dumps(data, indent=2, allow_nan=False), encoding="utf-8"
        )
        stage.rename(output)
    return data


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ["cli", "bridge", "entity_bridge", "level", "vpk", "output"]:
        parser.add_argument("--" + key.replace("_", "-"), type=Path, required=True)
    result = recover(
        **{key: value.resolve() for key, value in vars(parser.parse_args()).items()}
    )
    print(
        "SOURCE_REFLECTION_INPUTS_OK",
        result["level"],
        "cubes",
        result["cubes"],
        "mips",
        result["mip_count"],
    )
