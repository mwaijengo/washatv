#!/usr/bin/env bash
# Run WASHA Admin on a connected Android device / emulator (lightweight APK).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if [[ ! -f dev_defines.json ]]; then
  echo "Creating admin/dev_defines.json from example (edit if needed)."
  cp dev_defines.json.example dev_defines.json
fi

echo "Devices:"
flutter devices || true
echo
echo "Running Admin (release-ish profile optional via PROFILE=1)…"
if [[ "${PROFILE:-}" == "1" ]]; then
  exec flutter run --profile --dart-define-from-file=dev_defines.json "$@"
fi
exec flutter run --dart-define-from-file=dev_defines.json "$@"
