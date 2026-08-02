# Unwired Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the three installed-but-unreachable tools — `hyprpicker`, `swappy`, `checkupdates` — into the surfaces this repo already has.

**Architecture:** Three independent slices sharing one pattern: a single script owns each behaviour, every surface calls that script, each script no-ops when its binary is missing, and none writes tracked files or keeps state. The doctor needs no edits — its checks derive their targets from `keybinds.conf` and `config.jsonc`, so declaring the keybinds and the module is what puts this work under test.

**Tech Stack:** bash, `jq`, waybar custom modules, rofi (rasi themes), Hyprland keybinds, `notify-send`/swaync.

**Spec:** `docs/superpowers/specs/2026-08-02-unwired-tools-design.md`

---

## File Structure

| File | Status | Responsibility |
|------|--------|----------------|
| `scripts/hyprland/colorpicker.sh` | Create | Pick a colour, copy hex, notify. Slice 1, whole. |
| `scripts/hyprland/screenshot-annotate.sh` | Create | Region capture piped into swappy. Slice 2's single owner. |
| `swappy/config` | Create | swappy's save directory and filename format. |
| `scripts/waybar/updates.sh` | Create | Count repo + AUR updates, emit waybar JSON, open the updater. |
| `scripts/waybar/test-updates.sh` | Create | Suite for the above; auto-discovered by `test.sh`. |
| `hypr/config/software/keybinds.conf` | Modify | Two new binds, each with its cheatsheet label. |
| `rofi/screenshot.sh` | Modify | Fourth menu entry → the annotate script. |
| `rofi/themes/screenshot/main.rasi` | Modify | `columns: 4` → `5`. |
| `waybar/config.jsonc` | Modify | `custom/updates` module + its slot in `modules-right`. |
| `waybar/style.css` | Modify | `#custom-updates` in the text tier and as a self-contained group. |
| `install.sh` | Modify | Add `swappy` to `PACKAGES`. |
| `README.md` | Modify | Add `swappy` to the manual pacman list. |
| `CHANGELOG.md` | Modify | Record the three slices. |

Slices 1, 2+3 and 4+5 are independent of each other and can be implemented in any order. Task 3 depends on Task 2 (it calls the script Task 2 creates). Task 5 depends on Task 4. Task 6 depends on everything.

---

### Task 1: Colour picker

**Goal:** `$Mod SHIFT+C` picks a screen colour, copies the hex to the clipboard, and shows a toast that actually renders its icon.

**Files:**
- Create: `scripts/hyprland/colorpicker.sh`
- Modify: `hypr/config/software/keybinds.conf` (after line 52, the `$Mod, C` clipboard bind)

**Acceptance Criteria:**
- [ ] `scripts/hyprland/colorpicker.sh` exists, is executable, and passes `shellcheck`
- [ ] Running it with `hyprpicker` absent from `PATH` exits 0 and prints nothing
- [ ] Cancelling the pick (ESC) produces no notification and exit status 0
- [ ] A successful pick puts a `#rrggbb` string in the clipboard and raises a toast whose icon is visibly rendered
- [ ] `$Mod SHIFT, C` appears in `./rofi/keybinds-cheatsheet.sh --print` labelled "Colour picker (copies hex)"

**Verify:** `shellcheck scripts/hyprland/colorpicker.sh && ./rofi/keybinds-cheatsheet.sh --print | grep -i 'colour picker'` → shellcheck silent, grep prints the row.

**Steps:**

- [ ] **Step 1: Write the script**

Create `scripts/hyprland/colorpicker.sh`:

```bash
#!/bin/bash
#
# Colour picker -- pick a pixel, copy its hex, say so.
#
# This replaces a waybar `custom/hyprpicker` module that was deleted in
# d952dfa as defined-but-unreferenced. Do not restore that module's one-liner:
# it was wrong twice, and both mistakes are corrected here.
#
#   1. It used `color-select-symbolic`. swaync 0.12.6 reserves the icon slot
#      for Papirus-Dark symbolic icons and then draws nothing in it, so the
#      toast came up blank. The non-symbolic `color-select` is what renders.
#   2. It passed the colour as the notification TITLE with no body, which
#      styles the one piece of information as a heading.
#
# -b/--no-fancy suppresses hyprpicker's coloured output. Command substitution
# is not a TTY so it would likely stay clean anyway, but a stray escape
# sequence here goes silently into the clipboard, which is not a failure mode
# worth leaving to chance.
#

command -v hyprpicker >/dev/null 2>&1 || exit 0

# ESC cancels the pick: hyprpicker exits non-zero, and there is nothing to
# report. That is an ordinary outcome, not an error.
color=$(hyprpicker -f hex -b -q) || exit 0
[ -n "$color" ] || exit 0

printf '%s' "$color" | wl-copy

notify-send -i color-select 'Colour copied' "$color"
```

- [ ] **Step 2: Make it executable and lint it**

```bash
chmod +x scripts/hyprland/colorpicker.sh
shellcheck scripts/hyprland/colorpicker.sh
```

Expected: no output from shellcheck.

- [ ] **Step 3: Prove the missing-binary path is silent**

```bash
env PATH=/nonexistent bash scripts/hyprland/colorpicker.sh; echo "exit=$?"
```

Expected: `exit=0` and no other output.

- [ ] **Step 4: Confirm the icon exists non-symbolically**

```bash
find ~/.local/share/icons/Papirus-Dark -name 'color-select.svg' | head -3
```

Expected: at least one path, e.g. `.../22x22/actions/color-select.svg`.

- [ ] **Step 5: Add the keybind**

In `hypr/config/software/keybinds.conf`, immediately after the `$Mod, C` clipboard-history line:

