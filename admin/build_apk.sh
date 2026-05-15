#!/usr/bin/env bash
# Build Admin APK — uses dev_defines.json for WASHA_API_BASE_URL / optional WASHA_ADMIN_API_KEY.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if [[ ! -f dev_defines.json ]]; then
  echo "Missing admin/dev_defines.json — copying example (edit API URL/key if needed)."
  cp dev_defines.json.example dev_defines.json
fi

echo "Building Admin APK with --dart-define-from-file=dev_defines.json ..."
exec flutter build apk --release --dart-define-from-file=dev_defines.json "$@"
