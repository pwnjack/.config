#!/bin/bash
#
# Tests for scripts/waybar/updates.sh.
#
# Standalone, exit 1 on any failure, and runs the script under test as a
# subprocess because that is how waybar runs it -- the same style as
# test-battery.sh next door.
#
# The count comes from scripts/updates/updates-plan.sh, whose own suite
# (scripts/updates/test/test-plan.sh) owns the checkupdates/paru exit-status
# trap and the DB lock. Here UPDATES_PLAN_CMD swaps the planner for a stub
# with a chosen stdout, stderr and exit status, and the tooltip runs through
# the real scripts/updates/tooltip.mjs, so a model change that breaks the bar
# fails here too.
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
export UPDATES_PLAN_CMD="$TMP/plan"
export UPDATES_TOOLTIP="$TEST_DIR/../updates/tooltip.mjs"

# plan_stub <exit> <stdout> [stderr] -- the planner stand-in. It leaves a
# probe file, so a test can tell whether the module ran it.
plan_stub() {
    printf '%s' "$2" > "$TMP/plan.out"
    printf '%s' "${3-}" > "$TMP/plan.err"
    cat > "$TMP/plan" <<EOF
#!/bin/bash
touch "$TMP/ran"
cat "$TMP/plan.out"
cat "$TMP/plan.err" >&2
exit $1
EOF
    chmod +x "$TMP/plan"
}
probe_ran() { [ -e "$TMP/ran" ]; }

# The exit status goes to a FILE, not a variable: callers wrap run in `$(...)`,
# a subshell, so a variable would never reach the parent and every status
# check would pass vacuously. Without it, assert_silent could only see that
# nothing was printed, and a crashing module would masquerade as hidden.
run_status() { cat "$TMP/status"; }
run() {
    bash "$UPDATES" 2>"$TMP/stderr"
    echo $? > "$TMP/status"
}

# assert_silent <output> <label> -- hidden means BOTH nothing printed and exit 0.
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

# assert_total <output> <expected> <label> -- the trailing integer of `text`,
# matched EXACTLY; a substring test would accept 12 where 2 was expected.
assert_total() {
    local actual
    actual=$(printf '%s' "$1" | jq -r '.text | capture("(?<n>[0-9]+)$").n' 2>/dev/null)
    if [ "$actual" = "$2" ]; then
        pass "$3"
    else
        fail "$3" "expected total: $2" "actual total: $actual" "json: $1"
    fi
}

P0='{"repo":[],"aur":[],"bytes":0,"kernel":false,"flatpak":0}'
P3='{"repo":[{"name":"a"},{"name":"b"}],"aur":[{"name":"c"}],"bytes":1048576,"kernel":false,"flatpak":0}'
PFP='{"repo":[],"aur":[],"bytes":0,"kernel":false,"flatpak":2}'

echo "updates.sh"

# --- pending -----------------------------------------------------------------

plan_stub 0 "$P0"
assert_silent "$(run)" "an empty plan hides the module"

plan_stub 0 "$P3"
out=$(run)
assert_total "$out" 3 "the total is repo + AUR"
assert_json_contains "$out" .tooltip "<b>3 updates</b>" "the tooltip leads with the total"
assert_json_contains "$out" .tooltip "Repo  2   1 MiB" "with the repo row and its download size"
assert_json_contains "$out" .tooltip "AUR   1" "and the AUR row"
assert_json_lacks "$out" .tooltip "Flatpak" "a zero source has no row"
assert_json_contains "$out" .tooltip "Checked " "says when it checked"
assert_json_lacks "$out" .class attention "no attention without a reason"

plan_stub 0 "$PFP"
out=$(run)
assert_total "$out" 2 "Flatpak updates alone show the module"
assert_json_contains "$out" .tooltip "Flatpak  2" "with a Flatpak row"

# --- planner failures --------------------------------------------------------

plan_stub 1 "" "Could not sync package databases (offline?)"
assert_silent "$(run)" "a failed check hides the module"

out=$(UPDATES_PLAN_CMD="$TMP/no-such-planner" run)
assert_silent "$out" "a missing planner hides the module"

plan_stub 3 "" "pacman cannot resolve this upgrade; a & b"
out=$(run)
assert_json_field "$out" .class attention "an unresolvable upgrade shows as attention"
assert_json_field "$out" '.text | test("[0-9]")' false "with the glyph alone"
assert_json_contains "$out" .tooltip "Updates need a terminal" "the tooltip says what to do"
assert_json_contains "$out" .tooltip "a &amp; b" "with the planner's reason, escaped"

# --- the tooltip model failing must not hide the module ----------------------

