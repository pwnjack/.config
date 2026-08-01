# Hardware Truth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace three configs written for hardware this desktop does not have with one module that reports every battery the machine actually has.

**Architecture:** A single bash script scans `/sys/class/power_supply/*/uevent` and emits waybar JSON. `POWER_SUPPLY_SCOPE` selects behaviour rather than filtering: peripherals stay hidden until low, system batteries are always shown. Three dead surfaces are deleted alongside it — waybar's built-in `battery` module, swaync's `backlight` widget, and the two `XF86MonBrightness*` keybinds.

**Tech Stack:** bash, jq, waybar 0.15.0, swaync 0.12.6, GTK CSS, Nerd Font (Material Design range).

**Spec:** `docs/superpowers/specs/2026-08-01-hardware-truth-design.md`

---

## File Structure

| File | Responsibility |
|---|---|
| `scripts/waybar/battery.sh` | **Create.** The whole module: scan, classify, render JSON. One script, one consumer, no sourced lib. |
| `scripts/waybar/test-battery.sh` | **Create.** Fixture-driven tests. Executes the script as a subprocess, because that is how waybar runs it. |
| `waybar/config.jsonc` | **Modify.** Add `custom/battery`; delete the built-in `battery` module and its entry in `modules-right`. |
| `waybar/style.css` | **Modify.** Add `.low`/`.critical` rules; remove `#battery` from three grouped selectors; regroup `#bluetooth` and `#custom-battery` as self-contained; update the header's group map. |
| `swaync/config.json` | **Modify.** Delete the `backlight` widget entry and its `widget-config` block. |
| `hypr/config/software/keybinds.conf` | **Modify.** Delete both `XF86MonBrightness*` binds. |
| `CHANGELOG.md`, `CLAUDE.md` | **Modify.** Record the change; document the new script. |

---

### Task 1: The battery module and its tests

**Goal:** A script that turns sysfs into waybar JSON, with a test suite covering every boundary the spec names.

**Files:**
- Create: `scripts/waybar/battery.sh`
- Create: `scripts/waybar/test-battery.sh`

**Acceptance Criteria:**
- [ ] A peripheral at 76% produces no output and exit status 0
- [ ] A peripheral at 24% produces JSON with `class: low`; at 9%, `class: critical`; at exactly 25%, no output; at exactly 10%, `class: low`
- [ ] A peripheral with `POWER_SUPPLY_ONLINE=0` is ignored at every capacity, and absent from the tooltip
- [ ] A system battery is present in `text` at every capacity, including 100%
- [ ] A system battery with no `ONLINE` attribute is not skipped
- [ ] A system battery at 8% with `STATUS=Charging` yields `class: ok`; discharging at 8% yields `critical`
- [ ] With both kinds present, `text` shows the system battery first, then any low peripheral
- [ ] A non-numeric `CAPACITY` is skipped with no stderr output
- [ ] A model name containing `&` appears escaped as `&amp;` in the tooltip
- [ ] `shellcheck -S warning` reports nothing on either file

**Verify:** `./scripts/waybar/test-battery.sh` → final line ends `0 failed`, exit status 0

**Steps:**

- [ ] **Step 1: Write the test file first**

Create `scripts/waybar/test-battery.sh`:

