#!/bin/bash
set -euo pipefail
node "$(dirname "${BASH_SOURCE[0]}")/persist.mjs"
