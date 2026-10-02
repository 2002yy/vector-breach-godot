# Step 16 Windows Export Incremental Gate Acceptance

Date: 2026-08-31
Scope: PR #27 (`feature/step16-c4-device`)

## Purpose

Step 16 exposed two separate Windows release-gate problems:

1. The original `pull_request.paths` filter did not include normal runtime inputs such as `assets/**`, `data/**`, `scenes/**`, or `scripts/**`, so a real player-visible feature could bypass Windows export validation.
2. After those runtime paths were added, GitHub's pull-request path filter continued to match later docs-only synchronize events because the filter is evaluated against the pull request's accumulated diff. That would rerun the expensive Windows export even when the latest push changed only documentation.

The workflow now keeps the broad PR-level runtime path filter, then adds an incremental `detect-runtime-change` job. On `pull_request/synchronize`, it compares the event's previous PR head with the new PR head. Heavy export is allowed only when that incremental diff touches:

- `assets/**`
- `data/**`
- `scenes/**`
- `scripts/**`
- `export_presets.cfg`
- `project.godot`
- `.github/workflows/windows-export.yml`

If the previous head cannot be verified, the detector fails open to a full export rather than risking a false skip. Tag pushes and manual dispatches continue to export normally.

## Positive-path evidence already obtained

Workflow-change head `69d2a3395d2cb7799f923868a1d07adb5fe34e96` changed `.github/workflows/windows-export.yml` itself. `Windows Export #14` (`33326528381`) reported:

- `should_export=true`
- `reason=synchronize-runtime-or-export-change`

The full chain then succeeded: Godot 4.7.1 import, Windows EXE/PCK export, file verification, ZIP/SHA256 generation, artifact upload, Windows artifact download/verification/unpack, and a real exported `VectorBreach.exe --headless` smoke launch.

The same head also passed required `Tests #93` (`33326528374`) and legacy `Godot Tests #122` (`33326528372`).

## Negative-path acceptance represented by this commit

This file is intentionally a docs-only change. For the synchronize event created by this commit, acceptance requires:

- `detect-runtime-change` succeeds;
- detector output is `should_export=false` with `reason=synchronize-nonruntime-only`;
- `export-windows` is skipped;
- `smoke-windows` is skipped;
- required `Tests` and legacy `Godot Tests` remain green on the docs-only head.

Do not treat this document alone as proof of the negative path; the corresponding GitHub Actions run is the executable evidence.
