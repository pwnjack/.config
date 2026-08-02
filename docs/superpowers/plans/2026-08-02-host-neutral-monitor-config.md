# Host-Neutral Monitor Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove this desktop's monitor from the tracked config, so a fresh checkout is correct on any hardware, and make an empty main-monitor preference mean "no preference" everywhere it is read.

**Architecture:** No detection, at install time or at startup. `monitor.conf` becomes one host-neutral rule; `primary.conf` and `options/mainmonitor` ship empty; each of the four consumers gains an explicit empty branch resolving to "all monitors" or "any monitor". A sixth doctor check reads `/sys/class/drm` and warns when a tracked file names an output that is not connected, so the drift cannot return silently.

**Tech Stack:** Bash, Hyprland 0.56.1 / hyprlang, hyprlock 0.9.6, the `scripts/doctor/` module framework and its sourced-fragment test harness.

**Spec:** `docs/superpowers/specs/2026-08-02-host-neutral-monitor-config-design.md`

---

## File Structure

| File | Action | Responsibility after this plan |
|------|--------|-------------------------------|
| `hypr/config/hardware/monitor.conf` | Modify | One host-neutral `monitor=` rule; the wizard still appends host lines below it |
| `hypr/config/hardware/primary.conf` | Modify | Holds the hyprlock main-monitor preference; empty means every monitor |
| `options/mainmonitor` | Modify | Holds the script-side main-monitor preference; empty means no preference |
| `scripts/hyprland/wall.sh` | Modify | Skips the named awww lookup when the preference is empty |
| `scripts/hyprland/restore-wallpaper.sh` | Modify | Globs any monitor's awww cache entry when the preference is empty |
| `sddm/update_sddm_root.sh` | Modify | Same, running as root against another user's home |
| `sddm/watch_wallpaper.sh` | Modify | Accepts any monitor's cache file in both the inotify and poll branches |
| `scripts/doctor/checks/hardware.sh` | Create | `check_hardware` — tracked files must not name a disconnected output |
| `scripts/doctor/test/test-hardware.sh` | Create | Its tests, auto-discovered by `run-tests.sh` |
| `doctor.sh` | Modify | Sources and calls the sixth module |
| `README.md`, `QUICKSTART.md`, `CLAUDE.md`, `CHANGELOG.md` | Modify | Record the empty-means-no-preference contract and the new check |

**Task order is deliberate.** The consumers (Tasks 2 and 3) are made empty-safe *before* Task 4 empties the preference. Each of those commits is backward compatible — it handles both a named and an empty value — so no commit in this sequence leaves the machine in a broken state.

---

### Task 1: Host-neutral `monitor.conf`

**Goal:** Replace the hardcoded `DP-1` monitor rule with a generic one that gives every output its highest refresh rate.

**Files:**
- Modify: `hypr/config/hardware/monitor.conf` (whole file, 5 lines)

**Acceptance Criteria:**
- [ ] No connector name appears anywhere in the file
- [ ] `hyprctl reload` leaves DP-1 at 2560x1440@143.998, not @59.951
- [ ] `scripts/settings/advanced/monitor.sh` still reads and appends to the file unchanged

**Verify:** `hyprctl reload && sleep 1 && hyprctl monitors -j | jq -r '.[] | "\(.name) \(.width)x\(.height)@\(.refreshRate)"'` → `DP-1 2560x1440@143.998`

**Steps:**

- [ ] **Step 1: Record the current rate, so the comparison is real rather than remembered**

```bash
hyprctl monitors -j | jq -r '.[] | "\(.name) \(.width)x\(.height)@\(.refreshRate)"'
```
Expected: `DP-1 2560x1440@143.998`

- [ ] **Step 2: Replace the whole of `hypr/config/hardware/monitor.conf`**

```
## MONITORS
# Deliberately host-neutral: no connector is named here, so a fresh checkout is
# correct on any hardware.
#
# `highrr`, not `preferred`. `preferred` takes the EDID preferred timing, which
# on a high-refresh panel is routinely the 60 Hz mode. Measured on this machine
# 2026-08-02 by applying each keyword with `hyprctl keyword` and reading the
# rate back:
#     DP-1,preferred  ->  2560x1440@59.951
#     DP-1,highrr     ->  2560x1440@143.998
# Both `highrr` and `highres` are present in the Hyprland 0.56.1 binary.
#
# scripts/settings/advanced/monitor.sh appends machine-specific `monitor=` lines
# below this one. A rule naming an output beats this catch-all whatever the
# order, so appending stays correct.
monitor=,highrr,auto,1
```

- [ ] **Step 3: Confirm no connector name survives**

Run: `grep -nE '^monitor=[A-Za-z]' hypr/config/hardware/monitor.conf`
Expected: no output, exit status 1

- [ ] **Step 4: Apply and read the rate back**

Run: `hyprctl reload && sleep 1 && hyprctl monitors -j | jq -r '.[] | "\(.name) \(.width)x\(.height)@\(.refreshRate)"'`
Expected: `DP-1 2560x1440@143.998`

If it reports `@59.951`, `highrr` did not take: revert with `git checkout hypr/config/hardware/monitor.conf`, `hyprctl reload`, and stop — the spec's measurement no longer holds and the design needs revisiting.

- [ ] **Step 5: Commit**