```bash
#!/bin/bash
#
# Tests for scripts/waybar/battery.sh.
#
# Standalone and runnable on its own, exit 1 on any failure. It executes the
# script under test as a subprocess, because that is exactly how waybar runs
# it -- unlike scripts/doctor/test/test-*.sh, which are sourced fragments
# sharing one shell so that severity counters survive. Chunk D decides whether
# the two styles get one runner.
#
# jq is used to read fields back out. That is not a new dependency: battery.sh
# already requires it to emit the JSON in the first place.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATTERY="$TEST_DIR/battery.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASSED=0
FAILED=0

# fixture — a fresh empty sysfs root
fixture() {
    mktemp -d "$TMP/sysfs.XXXXXX"
}

# supply <root> <name> <KEY=VALUE>...
supply() {
    local root=$1 name=$2
    shift 2
    mkdir -p "$root/$name"
    printf '%s\n' "$@" > "$root/$name/uevent"
}

# run <root> — stdout of the module under that sysfs root
run() {
    BATTERY_SYSFS="$1" bash "$BATTERY" 2>"$TMP/stderr"
}

pass() { PASSED=$((PASSED + 1)); echo "  ok   $1"; }
fail() {
    FAILED=$((FAILED + 1))
    echo "  FAIL $1"
    shift
    printf '       %s\n' "$@"
}

# assert_silent <output> <label>
assert_silent() {
    if [ -z "$1" ]; then pass "$2"; else fail "$2" "expected no output" "got: $1"; fi
}

# assert_field <output> <jq-filter> <expected> <label>
assert_field() {
    local actual
    actual=$(printf '%s' "$1" | jq -r "$2" 2>/dev/null)
    if [ "$actual" = "$3" ]; then
        pass "$4"
    else
        fail "$4" "filter:   $2" "expected: $3" "actual:   $actual" "json:     $1"
    fi
}

# assert_contains <output> <jq-filter> <needle> <label>
assert_contains() {
    local actual
    actual=$(printf '%s' "$1" | jq -r "$2" 2>/dev/null)
    if printf '%s' "$actual" | grep -qF -- "$3"; then
        pass "$4"
    else
        fail "$4" "expected to contain: $3" "actual: $actual"
    fi
}

echo "battery.sh"

# --- peripherals: the auto-hiding tier -------------------------------------

r=$(fixture)
supply "$r" hidpp_battery_0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_ONLINE=1" "POWER_SUPPLY_CAPACITY=76" \
    "POWER_SUPPLY_MODEL_NAME=G Pro Wireless Gaming Mouse"
assert_silent "$(run "$r")" "peripheral at 76% is silent"

r=$(fixture)
supply "$r" hidpp_battery_0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_ONLINE=1" "POWER_SUPPLY_CAPACITY=25" \
    "POWER_SUPPLY_MODEL_NAME=Mouse"
assert_silent "$(run "$r")" "peripheral at exactly 25% is silent (rule is < LOW)"

r=$(fixture)
supply "$r" hidpp_battery_0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_ONLINE=1" "POWER_SUPPLY_CAPACITY=24" \
    "POWER_SUPPLY_MODEL_NAME=Mouse"
out=$(run "$r")
assert_field "$out" '.class' "low" "peripheral at 24% is low"
assert_contains "$out" '.text' "24%" "peripheral at 24% shows its level"

r=$(fixture)
supply "$r" hidpp_battery_0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_ONLINE=1" "POWER_SUPPLY_CAPACITY=10" \
    "POWER_SUPPLY_MODEL_NAME=Mouse"
assert_field "$(run "$r")" '.class' "low" "peripheral at exactly 10% is low, not critical"

r=$(fixture)
supply "$r" hidpp_battery_0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_ONLINE=1" "POWER_SUPPLY_CAPACITY=9" \
    "POWER_SUPPLY_MODEL_NAME=Mouse"
assert_field "$(run "$r")" '.class' "critical" "peripheral at 9% is critical"

# --- the powered-off case: the whole reason ONLINE is read -----------------

r=$(fixture)
supply "$r" hidpp_battery_0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_ONLINE=0" "POWER_SUPPLY_CAPACITY=9" \
    "POWER_SUPPLY_MODEL_NAME=Mouse"
assert_silent "$(run "$r")" "powered-off peripheral at 9% is ignored, not critical"

# --- system battery: the always-visible tier -------------------------------

r=$(fixture)
supply "$r" BAT0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=System" \
    "POWER_SUPPLY_CAPACITY=64" "POWER_SUPPLY_STATUS=Discharging" \
    "POWER_SUPPLY_MODEL_NAME=DELL ABC123"
out=$(run "$r")
assert_contains "$out" '.text' "64%" "system battery at 64% is shown"
assert_field "$out" '.class' "ok" "system battery at 64% is class ok"

r=$(fixture)
supply "$r" BAT0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_CAPACITY=100" \
    "POWER_SUPPLY_STATUS=Full" "POWER_SUPPLY_MODEL_NAME=DELL ABC123"
assert_contains "$(run "$r")" '.text' "100%" "system battery with no SCOPE and no ONLINE is shown"

r=$(fixture)
supply "$r" BAT0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=System" \
    "POWER_SUPPLY_CAPACITY=8" "POWER_SUPPLY_STATUS=Discharging" \
    "POWER_SUPPLY_MODEL_NAME=DELL ABC123"
assert_field "$(run "$r")" '.class' "critical" "system battery at 8% discharging is critical"

r=$(fixture)
supply "$r" BAT0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=System" \
    "POWER_SUPPLY_CAPACITY=8" "POWER_SUPPLY_STATUS=Charging" \
    "POWER_SUPPLY_MODEL_NAME=DELL ABC123"
out=$(run "$r")
assert_field "$out" '.class' "ok" "system battery at 8% charging is not an alert"
assert_contains "$out" '.text' "8%" "charging system battery still shows its level"

# --- both kinds present ----------------------------------------------------

r=$(fixture)
supply "$r" BAT0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=System" \
    "POWER_SUPPLY_CAPACITY=64" "POWER_SUPPLY_STATUS=Discharging" \
    "POWER_SUPPLY_MODEL_NAME=DELL ABC123"
supply "$r" hidpp_battery_0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_ONLINE=1" "POWER_SUPPLY_CAPACITY=18" \
    "POWER_SUPPLY_MODEL_NAME=G Pro Wireless Gaming Mouse"
out=$(run "$r")
assert_contains "$out" '.text' "64%" "system battery present in text"
assert_contains "$out" '.text' "18%" "low peripheral joins the text"
assert_field "$out" '.class' "low" "class comes from the most urgent entry"
assert_field "$out" '.text | test("64%.*18%")' "true" "system battery is rendered first"

r=$(fixture)
supply "$r" BAT0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=System" \
    "POWER_SUPPLY_CAPACITY=64" "POWER_SUPPLY_STATUS=Discharging" \
    "POWER_SUPPLY_MODEL_NAME=DELL ABC123"
supply "$r" hidpp_battery_0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_ONLINE=1" "POWER_SUPPLY_CAPACITY=80" \
    "POWER_SUPPLY_MODEL_NAME=G Pro Wireless Gaming Mouse"
out=$(run "$r")
assert_field "$out" '.text | test("80%")' "false" "healthy peripheral stays out of the text"
assert_contains "$out" '.tooltip' "80%" "healthy peripheral is still in the tooltip"

# --- nothing to report -----------------------------------------------------

r=$(fixture)
assert_silent "$(run "$r")" "empty sysfs is silent"

r=$(fixture)
supply "$r" AC \
    "POWER_SUPPLY_TYPE=Mains" "POWER_SUPPLY_ONLINE=1"
assert_silent "$(run "$r")" "a Mains supply is not a battery"

# --- parsing robustness ----------------------------------------------------

r=$(fixture)
supply "$r" weird \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_ONLINE=1" "POWER_SUPPLY_CAPACITY=" \
    "POWER_SUPPLY_MODEL_NAME=Broken"
out=$(run "$r")
assert_silent "$out" "empty capacity is skipped"
if [ -s "$TMP/stderr" ]; then
    fail "empty capacity produces no stderr" "stderr: $(cat "$TMP/stderr")"
else
    pass "empty capacity produces no stderr"
fi

r=$(fixture)
supply "$r" weird \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_ONLINE=1" "POWER_SUPPLY_CAPACITY=unknown" \
    "POWER_SUPPLY_MODEL_NAME=Broken"
assert_silent "$(run "$r")" "non-numeric capacity is skipped"

r=$(fixture)
supply "$r" hidpp_battery_0 \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_ONLINE=1" "POWER_SUPPLY_CAPACITY=18" \
    "POWER_SUPPLY_MODEL_NAME=Corsair HS80 & Mouse"
assert_contains "$(run "$r")" '.tooltip' "&amp;" "an ampersand in a model name is escaped"

# --- a real hidpp uevent, TYPE twice and all ------------------------------

r=$(fixture)
supply "$r" hidpp_battery_0 \
    "DEVTYPE=power_supply" "POWER_SUPPLY_NAME=hidpp_battery_0" \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_STATUS=Unknown" \
    "POWER_SUPPLY_ONLINE=1" "POWER_SUPPLY_VOLTAGE_NOW=3965000" \
    "POWER_SUPPLY_CAPACITY=18" "POWER_SUPPLY_TYPE=Battery" \
    "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_MODEL_NAME=G Pro Wireless Gaming Mouse" \
    "POWER_SUPPLY_MANUFACTURER=Logitech" "POWER_SUPPLY_SERIAL_NUMBER=5c-1c-d2-07"
out=$(run "$r")
assert_field "$out" '.class' "low" "a verbatim hidpp uevent parses"
assert_contains "$out" '.tooltip' "G Pro Wireless Gaming Mouse" "model name reaches the tooltip"

echo
echo "battery.sh: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
```

