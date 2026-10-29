#!/usr/bin/env bash
# The viewer app no longer bundles admin code — admin builds only come from admin/.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT/admin"
exec ./build_ipa.sh "$@"