```bash
git add hypr/config/hardware/monitor.conf
git commit -m "fix(hypr): stop hardcoding this desktop's monitor

Replaces monitor=DP-1,2560x1440@144 and the preferred catch-all with one
host-neutral highrr rule. preferred resolves to 59.951 Hz on this panel
because that is its EDID preferred timing, so the old catch-all was a 60 Hz
trap for any second monitor as well."
```

---

### Task 2: The Hyprland wallpaper scripts accept an empty preference

**Goal:** `wall.sh` and `restore-wallpaper.sh` treat an empty `options/mainmonitor` as "any monitor", and stop guessing `eDP-1`.

**Files:**
- Modify: `scripts/hyprland/wall.sh:10-16`
- Modify: `scripts/hyprland/restore-wallpaper.sh:25-31`

**Acceptance Criteria:**
- [ ] Neither script contains the string `eDP-1`
- [ ] With `options/mainmonitor` empty, `wall.sh` still resolves a wallpaper and propagates the palette
- [ ] With `options/mainmonitor` empty, `restore-wallpaper.sh` finds the newest awww cache entry for any monitor
- [ ] With a real name in `options/mainmonitor`, both behave exactly as before
- [ ] `shellcheck -S warning` clean on both

**Verify:** `shellcheck -S warning scripts/hyprland/wall.sh scripts/hyprland/restore-wallpaper.sh && grep -c 'eDP-1' scripts/hyprland/wall.sh scripts/hyprland/restore-wallpaper.sh` → shellcheck silent, both counts `0`

**Steps:**

- [ ] **Step 1: In `scripts/hyprland/wall.sh`, replace lines 10-16**

Current:
```bash
primary_monitor=$(cat "$HOME/.config/options/mainmonitor" 2>/dev/null)
wallpaper=$(awww query | grep "^: $primary_monitor:" | sed 's/.*image: //')

# Fallback: first monitor reported by awww
if [ -z "$wallpaper" ]; then
    wallpaper=$(awww query | head -n1 | sed 's/.*image: //')
fi
```

New:
```bash
# options/mainmonitor is a preference, not a hardware fact. Empty means "no
# preference", which resolves here to whatever awww reports first. The named
# lookup is skipped outright rather than left to grep "^: :", so the empty case
# is explicit instead of resting on a pattern that happens not to match.
primary_monitor=$(cat "$HOME/.config/options/mainmonitor" 2>/dev/null)
wallpaper=""
if [ -n "$primary_monitor" ]; then
    wallpaper=$(awww query | grep "^: $primary_monitor:" | sed 's/.*image: //')
fi

# Fallback: first monitor reported by awww
if [ -z "$wallpaper" ]; then
    wallpaper=$(awww query | head -n1 | sed 's/.*image: //')
fi
```

- [ ] **Step 2: In `scripts/hyprland/restore-wallpaper.sh`, replace lines 25-31**

Current:
```bash
# 2. Last wallpaper recorded in the awww cache for the main monitor
monitor=$(cat "$HOME/.config/options/mainmonitor" 2>/dev/null || echo "eDP-1")
cache=$(ls -t "$HOME/.cache/awww/"*/"$monitor" 2>/dev/null | head -n1)
if [ -f "$cache" ]; then
    wp=$(grep -oE '/.+$' "$cache")
    [ -f "$wp" ] && awww img "$wp" && exit 0
fi
```

New:
```bash
# 2. Last wallpaper recorded in the awww cache for the main monitor.
#    Empty preference means "no preference", so the newest entry for ANY
#    monitor is taken. Nothing is guessed: this used to fall back to eDP-1,
#    which is wrong on every machine that does not happen to have one.
monitor=$(cat "$HOME/.config/options/mainmonitor" 2>/dev/null)
if [ -n "$monitor" ]; then
    cache=$(ls -t "$HOME/.cache/awww/"*/"$monitor" 2>/dev/null | head -n1)
else
    cache=$(ls -t "$HOME/.cache/awww/"*/* 2>/dev/null | head -n1)
fi
if [ -f "$cache" ]; then
    wp=$(grep -oE '/.+$' "$cache")
    [ -f "$wp" ] && awww img "$wp" && exit 0
fi
```

- [ ] **Step 3: Lint both**

Run: `shellcheck -S warning scripts/hyprland/wall.sh scripts/hyprland/restore-wallpaper.sh`
Expected: no output

- [ ] **Step 4: Exercise the empty branch without touching the tracked file yet**

`options/mainmonitor` still says `DP-1` at this point, so the empty path is exercised by pointing the scripts at an empty value via a scratch HOME-free check of the glob itself:

```bash
ls -t "$HOME/.cache/awww/"*/* 2>/dev/null | head -n1
```
Expected: a path under `~/.cache/awww/<version>/<monitor>` — proving the empty-branch glob resolves to a real cache entry on this machine. If it prints nothing, awww has no cache yet; change the wallpaper once (`Super+Ctrl+W`) and re-run.

- [ ] **Step 5: Confirm the named path is untouched**

Run: `bash scripts/hyprland/wall.sh && hyprctl monitors -j >/dev/null && echo ok`
Expected: the bar restarts, the palette regenerates, `ok` prints. `options/mainmonitor` still holds `DP-1`, so this exercises the unchanged named branch.

- [ ] **Step 6: Commit**