```
bind = $Mod SHIFT, C, exec, ~/.config/scripts/hyprland/colorpicker.sh   # Colour picker (copies hex)
```

The trailing `#` comment is the cheatsheet label — `rofi/keybinds-cheatsheet.sh` renders itself from this file at runtime, so never hand-edit a cheatsheet row.

- [ ] **Step 6: Confirm the cheatsheet picked it up**

```bash
hyprctl reload
./rofi/keybinds-cheatsheet.sh --print | grep -i 'colour picker'
```

Expected: one row showing `Super + Shift + C` and `Colour picker (copies hex)`.

- [ ] **Step 7: Manual check — the toast**

Press `$Mod SHIFT+C`, click a pixel. Then:

```bash
wl-paste
```

Expected: a `#rrggbb` string matching the pixel. **Screenshot the toast** and confirm the icon square is filled, not blank — a `notify-send` that exits 0 is not evidence the icon rendered, and an icon that renders in the panel is not evidence it renders in a toast. That exact gap is what the night-light work found in swaync 0.12.6.

Also press `$Mod SHIFT+C` and hit ESC: expect no toast at all.

- [ ] **Step 8: Commit**

```bash
git add scripts/hyprland/colorpicker.sh hypr/config/software/keybinds.conf
git commit -m "feat(hyprpicker): bind a colour picker that copies the hex

hyprpicker has been installed by install.sh and advertised in the README
while being bound to nothing. Corrects both defects in the custom/hyprpicker
module deleted in d952dfa: a symbolic icon name swaync 0.12.6 renders as
blank, and the colour passed as the notification title instead of the body."
```

```json:metadata
{"files": ["scripts/hyprland/colorpicker.sh", "hypr/config/software/keybinds.conf"], "verifyCommand": "shellcheck scripts/hyprland/colorpicker.sh && ./rofi/keybinds-cheatsheet.sh --print | grep -i 'colour picker'", "acceptanceCriteria": ["script exists, executable, shellcheck clean", "no-hyprpicker path exits 0 silently", "ESC cancel produces no notification", "successful pick copies #rrggbb and renders a toast icon", "cheatsheet shows the Colour picker row"]}
```

---

### Task 2: Screenshot annotation script and swappy config

**Goal:** `$Mod ALT+S` captures a region straight into swappy for markup, saving into the same folder and filename format as every other screenshot.

**Files:**
- Create: `scripts/hyprland/screenshot-annotate.sh`
- Create: `swappy/config`
- Modify: `hypr/config/software/keybinds.conf` (after line 30, the `$Mod, S` region bind)
- Modify: `install.sh` (the `PACKAGES` array, screenshot/utility section)
- Modify: `README.md` (the manual `pacman -S` list)

**Acceptance Criteria:**
- [ ] `swappy/config` sets `save_dir` to `$HOME/Pictures/Screenshots` with no absolute `/home/<user>` path in it
- [ ] `scripts/hyprland/screenshot-annotate.sh` exists, is executable, passes `shellcheck`
- [ ] With `swappy` or `hyprshot` absent from `PATH` the script exits 0 and prints nothing
- [ ] A real `$Mod ALT+S` opens swappy on the captured region, and saving writes a `Screenshot_*.png` into `~/Pictures/Screenshots`
- [ ] `$Mod, S` and `$Mod SHIFT, S` behave exactly as before
- [ ] `swappy` appears in `install.sh`'s `PACKAGES` and in the README list

**Verify:** `shellcheck scripts/hyprland/screenshot-annotate.sh && grep -q swappy install.sh && grep -c 'home/' swappy/config` → shellcheck silent, grep succeeds, count is `0`.

**Steps:**

- [ ] **Step 1: Write swappy's config**

swappy has no config on this machine at all (`~/.config/swappy/` does not exist), so it currently defaults to saving on the desktop. Create `swappy/config`:

```ini
[Default]
save_dir=$HOME/Pictures/Screenshots
save_filename_format=Screenshot_%Y-%m-%d_%H:%M:%S.png
```

`$HOME` rather than `/home/pwnjack`, per the host-neutral rule from the monitor work — a tracked absolute home path is wrong on the next machine. swappy expands it: the binary links `wordexp` and its own built-in default for this key is the literal string `$HOME/Desktop`.

The filename format matches what `$Mod, S` and `rofi/screenshot.sh` already produce, so annotated and plain shots sort together.

- [ ] **Step 2: Write the capture script**

Create `scripts/hyprland/screenshot-annotate.sh`:

```bash
#!/bin/bash
#
# Region screenshot -> swappy, for marking up before saving.
#
# Deliberately additive: $Mod,S still writes straight to disk and the rofi
# menu's first three entries are untouched. Annotation is opt-in, because
# putting an editor in front of every capture taxes the quick grab that is
# most of what screenshots are for.
#
# -r streams raw PNG to stdout; -s suppresses hyprshot's own "saved"
# notification, which would otherwise announce a file that was never written.
# Where the result lands is swappy's decision, from swappy/config.
#
# Both surfaces that offer annotation -- the $Mod ALT+S keybind and the fourth
# entry in rofi/screenshot.sh -- call this script rather than repeating the
# pipeline, so they cannot drift apart.
#

command -v hyprshot >/dev/null 2>&1 || exit 0
command -v swappy   >/dev/null 2>&1 || exit 0

hyprshot -m region -r -s | swappy -f -
```

- [ ] **Step 3: Make it executable and lint it**

```bash
chmod +x scripts/hyprland/screenshot-annotate.sh
shellcheck scripts/hyprland/screenshot-annotate.sh
```

