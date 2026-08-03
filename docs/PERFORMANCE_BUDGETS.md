# Performance budgets

These budgets are regression guardrails for the current desktop Vulkan target. They are not claims about final minimum hardware. Formal assets are files under `assets` excluding the unshipped `assets/local_reference` cache.

## Static asset gates

| Metric | Trend warning | Hard failure |
| --- | ---: | ---: |
| One GLB (normal policy) | — | 16 MiB |
| All formal GLBs | 100 MiB | 112 MiB |
| One texture file | 4 MiB | 8 MiB |
| One PNG/JPEG dimension | 2048 px | 4096 px |
| All formal audio | 32 MiB | 64 MiB |

`assets/models/dustline/dustline_depths.glb` is a named known debt and currently exceeds the normal one-GLB gate. It emits a warning, not a failure. The exemption is path-specific: new or renamed GLBs over 16 MiB fail. The total GLB hard gate still applies.

Run from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\check_asset_budgets.ps1
```

The initial 2026-08-03 baseline is 9 GLBs / 93.03 MiB total. `dustline_depths.glb` is 49.52 MiB; the largest non-debt GLB is `foundry_reforged.glb` at 9.76 MiB. The first real-audio batch contains 14 files / 0.13 MiB.

## Vulkan Foundry probe

The probe renders Foundry Reforged from a fixed camera, warms for 60 frames and samples 180 rendered frames. It records average FPS/frame time, p95 frame time, visible objects, primitives, draw calls, texture/buffer memory, node/resource counts, renderer, adapter and engine version.

| Runtime metric | Trend warning | Hard failure |
| --- | ---: | ---: |
| Average FPS | below 45 | below 15 |
| Average frame time | above 22.23 ms | above 66.67 ms |
| P95 frame time | above 33.34 ms | above 100 ms |
| Visible objects | above 2,500 | above 5,000 |
| Primitives | above 2,500,000 | above 5,000,000 |
| Draw calls | above 2,500 | above 5,000 |
| Video memory | above 1 GiB | above 2 GiB |

Run it with the console build but without `--headless`, so Vulkan actually renders:

```powershell
& "D:\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe" --path . --scene res://scenes/tests/PerformanceBudgetProbe.tscn
```

Outputs are `user://performance-budget-foundry.json` and `user://performance-budget-foundry.png`. Runtime warnings are evidence for trend review; only hard thresholds return a failing exit code. Compare the JSON on the same machine/driver whenever practical.

The initial RTX 5060 Laptop / Godot 4.7.1 Forward+ capture measured 196.40 average FPS, 5.09 ms average / 7.15 ms p95 frame time, 977 visible objects and draw calls, 18,960 primitives, and 226.93 MiB reported video memory. It produced no trend warnings or hard failures. This is a local reference point, not a minimum-spec guarantee.

The headless contract suite is included in `tools/run_godot_tests.ps1`; it checks the static policy and known-debt boundary without pretending that headless rendering provides Vulkan metrics.