```bash
git add scripts/hyprland/wall.sh scripts/hyprland/restore-wallpaper.sh
git commit -m "fix(wallpaper): treat an empty main-monitor preference as any monitor

Both scripts now branch explicitly on an empty options/mainmonitor instead of
running a lookup that cannot match, and restore-wallpaper.sh stops guessing
eDP-1 — a connector this machine does not have."
```

---

### Task 3: The SDDM scripts accept an empty preference

**Goal:** `update_sddm_root.sh` and `watch_wallpaper.sh` treat an empty `options/mainmonitor` as "any monitor". `watch_wallpaper.sh` is the one that stops working entirely rather than degrading, so it gets both of its use sites fixed.

**Files:**
- Modify: `sddm/update_sddm_root.sh:19-24`
- Modify: `sddm/watch_wallpaper.sh:8`, `sddm/watch_wallpaper.sh:29-31`, `sddm/watch_wallpaper.sh:37`

**Acceptance Criteria:**
- [ ] Neither script contains the string `eDP-1`
- [ ] `watch_wallpaper.sh`'s inotify guard accepts any filename when the preference is empty
- [ ] `watch_wallpaper.sh`'s poll branch globs any monitor when the preference is empty
- [ ] `update_sddm_root.sh` carries a comment saying why its cache lookup is duplicated rather than shared
- [ ] `shellcheck -S warning` clean on both

**Verify:** `shellcheck -S warning sddm/update_sddm_root.sh sddm/watch_wallpaper.sh && grep -c 'eDP-1' sddm/update_sddm_root.sh sddm/watch_wallpaper.sh` → shellcheck silent, both counts `0`

**Steps:**

- [ ] **Step 1: In `sddm/update_sddm_root.sh`, replace lines 19-24**

Current:
```bash
monitor=$(cat "$USER_HOME/.config/options/mainmonitor" 2>/dev/null || echo "eDP-1")

# awww cache layout: ~/.cache/awww/<version>/<monitor>, line format: "<crop> <filter> <path>"
cache_file=$(ls -t "$USER_HOME/.cache/awww/"*/"$monitor" 2>/dev/null | head -n1)
wallpaper=$(grep -oE '/.+$' "$cache_file" 2>/dev/null)
```

New:
```bash
# Empty preference means "no preference": the newest cache entry for ANY
# monitor is taken. No connector name is guessed.
monitor=$(cat "$USER_HOME/.config/options/mainmonitor" 2>/dev/null)

# awww cache layout: ~/.cache/awww/<version>/<monitor>, line format: "<crop> <filter> <path>"
#
# This lookup is duplicated in scripts/hyprland/restore-wallpaper.sh and in
# sddm/watch_wallpaper.sh, deliberately. THIS script runs as root against
# another user's home, so sourcing a shared helper out of a user-writable
# $USER_HOME/.config/scripts/ would hand that user a root shell.
if [ -n "$monitor" ]; then
    cache_file=$(ls -t "$USER_HOME/.cache/awww/"*/"$monitor" 2>/dev/null | head -n1)
else
    cache_file=$(ls -t "$USER_HOME/.cache/awww/"*/* 2>/dev/null | head -n1)
fi
wallpaper=$(grep -oE '/.+$' "$cache_file" 2>/dev/null)
```

- [ ] **Step 2: In `sddm/watch_wallpaper.sh`, replace line 8**

Current:
```bash
monitor=$(cat "$HOME/.config/options/mainmonitor" 2>/dev/null || echo "eDP-1")
```

New:
```bash
# Empty preference means "no preference". Unlike the other consumers this
# script FAILS rather than degrades on an empty value: the inotify guard below
# compares a filename against it, so an empty string matches nothing and SDDM
# sync stops with no error printed anywhere. Both use sites branch explicitly.
monitor=$(cat "$HOME/.config/options/mainmonitor" 2>/dev/null)
```

- [ ] **Step 3: In `sddm/watch_wallpaper.sh`, fix the inotify guard (line 29-31 region)**

Current:
```bash
    inotifywait -m -r -e modify,close_write --format '%f' "$cache_dir" 2>/dev/null | while read -r file; do
        [[ "$file" == "$monitor" ]] || continue
```

New:
```bash
    inotifywait -m -r -e modify,close_write --format '%f' "$cache_dir" 2>/dev/null | while read -r file; do
        # With no preference set, any monitor's cache entry is a real change.
        [[ -z "$monitor" || "$file" == "$monitor" ]] || continue
```

Note: this `cmd | while read` is *not* the pattern lib.sh forbids. That rule is about the doctor's severity counters being lost in a subshell; this loop keeps no counter and must stream inotify output, so a pipeline is correct here.

- [ ] **Step 4: In `sddm/watch_wallpaper.sh`, fix the poll branch (line 37 region)**

Current:
```bash
        cache_file=$(ls -t "$cache_dir"/*/"$monitor" 2>/dev/null | head -n1)
```

New:
```bash
        if [ -n "$monitor" ]; then
            cache_file=$(ls -t "$cache_dir"/*/"$monitor" 2>/dev/null | head -n1)
        else
            cache_file=$(ls -t "$cache_dir"/*/* 2>/dev/null | head -n1)
        fi
```

- [ ] **Step 5: Lint both**