Expected: no output.

- [ ] **Step 4: Prove the missing-binary path is silent**

```bash
env PATH=/nonexistent bash scripts/hyprland/screenshot-annotate.sh; echo "exit=$?"
```

Expected: `exit=0`, nothing else.

- [ ] **Step 5: Add the keybind**

In `hypr/config/software/keybinds.conf`, immediately after the `$Mod, S` region line:

```
bind = $Mod ALT, S, exec, ~/.config/scripts/hyprland/screenshot-annotate.sh   # Screenshot a region and annotate
```

- [ ] **Step 6: Add swappy to install.sh**

In `install.sh`, the `PACKAGES` array around line 92 lists `"hyprshot" "hyprpicker" "hyprsunset"`. Add `swappy` beside the screenshot tool it extends:

```bash
    "hyprshot" "hyprpicker" "hyprsunset" "swappy"
```

- [ ] **Step 7: Add swappy to the README**

In `README.md`'s manual `sudo pacman -S` list (around line 247), add `swappy` next to `hyprshot`:

```
sudo pacman -S hyprland hyprlock hypridle hyprpolkitagent hyprshot swappy \
```

- [ ] **Step 8: Manual check — a real annotated save**

```bash
hyprctl reload
```

Press `$Mod ALT+S`, drag a region. swappy opens on it. Draw something, save (`Ctrl+S`). Then:

```bash
ls -t ~/Pictures/Screenshots | head -3
```

Expected: a freshly-timestamped `Screenshot_YYYY-MM-DD_HH:MM:SS.png` at the top. This is the live confirmation that `$HOME` expanded — do not rest on the `strings` evidence alone. If the file landed on the desktop instead, `$HOME` did not expand: fall back to letting swappy default and pass an explicit `-o "$HOME/Pictures/Screenshots/Screenshot_$(date +%Y-%m-%d_%H:%M:%S).png"` from the script.

Then confirm nothing regressed: press `$Mod, S`, drag a region, and check a new file appears with no swappy window.

- [ ] **Step 9: Commit**

```bash
git add swappy/config scripts/hyprland/screenshot-annotate.sh \
        hypr/config/software/keybinds.conf install.sh README.md
git commit -m "feat(swappy): add an opt-in annotate path for screenshots

swappy was installed with zero references anywhere in the repo and not even
listed in install.sh. \$Mod ALT+S now captures a region into it. \$Mod,S and
the rofi menu keep their current behaviour exactly -- an editor in front of
every capture would tax the quick grab that is most of what screenshots are.

swappy/config uses \$HOME rather than an absolute home path, per the
host-neutral rule; swappy links wordexp and its own default for the key is
the literal string \$HOME/Desktop."
```

```json:metadata
{"files": ["swappy/config", "scripts/hyprland/screenshot-annotate.sh", "hypr/config/software/keybinds.conf", "install.sh", "README.md"], "verifyCommand": "shellcheck scripts/hyprland/screenshot-annotate.sh && grep -q swappy install.sh && test \"$(grep -c 'home/' swappy/config)\" = 0", "acceptanceCriteria": ["swappy/config uses $HOME, no absolute home path", "script shellcheck clean and executable", "missing-binary path exits 0 silently", "real annotated save lands in ~/Pictures/Screenshots", "$Mod,S and $Mod SHIFT,S unchanged", "swappy listed in install.sh and README"]}
```

---

### Task 3: Annotate entry in the rofi screenshot menu

**Goal:** The `$Mod SHIFT+S` menu offers annotation as a fourth choice, ahead of settings, without the row falling out of view.

**Files:**
- Modify: `rofi/screenshot.sh`
- Modify: `rofi/themes/screenshot/main.rasi:listview` (`columns`)

**Blocked by:** Task 2 (calls the script it creates).

**Acceptance Criteria:**
- [ ] The menu shows five entries on one row: monitor, window, selection, annotate, settings
- [ ] Choosing annotate runs `scripts/hyprland/screenshot-annotate.sh`
- [ ] Choosing settings still opens `rofi/screenshot-settings.sh` — it moved from slot 4 to slot 5 and still works
- [ ] The `-mesg` legend lists all five
- [ ] `shellcheck rofi/screenshot.sh` is clean

**Verify:** `shellcheck rofi/screenshot.sh && grep -n 'columns' rofi/themes/screenshot/main.rasi` → shellcheck silent, `columns: 5;`.

**Steps:**

- [ ] **Step 1: Widen the listview**

`rofi/themes/screenshot/main.rasi` hardcodes `columns: 4; lines: 1;`, so a fifth entry wraps onto a second row that `lines: 1` will not show. In the `listview` block change:

```rasi
    columns:                     5;
```

Leave `lines: 1`, `dynamic: true` and the 600px window width alone — five elements at 32px glyphs fit.

- [ ] **Step 2: Add the option and its dispatch**

In `rofi/screenshot.sh`, add a fifth option glyph and move settings to it. The existing block:

```bash
# Options
option_1="󰹑"
option_2=""
option_3="󱊅"
option_4=""
```

becomes:

```bash
# Options
option_1="󰹑"
option_2=""
option_3="󱊅"
option_4=""
option_5=""
```

- [ ] **Step 3: Update the legend and the menu feed**

Change the `-mesg` line inside `rofi_cmd`:

```bash
        -mesg "Monitor | Window | Selection | Annotate | Settings"
```

and `run_rofi`:

```bash
run_rofi() {
    echo -e "$option_1\n$option_2\n$option_3\n$option_4\n$option_5" | rofi_cmd
}
```

- [ ] **Step 4: Add the annotate action**

Add a function beside `settings()`:

