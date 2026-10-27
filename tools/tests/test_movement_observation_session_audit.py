"""Recorded replay seams must not masquerade as continuous observation evidence."""

import copy
import sys
import unittest
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from movement_observation_session_audit import audit_samples


def sample(frame) -> dict[str, Any]:
    return dict(
        physics_frame=frame,
        consumed_usec=frame * 16667,
        input_event_usec=0,
        delta=1 / 60,
        direction=[0, -1],
        jump_requested=False,
        jumped=False,
        crouch_requested=False,
        walk_requested=False,
        grounded_before=True,
        grounded=True,
        capsule_height=1.8,
        position=[0, 0, -frame / 60],
        velocity=[0, 0, -1],
    )


class SessionAuditTests(unittest.TestCase):
    def setUp(self):
        self.manifest: dict[str, Any] = dict(
            observation_scheme="current",
            cases=[dict(parent_case="a"), dict(parent_case="b")],
        )
        self.data: dict[str, Any] = dict(
            human_review="pending",
            formal_release_ready=False,
            attempts=[
                dict(
                    case=case,
                    scheme="current",
                    human_review="pending",
                    reason=reason,
                    trace=[sample(frame)],
                )
                for case, reason, frame in (
                    ("a", "session_start", 1),
                    ("a", "retry", 2),
                    ("b", "next_case", 3),
                    ("a", "next_case", 4),
                )
            ],
        )

    def check(self):
        return audit_samples(self.data, self.manifest, 60)

    def test_recorded_transitions_and_speed_remain_technical_only(self):
        result = self.check()
        self.assertEqual(result["samples"], 4)
        self.assertEqual(result["max_observed_horizontal_speed"], 1)
        self.assertEqual(result["reset_reasons"]["next_case"], 2)
        self.assertFalse(result["physical_human_input_verified"])
        self.assertEqual(result["human_review"], "pending")

    def test_cross_attempt_frame_rollback_rejected(self):
        self.data["attempts"][1]["trace"][0]["physics_frame"] = 1
        with self.assertRaisesRegex(ValueError, "rollback"):
            self.check()

    def test_retry_cannot_jump_to_another_known_case(self):
        self.data["attempts"][1]["case"] = "b"
        with self.assertRaisesRegex(ValueError, "binding"):
            self.check()

    def test_next_case_cannot_skip_or_reuse_point(self):
        self.data["attempts"][2]["case"] = "a"
        with self.assertRaisesRegex(ValueError, "binding"):
            self.check()

    def test_unknown_and_repeated_session_start_rejected(self):
        for reason in ("next_scheme", "session_start"):
            self.data["attempts"][1]["reason"] = reason
            with self.assertRaises(ValueError):
                self.check()

    def test_physics_rate_mismatch_rejected(self):
        with self.assertRaisesRegex(ValueError, "rate mismatch"):
            audit_samples(self.data, self.manifest, 120)

    def test_sample_clocks_reject_backwards_future_boolean_and_nonfinite(self):
        original = copy.deepcopy(self.data)
        for field, value in (
            ("consumed_usec", 1),
            ("input_event_usec", 99999999),
            ("consumed_usec", True),
            ("input_event_usec", float("nan")),
        ):
            self.data = copy.deepcopy(original)
            self.data["attempts"][1]["trace"][0][field] = value
            with self.assertRaisesRegex(ValueError, "clock"):
                self.check()

    def test_direction_must_match_input_vector_domain(self):
        for direction in ([1, 1], [0], [0, float("inf")], [False, 0]):
            self.data["attempts"][0]["trace"][0]["direction"] = direction
            with self.assertRaisesRegex(ValueError, "direction"):
                self.check()

    def test_jump_evidence_requires_request_and_pre_step_support(self):
        first = self.data["attempts"][0]["trace"][0]
        first["jumped"] = True
        with self.assertRaisesRegex(ValueError, "jump without"):
            self.check()
        first["jump_requested"] = True
        self.check()
        first["grounded_before"] = False
        with self.assertRaisesRegex(ValueError, "jump without"):
            self.check()

    def test_immediate_retry_can_preserve_empty_attempt_without_inventing_samples(self):
        self.data["attempts"][1]["trace"] = []
        result = self.check()
        self.assertEqual(result["empty_attempts"], 1)
        self.assertEqual(result["samples"], 3)

    def test_truncation_and_fake_human_acceptance_rejected(self):
        self.data["attempts"][0]["trace_truncated"] = True
        with self.assertRaisesRegex(ValueError, "truncated"):
            self.check()
        self.data["attempts"][0]["trace_truncated"] = False
        self.data["human_review"] = "passed"
        with self.assertRaisesRegex(ValueError, "human acceptance"):
            self.check()

    def test_frozen_profile_and_duplicate_manifest_point_rejected(self):
        self.data["attempts"][0]["scheme"] = "legacy_16"
        with self.assertRaisesRegex(ValueError, "profile"):
            self.check()
        self.data["attempts"][0]["scheme"] = "current"
        self.manifest["cases"].append(dict(parent_case="a"))
        with self.assertRaisesRegex(ValueError, "ambiguous"):
            self.check()


if __name__ == "__main__":
    unittest.main()