Run: `shellcheck -S warning sddm/update_sddm_root.sh sddm/watch_wallpaper.sh`
Expected: no output

- [ ] **Step 6: Prove the empty guard actually matches, before relying on it**

```bash
monitor=""; file="DP-1"
[[ -z "$monitor" || "$file" == "$monitor" ]] && echo "empty: accepts"
monitor="DP-1"; file="DP-1"
[[ -z "$monitor" || "$file" == "$monitor" ]] && echo "named: accepts own"
monitor="DP-1"; file="HDMI-A-1"
[[ -z "$monitor" || "$file" == "$monitor" ]] || echo "named: rejects other"
```
Expected, all three lines:
```
empty: accepts
named: accepts own
named: rejects other
```

- [ ] **Step 7: Commit**

```bash
git add sddm/update_sddm_root.sh sddm/watch_wallpaper.sh
git commit -m "fix(sddm): keep wallpaper sync alive with no main-monitor preference

watch_wallpaper.sh compared each inotify filename against options/mainmonitor,
so an empty preference matched nothing and SDDM sync stopped silently. Both its
use sites and update_sddm_root.sh now branch on empty, and neither guesses
eDP-1 any more."
```

---

### Task 4: Empty the main-monitor preference

**Goal:** `primary.conf` and `options/mainmonitor` ship empty, and hyprlock is confirmed to render with an empty `$monitor`.

**Files:**
- Modify: `hypr/config/hardware/primary.conf` (whole file)
- Modify: `options/mainmonitor` (whole file)
- Modify (only on the fallback path): `hypr/hyprlock.conf:39,70,85,99,114,128`

**Acceptance Criteria:**
- [ ] Neither file names a connector
- [ ] hyprlock launches and its input field, clock and labels render
- [ ] `settings.sh` still writes a real name into both files and hyprlock honours it
- [ ] `ags bundle` still succeeds (the panel reads both files unchanged)

**Verify:** `hyprlock --grace 30` → lock screen renders with input field and clock; press any key to dismiss without a password

**Steps:**

- [ ] **Step 1: Replace `hypr/config/hardware/primary.conf`**

```
# Main-monitor preference for hyprlock.
#
# EMPTY MEANS EVERY MONITOR — hyprlock's own default, and what the background{}
# block in hyprlock.conf already relies on with its bare `monitor =`.
#
# Written by scripts/settings/settings.sh (Set Primary Monitor) and by the
# Super+I panel (ags/lib/monitors.ts). Do not hand-edit a connector name in on a
# single-monitor machine: empty is correct there and stays correct on the next.
$monitor =
```

- [ ] **Step 2: Empty `options/mainmonitor`**

```bash
: > options/mainmonitor
```

- [ ] **Step 3: Confirm neither file names a connector**

Run: `grep -nE '(eDP|DP|HDMI-A|DVI-D|LVDS)-[0-9]' hypr/config/hardware/primary.conf options/mainmonitor`
Expected: no output, exit status 1

- [ ] **Step 4: Verify the hyprlang expansion — the one open risk in the spec**

`hyprlock -c <file>` cannot be dry-run: it aborts at the Wayland connect (`hyprlock.cpp:63`) *before* parsing, so this needs a real launch. `--grace 30` makes that safe — the lock renders, and any keypress within 30 s dismisses it with no password.

Run: `hyprlock --grace 30`

Expected: the lock screen appears with the input field, the clock and the labels drawn — the same layout as before this change.

Press any key to dismiss.

Escape hatch if the screen is black and a keypress does nothing: `Ctrl+Alt+F2`, log in on the TTY, `pkill hyprlock`, `Ctrl+Alt+F1`.

- [ ] **Step 5 (ONLY if Step 4 rendered nothing): take the documented fallback**

`$monitor =` did not expand. Revert `primary.conf` to a file that only matters when a name is set, and put a bare `monitor =` on the six widgets that used the variable — the form `background {}` already proves works:

```bash
git checkout hypr/config/hardware/primary.conf
sed -i 's/^\(\s*\)monitor = \$monitor$/\1monitor =/' hypr/hyprlock.conf
grep -n 'monitor' hypr/hyprlock.conf
```
Expected: lines 39, 70, 85, 99, 114, 128 now read `monitor =`; no `$monitor` remains.

Re-run `hyprlock --grace 30` and confirm the widgets render. Then record the outcome in the spec's "Open risk" section before committing.

- [ ] **Step 6: Confirm the preference still round-trips**

```bash
echo "DP-1" > options/mainmonitor
printf '$monitor = DP-1\n' > hypr/config/hardware/primary.conf
hyprlock --grace 30
```
Expected: the lock renders on DP-1 as before. Dismiss with a keypress, then restore the empty state:
```bash
: > options/mainmonitor
git checkout hypr/config/hardware/primary.conf 2>/dev/null || true
```
If Step 1's version was not yet committed, re-apply it from Step 1 rather than relying on `git checkout`.

- [ ] **Step 7: Confirm the panel still builds**

Run: `(cd ags && ags bundle app.ts "$(mktemp)")`
Expected: no error. `ags/lib/monitors.ts` reads both files and already returns `""` on an empty read, so no panel change is needed. This is the same gate `scripts/hooks/pre-commit` applies to any change under `ags/`; esbuild writes a real file, so the output path must be a temp file rather than `/dev/null`.

