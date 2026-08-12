#!/usr/bin/env bash
# Prefer admin/build_ipa.sh — that IPA is lightweight (no video/Firebase).
# This root script embeds the full viewer plugin set; use only if signing lives under ./ios.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo "NOTE: For device installs, prefer: cd admin && ./build_ipa.sh (or ./build_apk.sh)."
echo "This root build uses lib/main_admin.dart and includes heavy viewer plugins."

DEF="admin/dev_defines.json"
if [[ ! -f "$DEF" ]]; then
  echo "Missing $DEF — copy admin/dev_defines.json.example and add WASHA_ADMIN_API_KEY."
  exit 1
fi

echo "Building IPA (-t lib/main_admin.dart) with --dart-define-from-file=$DEF ..."
exec flutter build ipa -t lib/main_admin.dart --dart-define-from-file="$DEF" "$@"
