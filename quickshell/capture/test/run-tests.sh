#!/bin/bash
# Exercise the capture strip's model without a compositor.
set -euo pipefail
test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
node "$test_dir/model.mjs"
runner=/usr/lib/qt6/bin/qmltestrunner
[[ -x $runner ]] || { echo 'Qt 6 declarative test tools are required.' >&2; exit 1; }
runtime=$(mktemp -d)
trap 'rmdir "$runtime"' EXIT
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software XDG_RUNTIME_DIR="$runtime" \
    "$runner" -input "$test_dir" "$@"
