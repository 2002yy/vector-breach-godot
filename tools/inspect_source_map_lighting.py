"""Recover private native map probe/fog inputs; never edit gameplay or source assets."""

import argparse
import hashlib
import json
import math
import os
import subprocess
import tempfile
from pathlib import Path, PurePosixPath

from source_probe_volume import FloatVolume, probe_record, sample_blended, sample_probe


def gpu_input(probes, volume, texture_name, volume_file):
    candidates = [
        p for p in probes if p["texture"] == texture_name and p["sample_supported"]
    ]
    selected = candidates[:6]
    for probe in candidates:
        if probe["yaw_degrees"] != 0 and probe not in selected:
            selected.append(probe)
            break
    cases = []
    directions = [
        [1, 0, 0],
        [-1, 0, 0],
        [0, 1, 0],
        [0, -1, 0],
        [0, 0, 1],
        [0, 0, -1],
        [1, -2, 3],
    ]
    for index, probe in enumerate(selected):
        for fraction in ([0.5, 0.5, 0.5], [0.13, 0.71, 0.61]):
            local = [
                b + s * f
                for b, s, f in zip(probe["bounds_min"], probe["bounds_size"], fraction)
            ]
            angle = math.radians(probe["yaw_degrees"])
            c, s = math.cos(angle), math.sin(angle)
            world = [c * local[0] - s * local[1], s * local[0] + c * local[1], local[2]]
            world = [v + o for v, o in zip(world, probe["origin"])]
            for direction in directions:
                rgb, _ = sample_probe(probe, volume, world, direction)
                cases.append(
                    {
                        "name": f"probe-{index}-{fraction}-{direction}",
                        "probe_origin": probe["origin"],
                        "bounds_min": probe["bounds_min"],
                        "bounds_size": probe["bounds_size"],
                        "atlas_size": probe["atlas_size"],
                        "atlas_offset": probe["atlas_offset"],
                        "yaw_degrees": probe["yaw_degrees"],
                        "source_position": world,
                        "source_direction": direction,
                        "rgb": rgb,
                    }
                )
    return {"dimensions": volume.dimensions, "volume_file": volume_file, "cases": cases}


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def resource_name(name):
    path = PurePosixPath(name)
    if (
        not name
        or path.is_absolute()
        or ".." in path.parts
        or "\\" in name
        or ":" in name
    ):
        raise ValueError("Unsafe native resource name")
    return name + "_c"


def run(arguments, env=None):
    result = subprocess.run(
        arguments,
        env=env,
        capture_output=True,
        encoding="utf-8",
        errors="strict",
        timeout=240,
    )
    if result.returncode:
        raise RuntimeError(result.stderr[-3000:] + result.stdout[-1000:])
    return result.stdout