- [ ] **Step 2: Run the tests and watch them fail**

```bash
chmod +x scripts/waybar/test-battery.sh
./scripts/waybar/test-battery.sh
```

Expected: every assertion FAILs, because `battery.sh` does not exist yet. `bash: scripts/waybar/battery.sh: No such file or directory` on stderr, final line `battery.sh: 0 passed, NN failed`, exit status 1.

- [ ] **Step 3: Write the module**

Create `scripts/waybar/battery.sh`:

```bash
#!/bin/bash
#
# Battery status for waybar -- every battery on the machine, system or
# peripheral.
#
# waybar's own battery module counts only POWER_SUPPLY_SCOPE=System, which is
# why it logged "No batteries." on this desktop while a wireless mouse sat on
# the bus with a perfectly readable charge. This module reads sysfs directly.
#
# SCOPE selects behaviour rather than filtering:
#
#   Device            a peripheral. Silent until it drops below LOW, so it
#                     costs no permanent bar space. The module APPEARING is
#                     the warning -- that is what keeps this stateless, with
#                     nothing to remember and nothing to expire.
#   System or absent  the machine's own battery. Always shown, at every level,
#                     because a laptop battery is a status readout rather than
#                     an alert.
#
# A powered-off peripheral keeps its sysfs node AND its last capacity reading
# -- verified by switching the mouse off, which left CAPACITY=75 in place. The
# only field that told the truth was POWER_SUPPLY_ONLINE, which flipped 1 -> 0.
# The test is present-and-0 rather than "not 1": a laptop battery generally
# carries no ONLINE attribute at all (it lives on the Mains adapter) and must
# not be skipped by it.
#
# Charge state is honoured for system batteries only. This mouse reported
# Discharging and then Unknown minutes apart while sitting still, so a
# peripheral's STATUS is not evidence of anything. For a system battery it is
# reliable, and charging suppresses the alert classes -- which is what the old
# `#battery.critical:not(.charging)` rule encoded.
#
# BATTERY_SYSFS overrides the scan root; test-battery.sh points it at fixtures.
#

LOW=25
CRITICAL=10
SYSFS="${BATTERY_SYSFS:-/sys/class/power_supply}"

# Nerd Font, Material Design range.
ICON_SYSTEM=$'\U000f0079'    # battery
ICON_MOUSE=$'\U000f037d'     # mouse
ICON_KEYBOARD=$'\U000f030c'  # keyboard
ICON_HEADSET=$'\U000f02cb'   # headphones
ICON_DEVICE=$'\U000f0083'    # battery-alert, for a peripheral we cannot name

