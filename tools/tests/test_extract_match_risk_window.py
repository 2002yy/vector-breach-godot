import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
from typing import Any
import unittest

SPEC = importlib.util.spec_from_file_location(
    "risk_window",
    Path(__file__).parents[1] / "authoring" / "extract_match_risk_window.py",
)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
extract = MODULE.extract


def row(frame, serial=2) -> dict[str, Any]:
    actors = []
    for index, distance in enumerate([8, 3, 1, 2, 0]):
        actors.append(
            dict(
                name=f"actor{index}",
                team="T",
                alive=index != 4,
                x=distance,
                y=0,
                z=0,
                ai=dict(
                    state="ENGAGE",
                    tactical_reason="fixture",
                    navigation_path_nodes=4,
                    route_stalled_seconds=0,
                    route_blocked=False,
                    target_visible_seconds=1,
                    damage_seconds=2,
                    bomb_carrier=index == 0,
                ),
            )
        )
    return dict(
        frame=frame,
        serial=serial,
        round_state="Live",
        round_seconds=20,
        c4_state="dropped",
        c4_position="(0, 0, 0)",
        player_dead=True,
        spectator=dict(active=True),
        actors=actors,
    )


class ExtractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.source = Path(self.temp.name) / "trace.jsonl"

    def write(self, rows):
        self.source.write_text(
            "".join(json.dumps(r) + "\n" for r in rows), encoding="utf8"
        )

    def test_nearest_are_not_carriers_and_next_serial_is_explicit(self):
        self.write(
            [
                row(60, 1),
                {"event": "round_ended", "serial": 1},
                row(120),
                row(180, 3),
            ]
        )
        result = extract(self.source, 2, 100, 120)
        self.assertEqual(
            result["source_sha256"],
            hashlib.sha256(self.source.read_bytes()).hexdigest(),
        )
        self.assertEqual(result["samples"][0]["carriers"], ["actor0"])
        self.assertEqual(
            [a["name"] for a in result["samples"][0]["nearest_alive_t"]],
            ["actor2", "actor3", "actor1"],
        )
        self.assertEqual(result["following"]["serial"], 3)
        self.assertTrue(result["samples"][0]["player_dead"])
        self.assertNotIn("lease_owner", json.dumps(result))

    def test_missing_window_invalid_range_and_reordered_frames_fail(self):
        self.write([row(60), row(120)])
        for arguments in [(9, 0, 120), (2, 120, 60)]:
            with self.assertRaises(ValueError):
                extract(self.source, *arguments)
        self.write([row(120), row(60)])
        with self.assertRaises(ValueError):
            extract(self.source, 2, 0, 120)

    def test_eof_does_not_invent_following_and_ct_is_excluded(self):
        sample = row(60)
        sample["actors"][2]["team"] = "CT"
        self.write([sample])
        result = extract(self.source, 2, 60, 60)
        self.assertIsNone(result["following"])
        self.assertNotIn(
            "actor2", [a["name"] for a in result["samples"][0]["nearest_alive_t"]]
        )


if __name__ == "__main__":
    unittest.main()