- [ ] **Step 8: Commit**

```bash
git add hypr/config/hardware/primary.conf options/mainmonitor
git commit -m "fix(hypr): ship no main-monitor preference

primary.conf and options/mainmonitor named DP-1, so a fresh checkout drew
hyprlock's widgets on a monitor that does not exist. Both now ship empty,
meaning 'no preference'; settings.sh and the Super+I panel still write a real
name the moment one is picked."
```

---

### Task 5: Doctor check — no tracked file names a disconnected output

**Goal:** A sixth doctor module that reads `/sys/class/drm` for the connected set and warns when a tracked, non-documentation file names an output that is not connected here.

**Files:**
- Create: `scripts/doctor/checks/hardware.sh`
- Create: `scripts/doctor/test/test-hardware.sh`
- Modify: `doctor.sh:51` (module list), `doctor.sh:71` (call list)

**Acceptance Criteria:**
- [ ] `check_hardware` warns for a tracked file naming a disconnected connector
- [ ] It does not warn for a connected one
- [ ] `*.md`, `docs/*` and `scripts/doctor/*` are skipped, each for a stated reason
- [ ] `eDP-1` is not mis-read as `DP-1`, and `HDMI-A-1` is matched whole
- [ ] An empty connected set produces one INFO and no warnings
- [ ] `ok` prints only when the check finds nothing at all
- [ ] The probe is overridable via `DOCTOR_DRM_SYSFS`, so the tests need no hardware
- [ ] No loop runs in a pipeline; `git ls-files -z` is read with `while IFS= read -r -d ''`
- [ ] `./doctor.sh` reports 0 errors, 0 warnings, 1 notice

**Verify:** `bash scripts/doctor/test/run-tests.sh && ./doctor.sh`

**Steps:**

- [ ] **Step 1: Write the failing tests — `scripts/doctor/test/test-hardware.sh`**

```bash
# Tests for scripts/doctor/checks/hardware.sh — sourced by run-tests.sh
#
# Sourced fragment, never executed directly, so it carries no shebang; the
# directive below tells shellcheck which shell to assume (SC2148).
# shellcheck shell=bash
#
# The host probe is exercised for real against a fake DRM tree via
# DOCTOR_DRM_SYSFS, rather than being shadowed by a stub function. That seam
# already exists in this repo — scripts/waybar/battery.sh takes BATTERY_SYSFS
# for the same reason — and testing the real probe also covers the card-prefix
# strip, which a stub would skip entirely.
#
# Checks run ONCE, redirected to a file under $DOCTOR_TEST_TMP, and the output
# is read back. `out="$(check_hardware)"` would run the check in a subshell and
# discard its severity counters.

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/hardware.sh"

# Assigned throughout this file but read only by the check sourced above.
export DOCTOR_ROOT DOCTOR_DRM_SYSFS

hw_out_file="$DOCTOR_TEST_TMP/hardware.out"

# hw_sysfs <dir> <name:status>... — build a fake /sys/class/drm.
hw_sysfs() {
    local dir="$1"; shift
    local entry
    mkdir -p "$dir"
    for entry in "$@"; do
        mkdir -p "$dir/${entry%%:*}"
        printf '%s\n' "${entry##*:}" > "$dir/${entry%%:*}/status"
    done
}

# hw_track <root> <path> <content> — write a file and stage it, so git ls-files
# sees it. An unstaged file is invisible to the check by design.
hw_track() {
    mkdir -p "$(dirname "$1/$2")"
    printf '%s\n' "$3" > "$1/$2"
    git -C "$1" add -- "$2"
}

# --- the probe itself ------------------------------------------------------
hw_drm="$DOCTOR_TEST_TMP/drm-a"
hw_sysfs "$hw_drm" "card1-DP-1:connected" "card1-HDMI-A-1:disconnected" \
                   "card0-eDP-1:connected"
DOCTOR_DRM_SYSFS="$hw_drm"
hw_probe="$(_hw_connected_outputs | sort | tr '\n' ' ')"
assert_eq "$hw_probe" "DP-1 eDP-1 " "probe strips the card prefix and keeps only connected"

# --- a fixture exercising every finding ------------------------------------
hw_fixture="$(make_fixture)"
DOCTOR_ROOT="$hw_fixture"
hw_track "$hw_fixture" "options/mainmonitor" "HDMI-A-1"
hw_track "$hw_fixture" "hypr/good.conf" "monitor=DP-1,highrr,auto,1"
hw_track "$hw_fixture" "hypr/stale.conf" '$monitor = eDP-9'
hw_track "$hw_fixture" "README.md" "mainmonitor  # DP-9"
hw_track "$hw_fixture" "docs/note.txt" "example uses DP-9"
hw_track "$hw_fixture" "scripts/doctor/checks/hardware.sh" "eDP|DP|HDMI-A pattern DP-9"

hw_drm2="$DOCTOR_TEST_TMP/drm-b"
hw_sysfs "$hw_drm2" "card1-DP-1:connected"
DOCTOR_DRM_SYSFS="$hw_drm2"

doctor_reset
check_hardware > "$hw_out_file" 2>&1
hw_out="$(cat "$hw_out_file")"

assert_contains "$hw_out" "options/mainmonitor names HDMI-A-1" "disconnected connector is reported"
assert_contains "$hw_out" "hypr/stale.conf names eDP-9" "eDP-9 is matched whole, not as DP-9"
assert_not_contains "$hw_out" "hypr/good.conf" "a connected connector is not reported"
assert_not_contains "$hw_out" "README.md" "markdown is skipped — docs carry example names"
assert_not_contains "$hw_out" "docs/note.txt" "docs/ is skipped"
assert_not_contains "$hw_out" "scripts/doctor/checks/hardware.sh" "the doctor's own tree is skipped"
assert_eq "$DOCTOR_WARNINGS" "2" "exactly two warnings"
assert_eq "$DOCTOR_ERRORS" "0" "a stale connector is never an error"

# --- a clean tree gets the all-clear, and nothing else ----------------------
hw_clean="$(make_fixture)"
DOCTOR_ROOT="$hw_clean"
hw_track "$hw_clean" "options/mainmonitor" ""
hw_track "$hw_clean" "hypr/monitor.conf" "monitor=,highrr,auto,1"

doctor_reset
check_hardware > "$hw_out_file" 2>&1
hw_out="$(cat "$hw_out_file")"

assert_contains "$hw_out" "no tracked config names a disconnected output" "clean tree prints ok"
assert_eq "$DOCTOR_WARNINGS" "0" "clean tree warns about nothing"

# --- no DRM nodes at all: one INFO, never a wall of warnings ----------------
hw_empty="$DOCTOR_TEST_TMP/drm-empty"
mkdir -p "$hw_empty"
DOCTOR_DRM_SYSFS="$hw_empty"
DOCTOR_ROOT="$hw_fixture"

doctor_reset
check_hardware > "$hw_out_file" 2>&1
hw_out="$(cat "$hw_out_file")"

assert_contains "$hw_out" "no connected display output" "headless run explains itself"
assert_eq "$DOCTOR_WARNINGS" "0" "headless run warns about nothing"
```

