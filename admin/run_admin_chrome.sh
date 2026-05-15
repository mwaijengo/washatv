#!/usr/bin/env bash
# Run admin web — login once; JWT is saved on this device (Supasoka-style).
# Optional: set WASHA_ADMIN_API_KEY in dev_defines.json to skip login (CI/release builds only).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
if [[ -f dev_defines.json ]]; then
  exec flutter run -d chrome --dart-define-from-file=dev_defines.json
fi
exec flutter run -d chrome
