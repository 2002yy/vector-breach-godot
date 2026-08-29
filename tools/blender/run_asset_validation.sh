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

tmp_files=()
cleanup() {
  if (( ${#tmp_files[@]} > 0 )); then
    rm -f -- "${tmp_files[@]}"
  fi
}
trap cleanup EXIT

failures=0
for source in "${SOURCES[@]}"; do
  metadata="${source}.asset.json"
  validation_input="$source"
  echo "==> Validating ${source}"

  preflight="$(python - "$source" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
data = path.read_bytes()
head = data[:80]
if head.startswith(b"version https://git-lfs.github.com/spec/v1"):
    status = "UNRESOLVED_LFS_POINTER"
elif head.startswith(b"BLENDER"):
    status = "BLENDER_HEADER_OK"
elif head.startswith(bytes.fromhex("28b52ffd")):
    status = "ZSTD_COMPRESSED_BLEND"
else:
    status = "INVALID_BINARY_HEADER"
print(f"{status}|{len(data)}|{head[:16].hex()}")
PY
)"
  IFS='|' read -r preflight_status preflight_size preflight_hex <<< "$preflight"
  echo "BLENDER_SOURCE_PREFLIGHT=${preflight_status} path=${source} size=${preflight_size} head16=${preflight_hex}"

  if [[ "$preflight_status" == "ZSTD_COMPRESSED_BLEND" ]]; then
    if ! command -v zstd >/dev/null 2>&1; then
      echo "- ${source}: zstd is required to validate this compressed Blender master"
      failures=$((failures + 1))
      continue
    fi
    validation_input="$(mktemp "${TMPDIR:-/tmp}/vb-blender-validation-XXXXXX.blend")"
    tmp_files+=("$validation_input")
    if ! zstd --quiet --decompress --stdout "$source" > "$validation_input"; then
      echo "- ${source}: zstd decompression failed"
      failures=$((failures + 1))
      continue
    fi
    expanded_preflight="$(python - "$validation_input" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
data = path.read_bytes()
print(f"{len(data)}|{data[:16].hex()}|{int(data.startswith(b'BLENDER'))}")
PY
)"
    IFS='|' read -r expanded_size expanded_hex expanded_ok <<< "$expanded_preflight"
    echo "BLENDER_SOURCE_DECOMPRESSED path=${source} size=${expanded_size} head16=${expanded_hex}"
    if [[ "$expanded_ok" != "1" ]]; then
      echo "- ${source}: decompressed payload is not a Blender file"
      failures=$((failures + 1))
      continue
    fi
  elif [[ "$preflight_status" != "BLENDER_HEADER_OK" ]]; then
    echo "- ${source}: source binary preflight failed (${preflight_status})"
    failures=$((failures + 1))
    continue
  fi

  if "$BLENDER_BIN" \
    --background "$validation_input" \
    --python-exit-code 1 \
    --python tools/blender/validate_asset_source.py \
    -- --metadata "$metadata" --source "$source"; then
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
