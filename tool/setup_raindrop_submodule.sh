#!/usr/bin/env bash
# Raindrop is vendored under libs/raindrop. Its repository root is a separate Dart
# workspace; keeping that pubspec.yaml next to path dependencies into packages/*
# trips pub's "stray pubspec" check for the zonai workspace. Sparse-checkout only
# the packages/ tree so path deps like apps/db -> libs/raindrop/packages/raindrop work.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUBMODULE="${ROOT}/libs/raindrop"

if [[ ! -f "${ROOT}/.gitmodules" ]] || ! grep -q 'libs/raindrop' "${ROOT}/.gitmodules" 2>/dev/null; then
  echo "libs/raindrop submodule is not configured in .gitmodules." >&2
  exit 1
fi

git -C "${ROOT}" submodule update --init --recursive "${SUBMODULE}"

git -C "${SUBMODULE}" sparse-checkout init --no-cone
git -C "${SUBMODULE}" sparse-checkout set '/*' '!/pubspec.yaml' '!/.gitignore' '/packages/'
git -C "${SUBMODULE}" sparse-checkout reapply

# Fallback: sparse-checkout can leave root files on some platforms (notably Windows).
rm -f "${SUBMODULE}/pubspec.yaml" "${SUBMODULE}/.gitignore"

echo "Raindrop submodule: sparse checkout applied (packages/ only, root pubspec.yaml omitted)."
