#!/usr/bin/env bash
# Same as admin/build_ipa.sh but run from repo root using the root iOS target + lib/main_admin.dart
# (use this if your signing / bundle id lives under ./ios rather than ./admin/ios).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

DEF="admin/dev_defines.json"
if [[ ! -f "$DEF" ]]; then
  echo "Missing $DEF — copy admin/dev_defines.json.example and add WASHA_ADMIN_API_KEY."
  exit 1
fi

echo "Building IPA (-t lib/main_admin.dart) with --dart-define-from-file=$DEF ..."
exec flutter build ipa -t lib/main_admin.dart --dart-define-from-file="$DEF" "$@"
