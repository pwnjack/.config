#!/bin/bash
set -euo pipefail
test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
runtime=$(mktemp -d)
trap 'rmdir "$runtime"' EXIT
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software XDG_RUNTIME_DIR="$runtime" \
    /usr/lib/qt6/bin/qmltestrunner -input "$test_dir" "$@"
bash "$test_dir/../../../ags/test/test-persist.sh"
node "$test_dir/backend.mjs"
