"""Cross-category candidate cohorts keep every site, mode and outcome source."""

import copy
import json
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from modern_quadrature_cross_category import (
    BASE_PROBES,
    CADENCE_PROBES,
    FAMILIES,
    PROBES,
    QUEUE_PROBES,
    choose_groups,
    payload,
)
from movement_evidence_bank import LEVELS


class CrossCategoryTests(unittest.TestCase):
    def setUp(self):
        temp = TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        for name in (*BASE_PROBES, *QUEUE_PROBES, *CADENCE_PROBES, *PROBES):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture")

    @staticmethod
    def point(parent, kind, mode) -> dict[str, Any]:
        keys = ["W", "Space"] if mode == "jump" else ["W"]
        if mode == "walk":
            keys.append("Shift")
        return dict(
            id=f"{parent}__{mode}",
            parent_case=parent,
            kind=kind,
            scheme="modern_cs",
            queued_input=True,
            trial_mode=mode,
            start=[0, 0.9, 0],
            target_feet=[0, 0, -1],
            yaw=0,
            duration=2,
            target_radius=0.35,
            target_height_tolerance=0.18,
            native_timeline=[dict(at=0, keys=keys, mouse_dx=0)],
            probe_sha256={},
        )

    def source(self, family="critical", name="dust2") -> dict[str, Any]:
        parents = (
            ("rise_00", "rise_01")
            if name == "inferno" and family == "critical"
            else (family,)
        )
        return dict(
            schema=4,
            formal_qualification=False,
            level=LEVELS[name],
            identity={},
            runtime_sha256={},
            input_map_sha256="fixture",
            cases=[
                self.point(p, FAMILIES[family], m)
                for p in parents
                for m in ("jump", "no_jump", "walk")
            ],
        )

    def providers(self, name="dust2"):
        result = {}
        for family in FAMILIES:
            source = self.source(family, name)
            paths = {}
            for field, value in (
                ("manifest", source),
                ("report60", {}),
                ("report120", {}),
            ):
                path = self.root / f"{name}-{family}-{field}.json"
                path.write_text(json.dumps(value), encoding="utf-8")
                paths[field] = str(path)
            result[family] = paths
        return result

    def test_only_queued_modern_category_is_selected(self):
        source = self.source()
        other = copy.deepcopy(source["cases"])
        for p in other:
            p["queued_input"] = False
        source["cases"].extend(other)
        self.assertEqual(len(choose_groups(source, "critical")), 1)
        self.assertEqual(sum(map(len, choose_groups(source, "critical").values())), 3)

    def test_missing_or_duplicate_mode_rejected(self):
        source = self.source()
        source["cases"].pop()
        with self.assertRaisesRegex(ValueError, "all three modes"):
            choose_groups(source, "critical")
        source = self.source()
        source["cases"].append(copy.deepcopy(source["cases"][0]))
        with self.assertRaisesRegex(ValueError, "all three modes"):
            choose_groups(source, "critical")

    def test_control_geometry_cannot_change(self):
        source = self.source()
        source["cases"][1]["target_radius"] = 2
        with self.assertRaisesRegex(ValueError, "geometry"):
            choose_groups(source, "critical")

    def test_control_timeline_cannot_change(self):
        source = self.source()
        source["cases"][1]["native_timeline"][0]["at"] = 0.1
        with self.assertRaisesRegex(ValueError, "timeline"):
            choose_groups(source, "critical")

    def test_camera_source_rejected(self):
        source = self.source()
        source["camera_only"] = True
        with self.assertRaisesRegex(ValueError, "physical"):
            choose_groups(source, "critical")

    def test_all_predeclared_sites_and_modes_survive_candidate_expansion(self):
        for name, count in (("dust2", 18), ("mirage", 18), ("inferno", 24)):
            providers = self.providers(name)
            result = payload(name, providers, self.root, self.root / "reject.json")
            self.assertEqual(len(result["cases"]), count)
            self.assertEqual(
                sum(p["quadrature_enabled"] for p in result["cases"]), count // 2
            )
            for point in result["cases"]:
                original = self.source(point["source_family"], name)
                parent = next(
                    p for p in original["cases"] if p["id"] == point["source_case"]
                )
                self.assertEqual(point["native_timeline"], parent["native_timeline"])
                self.assertEqual(point["kind"], parent["kind"])
            self.assertFalse(result["formal_qualification"])

    def test_source_map_alias_rejected(self):
        providers = self.providers()
        path = Path(providers["edge"]["manifest"])
        data = json.loads(path.read_text())
        data["level"] = LEVELS["mirage"]
        path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "map label"):
            payload("dust2", providers, self.root, self.root / "reject.json")

    def test_inferno_missing_second_critical_site_rejected(self):
        providers = self.providers("inferno")
        path = Path(providers["critical"]["manifest"])
        data = json.loads(path.read_text())
        data["cases"] = [p for p in data["cases"] if p["parent_case"] != "rise_01"]
        path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "site coverage"):
            payload("inferno", providers, self.root, self.root / "reject.json")


if __name__ == "__main__":
    unittest.main()
