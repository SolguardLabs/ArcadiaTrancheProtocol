#!/usr/bin/env bash
set -euo pipefail

if [[ -f lib/forge-std/src/Test.sol && -f lib/forge-std/src/Script.sol ]]; then
  exit 0
fi

if [[ -d lib/forge-std ]]; then
  echo "lib/forge-std exists but forge-std sources are missing" >&2
  exit 1
fi

resolve_forge() {
  if command -v "${FORGE_BIN:-forge}" >/dev/null 2>&1; then
    command -v "${FORGE_BIN:-forge}"
    return
  fi
  if command -v forge.exe >/dev/null 2>&1 && forge.exe --version >/dev/null 2>&1; then
    command -v forge.exe
    return
  fi
  echo "forge executable not found" >&2
  exit 127
}

"$(resolve_forge)" install --no-git --shallow foundry-rs/forge-std
