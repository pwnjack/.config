#!/bin/bash
#
# Suite for the native workspace module: build every C test out of tree and
# run it. Discovered by ./test.sh; owning directory waybar/workspaces.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(dirname "$TEST_DIR")"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

echo "waybar/workspaces"
if ! make -s -C "$SRC" BUILD="$BUILD" test; then
    echo "  FAIL native workspace module tests"
    exit 1
fi