# Fields of the uevent currently being read.
u_type=""; u_cap=""; u_scope=""; u_online=""; u_model=""; u_status=""

# read_uevent <path> — parse one uevent into the u_* variables.
read_uevent() {
    local key val
    u_type=""; u_cap=""; u_scope=""; u_online=""; u_model=""; u_status=""
    while IFS='=' read -r key val; do
        case "$key" in
            # TYPE appears twice in a hidpp uevent. Keep the first.
            POWER_SUPPLY_TYPE)       [ -n "$u_type" ] || u_type="$val" ;;
            POWER_SUPPLY_CAPACITY)   u_cap="$val" ;;
            POWER_SUPPLY_SCOPE)      u_scope="$val" ;;
            POWER_SUPPLY_ONLINE)     u_online="$val" ;;
            POWER_SUPPLY_MODEL_NAME) u_model="$val" ;;
            POWER_SUPPLY_STATUS)     u_status="$val" ;;
        esac
    done < "$1"
}

# device_icon <model> — a glyph from the vendor string, which is all sysfs
# gives us. upower knows the real device type, but costs a daemon and a D-Bus
# round trip per device per poll; an unmatched device gets a generic battery
# glyph, which is unspecific rather than wrong.
device_icon() {
    case "${1,,}" in
        *mouse*)               printf '%s' "$ICON_MOUSE" ;;
        *keyboard*|*keypad*)   printf '%s' "$ICON_KEYBOARD" ;;
        *headset*|*headphone*) printf '%s' "$ICON_HEADSET" ;;
        *)                     printf '%s' "$ICON_DEVICE" ;;
    esac
}

# entry <icon> <capacity> — one rendered chunk of the bar text. The glyph is
# promoted a fifth to match the bar scale (13px base); see waybar/style.css.
# Two spaces, not one: like the volume glyph, a battery glyph carries ink to
# the right and the wider spacer is what makes it look equal to its neighbours.
entry() {
    printf '<span size="large">%s</span>  %s%%' "$1" "$2"
}

system_text=""
system_worst=101      # capacity driving the class; 101 means "not alerting"
low_worst=101
declare -a low_text=()
declare -a tips=()

shopt -s nullglob
for uevent in "$SYSFS"/*/uevent; do
    [ -r "$uevent" ] || continue
    read_uevent "$uevent"

    [ "$u_type" = "Battery" ] || continue

    # A missing or non-numeric capacity would make the arithmetic tests below
    # throw into waybar's log once every interval.
    case "$u_cap" in ''|*[!0-9]*) continue ;; esac

    # Present-and-0 only. See the header.
    [ "$u_online" = "0" ] && continue

    dir="${uevent%/uevent}"
    label="${u_model:-${dir##*/}}"

    if [ "$u_scope" = "Device" ]; then
        tips+=("$label  $u_cap%")
        if [ "$u_cap" -lt "$LOW" ]; then
            low_text+=("$(entry "$(device_icon "$u_model")" "$u_cap")")
            [ "$u_cap" -lt "$low_worst" ] && low_worst="$u_cap"
        fi
    else
        system_text="$(entry "$ICON_SYSTEM" "$u_cap")"
        case "$u_status" in
            Charging|Full)
                tips+=("$label  $u_cap% ($u_status)")
                ;;
            *)
                tips+=("$label  $u_cap%")
                # Only a discharging system battery can raise an alert.
                system_worst="$u_cap"
                ;;
        esac
    fi
done
shopt -u nullglob

parts=()
[ -n "$system_text" ] && parts+=("$system_text")
[ "${#low_text[@]}" -gt 0 ] && parts+=("${low_text[@]}")

# Nothing worth saying: print nothing and let waybar hide the module, the same
# idiom custom/media uses.
[ "${#parts[@]}" -eq 0 ] && exit 0

worst=101
[ "$system_worst" -lt "$worst" ] && worst="$system_worst"
[ "$low_worst" -lt "$worst" ] && worst="$low_worst"

if [ "$worst" -lt "$CRITICAL" ]; then
    class="critical"
elif [ "$worst" -lt "$LOW" ]; then
    class="low"
else
    class="ok"
fi

text=""
for part in "${parts[@]}"; do
    [ -n "$text" ] && text+="  "
    text+="$part"
done

tooltip=""
for tip in "${tips[@]}"; do
    [ -n "$tooltip" ] && tooltip+=$'\n'
    tooltip+="$tip"
done

# `text` is ours: glyphs and digits, no vendor string, so its markup is safe.
# `tooltip` carries model names, which are arbitrary vendor text -- "Corsair
# HS80 & Mouse" is malformed Pango and would blank the tooltip. Escape it.
jq -nc --arg text "$text" --arg tooltip "$tooltip" --arg class "$class" '
    def pango: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
    {text: $text, tooltip: ($tooltip | pango), class: $class}'
