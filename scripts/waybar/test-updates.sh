#!/bin/bash
#
# Tests for scripts/waybar/updates.sh.
#
# Standalone, exit 1 on any failure, and runs the script under test as a
# subprocess because that is how waybar runs it -- the same style as
# test-battery.sh next door.
#
# UPDATES_REPO_CMD and UPDATES_AUR_CMD are the seam. They let the suite run
# with no network and no pending updates, and more importantly they let it
# reproduce the exit codes that make this module hard: `checkupdates` exits 2
# when there is nothing to do and `paru -Qua` exits 1, so any implementation
# that gates on exit status silently reports zero forever.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATES="$TEST_DIR/updates.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"

# The user's own Bar page choice must not steer the baseline: an empty options
# directory means the default mode. The mode test below sets its own.
export BAR_OPTIONS="$TMP/no-options"
# A live update run's state must not steer the baseline either.
export UPDATES_STATE_DIR="$TMP/no-state"
# Nor may the real checkupdates DB lock.
export UPDATES_DB="$TMP/db"

# fake <name> <exit> <line>... — a stub command on PATH that prints the given
# lines and exits with the given status.
fake() {
    local name=$1 code=$2
    shift 2
    mkdir -p "$TMP/bin"
    {
        echo '#!/bin/bash'
        local line
        for line in "$@"; do
            printf 'echo %q\n' "$line"
        done
        echo "exit $code"
    } > "$TMP/bin/$name"
    chmod +x "$TMP/bin/$name"
}

# run <repo-cmd> <aur-cmd> — stdout of the module with BOTH commands pinned.
# Use this when the test is about counting, not about where the helper name
# came from.
#
# The exit status goes to a FILE, not a variable. Callers wrap these in
# `$(...)`, which is a subshell, so a variable assigned here would never reach
# the parent and every status check would pass vacuously -- the same shape of
# bug as the exit-status trap this suite exists to catch. `run_status` reads it
# back. Without this, assert_silent could only see that nothing was printed,
# and a module that printed nothing but crashed would masquerade as hidden.
run_status() { cat "$TMP/status"; }

run() {
    UPDATES_REPO_CMD="$1" UPDATES_AUR_CMD="$2" \
        PATH="$TMP/bin:$PATH" bash "$UPDATES" 2>"$TMP/stderr"
    echo $? > "$TMP/status"
}

# run_derived <repo-cmd> <aurhelper-file> — stdout of the module with
# UPDATES_AUR_CMD deliberately LEFT UNSET, so the script must derive the helper
# from the aurhelper file. Pinning the env var would short-circuit exactly the
# derivation these cases exist to test.
run_derived() {
    env -u UPDATES_AUR_CMD \
        UPDATES_REPO_CMD="$1" UPDATES_AURHELPER="$2" \
        PATH="$TMP/bin:$PATH" bash "$UPDATES" 2>"$TMP/stderr"
    echo $? > "$TMP/status"
}

# helper_file <content> — an options/aurhelper stand-in; empty arg means the
# file exists but is blank
helper_file() {
    local f
    f=$(mktemp "$TMP/aurhelper.XXXXXX")
    printf '%s' "$1" > "$f"
    echo "$f"
}

# assert_silent <output> <label> — the hide contract is BOTH halves: nothing
# printed and exit 0. Checking only the output would let a crashing module
# masquerade as a hidden one.
assert_silent() {
    local status
    status=$(run_status)
    if [ -n "$1" ]; then
        fail "$2" "expected no output" "got: $1"
    elif [ "$status" != "0" ]; then
        fail "$2" "expected exit 0" "got exit: $status"
    else
        pass "$2"
    fi
}

# assert_total <output> <expected> <label> — the combined count, matched
# EXACTLY. The count is the trailing integer of `text`; a substring test would
# accept 12 where 2 was expected, which is precisely the kind of miscount this
# suite exists to catch.
assert_total() {
    local actual
    actual=$(printf '%s' "$1" | jq -r '.text | capture("(?<n>[0-9]+)$").n' 2>/dev/null)
    if [ "$actual" = "$2" ]; then
        pass "$3"
    else
        fail "$3" "expected total: $2" "actual total: $actual" "json: $1"
    fi
}

echo "updates.sh"

