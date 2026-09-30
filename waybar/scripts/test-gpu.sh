#!/bin/bash
#
# Tests for waybar/scripts/gpu.sh. A stub nvidia-smi on PATH prints one CSV
# row and logs that it ran; BAR_OPTIONS points at a fixture options dir.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GPU="$TEST_DIR/gpu.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck disable=SC1091 # Shared assertions are checked by their own suite.
# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../../scripts/lib/assert.sh"

mkdir -p "$TMP/bin" "$TMP/opt"
# reading <csv> — make the stub print that row
reading() {
    printf '#!/bin/sh\necho ran >> "%s/smi.log"\necho "%s"\n' "$TMP" "$1" > "$TMP/bin/nvidia-smi"
    chmod +x "$TMP/bin/nvidia-smi"
}
# run <mode|-> — gpu.sh 70 90 under that mode ("-" = no option file)
run() {
    rm -f "$TMP/opt/bar-gpu" "$TMP/smi.log"
    [ "$1" = - ] || printf '%s\n' "$1" > "$TMP/opt/bar-gpu"
    BAR_OPTIONS="$TMP/opt" PATH="$TMP/bin:$PATH" bash "$GPU" 70 90 2>&1
}

reading '40, 50, 1000, 12000, RTX'
assert_json_field "$(run -)" .class ok "no option file behaves like always"
assert_json_field "$(run always)" .class ok "always shows a quiet GPU"
assert_eq "$(run high)" "" "high hides a GPU below the warning threshold"
reading '75, 50, 1000, 12000, RTX'
assert_json_field "$(run high)" .class warning "high shows a GPU at the warning threshold"
assert_eq "$(run hidden)" "" "hidden prints nothing"
ran=0; [ -e "$TMP/smi.log" ] && ran=1
assert_eq "$ran" 0 "hidden never runs nvidia-smi"
reading '[N/A], 50, 1000, 12000, RTX'
assert_eq "$(run always)" "" "a non-numeric reading hides the module"
reading 'NVIDIA-SMI has failed because it could not communicate'
assert_eq "$(run always)" "" "driver error text hides the module without shell errors"

test_summary test-gpu
