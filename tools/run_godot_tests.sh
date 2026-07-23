#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${1:-${GODOT_EXE:-}}"

if [[ -z "${godot_bin}" ]]; then
  if [[ -x "${project_root}/.tools/godot/godot" ]]; then
    godot_bin="${project_root}/.tools/godot/godot"
  elif command -v godot >/dev/null 2>&1; then
    godot_bin="$(command -v godot)"
  else
    echo "Godot not found. Pass its path, set GODOT_EXE, or run the Copilot setup workflow." >&2
    exit 1
  fi
fi

scenes=(
  "res://scenes/tests/LevelDataLoaderTestRunner.tscn"
  "res://scenes/tests/WeaponSystemTestRunner.tscn"
  "res://scenes/tests/GrayboxLevelTestRunner.tscn"
  "res://scenes/tests/HitFeedbackLayerTestRunner.tscn"
  "res://scenes/tests/TacticalBotTestRunner.tscn"
  "res://scenes/tests/MainStateFlowTestRunner.tscn"
)

echo "Using Godot: ${godot_bin}"
echo "Project: ${project_root}"
echo
echo "==> Importing project resources"
"${godot_bin}" --headless --path "${project_root}" --import

for scene in "${scenes[@]}"; do
  echo
  echo "==> Running ${scene}"
  "${godot_bin}" --headless --path "${project_root}" --scene "${scene}"
done

echo
echo "All Godot test suites passed."
echo "RUN_ALL_OK"