def recover(cli, bridge, level, vpk, output):
    if output.exists():
        raise FileExistsError("Existing evidence preserved; use a new output directory")
    config = json.loads(level.read_text(encoding="utf-8"))
    trace = config["sourceTrace"]
    if vpk.stem != trace["referenceMap"] or sha(vpk) != trace["vpkSha256"]:
        raise ValueError("Map package differs from authoritative level source trace")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        dir=output.parent, prefix=output.name + ".partial-"
    ) as folder:
        stage = Path(folder)
        sources = {}

        def load(name, texture=False):
            compiled = resource_name(name)
            source = stage / "native" / compiled
            source.parent.mkdir(parents=True, exist_ok=True)
            run([str(cli), "-i", str(vpk), "-f", compiled, "-o", str(source)])
            if not source.is_file():
                raise FileNotFoundError("Missing compiled resource: " + compiled)
            env = os.environ.copy()
            env.pop("VB_RESOURCE_RGBA", None)
            env.update(DOTNET_STARTUP_HOOKS=str(bridge), VB_RESOURCE_INPUT=str(source))
            raw = stage / (str(len(sources)) + ".rgba32f")
            if texture:
                env["VB_RESOURCE_RGBA"] = str(raw)
            parsed = json.loads(run([str(cli), "--help"], env=env))
            (source.parent / (source.name + ".json")).write_text(
                json.dumps(parsed, indent=2) + "\n", encoding="utf-8"
            )
            sources[name] = {"compiled_sha256": sha(source)}
            if name.endswith(".vtex"):
                sources[name]["metadata"] = parsed.copy()
            if texture:
                parsed["file"] = raw.name
                parsed["sha256"] = sha(raw)
                sources[name]["decoded"] = parsed
            return parsed

        world = load("maps/" + vpk.stem + "/world.vwrld")
        info = world["m_worldLightingInfo"]
        if (info["m_nLightmapVersionNumber"], info["m_nLightmapGameVersionNumber"]) != (
            8,
            2,
        ):
            raise ValueError("Only audited 8.2 atlas lighting is supported")
        entities, child_lumps = [], []
        for name in world["m_entityLumps"]:
            lump = load(name)
            entities.extend(lump["entities"])
            child_lumps.extend(lump["children"] or [])
        probes = [
            probe_record(e)
            for e in entities
            if e.get("classname")
            in ("env_light_probe_volume", "env_combined_light_probe_volume")
        ]
        fog = [e for e in entities if "fog" in e.get("classname", "")]
        sun = [e for e in entities if e.get("classname") == "light_environment"]
        if not probes:
            raise ValueError("No atlas probes found")
        for name in dict.fromkeys(
            p["shadow_texture"] for p in probes if p["shadow_texture"]
        ):
            load(name)
        volumes = {}
        for name in dict.fromkeys(p["texture"] for p in probes):
            metadata = load(name, texture=True)
            volumes[name] = FloatVolume(
                (stage / metadata["file"]).read_bytes(), metadata["dimensions"]
            )
        for probe in probes:
            shadow = sources[probe["shadow_texture"]]["metadata"]["dimensions"]
            irradiance = volumes[probe["texture"]].dimensions
            if list(irradiance) != [shadow[0], shadow[1], shadow[2] * 6]:
                raise ValueError("Shadow/irradiance atlas dimensions disagree")
        samples = []
        gpu_inputs = []
        for index, (name, volume) in enumerate(volumes.items()):
            filename = f"probe-{index}-gpu-input.json"
            checks = gpu_input(probes, volume, name, sources[name]["decoded"]["file"])
            (stage / filename).write_text(
                json.dumps(checks, indent=2, allow_nan=False) + "\n", encoding="utf-8"
            )
            gpu_inputs.append(filename)
        supported = all(p["sample_supported"] for p in probes)
        if supported:
            for entity in entities:
                if entity.get("classname") not in (
                    "info_player_terrorist",
                    "info_player_counterterrorist",
                ):
                    continue
                position = list(entity["origin"])
                position[2] += (
                    64  # Probe native eye height; gameplay remains untouched.
                )
                samples.append(
                    {
                        "classname": entity["classname"],
                        "position_source": position,
                        "directions": {
                            name: sample_blended(probes, volumes, position, direction)
                            for name, direction in {
                                "+x": [1, 0, 0],
                                "-x": [-1, 0, 0],
                                "+y": [0, 1, 0],
                                "-y": [0, -1, 0],
                                "+z": [0, 0, 1],
                                "-z": [0, 0, -1],
                            }.items()
                        },
                    }
                )
        receipt = {
            "schema": 1,
            "contract": "source-map-lighting-diagnostic-v1",
            "level": config["id"],
            "source_trace": trace,
            "world_lighting": info,
            "sources": sources,
            "probes": probes,
            "fog_entities": fog,
            "sun_entities": sun,
            "spawn_samples": samples,
            "gpu_inputs": gpu_inputs,
            "child_lumps_not_instantiated": child_lumps,
            "limits": [
                "native Source coordinates; game alignment not applied",
                "VRF 8.2 LPV rules; original-engine image reference pending",
                "SH1 fallback and FogModificationAmount not recovered",
                "not enabled in gameplay",
                "child/prefab transforms and pitch/roll probes require separate handling",
            ],
        }
        (stage / "lighting.json").write_text(
            json.dumps(receipt, indent=2, allow_nan=False) + "\n", encoding="utf-8"
        )
        stage.rename(output)
    return receipt


def main():
    parser = argparse.ArgumentParser()
    for name in ["cli", "bridge", "level", "vpk", "output"]:
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    data = recover(**{key: value.resolve() for key, value in vars(args).items()})
    print(
        "SOURCE_MAP_LIGHTING_RECOVERED",
        data["level"],
        "probes=",
        len(data["probes"]),
        "spawn_samples=",
        len(data["spawn_samples"]),
    )


if __name__ == "__main__":
    main()