```bash
annotate() {
    $HOME/.config/scripts/hyprland/screenshot-annotate.sh
}
```

Note it takes no `$timer` and no `$freeze`: hyprshot's own `-z` freeze is not wanted when the capture goes straight into an editor, and a delay before a region drag helps nothing.

- [ ] **Step 5: Rewire the dispatch**

`run_cmd` becomes:

```bash
run_cmd() {
    if [[ "$1" == '--opt1' ]]; then
        sleep 0.5
        shotscreen
    elif [[ "$1" == '--opt2' ]]; then
        sleep 0.5
        shotwin
    elif [[ "$1" == '--opt3' ]]; then
        sleep 0.5
        shotarea
    elif [[ "$1" == '--opt4' ]]; then
        sleep 0.5
        annotate
    elif [[ "$1" == '--opt5' ]]; then
        settings
    fi
}
```

and the `case` at the bottom gains its fifth arm:

```bash
chosen="$(run_rofi)"
case ${chosen} in
    "$option_1")
        run_cmd --opt1
        ;;
    "$option_2")
        run_cmd --opt2
        ;;
    "$option_3")
        run_cmd --opt3
        ;;
    "$option_4")
        run_cmd --opt4
        ;;
    "$option_5")
        run_cmd --opt5
        ;;
esac
```

- [ ] **Step 6: Lint**

```bash
shellcheck rofi/screenshot.sh
```

Expected: no output. (`$HOME/...` unquoted in `annotate()` matches the existing `settings()` line; if shellcheck flags it, quote both.)

- [ ] **Step 7: Manual check — all five rows**

Press `$Mod SHIFT+S`. Expected: five glyphs on a single row, legend reading `Monitor | Window | Selection | Annotate | Settings`. Pick the fourth → swappy opens. Re-open and pick the fifth → the settings menu opens.

- [ ] **Step 8: Commit**

```bash
git add rofi/screenshot.sh rofi/themes/screenshot/main.rasi
git commit -m "feat(rofi): offer annotation from the screenshot menu

Fourth entry, calling the same screenshot-annotate.sh the keybind uses so the
two surfaces cannot drift. The theme hardcoded columns: 4 with lines: 1, which
would have wrapped the fifth entry out of view; it is now columns: 5."
```

```json:metadata
{"files": ["rofi/screenshot.sh", "rofi/themes/screenshot/main.rasi"], "verifyCommand": "shellcheck rofi/screenshot.sh && grep -q 'columns: *5' rofi/themes/screenshot/main.rasi", "acceptanceCriteria": ["five entries render on one row", "annotate entry runs screenshot-annotate.sh", "settings entry still works from slot 5", "legend lists all five", "shellcheck clean"]}
```

---

### Task 4: Updates counter script, test-first

**Goal:** `scripts/waybar/updates.sh` reports how many repo and AUR updates are pending, hides itself at zero, and cannot be fooled by the exit codes these commands use to mean "nothing found".

**Files:**
- Create: `scripts/waybar/updates.sh`
- Create: `scripts/waybar/test-updates.sh`

**Acceptance Criteria:**
- [ ] Zero repo and zero AUR updates → no output, exit 0 (the module hides)
- [ ] A repo command exiting `2` with no output is treated as zero, not as failure
- [ ] An AUR helper exiting `1` with no output is treated as zero, not as failure
- [ ] A command exiting non-zero **with** output still has its lines counted
- [ ] Empty or missing `options/aurhelper` → repo-only tooltip, total is the repo count
- [ ] An `aurhelper` naming an uninstalled binary → repo-only tooltip
- [ ] Both counts non-zero → `text` shows the combined total, `tooltip` reads `N repo · M AUR`
- [ ] The helper name is read from `options/aurhelper`, never hardcoded
- [ ] `shellcheck` clean on both files; `bash scripts/waybar/test-updates.sh` exits 0
- [ ] The suite runs with no network access

**Verify:** `bash scripts/waybar/test-updates.sh` → every line `ok`, final summary `0 failed`, exit 0.

**Steps:**

- [ ] **Step 1: Write the failing test suite**

Create `scripts/waybar/test-updates.sh`. It follows `test-battery.sh`: standalone, exit 1 on any failure, runs the script under test as a subprocess exactly the way waybar does, and reads fields back with `jq` (not a new dependency — the script needs it to emit JSON). The seam is a pair of command overrides, the same idea as `BATTERY_SYSFS`.

