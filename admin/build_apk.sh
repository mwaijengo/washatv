#!/usr/bin/env bash
# Build a lightweight Admin APK (no video/Firebase native libs).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if [[ ! -f dev_defines.json ]]; then
  echo "Missing admin/dev_defines.json — copying example (edit API URL/key if needed)."
  cp dev_defines.json.example dev_defines.json
fi

echo "Building lightweight Admin APK with --dart-define-from-file=dev_defines.json ..."
flutter build apk --release --dart-define-from-file=dev_defines.json "$@"
APK="$ROOT/build/app/outputs/flutter-apk/app-release.apk"
echo
echo "APK: $APK"
ls -lh "$APK"
echo
echo "Install: adb install -r \"$APK\""