plan_stub 0 "$P3"
out=$(UPDATES_TOOLTIP="$TMP/no-such.mjs" run)
assert_total "$out" 3 "a broken tooltip still shows the count"
assert_json_field "$out" .tooltip "3 updates" "with a one-line tooltip"

# --- Bar page mode ----------------------------------------------------------

mkdir -p "$TMP/opt"
printf 'hidden\n' > "$TMP/opt/bar-updates"
rm -f "$TMP/ran"
out=$(BAR_OPTIONS="$TMP/opt" run)
assert_eq "$out" "" "hidden prints nothing even with updates pending"
probe_ran; assert_eq "$?" 1 "hidden never runs the planner"

# --- the update card's run state (scripts/updates/updates-run.sh) -----------
# While a run is active the module must not run the planner: checkupdates
# would sync a DB while pacman holds the real one.
mkdir -p "$TMP/state"
export UPDATES_STATE_DIR="$TMP/state"
rm -f "$TMP/ran"

# A live runner holds run.lock; fd 9 here plays that part.
exec 9>"$TMP/state/run.lock"
flock -n 9

printf '{"status":"running","progress":0.5,"line":"Installing (1/2)","finishedAt":0}\n' > "$TMP/state/state.json"
out=$(run)
assert_json_contains "$out" .text "50%" "a running update shows its percentage"
assert_json_field "$out" .class running "with the running class"
assert_json_contains "$out" .tooltip "Updating · 50%" "the tooltip repeats it"
assert_json_contains "$out" .tooltip "Installing (1/2)" "with pacman's current step"
probe_ran; assert_eq "$?" 1 "and never runs the planner"

# A "running" file whose runner is gone (SIGKILL) must not stick on the bar.
exec 9>&-
out=$(run)
assert_json_lacks "$out" .class running "a running state with no live runner is stale"
assert_total "$out" 3 "and the module goes back to counting"
probe_ran; assert_eq "$?" 0 "which runs the planner again"
rm -f "$TMP/ran"

printf '{"status":"restart","progress":1,"restart":"7.2.9-1-cachyos","total":4,"done":4,"startedAt":1640,"finishedAt":1700}\n' > "$TMP/state/state.json"
rm -f "$TMP/state/ack"
out=$(run)
assert_json_field "$out" .class restart "an unseen restart flags the module"
assert_json_contains "$out" .tooltip "Restart to finish" "the tooltip uses the card's title"
assert_json_contains "$out" .tooltip "Kernel 7.2.9-1-cachyos loads on next boot" "and names the kernel"
probe_ran; assert_eq "$?" 1 "without running the planner"

echo 1700 > "$TMP/state/ack"
out=$(run)
assert_json_lacks "$out" .class restart "a seen restart is back to normal"
rm -f "$TMP/ran"

printf '{"status":"attention","progress":0.4,"startedAt":1700,"finishedAt":1800}\n' > "$TMP/state/state.json"
rm -f "$TMP/state/ack"
out=$(run)
assert_json_field "$out" .class attention "an unseen problem flags the count"
assert_total "$out" 3 "and still counts what is pending"
assert_json_contains "$out" .tooltip "Needs your attention" "the tooltip uses the card's title"
assert_json_contains "$out" .tooltip "3 updates waiting" "and lists what is waiting"
rm -f "$TMP/state/state.json" "$TMP/ran"

# A held lock with no state.json yet (the runner just cleared it) is running.
exec 9>"$TMP/state/run.lock"
flock -n 9
out=$(run)
assert_json_field "$out" .class running "a held lock with no state.json is still running"
assert_json_contains "$out" .text "0%" "at 0%"
assert_json_contains "$out" .tooltip "Starting…" "and the tooltip says it is starting"
probe_ran; assert_eq "$?" 1 "without running the planner"
exec 9>&-

# An unseen failure shows even when nothing is pending, or the check failed.
plan_stub 0 "$P0"
printf '{"status":"failed","progress":0.4,"startedAt":1800,"finishedAt":1900}\n' > "$TMP/state/state.json"
rm -f "$TMP/state/ack"
out=$(run)
assert_json_field "$out" .class attention "an unseen failure shows with nothing pending"
assert_json_contains "$out" .tooltip "The update did not finish" "and says so"
plan_stub 1 "" "offline"
out=$(run)
assert_json_field "$out" .class attention "and when the check itself failed"
echo 1900 > "$TMP/state/ack"
plan_stub 0 "$P0"
out=$(run)
assert_eq "$out" "" "a seen failure with nothing pending is hidden again"
rm -f "$TMP/state/state.json" "$TMP/state/ack"

test_summary