```bash
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

PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); echo "  ok   $1"; }
fail() {
    FAILED=$((FAILED + 1))
    echo "  FAIL $1"
    shift
    printf '       %s\n' "$@"
}

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
run() {
    UPDATES_REPO_CMD="$1" UPDATES_AUR_CMD="$2" \
        PATH="$TMP/bin:$PATH" bash "$UPDATES" 2>"$TMP/stderr"
}

# run_derived <repo-cmd> <aurhelper-file> — stdout of the module with
# UPDATES_AUR_CMD deliberately LEFT UNSET, so the script must derive the helper
# from the aurhelper file. Pinning the env var would short-circuit exactly the
# derivation these cases exist to test.
run_derived() {
    env -u UPDATES_AUR_CMD \
        UPDATES_REPO_CMD="$1" UPDATES_AURHELPER="$2" \
        PATH="$TMP/bin:$PATH" bash "$UPDATES" 2>"$TMP/stderr"
}

# helper_file <content> — an options/aurhelper stand-in; empty arg means the
# file exists but is blank
helper_file() {
    local f
    f=$(mktemp "$TMP/aurhelper.XXXXXX")
    printf '%s' "$1" > "$f"
    echo "$f"
}

assert_silent() {
    if [ -z "$1" ]; then pass "$2"; else fail "$2" "expected no output" "got: $1"; fi
}

assert_field() {
    local actual
    actual=$(printf '%s' "$1" | jq -r "$2" 2>/dev/null)
    if [ "$actual" = "$3" ]; then
        pass "$4"
    else
        fail "$4" "filter:   $2" "expected: $3" "actual:   $actual" "json:     $1"
    fi
}

assert_contains() {
    local actual
    actual=$(printf '%s' "$1" | jq -r "$2" 2>/dev/null)
    if printf '%s' "$actual" | grep -qF -- "$3"; then
        pass "$4"
    else
        fail "$4" "expected to contain: $3" "actual: $actual"
    fi
}

assert_lacks() {
    local actual
    actual=$(printf '%s' "$1" | jq -r "$2" 2>/dev/null)
    if printf '%s' "$actual" | grep -qF -- "$3"; then
        fail "$4" "expected NOT to contain: $3" "actual: $actual"
    else
        pass "$4"
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
assert_contains "$out" '.text' "2" "two repo updates are counted"
assert_contains "$out" '.tooltip' "2 repo" "tooltip names the repo count"

fake checkupdates 1 "foo 1-1 -> 1-2" "bar 2-1 -> 2-2" "baz 3-1 -> 3-2"
fake paru 1
assert_contains "$(run checkupdates paru)" '.text' "3" \
    "a non-zero exit WITH output still has its lines counted"

# --- repo + AUR ------------------------------------------------------------

fake checkupdates 0 "foo 1-1 -> 1-2" "bar 2-1 -> 2-2"
fake paru 0 "aurpkg 1-1 -> 1-2"
out=$(run checkupdates paru)
assert_contains "$out" '.text' "3" "text shows the combined total"
assert_contains "$out" '.tooltip' "2 repo" "tooltip shows the repo count"
assert_contains "$out" '.tooltip' "1 AUR" "tooltip shows the AUR count"

fake checkupdates 2
fake paru 0 "aurpkg 1-1 -> 1-2"
out=$(run checkupdates paru)
assert_contains "$out" '.text' "1" "AUR-only updates still show the module"
assert_lacks "$out" '.tooltip' "0 repo" "a zero side is left out of the tooltip"

# --- deriving the helper from options/aurhelper ----------------------------
# UPDATES_AUR_CMD is unset in every case below, so the script has to read the
# file. That is the behaviour under test.

fake checkupdates 0 "foo 1-1 -> 1-2" "bar 2-1 -> 2-2"
fake paru 0 "aurpkg 1-1 -> 1-2"
out=$(run_derived checkupdates "$H_PARU")
assert_contains "$out" '.text' "3" "the helper name is taken from the first word of aurhelper"
assert_contains "$out" '.tooltip' "1 AUR" "a derived helper's count reaches the tooltip"

fake checkupdates 0 "foo 1-1 -> 1-2" "bar 2-1 -> 2-2"
out=$(run_derived checkupdates "$H_EMPTY")
assert_contains "$out" '.text' "2" "empty aurhelper still reports the repo count"
assert_lacks "$out" '.tooltip' "AUR" "empty aurhelper gives a repo-only tooltip"

fake checkupdates 0 "foo 1-1 -> 1-2" "bar 2-1 -> 2-2"
out=$(run_derived checkupdates "$H_GONE")
assert_contains "$out" '.text' "2" "an uninstalled helper still reports the repo count"
assert_lacks "$out" '.tooltip' "AUR" "an uninstalled helper gives a repo-only tooltip"

fake checkupdates 0 "foo 1-1 -> 1-2"
out=$(run_derived checkupdates "$TMP/definitely-not-here")
assert_contains "$out" '.text' "1" "a missing aurhelper file is not fatal"

# --- summary ---------------------------------------------------------------

echo
echo "  $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
```

- [ ] **Step 2: Run the suite and watch it fail**

```bash
bash scripts/waybar/test-updates.sh; echo "exit=$?"
```

Expected: failures on every assertion, because `scripts/waybar/updates.sh` does not exist yet. `exit=1`.

- [ ] **Step 3: Write the module**

Create `scripts/waybar/updates.sh`:

