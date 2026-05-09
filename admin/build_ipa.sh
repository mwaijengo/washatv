#!/usr/bin/env bash
# Build signed Admin IPA with WASHA_ADMIN_API_KEY baked in (from dev_defines.json).
# Prereq: copy dev_defines.json.example → dev_defines.json and set your Railway ADMIN_API_KEY value.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if [[ ! -f dev_defines.json ]]; then
  echo "Missing admin/dev_defines.json"
  echo "  cp dev_defines.json.example dev_defines.json"
  echo "  # then set WASHA_ADMIN_API_KEY to the same value as Railway ADMIN_API_KEY"
  exit 1
fi

echo "Building Admin IPA with --dart-define-from-file=dev_defines.json ..."
exec flutter build ipa --dart-define-from-file=dev_defines.json "$@"