H_PARU=$(helper_file "paru -Syu")
H_EMPTY=$(helper_file "")
H_GONE=$(helper_file "nosuchhelper -Syu")

# --- the exit-status trap, which is the whole point of this module ---------

fake checkupdates 2
fake paru 1
assert_silent "$(run checkupdates paru)" \
    "nothing pending is silent: checkupdates exit 2 and paru exit 1 mean 'none', not failure"

fake checkupdates 0 "foo 1-1 -> 1-2" "bar 2-1 -> 2-2"
fake paru 1
out=$(run checkupdates paru)
assert_total "$out" "2" "two repo updates are counted"
assert_json_contains "$out" '.tooltip' "2 repo" "tooltip names the repo count"

fake checkupdates 1 "foo 1-1 -> 1-2" "bar 2-1 -> 2-2" "baz 3-1 -> 3-2"
fake paru 1
assert_total "$(run checkupdates paru)" "3" \
    "a non-zero exit WITH output still has its lines counted"

# --- repo + AUR ------------------------------------------------------------

fake checkupdates 0 "foo 1-1 -> 1-2" "bar 2-1 -> 2-2"
fake paru 0 "aurpkg 1-1 -> 1-2"
out=$(run checkupdates paru)
assert_total "$out" "3" "text shows the combined total"
assert_json_contains "$out" '.tooltip' "2 repo" "tooltip shows the repo count"
assert_json_contains "$out" '.tooltip' "1 AUR" "tooltip shows the AUR count"

fake checkupdates 2
fake paru 0 "aurpkg 1-1 -> 1-2"
out=$(run checkupdates paru)
assert_total "$out" "1" "AUR-only updates still show the module"
assert_json_lacks "$out" '.tooltip' "0 repo" "a zero side is left out of the tooltip"

# --- deriving the helper from options/aurhelper ----------------------------
# UPDATES_AUR_CMD is unset in every case below, so the script has to read the
# file. That is the behaviour under test.

fake checkupdates 0 "foo 1-1 -> 1-2" "bar 2-1 -> 2-2"
fake paru 0 "aurpkg 1-1 -> 1-2"
out=$(run_derived checkupdates "$H_PARU")
assert_total "$out" "3" "the helper name is taken from the first word of aurhelper"
assert_json_contains "$out" '.tooltip' "1 AUR" "a derived helper's count reaches the tooltip"

fake checkupdates 0 "foo 1-1 -> 1-2" "bar 2-1 -> 2-2"
out=$(run_derived checkupdates "$H_EMPTY")
assert_total "$out" "2" "empty aurhelper still reports the repo count"
assert_json_lacks "$out" '.tooltip' "AUR" "empty aurhelper gives a repo-only tooltip"

fake checkupdates 0 "foo 1-1 -> 1-2" "bar 2-1 -> 2-2"
out=$(run_derived checkupdates "$H_GONE")
assert_total "$out" "2" "an uninstalled helper still reports the repo count"
assert_json_lacks "$out" '.tooltip' "AUR" "an uninstalled helper gives a repo-only tooltip"

fake checkupdates 0 "foo 1-1 -> 1-2"
out=$(run_derived checkupdates "$TMP/definitely-not-here")
assert_total "$out" "1" "a missing aurhelper file is not fatal"

# --- Bar page mode --------------------------------------------------------
mkdir -p "$TMP/opt"
printf 'hidden\n' > "$TMP/opt/bar-updates"
printf '#!/bin/bash\ntouch "%s/ran"\necho "linux 6.1 -> 6.2"\n' "$TMP" > "$TMP/bin/checkupdates-probe"
chmod +x "$TMP/bin/checkupdates-probe"
out=$(BAR_OPTIONS="$TMP/opt" UPDATES_REPO_CMD="$TMP/bin/checkupdates-probe" UPDATES_AUR_CMD='' bash "$UPDATES")
assert_eq "$out" "" "hidden prints nothing even with updates pending"
[ -e "$TMP/ran" ] && ran=1 || ran=0
assert_eq "$ran" 0 "hidden never runs checkupdates"