- [ ] **Step 2: Run the suite and watch it fail for the right reason**

Run: `bash scripts/doctor/test/run-tests.sh 2>&1 | tail -20`
Expected: failure sourcing `checks/hardware.sh` — the file does not exist yet.

- [ ] **Step 3: Write `scripts/doctor/checks/hardware.sh`**

```bash
#!/bin/bash
#
# Host hardware truth: no tracked config names a display output that this
# machine does not have.
#
# Nothing is enumerated here. The valid set comes from the kernel, the
# occurrences come from `git ls-files -z`. A config file added tomorrow is
# covered the moment it is committed.
#
# WHY /sys/class/drm RATHER THAN hyprctl. The doctor must be runnable from a
# TTY with no compositor — that is exactly when a broken monitor config is
# worth diagnosing — and sysfs answers there. hyprctl does not.
#
# SEVERITY IS WARN, NEVER ERROR. Naming a connector that happens to be unplugged
# right now is legitimate: a docked laptop, a monitor switched off at the wall.
# The finding says the config is stale, not that the session is broken.
#
# WHAT IS DELIBERATELY NOT SCANNED:
#
#   *.md — README.md and QUICKSTART.md carry DP-1 and HDMI-A-1 as deliberate
#   examples of what a value looks like. This is the same reasoning that
#   already excludes docs/ from references.sh's literal-path scan.
#
#   docs/ — the specs and plans quote real connector names when recording what
#   was measured on a given machine.
#
#   scripts/doctor/ — this file's own pattern below, and its fixtures, are
#   made of connector names.
#
# Accepted limitation: a connector name inside a comment reads the same as one
# in a live setting. Distinguishing them means knowing the comment syntax of
# every tracked file type, which is a worse trade than one occasional finding
# on a line that was already documenting the stale value.

# The DRM connector namespace, as the kernel spells it. This is upstream
# vocabulary — the same kind of constant as DOCTOR_WAYBAR_ACTIONS in waybar.sh,
# and stale only on a kernel release, never on a change to this repo. eDP is
# listed before DP so a leading `e` is consumed rather than left dangling.
DOCTOR_DRM_CONNECTOR_RE='(eDP|DP|HDMI-A|HDMI-B|DVI-D|DVI-I|DVI-A|LVDS|DSI|VGA|Virtual)-[0-9]+'

# Overridable so the test suite can point the probe at a fake DRM tree instead
# of the running machine. Same seam, for the same reason, as BATTERY_SYSFS in
# scripts/waybar/battery.sh.
DOCTOR_DRM_SYSFS="${DOCTOR_DRM_SYSFS:-/sys/class/drm}"

# _hw_connected_outputs — host probe, in its own function so tests can aim it.
#
# Node names are card<N>-<CONNECTOR>; the card prefix is stripped so what comes
# back is the name Hyprland, hyprlock and awww all use (DP-1, HDMI-A-1, eDP-1).
# The strip is a shortest-match prefix removal, so HDMI-A-1 survives whole.
_hw_connected_outputs() {
    local node base status
    for node in "$DOCTOR_DRM_SYSFS"/card*-*; do
        [ -r "$node/status" ] || continue
        read -r status < "$node/status" || continue
        [ "$status" = "connected" ] || continue
        base="${node##*/}"
        printf '%s\n' "${base#card*-}"
    done
}

check_hardware() {
    group "Hardware"

    local before_warnings="$DOCTOR_WARNINGS"
    local connected file token

    connected="$(_hw_connected_outputs)"

    if [ -z "$connected" ]; then
        note "no connected display output found under $DOCTOR_DRM_SYSFS — skipping the connector scan" \
             "run doctor.sh on the machine itself; a container has no DRM nodes to read"
        return 0
    fi

    # Process substitution, not a pipeline — see the contract note in lib.sh.
    # -z and -d '' because git C-quotes any path holding a non-ASCII or quote
    # character, and the quoted form names no file on disk.
    while IFS= read -r -d '' file; do
        case "$file" in
            *.md|docs/*|scripts/doctor/*) continue ;;
        esac
        [ -f "$DOCTOR_ROOT/$file" ] || continue

        while IFS= read -r token; do
            [ -n "$token" ] || continue
            printf '%s\n' "$connected" | grep -qxF -- "$token" && continue
            warn "$file names $token, which is not a connected output on this machine" \
                 "update $(doctor_q "$DOCTOR_ROOT/$file"), or leave the value empty to mean no preference"
        done < <(grep -ohIE "$DOCTOR_DRM_CONNECTOR_RE" "$DOCTOR_ROOT/$file" 2>/dev/null | sort -u)
    done < <(git -C "$DOCTOR_ROOT" ls-files -z)

    # ok is the all-clear and nothing else.
    if [ "$DOCTOR_WARNINGS" -eq "$before_warnings" ]; then
        ok "no tracked config names a disconnected output"
    fi
}
```