```bash
#!/bin/bash
#
# Pending updates for waybar -- repo and AUR, one count.
#
# There is no update notifier on this machine. The arch-update tray entry in
# ~/.config/autostart names a binary that is not installed, and Discover's
# notifier carries OnlyShowIn=KDE so it never starts under Hyprland. This
# module is the replacement, and it does not duplicate the updater:
# scripts/settings/update.sh already exists and is what the click opens.
#
# THE EXIT-STATUS TRAP. Both count commands use exit status to mean "nothing
# found", with different codes:
#
#   checkupdates   exit 2   no updates          (exit 0 with updates)
#   paru -Qua      exit 1   no AUR updates
#
# So this script must ignore exit status entirely and count lines. Any `&&`
# chain, any `set -e`, any `if cmd; then count; fi` reports zero forever and
# looks perfectly healthy doing it -- the failure mode is silence, which is
# why test-updates.sh pins all four combinations of status and output.
#
# The AUR helper is DERIVED from options/aurhelper (first word of e.g.
# "paru -Syu"), never hardcoded. A hardcoded name would be a second source of
# truth beside the file the settings panel and update.sh already read.
#
# UPDATES_REPO_CMD, UPDATES_AUR_CMD and UPDATES_AURHELPER are the test seam;
# test-updates.sh drives them the way test-battery.sh drives BATTERY_SYSFS.
#

REPO_CMD="${UPDATES_REPO_CMD:-checkupdates}"
AURHELPER_FILE="${UPDATES_AURHELPER:-$HOME/.config/options/aurhelper}"

ICON=$'\U000f06b0'   # Nerd Font, Material Design: update (󰚰)

# count <command> [args...] — lines of output, exit status ignored on purpose.
count() {
    local out
    out=$("$@" 2>/dev/null)
    [ -n "$out" ] || { printf '0'; return; }
    printf '%s' "$out" | grep -c ''
}

# repo count
if command -v "$REPO_CMD" >/dev/null 2>&1; then
    repo=$(count "$REPO_CMD")
else
    repo=0
fi

# AUR count. UPDATES_AUR_CMD overrides the derivation for the tests; otherwise
# take the first word of options/aurhelper, which holds a full command line.
aur_cmd="${UPDATES_AUR_CMD-}"
if [ -z "${UPDATES_AUR_CMD+set}" ]; then
    aur_cmd=$(awk 'NR==1 {print $1}' "$AURHELPER_FILE" 2>/dev/null)
fi

aur=""
if [ -n "$aur_cmd" ] && command -v "$aur_cmd" >/dev/null 2>&1; then
    aur=$(count "$aur_cmd" -Qua)
fi

total=$((repo + ${aur:-0}))

# Nothing pending: print nothing and let waybar hide the module -- the idiom
# battery.sh and custom/media already use. The module APPEARING is the signal,
# which is what keeps this stateless with nothing to remember or expire.
[ "$total" -gt 0 ] || exit 0

# Only non-zero sides are named. "0 repo · 1 AUR" reads as a fault report
# rather than a count, and the zero carries nothing the total does not.
# `total > 0` above guarantees at least one side survives, so this is never
# empty.
tooltip=""
[ "$repo" -gt 0 ] && tooltip="$repo repo"
if [ -n "$aur" ] && [ "$aur" -gt 0 ]; then
    [ -n "$tooltip" ] && tooltip+=" · "
    tooltip+="$aur AUR"
fi

text="<span size=\"large\">$ICON</span>  $total"

# Both fields are ours -- a glyph and digits, no package names, no vendor
# strings -- so unlike battery.sh's tooltip there is no arbitrary text to
# escape for Pango here.
jq -nc --arg text "$text" --arg tooltip "$tooltip" \
    '{text: $text, tooltip: $tooltip}'
```

- [ ] **Step 4: Run the suite and watch it pass**

```bash
chmod +x scripts/waybar/updates.sh
bash scripts/waybar/test-updates.sh; echo "exit=$?"
```

Expected: every line `ok`, `N passed, 0 failed`, `exit=0`.

- [ ] **Step 5: Lint both files**

```bash
shellcheck scripts/waybar/updates.sh scripts/waybar/test-updates.sh
```

Expected: no output.

- [ ] **Step 6: Check it against the real machine**

```bash
bash scripts/waybar/updates.sh | jq .
```

Expected: JSON whose `text` total equals `checkupdates | wc -l` plus `paru -Qua | wc -l`. Cross-check:

```bash
echo "repo=$(checkupdates | grep -c '')  aur=$(paru -Qua | grep -c '')"
```

- [ ] **Step 7: Confirm the runner discovers the suite**

```bash
./test.sh --list
```

Expected: `scripts/waybar/test-updates.sh` appears. No registration step exists — `test.sh` treats any tracked `test-*.sh` in a directory without a `run-tests.sh` as an entry point.

```bash
./test.sh
```

Expected: every suite passes.

- [ ] **Step 8: Commit**

```bash
git add scripts/waybar/updates.sh scripts/waybar/test-updates.sh
git commit -m "feat(waybar): count pending repo and AUR updates

checkupdates was installed and referenced nowhere, and this machine has no
working update notifier -- arch-update's tray entry names an uninstalled
binary and Discover's carries OnlyShowIn=KDE.

The suite pins the trap this module exists around: checkupdates exits 2 and
paru -Qua exits 1 to mean 'nothing found', so counting must ignore exit
status. Gating on it reports zero forever while looking healthy.

The helper is derived from options/aurhelper rather than hardcoded, so it
stays one source of truth with update.sh and the settings panel."
```

```json:metadata
{"files": ["scripts/waybar/updates.sh", "scripts/waybar/test-updates.sh"], "verifyCommand": "bash scripts/waybar/test-updates.sh && shellcheck scripts/waybar/updates.sh scripts/waybar/test-updates.sh && ./test.sh", "acceptanceCriteria": ["zero updates prints nothing and exits 0", "checkupdates exit 2 treated as zero not failure", "paru -Qua exit 1 treated as zero not failure", "non-zero exit with output still counts lines", "empty or missing aurhelper gives repo-only tooltip", "uninstalled helper gives repo-only tooltip", "both counts give combined total and 'N repo . M AUR' tooltip", "helper derived from options/aurhelper, not hardcoded", "shellcheck clean, test suite exits 0, runs with no network"]}
```

---

### Task 5: Updates module on the bar

**Goal:** The count appears on the bar between disk and network, opens the existing updater on click, and refreshes the instant an update finishes rather than waiting out the interval.

**Files:**
- Modify: `waybar/config.jsonc` (`modules-right` array; a new `custom/updates` block)
- Modify: `waybar/style.css` (text-tier list, rhythm list, self-contained group list)
- Modify: `scripts/waybar/updates.sh` (add the `update` verb)

**Blocked by:** Task 4.

