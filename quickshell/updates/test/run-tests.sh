#!/bin/bash
# Exercise the update card's model (and, from Task 7, its QML view) without a compositor.
set -euo pipefail
test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
node "$test_dir/model.mjs"
