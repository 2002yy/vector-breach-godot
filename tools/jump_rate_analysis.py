"""Explain frozen flat-fixture jump traces without changing gameplay parameters."""

import argparse
import hashlib
import json
from pathlib import Path


def analyze(evidence: Path) -> dict:
    rows = []
    sources = {}
    for rate in (60, 120):
        source = evidence / f"rate{rate}-v3" / "raw.json"
        sources[str(source)] = hashlib.sha256(source.read_bytes()).hexdigest()
        data = json.loads(source.read_text(encoding="utf-8"))
        assert data["physics_rate"] == rate
        for case in data["rows"]:
            if case["case"] not in ("jump", "crouch_jump"):
                continue
            trace = case["trace"]
            jumps = [i for i, x in enumerate(trace) if x["jumped"]]
            assert len(jumps) == 1
            start = jumps[0]
            first = trace[start]
            assert first["grounded_before"] and first["jump_requested"]
            dt = 1 / rate
            assert all(abs(x["delta"] - dt) < 1e-12 for x in trace)
            gravity = 9.8 if case["scheme"] == "current" else 20.32
            impulse = first["velocity"][1]
            # Runtime skips gravity on grounded launch and moves by full impulse.
            offset = first["foot_y"] - first["foot_before"] - impulse * dt
            ascent = []
            for n, sample in enumerate(trace[start:]):
                if sample["velocity"][1] < 0:
                    break
                expected = (n + 1) * impulse * dt - gravity * dt * dt * n * (n + 1) / 2
                ascent.append((sample, expected))
            residual = max(
                abs(x["foot_y"] - first["foot_before"] - y - offset) for x, y in ascent
            )
            assert residual < 0.00001
            discrete_peak = max(y for _, y in ascent)
            continuous_peak = impulse * impulse / (2 * gravity)
            rows.append(
                dict(
                    rate=rate,
                    scheme=case["scheme"],
                    case=case["case"],
                    launch_tick=first["tick"],
                    impulse_mps=impulse,
                    gravity_mps2=gravity,
                    measured_peak_m=max(x["foot_y"] for x, _ in ascent)
                    - first["foot_before"],
                    discrete_peak_m=discrete_peak,
                    continuous_peak_m=continuous_peak,
                    launch_separation_m=offset,
                    ascent_model_max_error_m=residual,
                    launch_input=True,
                )
            )
    assert len(rows) == 12
    differences = []
    for scheme in ("current", "legacy_16", "modern_cs"):
        for case in ("jump", "crouch_jump"):
            a, b = [x for x in rows if x["scheme"] == scheme and x["case"] == case]
            differences.append(
                dict(
                    scheme=scheme,
                    case=case,
                    measured_60_minus_120_m=a["measured_peak_m"] - b["measured_peak_m"],
                    predicted_60_minus_120_m=a["discrete_peak_m"]
                    - b["discrete_peak_m"],
                )
            )
    return dict(
        schema=1,
        kind="offline_existing_trace_analysis",
        source_sha256=sources,
        rows=rows,
        differences=differences,
        release_ready=False,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    result = analyze(args.evidence)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result["differences"], indent=2))


if __name__ == "__main__":
    main()