**Acceptance Criteria:**
- [ ] `custom/updates` sits between `disk` and `network` in `modules-right`
- [ ] The module renders at the text tier (14px), with 15px padding on both sides
- [ ] Left-click opens `scripts/settings/update.sh` in the terminal from `options/terminal`
- [ ] When that terminal exits, the module refreshes without waiting for the interval
- [ ] Right-click forces an immediate refresh
- [ ] `./doctor.sh` reports 0 errors and 0 warnings
- [ ] Gaps either side stay 30px whether the module is showing or hidden

**Verify:** `./doctor.sh; echo "exit=$?"` → `0 error(s)`, `0 warning(s)`, exit 0.

**Steps:**

- [ ] **Step 1: Add the `update` verb to the script**

Append to `scripts/waybar/updates.sh`, immediately after the `ICON` assignment and before the `count()` function, so an argument short-circuits before any counting happens:

```bash
# `update` verb: open the updater that already exists, then refresh the module
# the moment it exits instead of waiting out the 30-minute interval. Signal 9
# is this module's; custom/nightlight uses 8 for the same purpose.
if [ "${1-}" = "update" ]; then
    term=$(cat "$HOME/.config/options/terminal" 2>/dev/null)
    [ -n "$term" ] || term=ghostty
    "$term" -e "$HOME/.config/scripts/settings/update.sh"
    pkill -RTMIN+9 waybar
    exit 0
fi
```

The `ghostty` fallback matches the repo's documented default terminal and keeps the click working if `options/terminal` is ever blank.

- [ ] **Step 2: Re-run the suite**

```bash
bash scripts/waybar/test-updates.sh; echo "exit=$?"
shellcheck scripts/waybar/updates.sh
```

Expected: still `0 failed`, `exit=0`, shellcheck silent. The suite calls the script with no arguments, so the new branch does not disturb it.

- [ ] **Step 3: Place the module in the bar**

In `waybar/config.jsonc`, `modules-right` becomes:

```jsonc
  "modules-right": [
    "cpu",
    "memory",
    "custom/gpu",
    "disk",
    "custom/updates",
    "network",
    "bluetooth",
    "custom/battery",
    "pulseaudio",
    "tray",
    "custom/nightlight",
    "custom/sidebar",
    "custom/settings",
    "custom/power",
  ],
```

- [ ] **Step 4: Define the module**

In `waybar/config.jsonc`, after the `"disk"` block (around line 204) and before `// Network`:

```jsonc
  // Updates
  // Hidden entirely when nothing is pending -- the module appearing IS the
  // notice, the same stateless grammar custom/battery uses for peripherals.
  // The interval is long because checkupdates syncs a private pacman DB over
  // the network on every run; signal 9 is what makes a finished update clear
  // the count immediately rather than up to half an hour later.
  "custom/updates": {
    "format": "{}",
    "return-type": "json",
    "interval": 1800,
    "signal": 9,
    "exec": "~/.config/scripts/waybar/updates.sh",
    "on-click": "~/.config/scripts/waybar/updates.sh update",
    "on-click-right": "pkill -RTMIN+9 waybar",
  },
```

- [ ] **Step 5: Style it**

Three edits in `waybar/style.css`, matching how `#custom-battery` is handled — it is the existing precedent for a module that comes and goes.

Add to the **text tier** list (the block ending `#tray { font-size: 14px; }`), after `#disk,`:

```css
#custom-updates,
```

Add to the **rhythm** list (the block setting `margin: 4px 0px; padding: 0px 10px;`), after `#disk,`:

```css
#custom-updates,
```

Add to the **self-contained groups** list (the block setting `padding-left: 15px; padding-right: 15px;`), after `#workspaces,`:

```css
#custom-updates,
```

That third one carries the reasoning already written above that block: a module that comes and goes cannot be load-bearing for a gap. `#disk` closes its group with `padding-right: 15px` and `#network` already has 15px on both sides, so with `#custom-updates` self-contained the gap either side is 30px whether it shows or not. No class rule is needed — it inherits `@foreground` like every other healthy readout, and nothing here is an alert state.

- [ ] **Step 6: Restart the bar and look at it**

```bash
~/.config/scripts/waybar/waybar.sh
```

Expected: with updates pending, `󰚰 N` between the disk and network readouts, tooltip `N repo · M AUR`. Confirm by eye that the gap on each side matches the gaps elsewhere in that row.

- [ ] **Step 7: Exercise both clicks**

Right-click the module. Expected: it refreshes in place (no visible change if the count is unchanged; no error in `journalctl --user -u waybar` or the terminal waybar was started from).

Left-click. Expected: a terminal opens running the updater with its `Press ENTER` prompts. After it exits, the module's count drops to reflect what was installed — if everything updated, the module disappears.

- [ ] **Step 8: Run the doctor**

```bash
./doctor.sh; echo "exit=$?"
```

Expected: `0 error(s)`, `0 warning(s)`, and the single known notice about which daemon owns `org.freedesktop.Notifications`. `exit=0`. No doctor edits were needed: `checks/waybar.sh` derives its targets from the `modules-*` arrays and handler values, so declaring the module is what put it under test.

- [ ] **Step 9: Commit**

```bash
git add waybar/config.jsonc waybar/style.css scripts/waybar/updates.sh
git commit -m "feat(waybar): show pending updates between disk and network

Click opens the updater that already exists and signals the module when it
exits, so the count clears immediately instead of up to 30 minutes later.

The slot follows the stylesheet's own rule rather than taste: a module that
comes and goes cannot be load-bearing for a gap, so it is styled
self-contained like #custom-battery, which keeps both neighbouring gaps at
30px whether it is showing or hidden."
```

