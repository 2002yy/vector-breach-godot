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
  "res://scenes/tests/TacticalBombTestRunner.tscn"
  "res://scenes/tests/MatchLifecycleTestRunner.tscn"
  "res://scenes/tests/CombatEventsTestRunner.tscn"
  "res://scenes/tests/GatehouseMatchIntegrationTestRunner.tscn"
  "res://scenes/tests/MainStateFlowTestRunner.tscn"
  "res://scenes/tests/AudioAssetTestRunner.tscn"
  "res://scenes/tests/C4DeviceTestRunner.tscn"
  "res://scenes/tests/PerformanceBudgetTestRunner.tscn"
  "res://scenes/tests/SourceProbeDiagnosticTests.tscn"
  "res://scenes/tests/SourceReflectionTests.tscn"
)

run_scene() {
  local scene="$1"
  local status=0
  local suite_log
  suite_log="$(mktemp)"

  echo
  echo "==> Running ${scene}"
  echo "[native-test] START ${scene}"

  "${godot_bin}" --headless --path "${project_root}" --scene "${scene}" >"${suite_log}" 2>&1 || status=$?
  cat "${suite_log}"
  if [[ "${status}" -eq 0 ]] && ! grep -Eq 'SCRIPT ERROR:|^ERROR:' "${suite_log}"; then
    rm -f "${suite_log}"
    echo "[native-test] PASS ${scene}"
    return 0
  else
    rm -f "${suite_log}"
    if [[ "${status}" -eq 0 ]]; then status=1; fi
    echo "[native-test] FAIL ${scene} (exit ${status})" >&2
    echo "::error title=Native test suite failed::${scene} exited with status ${status}"
    return "${status}"
  fi
}

echo "Using Godot: ${godot_bin}"
echo "Project: ${project_root}"
echo
echo "==> Importing project resources"
if "${godot_bin}" --headless --path "${project_root}" --import; then
  echo "[native-test] IMPORT PASS"
else
  status=$?
  echo "[native-test] IMPORT FAIL (exit ${status})" >&2
  echo "::error title=Native project import failed::Godot import exited with status ${status}"
  exit "${status}"
fi

for scene in "${scenes[@]}"; do
  run_scene "${scene}"
done

echo
echo "All Godot test suites passed."
echo "RUN_ALL_OK"