```

- [ ] **Step 4: Run the tests until green**

```bash
chmod +x scripts/waybar/battery.sh
./scripts/waybar/test-battery.sh
```

Expected: a final line reading `battery.sh: NN passed, 0 failed` and exit status 0. What matters is `0 failed` — do not tune the code until a hardcoded pass count matches.

- [ ] **Step 5: Check it against real hardware**

```bash
./scripts/waybar/battery.sh; echo "exit=$?"
```

Expected with the mouse switched **on** and above 25%: no output, `exit=0`.
Then switch the mouse off and run again — still no output, and confirm the stale reading is really there with `grep -E 'ONLINE|CAPACITY' /sys/class/power_supply/hidpp_battery_0/uevent`, which should show `ONLINE=0` alongside a non-zero capacity. That combination is the bug this module avoids.

To see it render, force a low threshold rather than draining the mouse:

```bash
sed 's/^LOW=25/LOW=99/' scripts/waybar/battery.sh > /tmp/bat-preview.sh
bash /tmp/bat-preview.sh | jq .
```

Expected: JSON whose `text` contains the mouse glyph and the real percentage, `class: "low"`, and a tooltip naming `G Pro Wireless Gaming Mouse`.

- [ ] **Step 6: Lint**

```bash
shellcheck -S warning scripts/waybar/battery.sh scripts/waybar/test-battery.sh
```

Expected: no output. (`-S warning` is the level the pre-commit hook enforces; info-level SC1091/SC2162 do not fail it.)

- [ ] **Step 7: Commit**

```bash
git add scripts/waybar/battery.sh scripts/waybar/test-battery.sh
git commit -m "feat(waybar): report every battery, system or peripheral

waybar's battery module counts only SCOPE=System, so this desktop logged
'No batteries.' while the mouse sat on the bus at 76%. This module reads
sysfs directly and lets SCOPE select behaviour instead of filtering:
peripherals stay hidden until they are low, system batteries are always
shown.

A powered-off peripheral keeps both its node and its last reading, so
ONLINE is the only trustworthy field; present-and-0 is skipped, while a
missing ONLINE (a laptop battery, where it lives on the Mains adapter) is
not."
```

---

### Task 2: Wire it into the bar

**Goal:** `custom/battery` renders in waybar with correct colours and spacing, and the built-in `battery` module is gone.

**Files:**
- Modify: `waybar/config.jsonc` — `modules-right` array, `"battery"` block at ~line 225
- Modify: `waybar/style.css` — header map ~line 28, grouped selectors ~88/~121/~145, self-contained group ~157, battery section ~263

**Acceptance Criteria:**
- [ ] `grep -c '"battery"' waybar/config.jsonc` returns 0
- [ ] `grep -c '#battery' waybar/style.css` returns 0
- [ ] waybar starts with no `No batteries.` warning and no CSS parse error in its log
- [ ] `#bluetooth` and `#custom-battery` both carry `padding-left: 15px; padding-right: 15px`
- [ ] The header's group map reads `... | net | bt | [bat] | vol | ...`

**Verify:** `killall waybar; waybar > /tmp/wb.log 2>&1 & sleep 3; grep -iE "batter|error|css" /tmp/wb.log` → no battery warning, no CSS error

**Steps:**

- [ ] **Step 1: Replace the module in `waybar/config.jsonc`**

In `modules-right`, replace the line `    "battery",` with `    "custom/battery",`.

Then delete this whole block:

```jsonc
  "battery": {
    "states": {
      "warning": 30,
      "critical": 15,
    },
    "format": "<span size='large'>{icon}</span>  {capacity}%",
    "format-charging": "<span size='large'></span>  {capacity}%",
    "format-plugged": "<span size='large'></span>  {capacity}%",
    "format-alt": "<span size='large'>{icon}</span>  {time}",
    "format-icons": ["", "", "", "", ""],
  },
```

and put this in its place:

```jsonc
  // Battery — every battery on the machine, system or peripheral.
  // The script decides what to show: peripherals stay hidden until they are
  // low, a system battery is always visible. Empty output hides the module,
  // the same idiom custom/media uses. Glyph and spacing live in the script
  // because the text is assembled there.
  "custom/battery": {
    "format": "{}",
    "return-type": "json",
    "interval": 60,
    "exec": "~/.config/scripts/waybar/battery.sh",
  },
```

- [ ] **Step 2: Remove `#battery` from the three grouped selectors in `waybar/style.css`**

In the `font-size: 14px` block (~line 88), the `background: transparent` block (~line 121), and the group-closing `padding-right: 15px` block (~line 145), delete the `#battery,` line. In the first two, add `#custom-battery,` in its place; in the group-closing block, do **not** — `#custom-battery` becomes self-contained instead.

- [ ] **Step 3: Make both modules self-contained groups**

Change the self-contained group block from:

```css
/* self-contained groups */
#workspaces,
#network,
#pulseaudio,
#tray {
    padding-left: 15px;
    padding-right: 15px;
}
```

to:

```css
/* self-contained groups.
   #bluetooth and #custom-battery are here rather than paired as a group
   because #custom-battery hides itself whenever there is nothing to report.
   A module that comes and goes cannot be load-bearing for a gap: with 15px
   on both sides of each, every neighbouring gap stays 30px whether the
   battery is showing or not. */
#workspaces,
#network,
#bluetooth,
#custom-battery,
#pulseaudio,
#tray {
    padding-left: 15px;
    padding-right: 15px;
}
```

Then delete `#bluetooth,` from the group-opening block (`#clock, #cpu, #bluetooth, #custom-nightlight { padding-left: 15px; }`), leaving `#clock, #cpu, #custom-nightlight`.

- [ ] **Step 4: Replace the battery colour rules**

Change:

```css
/* ── BATTERY ─────────────────────────────────────────────────────────*/

/* ALERT EXCEPTION — see #pulseaudio.muted above. */
#battery.critical:not(.charging) {
    color: #ff5555;
}
```

to:

```css
/* ── BATTERY ─────────────────────────────────────────────────────────*/

/* class: ok deliberately has no rule — it inherits @foreground from the
   grouped selector above, so a healthy battery looks like every other
   readout on the bar.

   The script never emits an alert class for a charging system battery, so
   the old :not(.charging) qualifier has no counterpart here. */

#custom-battery.low {
    color: @color3;
}

/* ALERT EXCEPTION — see #pulseaudio.muted above. */
#custom-battery.critical {
    color: #ff5555;
}
```

- [ ] **Step 5: Update the header's group map and prose**

In the header comment, change the group map line to:

```
     right    cpu·mem·gpu·disk | net | bt | [bat] | vol | tray | night·set·notif·power
```

and replace the paragraph beginning "network, volume and tray stand alone." with:

```
   network, volume, bluetooth, battery and tray stand alone. Volume is a
   control rather than a status readout. Bluetooth and battery stand alone
   because battery hides itself whenever there is nothing to report — a
   module that comes and goes cannot be load-bearing for a gap, so each
   carries its own 15px on both sides and the rhythm holds either way.
```

Also add `battery` to the `gap-glyph` note listing the two-space cases, so it reads `~14px   volume, battery -- two spaces.`

- [ ] **Step 6: Verify in the running bar**

```bash
killall waybar; sleep 1
setsid waybar > /tmp/wb.log 2>&1 < /dev/null &
sleep 3
grep -iE "batter|error|css" /tmp/wb.log
```

Expected: no `No batteries.` line, no CSS parse error. The module is invisible because the mouse is healthy — that is correct behaviour.

Force it visible and screenshot to check glyph spacing and that gaps did not move. **Do this via `BATTERY_SYSFS`, never by editing the config** — waybar passes its environment to module scripts, so a fixture root makes the module render without touching a single tracked file:

```bash
# a fake sysfs with a nearly-flat mouse
FIX=$(mktemp -d)
mkdir -p "$FIX/hidpp_battery_0"
printf '%s\n' \
    "POWER_SUPPLY_TYPE=Battery" "POWER_SUPPLY_SCOPE=Device" \
    "POWER_SUPPLY_ONLINE=1" "POWER_SUPPLY_CAPACITY=18" \
    "POWER_SUPPLY_MODEL_NAME=G Pro Wireless Gaming Mouse" \
    > "$FIX/hidpp_battery_0/uevent"

# before-shot, module hidden
killall waybar; sleep 1; setsid waybar > /tmp/wb-hidden.log 2>&1 < /dev/null & sleep 3
grim -g "1700,0 860x46" /tmp/bar-hidden.png

# after-shot, module forced visible
killall waybar; sleep 1
BATTERY_SYSFS="$FIX" setsid waybar > /tmp/wb-shown.log 2>&1 < /dev/null & sleep 3
grim -g "1700,0 860x46" /tmp/bar-shown.png
magick /tmp/bar-shown.png -filter point -resize 300% /tmp/bar-shown-zoom.png

# back to reality — no file was ever edited, so just restart plain
killall waybar; sleep 1; setsid waybar > /tmp/wb.log 2>&1 < /dev/null &
rm -rf "$FIX"
```

Read `/tmp/bar-shown-zoom.png` and confirm: the glyph reads as a mouse, the gap between glyph and digits matches `pulseaudio`'s, and `class: low` colour is applied. Then compare against `/tmp/bar-hidden.png` and confirm every *other* module sits at the same x-position in both — that is the self-contained-grouping claim from Step 3, and it is the one thing a screenshot can prove that a test cannot.

- [ ] **Step 7: Commit**

```bash
git add waybar/config.jsonc waybar/style.css
git commit -m "feat(waybar): swap the dead battery module for custom/battery

The built-in module counted only SCOPE=System and rendered nothing on this
desktop. custom/battery replaces it and reports peripherals too.

bluetooth and battery become self-contained 15px groups rather than a pair:
the new module hides itself when there is nothing to report, and a module
that comes and goes cannot be load-bearing for a gap."
```

---

### Task 3: Delete the other two dead surfaces

**Goal:** swaync stops configuring a backlight it cannot find, and the two brightness keybinds stop pretending.

**Files:**
- Modify: `swaync/config.json` — `widgets` array (~line 39), `widget-config.backlight` (~line 56)
- Modify: `hypr/config/software/keybinds.conf:144-145`

**Acceptance Criteria:**
- [ ] `grep -c backlight swaync/config.json` returns 0
- [ ] `jq . swaync/config.json` parses without error
- [ ] The swaync control center looks identical to before (the widget was never rendered)
- [ ] `grep -c XF86MonBrightness hypr/config/software/keybinds.conf` returns 0
- [ ] `./rofi/keybinds-cheatsheet.sh --print` no longer lists "Brightness up"/"Brightness down"

**Verify:** `jq -e '.widgets | index("backlight") == null' swaync/config.json && ! grep -q XF86MonBrightness hypr/config/software/keybinds.conf && echo OK` → `true` then `OK`

**Steps:**

