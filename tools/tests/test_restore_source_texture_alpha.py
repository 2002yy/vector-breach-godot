"""Regression: unused alpha and same-basename resources must remain distinct."""

import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image

SPEC = importlib.util.spec_from_file_location(
    "restore_alpha",
    Path(__file__).resolve().parents[1] / "restore_source_texture_alpha.py",
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class AlphaRestoreTests(unittest.TestCase):
    def test_constant_channels_skipped_and_shared_names_keep_resource_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            resources = root / "resources"
            target = root / "target"
            target.mkdir()
            work = root / "work"
            scene = {"materials": [], "textures": [], "images": []}
            hashes = {}
            channels = [(0, 0), (127, 127), (255, 255), (0, 64), (0, 255)]
            for index, alpha in enumerate(channels):
                uri = f"{index}/shared.png"
                original = resources / f"materials/{index}/shared.vtex_c"
                original.parent.mkdir(parents=True)
                image = Image.new("RGBA", (2, 1), (index * 20, 80, 140, 255))
                image.putalpha(Image.frombytes("L", (2, 1), bytes(alpha)))
                image.save(original, format="PNG")
                output = target / uri
                output.parent.mkdir()
                image.convert("RGB").save(output)
                hashes[uri] = hashlib.sha256(output.read_bytes()).hexdigest()
                scene["images"].append({"uri": uri})
                scene["textures"].append({"source": index})
                scene["materials"].append(
                    {
                        "alphaMode": "MASK",
                        "pbrMetallicRoughness": {"baseColorTexture": {"index": index}},
                        "extras": {
                            "vmat": {
                                "TextureParams": {
                                    "g_tColor": f"materials/{index}/shared.vtex"
                                }
                            }
                        },
                    }
                )
            source = root / "source.gltf"
            source.write_text(json.dumps(scene), encoding="utf-8")
            visual = target / "map.gltf"
            visual.write_text(json.dumps(scene), encoding="utf-8")
            receipt = visual.with_suffix(".receipt.json")
            receipt.write_text(
                json.dumps({"copied_dependency_sha256": hashes}), encoding="utf-8"
            )

            def decode(command, **_kwargs):
                inputs = Path(command[command.index("-i") + 1])
                decoded = Path(command[command.index("-o") + 1])
                staged = list(inputs.rglob("*.vtex_c"))
                self.assertEqual(len(staged), len(channels))
                for path in staged:
                    output = decoded / path.relative_to(inputs).with_suffix(".png")
                    output.parent.mkdir(parents=True, exist_ok=True)
                    with Image.open(path) as image:
                        image.save(output)
                return subprocess.CompletedProcess(command, 0)

            arguments = [
                "restore",
                "--source-gltf",
                str(source),
                "--target-gltf",
                str(visual),
                "--resources",
                str(resources),
                "--decoder",
                "mock-decoder",
                "--work",
                str(work),
            ]
            with (
                patch.object(sys, "argv", arguments),
                patch.object(MODULE.subprocess, "run", decode),
            ):
                MODULE.main()
            for index in range(3):
                output = target / f"{index}/shared.png"
                self.assertEqual(
                    hashlib.sha256(output.read_bytes()).hexdigest(),
                    hashes[f"{index}/shared.png"],
                )
            for index in [3, 4]:
                with Image.open(target / f"{index}/shared.png") as image:
                    self.assertEqual(
                        image.getchannel("A").getextrema(), channels[index]
                    )
                self.assertTrue((work / f"before/{index}/shared.png").is_file())
            result = json.loads(receipt.read_text(encoding="utf-8"))
            self.assertEqual(
                {item["uri"] for item in result["native_alpha_restorations"]},
                {"3/shared.png", "4/shared.png"},
            )


if __name__ == "__main__":
    unittest.main()
