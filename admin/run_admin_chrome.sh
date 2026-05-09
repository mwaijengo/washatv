#!/usr/bin/env bash
# Run admin web from this package folder with secrets from dev_defines.json (gitignored).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
exec flutter run -d chrome --dart-define-from-file=dev_defines.json