- [ ] **Step 1: Capture a before-shot of the sidebar**

```bash
swaync-client -t; sleep 2
grim -g "1900,40 660x900" /tmp/swaync-before.png
swaync-client -t
```

- [ ] **Step 2: Remove the widget from `swaync/config.json`**

Delete `"backlight",` from the `widgets` array, leaving:

```json
  "widgets": [
    "label",
    "mpris",
    "volume",
    "dnd",
    "notifications"
  ],
```

and delete this block from `widget-config`:

```json
    "backlight": {
      "label": " 󰃞   ",
      "step": 5
    },
```

- [ ] **Step 3: Confirm the JSON still parses and nothing moved**

```bash
jq . swaync/config.json > /dev/null && echo "parses"
killall swaync; sleep 1; setsid swaync > /tmp/swaync.log 2>&1 < /dev/null & sleep 2
swaync-client -t; sleep 2
grim -g "1900,40 660x900" /tmp/swaync-after.png
swaync-client -t
magick compare -metric AE /tmp/swaync-before.png /tmp/swaync-after.png null: 2>&1 || true
```

Expected: `parses`, and the two screenshots differ only in the clock/notification content — the widget stack (media, volume, DND, notifications) is unchanged, because swaync was already dropping the backlight widget silently.

- [ ] **Step 4: Delete the two keybinds**

Remove these two lines from `hypr/config/software/keybinds.conf` (currently 144–145), **including the blank line that separated them** from the audio binds above, so the Media Keys block does not gain a double gap:

```
bindel = ,XF86MonBrightnessUp, exec, brightnessctl s 10%+     # Brightness up
bindel = ,XF86MonBrightnessDown, exec, brightnessctl s 10%-   # Brightness down
```

- [ ] **Step 5: Confirm the cheatsheet drops them by itself**

```bash
hyprctl reload
./rofi/keybinds-cheatsheet.sh --print | grep -i brightness || echo "gone from the cheatsheet"
```

Expected: `gone from the cheatsheet`. Nothing in `rofi/` is edited — it renders from `keybinds.conf`.

- [ ] **Step 6: Commit**

```bash
git add swaync/config.json hypr/config/software/keybinds.conf
git commit -m "fix: stop configuring a backlight this machine does not have

/sys/class/backlight is empty. swaync was silently dropping its backlight
widget, and the two XF86MonBrightness binds called brightnessctl, whose
only devices here are the capslock, scrolllock and compose LEDs.

The binds leave the Super+H cheatsheet on their own — it renders from
keybinds.conf."
```

---

### Task 4: Document it, and verify every surface

**Goal:** The change is recorded where the repo records changes, and every surface it touched has been looked at.

**USER-ORDERED GATE — NON-SKIPPABLE.** This task was requested by the user in the current conversation. It MUST NOT be closed by walking around it, by declaring it "verified inline", or by substituting a cheaper check. Close only after every item in `acceptanceCriteria` has been re-validated independently, with output captured.

**Files:**
- Modify: `CHANGELOG.md` — new dated section at the top
- Modify: `CLAUDE.md` — the `scripts/` bullet list, and the options/preferences prose if it mentions brightness

**Acceptance Criteria:**
- [ ] `./scripts/waybar/test-battery.sh` exits 0 with 0 failures
- [ ] `./doctor.sh` exits 0 with no new ERROR or WARN findings
- [ ] `shellcheck -S warning` clean on both new scripts
- [ ] waybar log contains no `No batteries.` and no CSS error
- [ ] A screenshot of the bar with the module forced visible has been captured and inspected
- [ ] A screenshot of the swaync control center has been captured and compared against the before-shot
- [ ] `CHANGELOG.md` has a `## [2026-08-01]` section describing the module and the three deletions
- [ ] `CLAUDE.md` documents `scripts/waybar/battery.sh` and its `SCOPE`-selects-behaviour rule

**Verify:** `./scripts/waybar/test-battery.sh && ./doctor.sh && shellcheck -S warning scripts/waybar/battery.sh scripts/waybar/test-battery.sh && echo ALL GREEN` → `ALL GREEN`

**Steps:**

- [ ] **Step 1: Add the CHANGELOG entry**

Insert directly below the `All notable changes to this dotfiles repository.` line:

```markdown
## [2026-08-01] - Hardware Truth

### Added
- **`scripts/waybar/battery.sh`** + `custom/battery`: reports every battery on
  the machine by reading `/sys/class/power_supply` directly. waybar's own
  module counts only `SCOPE=System`, so this desktop logged `No batteries.`
  while a wireless mouse sat on the bus at 76%. `SCOPE` now selects behaviour
  instead of filtering — peripherals stay hidden until they drop below 25%, a
  system battery is always visible at every level.
- **`scripts/waybar/test-battery.sh`**: fixture-driven tests over a fake sysfs
  root (`BATTERY_SYSFS`), so the suite needs neither hardware nor root.

### Removed
- **waybar's built-in `battery` module**, its CSS, and `#battery.critical:not(.charging)`.
- **swaync's `backlight` widget.** `/sys/class/backlight` is empty; swaync was
  dropping the widget silently.
- **Both `XF86MonBrightness*` keybinds.** `brightnessctl`'s only devices on this
  machine are the capslock, scrolllock and compose LEDs.

