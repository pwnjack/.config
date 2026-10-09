#!/bin/bash
# Exercise the capture strip's model without a compositor.
set -euo pipefail
test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
node "$test_dir/model.mjs"
