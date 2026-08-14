#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

bash scripts/bootstrap.sh
FORGE="${FORGE_BIN:-forge}"
"$FORGE" fmt --check
"$FORGE" build --sizes
FOUNDRY_PROFILE=ci "$FORGE" test -vvv