### Notes
- **A powered-off peripheral keeps its node and its last reading.** Switching
  the mouse off left `CAPACITY=75` in place; only `POWER_SUPPLY_ONLINE` flipped
  `1 → 0`. The scan skips present-and-`0`, not "not 1" — a laptop battery
  usually has no `ONLINE` attribute at all, since it lives on the Mains adapter.
- **Charge state is trusted for system batteries only.** The mouse reported
  `Discharging` and then `Unknown` minutes apart while sitting still. For a
  system battery `STATUS` is reliable, and charging suppresses the alert
  classes — what the deleted `:not(.charging)` rule encoded.
- **swaync cannot host a live readout.** Its only text widget, `label`, takes a
  static string from `config.json`; there is no command-execution widget in
  0.12.6.
- `bluetooth` and `battery` became self-contained 15px groups. A module that
  hides itself cannot be load-bearing for a gap.
```

- [ ] **Step 2: Update `CLAUDE.md`**

Change the `hyprland/` sibling bullet under **Scripts** so the `waybar/` line reads:

```markdown
- `waybar/` — Bar management and toggling, plus `battery.sh`: the battery module for the whole machine. It reads `/sys/class/power_supply` directly because waybar's own module counts only `SCOPE=System`. `SCOPE` selects behaviour rather than filtering — `Device` peripherals stay hidden until they fall below 25% (the module appearing is the warning, which is what keeps it stateless), while a system battery is always visible. A powered-off peripheral keeps its node *and* its last reading, so `POWER_SUPPLY_ONLINE` present-and-`0` is the skip test; a laptop battery has no `ONLINE` at all and must not be caught by it. `BATTERY_SYSFS` overrides the scan root for `test-battery.sh`.
```

- [ ] **Step 3: Run the full verification sweep and capture the output**

```bash
./scripts/waybar/test-battery.sh
./doctor.sh; echo "doctor exit=$?"
shellcheck -S warning scripts/waybar/battery.sh scripts/waybar/test-battery.sh && echo "shellcheck clean"
killall waybar; sleep 1; setsid waybar > /tmp/wb-final.log 2>&1 < /dev/null & sleep 3
grep -iE "batter|error|css" /tmp/wb-final.log || echo "waybar log clean"
```

Expected: tests `0 failed`; `doctor exit=0` with `0 errors, 0 warnings`; `shellcheck clean`; `waybar log clean`.

- [ ] **Step 4: Capture both screenshots and look at them**

Re-run the `BATTERY_SYSFS` fixture capture from Task 2 Step 6 (it edits no files), and re-capture the swaync sidebar as in Task 3 Step 1. Read both images. Confirm the bar's other modules sit at the same x-positions with the battery shown and hidden, and that the sidebar lost nothing visible.

This step is the gate. "The tests pass" is not evidence about the bar — the media module passed its own reasoning twice today and was still wrong on screen both times.

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md CLAUDE.md
git commit -m "docs: record the hardware-truth change

Three configs for hardware this desktop does not have, replaced by one
module that reports the battery it actually has."
```

---

## Amendments after code review

**The Task 1 code block above has a bug. Do not copy it verbatim without applying this.**

Found by the quality review of commit `8d9ac90`, reproduced directly:

```
BAT0 5% Discharging, BAT1 90% Discharging
→ {"text": "…90%", "tooltip": "BAT0 …5%\nBAT1 …90%", "class": "ok"}
```

The non-`Device` branch assigns `system_text` and `system_worst` on every matching uevent instead of accumulating, so the last system battery scanned wins and can mask a critical one. Dual-battery laptops are common, and the spec names laptop hosts as a target — so this is a real gap, not a theoretical one.

Fixes applied on top of the code block:

1. System batteries accumulate into an array like peripherals do. Every system battery gets its own entry in `text`; the alert class takes the **minimum** across discharging ones. Ordering is unchanged (system batteries first, then low peripherals), and charging batteries still contribute text while being excluded from the class.
2. The `worst=101` sentinel is replaced by an empty-string sentinel. The capacity guard only checks all-digits, so a malformed `CAPACITY=101` was indistinguishable from "nothing is alerting" and could have suppressed a real alert.
3. Two tests added: "two low peripherals → both in text, class from the lower" (promised by the spec's Testing section and never written), and a regression test for the masking bug above.
4. `parts=()` made consistent with the `declare -a` form used by its siblings.

## Notes for the implementer

- **The pre-commit hook runs `shellcheck -S warning` on staged `*.sh`.** Both new files are staged in Task 1, so a warning there blocks that commit. Info-level findings (SC1091, SC2162) do not.
- **Do not hand-edit `rofi/keybinds-cheatsheet.sh`.** It renders from `keybinds.conf` at runtime; deleting a bind is the whole edit.
- **`waybar/style.css` says "Change the grouped selector, never one module alone."** Task 2 respects that: `#battery` leaves three grouped selectors and `#custom-battery` joins two of them.
- **There is uncommitted work on this branch** from earlier in the session (the media module, the hyprlock `--plain` fix, the night light pill removal). Do not fold it into these commits; stage paths explicitly, as every commit block above does.
- **The laptop paths cannot be exercised on this machine.** The fixtures cover them; no real system battery exists here. Do not "verify" them against hardware and claim success.