# --- the update card's run state (scripts/updates/updates-run.sh) ----------
# While a run is active the module must not run checkupdates: it would sync a
# DB while pacman holds the real one, and the count is about to change anyway.
mkdir -p "$TMP/state"
probe_ran() { [ -e "$TMP/ran" ]; }
rm -f "$TMP/ran"
run_state() {
    UPDATES_STATE_DIR="$TMP/state" UPDATES_REPO_CMD="$TMP/bin/checkupdates-probe" UPDATES_AUR_CMD='' \
        bash "$UPDATES"
}

# A live runner holds run.lock; fd 9 here plays that part (children inherit
# the open file description, and a second flock -n on the file still fails).
exec 9>"$TMP/state/run.lock"
flock -n 9

printf '{"status":"running","progress":0.5,"finishedAt":0}\n' > "$TMP/state/state.json"
out=$(run_state)
assert_json_contains "$out" .text "50%" "a running update shows its percentage"
assert_json_field "$out" .class running "with the running class"
probe_ran; assert_eq "$?" 1 "and never runs checkupdates"

# A "running" file whose runner is gone (SIGKILL) must not stick on the bar.
exec 9>&-
out=$(run_state)
assert_json_lacks "$out" .class running "a running state with no live runner is stale"
assert_total "$out" "1" "and the module goes back to counting"
probe_ran; assert_eq "$?" 0 "which runs checkupdates again"
rm -f "$TMP/ran"

printf '{"status":"restart","progress":1,"finishedAt":1700}\n' > "$TMP/state/state.json"
rm -f "$TMP/state/ack"
out=$(run_state)
assert_json_field "$out" .class restart "an unseen restart flags the module"
assert_json_contains "$out" .tooltip "Restart" "and says why"
probe_ran; assert_eq "$?" 1 "without running checkupdates"

echo 1700 > "$TMP/state/ack"
out=$(run_state)
assert_json_lacks "$out" .class restart "a seen restart is back to normal"
rm -f "$TMP/ran"

printf '{"status":"attention","progress":0.4,"finishedAt":1800}\n' > "$TMP/state/state.json"
rm -f "$TMP/state/ack"
out=$(run_state)
assert_json_field "$out" .class attention "an unseen problem flags the count"
assert_total "$out" "1" "and still counts what is pending"
rm -f "$TMP/state/state.json" "$TMP/ran"

# A held lock with no state.json yet (the runner just cleared it) is running.
exec 9>"$TMP/state/run.lock"
flock -n 9
rm -f "$TMP/state/state.json" "$TMP/ran"
out=$(run_state)
assert_json_field "$out" .class running "a held lock with no state.json is still running"
assert_json_contains "$out" .text "0%" "at 0%"
probe_ran; assert_eq "$?" 1 "without running checkupdates"
exec 9>&-

# An unseen failure shows even when nothing is pending.
fake checkupdates 2
printf '{"status":"failed","progress":0.4,"finishedAt":1900}\n' > "$TMP/state/state.json"
rm -f "$TMP/state/ack"
out=$(UPDATES_STATE_DIR="$TMP/state" UPDATES_REPO_CMD=checkupdates UPDATES_AUR_CMD='' PATH="$TMP/bin:$PATH" bash "$UPDATES")
assert_json_field "$out" .class attention "an unseen failure shows with nothing pending"
assert_json_contains "$out" .tooltip "attention" "and says so"
echo 1900 > "$TMP/state/ack"
out=$(UPDATES_STATE_DIR="$TMP/state" UPDATES_REPO_CMD=checkupdates UPDATES_AUR_CMD='' PATH="$TMP/bin:$PATH" bash "$UPDATES")
assert_eq "$out" "" "a seen failure with nothing pending is hidden again"
rm -f "$TMP/state/state.json" "$TMP/state/ack"

# checkupdates must run under the lock updates-plan.sh takes on the same DB.
printf '#!/bin/bash\nflock -n "%s.lock" true; echo $? > "%s/lockrc"\necho "linux 6.1 -> 6.2"\n' "$TMP/db" "$TMP" > "$TMP/bin/checkupdates-lock"
chmod +x "$TMP/bin/checkupdates-lock"
UPDATES_REPO_CMD="$TMP/bin/checkupdates-lock" UPDATES_AUR_CMD='' bash "$UPDATES" >/dev/null
assert_eq "$(cat "$TMP/lockrc" 2>/dev/null)" 1 "checkupdates runs while the shared DB lock is held"

# --- summary ---------------------------------------------------------------

test_summary