- [ ] **Step 4: Wire it into `doctor.sh`**

Line 51 — add `hardware` to the module list:
```bash
for _doctor_module in symlinks references binaries services waybar hardware; do
```

After line 71 — add the call:
```bash
check_waybar
check_hardware
```

- [ ] **Step 5: Run the suite until green**

Run: `bash scripts/doctor/test/run-tests.sh`
Expected: `0 failures`, and the `▸ contract` block still passes — the new module uses `done < <(...)`, never a pipeline.

- [ ] **Step 6: Run the doctor against the live tree**

Run: `./doctor.sh`
Expected: a `▸ Hardware` group reporting `✓ no tracked config names a disconnected output`, and a summary of `0 errors, 0 warnings, 1 notice`. The single notice is the pre-existing one naming the owner of `org.freedesktop.Notifications`.

Any warning here is a real finding: it means a tracked file still names an output this machine does not have. Fix the file, not the check.

- [ ] **Step 7: Run every suite in the repo**

Run: `./test.sh`
Expected: all suites pass. `test-hardware.sh` needs no registration — `run-tests.sh` globs `test-*.sh`.

- [ ] **Step 8: Commit**

```bash
git add scripts/doctor/checks/hardware.sh scripts/doctor/test/test-hardware.sh doctor.sh
git commit -m "feat(doctor): check that tracked configs name outputs this host has

Reads the connected set from /sys/class/drm rather than hyprctl, so it works
from a TTY with no compositor, and derives the occurrences from git ls-files.
WARN, not ERROR: an unplugged monitor is legitimate. Markdown, docs/ and the
doctor's own tree are skipped, all three of which carry connector names as
examples."
```

---

### Task 6: Documentation

**Goal:** Every doc that states the old behaviour states the new one, and the CHANGELOG records the measurement that drove it.

**Files:**
- Modify: `README.md:277`
- Modify: `QUICKSTART.md:60-71` (the Quick Edits block)
- Modify: `CLAUDE.md` (the `options/` paragraph and the Doctor Architecture tree)
- Modify: `CHANGELOG.md` (new entry at the top, under the title block)

**Acceptance Criteria:**
- [ ] No doc claims `mainmonitor` holds `DP-1` on a fresh checkout
- [ ] `CLAUDE.md` states the empty-means-no-preference contract
- [ ] `CLAUDE.md`'s doctor tree lists `hardware.sh`
- [ ] The CHANGELOG records the `preferred` vs `highrr` measurement
- [ ] `./doctor.sh` and `./test.sh` still pass

**Verify:** `grep -rn 'mainmonitor' README.md QUICKSTART.md CLAUDE.md && ./doctor.sh && ./test.sh`

**Steps:**

- [ ] **Step 1: `README.md:277`**

Current:
```
├── mainmonitor  # DP-1
```
New:
```
├── mainmonitor  # empty = no preference
```

- [ ] **Step 2: `QUICKSTART.md` — replace the "Change primary monitor" line**

Current:
```bash
# Change primary monitor
echo "HDMI-A-1" > ~/.config/options/mainmonitor
```
New:
```bash
# Pick a primary monitor (multi-monitor setups). Leave the file EMPTY to mean
# "no preference": hyprlock then draws on every monitor and the wallpaper
# scripts use whichever awww reports first, which is what a single-monitor
# machine wants. `scripts/settings/settings.sh` writes both this file and
# hypr/config/hardware/primary.conf together.
echo "HDMI-A-1" > ~/.config/options/mainmonitor
```

- [ ] **Step 3: `CLAUDE.md` — the `options/` paragraph under "User Preferences"**

Append to that paragraph:

