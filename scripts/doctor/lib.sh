#!/bin/bash
#
# Reporting primitives for doctor.sh checks.
#
# CONTRACT FOR CHECK MODULES:
#   Never run a check loop in a pipeline or subshell. The severity counters
#   below are plain shell variables, so `cmd | while read` increments them in
#   a subshell and every finding is silently discarded. Always write:
#       while read -r x; do ... done < <(cmd)
#

# Root of the dotfiles tree under test. Overridable so the test suite can point
# the checks at a throwaway fixture repo instead of the live system.
DOCTOR_ROOT="${DOCTOR_ROOT:-$HOME/.config}"

DOCTOR_RED='\033[0;31m'
DOCTOR_GREEN='\033[0;32m'
DOCTOR_YELLOW='\033[1;33m'
DOCTOR_BLUE='\033[0;34m'
DOCTOR_DIM='\033[2m'
DOCTOR_NC='\033[0m'

DOCTOR_ERRORS=0
DOCTOR_WARNINGS=0
DOCTOR_NOTICES=0

doctor_reset() {
    DOCTOR_ERRORS=0
    DOCTOR_WARNINGS=0
    DOCTOR_NOTICES=0
}

group() {
    echo
    echo -e "${DOCTOR_BLUE}▸${DOCTOR_NC} $1"
}

ok() {
    echo -e "  ${DOCTOR_GREEN}✓${DOCTOR_NC} $1"
}

# _finding <colored-tag> <message> [fix-hint]
_finding() {
    echo -e "  $1  $2"
    if [ -n "${3:-}" ]; then
        echo -e "           ${DOCTOR_DIM}fix: $3${DOCTOR_NC}"
    fi
}

err() {
    DOCTOR_ERRORS=$((DOCTOR_ERRORS + 1))
    _finding "${DOCTOR_RED}✗ ERROR${DOCTOR_NC}" "$1" "${2:-}"
}

warn() {
    DOCTOR_WARNINGS=$((DOCTOR_WARNINGS + 1))
    _finding "${DOCTOR_YELLOW}! WARN ${DOCTOR_NC}" "$1" "${2:-}"
}

note() {
    DOCTOR_NOTICES=$((DOCTOR_NOTICES + 1))
    _finding "${DOCTOR_DIM}· INFO ${DOCTOR_NC}" "$1" "${2:-}"
}

# Prints the tally. Returns 1 if any ERROR was recorded, else 0.
summary() {
    local e="$DOCTOR_ERRORS" w="$DOCTOR_WARNINGS" n="$DOCTOR_NOTICES"
    echo
    echo "$e error$([ "$e" -eq 1 ] || echo s), $w warning$([ "$w" -eq 1 ] || echo s), $n notice$([ "$n" -eq 1 ] || echo s)"
    if [ "$e" -gt 0 ]; then
        return 1
    fi
    return 0
}
