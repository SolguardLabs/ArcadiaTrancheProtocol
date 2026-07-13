#!/usr/bin/env bash
set -euo pipefail

forge fmt --check
forge build --sizes
FOUNDRY_PROFILE=ci forge test -vvv
