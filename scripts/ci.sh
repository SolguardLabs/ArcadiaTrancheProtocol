#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

bash scripts/bootstrap.sh
forge fmt --check
forge build --sizes
FOUNDRY_PROFILE=ci forge test -vvv
