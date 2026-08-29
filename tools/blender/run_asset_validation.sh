#!/usr/bin/env bash
set -uo pipefail

BLENDER_BIN="${1:-${BLENDER_BIN:-blender}}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

if [[ "$BLENDER_BIN" == */* ]]; then
  if [[ ! -x "$BLENDER_BIN" ]]; then
    echo "BLENDER_ASSET_VALIDATION_ALL=FAIL"
    echo "- Blender executable is not executable: $BLENDER_BIN"
    exit 1
  fi
elif ! command -v "$BLENDER_BIN" >/dev/null 2>&1; then
  echo "BLENDER_ASSET_VALIDATION_ALL=FAIL"
  echo "- Blender executable was not found on PATH: $BLENDER_BIN"
  exit 1
fi

mapfile -t SOURCES < <(
  find assets-source/blender -type f \( -name '*.blend' -o -name '*.blend1' \) -print | sort
)

if (( ${#SOURCES[@]} == 0 )); then
  echo "BLENDER_ASSET_VALIDATION_ALL=FAIL"
  echo "- No canonical Blender source masters found under assets-source/blender/"
  exit 1
fi

failures=0
for source in "${SOURCES[@]}"; do
  metadata="${source}.asset.json"
  echo "==> Validating ${source}"
  if "$BLENDER_BIN" \
    --background "$source" \
    --python-exit-code 1 \
    --python tools/blender/validate_asset_source.py \
    -- --metadata "$metadata"; then
    :
  else
    failures=$((failures + 1))
  fi
done

if (( failures > 0 )); then
  echo "BLENDER_ASSET_VALIDATION_ALL=FAIL"
  echo "validated=${#SOURCES[@]}"
  echo "failed=${failures}"
  exit 1
fi

echo "BLENDER_ASSET_VALIDATION_ALL=PASS"
echo "validated=${#SOURCES[@]}"
echo "failed=0"