```markdown
`mainmonitor` is the one preference that is legitimately empty: **empty means
"no preference"**, and every consumer resolves that itself — hyprlock draws on
every monitor via `$monitor =` in `hardware/primary.conf`, and `wall.sh`,
`restore-wallpaper.sh` and both SDDM scripts fall back to whichever monitor
awww reports first. Nothing guesses a connector name; a tracked default like
`DP-1` or `eDP-1` is wrong on the next machine, which is what
`scripts/doctor/checks/hardware.sh` now guards. `hypr/config/hardware/monitor.conf`
is host-neutral for the same reason and uses `highrr`, not `preferred` —
`preferred` takes the EDID preferred timing, measured at 59.951 Hz on this
144 Hz panel.
```

- [ ] **Step 4: `CLAUDE.md` — the Doctor Architecture tree**

Add under `checks/`, after the `waybar.sh` line:
```
│   └── hardware.sh    — from `/sys/class/drm` connected set vs tracked files
```
and adjust the `waybar.sh` line's box-drawing prefix from `└──` to `├──`.

Then confirm no prose nearby still counts the modules:

Run: `grep -niE 'fifth|five (check|module)' CLAUDE.md`
Expected: no output. If a line does count them, correct it to six.

- [ ] **Step 5: `CHANGELOG.md` — new entry directly under the `All notable changes` line**

```markdown
## [2026-08-02] - Host-Neutral Monitor Config

### Changed
- **`hypr/config/hardware/monitor.conf`** is now one host-neutral rule,
  `monitor=,highrr,auto,1`. It named `DP-1,2560x1440@144`, so a fresh checkout
  configured this desktop's monitor on someone else's hardware.
- **`hypr/config/hardware/primary.conf` and `options/mainmonitor` ship empty.**
  Empty means "no preference": hyprlock draws its widgets on every monitor, the
  same as its `background {}` block already did. `scripts/settings/settings.sh`
  and the Super+I panel still write a real name when one is picked.
- **`wall.sh`, `restore-wallpaper.sh` and both SDDM scripts** branch explicitly
  on an empty preference instead of guessing a connector. The `eDP-1` default
  in three of them is gone — this machine has no such output.

### Added
- **`scripts/doctor/checks/hardware.sh`** + `test-hardware.sh`: warns when a
  tracked file names a display output that is not connected. The valid set
  comes from `/sys/class/drm` (so it works from a TTY with no compositor), the
  occurrences from `git ls-files -z`. Markdown, `docs/` and the doctor's own
  tree are skipped — all three carry connector names as examples.

### Fixed
- **`sddm/watch_wallpaper.sh` no longer stops silently.** It compared each
  inotify filename against `options/mainmonitor`, so an empty preference
  matched nothing and SDDM wallpaper sync died with no error printed anywhere.

### Notes
- **`preferred` is not the best mode; it is the EDID preferred timing.** Measured
  by applying each keyword and reading the rate back: `DP-1,preferred` gives
  `2560x1440@59.951`, `DP-1,highrr` gives `2560x1440@143.998`. The old catch-all
  `monitor=,preferred,auto,1` was therefore a 60 Hz trap for any *second*
  monitor as well, not just a portability problem.
- **hyprlock cannot be dry-run.** `hyprlock -c <file>` aborts at the Wayland
  connect (`hyprlock.cpp:63`) before it parses the config, so config changes are
  verified with a real `hyprlock --grace 30` launch — the grace window lets any
  keypress dismiss the lock without a password.
- **The awww cache lookup is duplicated in three scripts on purpose.**
  `sddm/update_sddm_root.sh` runs as root against another user's home, and
  sourcing a helper out of a user-writable `~/.config/scripts/` would hand that
  user a root shell.
```

- [ ] **Step 6: Verify nothing else still claims the old behaviour**

Run: `grep -rn 'mainmonitor' README.md QUICKSTART.md CLAUDE.md`
Expected: no line asserts a `DP-1` default.

Run: `./doctor.sh && ./test.sh`
Expected: `0 errors, 0 warnings, 1 notice`, and every suite passing.

- [ ] **Step 7: Commit**

```bash
git add README.md QUICKSTART.md CLAUDE.md CHANGELOG.md
git commit -m "docs: record the host-neutral monitor contract

Empty mainmonitor means 'no preference' in every consumer, monitor.conf names
no connector, and the CHANGELOG keeps the preferred-vs-highrr measurement and
the reason hyprlock has to be verified by a real launch."
```

---

## Final verification

Run once, after Task 6, before merging:

| What | Command | Expected |
|------|---------|----------|
| Hyprland config applies | `hyprctl reload && sleep 1 && hyprctl monitors -j \| jq -r '.[].refreshRate'` | `143.998` |
| Nothing tracked names a connector | `git grep -nIE '(eDP\|DP\|HDMI-A\|DVI-D\|LVDS)-[0-9]+' -- . ':!docs' ':!*.md' ':!scripts/doctor'` | no output |
| hyprlock renders | `hyprlock --grace 30` | input field and clock draw; keypress dismisses |
| Wallpaper pipeline | `bash scripts/hyprland/wall.sh` | palette regenerates, bar restarts |
| SDDM sync fires | change wallpaper, then `ls -t ~/.cache/awww/*/* \| head -1` | a fresh cache entry exists |
| Doctor | `./doctor.sh` | `0 errors, 0 warnings, 1 notice` |
| Suites | `./test.sh` | all pass |
| Panel builds | `cd ags && ags bundle app.ts /dev/null` | no error |