```json:metadata
{"files": ["waybar/config.jsonc", "waybar/style.css", "scripts/waybar/updates.sh"], "verifyCommand": "bash scripts/waybar/test-updates.sh && ./doctor.sh", "acceptanceCriteria": ["custom/updates between disk and network", "text tier 14px with 15px both sides", "left-click opens update.sh in options/terminal", "module refreshes when the updater exits", "right-click forces refresh", "doctor 0 errors 0 warnings", "30px gaps whether showing or hidden"]}
```

---

### Task 6: Close out — changelog and full verification

**Goal:** Record the three slices, confirm the whole repo is still clean, and update the backlog memory so the next session knows chunk B is done.

**Files:**
- Modify: `CHANGELOG.md`

**Blocked by:** Tasks 1, 3, 5.

**Acceptance Criteria:**
- [ ] `CHANGELOG.md` has an `### Added` entry for each of the three slices
- [ ] `./test.sh` passes every suite
- [ ] `./doctor.sh` reports 0 errors, 0 warnings, exits 0
- [ ] `git status` is clean and every new script is executable
- [ ] Nothing is pushed — main is behind origin and the user pushes themselves

**Verify:** `./test.sh && ./doctor.sh && git status --short` → all suites pass, 0 errors / 0 warnings, no output from status.

**Steps:**

- [ ] **Step 1: Write the changelog entry**

Add a dated section at the top of `CHANGELOG.md`, matching the existing house style (`## [YYYY-MM-DD] - Title`, then `### Added` / `### Fixed`):

```markdown
## [2026-08-02] - Unwired Tools

### Added
- **Colour picker** on `$Mod SHIFT+C` — `hyprpicker` had been installed by
  `install.sh` and advertised in the README while bound to nothing. Copies the
  hex and notifies. Corrects both defects in the `custom/hyprpicker` module
  deleted in `d952dfa`: a symbolic icon name swaync 0.12.6 renders blank, and
  the colour passed as the notification title rather than its body.
- **Screenshot annotation** on `$Mod ALT+S` and as a fourth entry in the
  `$Mod SHIFT+S` menu, capturing a region straight into `swappy`. `swappy` was
  installed with zero references anywhere in the repo and was not even listed
  in `install.sh`. Existing capture paths are untouched — annotation is opt-in.
  A tracked `swappy/config` points its save directory at
  `$HOME/Pictures/Screenshots` with the same filename format as every other
  screenshot; `$HOME`, not an absolute home path, per the host-neutral rule.
- **Pending-updates module** on the bar, hidden entirely when nothing is due.
  `checkupdates` was installed and unused, and this machine has no working
  notifier: `~/.config/autostart/arch-update-tray.desktop` names an
  uninstalled binary and Discover's notifier carries `OnlyShowIn=KDE`. Counting
  ignores exit status on purpose — `checkupdates` exits 2 and `paru -Qua` exits
  1 to mean "nothing found", so gating on status reports zero forever while
  looking healthy. `scripts/waybar/test-updates.sh` pins all four combinations.
  The AUR helper is derived from `options/aurhelper`, and the click opens the
  `scripts/settings/update.sh` that already existed.
```

- [ ] **Step 2: Confirm every new script is executable**

```bash
git ls-files -s scripts/hyprland/colorpicker.sh \
                scripts/hyprland/screenshot-annotate.sh \
                scripts/waybar/updates.sh \
                scripts/waybar/test-updates.sh
```

Expected: mode `100755` on all four. If any shows `100644`:

```bash
chmod +x <path> && git add --chmod=+x <path>
```

- [ ] **Step 3: Run every suite**

```bash
./test.sh
```

Expected: every suite passes, including the newly discovered `scripts/waybar/test-updates.sh`.

- [ ] **Step 4: Run the doctor**

```bash
./doctor.sh; echo "exit=$?"
```

Expected: `0 error(s)`, `0 warning(s)`, one notice about the notification daemon, `exit=0`. Any other finding is a real regression in this work — the pre-existing baseline was clean.

- [ ] **Step 5: Re-confirm the manual checks in one pass**

Not automatable, and each has burned this repo before:

- `$Mod SHIFT+C` → pick a colour → `wl-paste` shows the hex, **and a screenshot of the toast shows a rendered icon**
- `$Mod SHIFT+C` → ESC → no toast at all
- `$Mod ALT+S` → swappy opens → save → the file is in `~/Pictures/Screenshots`
- `$Mod, S` → still writes straight to disk with no swappy
- `$Mod SHIFT+S` → five entries on one row; the fourth annotates, the fifth opens settings
- the bar shows `󰚰 N` between disk and network with a `N repo · M AUR` tooltip

- [ ] **Step 6: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: record the three unwired tools now being wired"
```

- [ ] **Step 7: Report, do not push**

`main` and this branch are not to be pushed — the user pushes themselves. Report the branch name, the commits, and the output of `./test.sh` and `./doctor.sh` as evidence.

```json:metadata
{"files": ["CHANGELOG.md"], "verifyCommand": "./test.sh && ./doctor.sh && git status --short", "acceptanceCriteria": ["CHANGELOG has an Added entry per slice", "./test.sh passes every suite", "./doctor.sh 0 errors 0 warnings exit 0", "git status clean and all four new scripts mode 100755", "nothing pushed"]}
```

---

## Notes for the implementer

- **Do not push.** The user pushes this repo themselves.
- **Never hand-edit a cheatsheet row.** `rofi/keybinds-cheatsheet.sh` renders from `keybinds.conf` at runtime; the trailing `#` comment on a bind is its label.
- **`ok` in the doctor means all-clear**, never a consolation summary — but no doctor edits are needed here at all.
- **A subagent's test output is evidence submitted, not evidence accepted.** Re-run `./test.sh` and `./doctor.sh` yourself before calling any task done.
