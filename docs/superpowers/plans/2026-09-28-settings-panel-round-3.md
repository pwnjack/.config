# Settings Panel Round 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Network page (Wi-Fi list with connect and forget, wired status, VPN up/down including Proton VPN), a Date & Region page (time zone, NTP, 12/24 h clock, language and formats), and real startup-app management, without adding any cost to the idle system.

**Architecture:**
- **Network** is a custom view (`NetworkView.qml`) fed by an `op:"read"` flag, `network: true`. The GJS backend reads NetworkManager through libnm in `nm.js`, which is the only file importing `gi://NM`. The pure shaping and validation logic lives in `network.mjs`.
- **Live Network updates** run only while that page is shown. `nmcli monitor` is the event source, a 20 s rescan timer requests scans, and re-reads are debounced.
- **Date & Region** is ordinary catalog rows on a `region` source. Reads come from files first, then D-Bus. Privileged writes go through `dbus.js` with interactive polkit. While a prompt is open, the panel releases keyboard focus (and hides, if Task 1 says so).
- **12/24 h** is `options/clock`, rendered into a Waybar `include` under `~/.local/state` and read directly by hyprlock.
- **Startup** is a custom view over the XDG autostart set that uwsm's systemd generator already launches. Its pure rules live in `autostart.mjs`. Every write request now reaches the helper on stdin, so a Wi-Fi password never sits in a process's argv.

**Tech Stack:** GJS (`gi://NM` libnm 1.58, `gi://Gio`, `gi://GLib`), Quickshell/QML (Qt 6, `Quickshell.Io`), ES modules (`.mjs`, importable by GJS, QML and Node), bash, Node for backend unit tests (`node:assert`), `qmltestrunner` for UI tests, `nmcli`, systemd `timedate1`/`locale1` over D-Bus, polkit (`hyprpolkitagent`), `systemctl --user`.

**Spec:** `docs/superpowers/specs/2026-09-28-settings-panel-round-3-design.md`. Read it first. It lists the verified facts every task relies on.

---

## Context the engineer needs

- **Branch:** `settings-panel-round-3` already exists. The spec is committed on it, and round 2 is at `ee1ab1d`, which is the review base in Task 11.
- **Run all tests:** `./test.sh` from `~/.config`. The panel suite is `quickshell/settings-panel/test/run-tests.sh`:
  - QML tests (`tst_Settings.qml`)
  - `test-persist.sh`, `backend.mjs`, `displays.mjs`, `monitor-lua.mjs`
  - added this round: `test-request-stdin.sh`, `network.mjs`, `autostart.mjs`

  `backend.mjs` runs the real `backend.js` against in-memory mocks that a `registerHooks` resolve hook injects: `gi://GLib`, `gi://Gio`, `./process.js`, and from this round `./nm.js` and `./dbus.js`. **Every backend change gets a case in `backend.mjs`.**
- **Talk to the real backend without the UI:** `bash scripts/settings/panel-request.sh '<json>'`. Reads are side-effect free. From Task 2 on, `panel-request.sh -` reads one JSON line from stdin.
- **Drive the panel from a shell:** `qs -p ~/.config/quickshell/settings-panel/shell.qml ipc call settings status`, and `… ipc call settings page network`.
- **The pre-commit hook** runs shellcheck plus the suites that own the staged paths. Never bypass it.
- **Nothing may become a second source of truth** (see `CLAUDE.md` → Conventions). The catalog is the only list of settings. Session commands are parsed from `autostart.lua`, XDG entries are read from their directories, and locales and zones come from the system.
- **Performance is the first priority.** Nothing new may run while the panel is closed. `nmcli monitor` and the rescan timer run only while the Network page is on screen, and Task 11 measures this.
- **Measured on this machine:**
  - `NM.Client.new(null)`: 7.5 ms
  - `nmcli` reads: about 8 ms
  - `timedatectl show` plus `localectl status`, cold: about 100 ms (both daemons are socket-activated)
  - A full panel read: 286 ms (round 2's figure; re-measured in Task 1)
- **The machine:** `eno1` is wired and up. `wlan0` is disconnected, with no saved Wi-Fi connection and several visible networks. The Proton VPN WireGuard connection `ProtonVPN IT#113` is active, along with the `dummy` kill-switch connection `pvpn-killswitch-ipv6`.
- **Before any synthetic input or screenshot of the panel**, check the session isn't locked: `pgrep -x hyprlock` must print nothing.
- **Glyphs:** in shell scripts, write glyphs as `$'\uXXXX'` escapes. In QML, use `String.fromCodePoint(0xF0920)`. Never paste a glyph. Nerd Font private-use characters vanish when retyped.
- **Never suggest interactive `sudo` in a terminal** (it trips `pam_faillock`). This round needs no sudo at all.
- **Scratch files** go in `/tmp/claude-1000/` (create it with `mkdir -p`).

## What is deliberately NOT in this plan

- Hidden SSIDs, 802.1X/enterprise Wi-Fi, WEP, hotspot, and DNS/IP editing. **Advanced…** opens `nm-connection-editor` instead.
- Creating or importing VPN profiles.
- Setting the time manually, RTC in local time, and hostname.
- Generating locales, keyboard layouts.
- Starting or stopping an autostart app immediately.
- Moving `startup.sh`'s Proton VPN toggle to XDG autostart.
- Icons in the Startup list. `qmltestrunner` cannot load `Quickshell` for `Quickshell.iconPath`.

## File map

| File | Responsibility | Tasks |
|---|---|---|
| `docs/settings-panel.md` | Round 3 probe results, Network/Region/Startup sections, measurements | 1, 11 |
| `scripts/settings/panel-request.sh`, `quickshell/settings-panel/request.js` | `-` reads the request from stdin | 2 |
| new `quickshell/settings-panel/test/test-request-stdin.sh` | stdin path test | 2 |
| new `quickshell/settings-panel/network.mjs`, `test/network.mjs` | Pure Wi-Fi/VPN shaping and validation | 3, 5 |
| new `quickshell/settings-panel/nm.js` | libnm adapter | 4 |
| `quickshell/settings-panel/backend.js` | `network`/`region` sources; `network`/`startup` read flags; new ops | 4, 6, 7, 9 |
| `quickshell/settings-panel/catalog.json` | `network` and `region` categories and rows | 4, 6, 7, 9 |
| `quickshell/settings-panel/shell.qml` | stdin writes, `network` live tag, rescan, `authPending`, page env, `open` IPC | 2, 5, 6, 9 |
| new `quickshell/settings-panel/NetworkView.qml` | Wi-Fi / Wired / VPN sections | 5 |
| `quickshell/settings-panel/SettingsView.qml` | Hosts the views, auth banner | 5, 6, 9 |
| `quickshell/settings-panel/SettingControl.qml` | `note` subtitle | 6 |
| `quickshell/settings-panel/PanelCombo.qml` | Filter field for long lists | 6 |
| new `quickshell/settings-panel/dbus.js`, `region.js` | System D-Bus calls, time and locale | 6 |
| `scripts/hyprland/settings-panel.sh`, `waybar/config.jsonc` | Page argument, network click, clock include | 5, 7 |
| new `options/clock`, `scripts/waybar/clock-format.sh`, `scripts/waybar/test-clock-format.sh` | 12/24 h | 7 |
| `hypr/hyprlock.conf`, `install.sh` | Clock consumers | 7 |
| new `quickshell/settings-panel/autostart.mjs`, `test/autostart.mjs` | Pure XDG autostart rules | 8 |
| new `quickshell/settings-panel/StartupView.qml` | Startup page | 9 |
| new `scripts/doctor/checks/autostart.sh`, `scripts/doctor/test/test-autostart.sh`; `doctor.sh` | Doctor check | 10 |
| `quickshell/settings-panel/test/run-tests.sh`, `test/backend.mjs`, `test/tst_Settings.qml` | Tests | 2–9 |
| `quickshell/settings-panel/test/live-smoke.sh`, `CLAUDE.md` | Smoke test, docs | 11 |

---

### Task 1: Probe the live behaviours and record the baseline

**Goal:** Settle the five design points that could not be checked passively (Proton up/down, the polkit dialog versus the overlay, per-user `locale.conf`, Waybar `include`, `nmcli monitor` output on scans), plus the stdin write from Quickshell, the cold D-Bus cost and the full-read baseline.

**Background:** Steps 6 and 7 need the user present. Step 6 briefly drops the Proton tunnel, and step 7 shows a password dialog the user must cancel. Ask before each one. Every other step is invisible or self-reverting.

**Files:**
- Modify: `docs/settings-panel.md` (new section `## Round 3: verified behaviour`, before `## Measurements`)

**Acceptance Criteria:**
- [ ] The median of five full reads is recorded as the round-3 baseline
- [ ] Cold and warm times for `NTP` + `ListTimezones` over D-Bus are recorded
- [ ] Whether `nmcli monitor` prints anything when a Wi-Fi scan completes is recorded, with the line count
- [ ] Whether a Quickshell `Process` with `stdinEnabled: true` delivers a line written in `onStarted` is recorded
- [ ] Whether Waybar 0.15 applies `clock.format` from an `include` given as `~/.local/state/…` when the main file omits it is recorded, with a screenshot path
- [ ] Whether a per-user `~/.config/locale.conf` would reach a uwsm session is recorded (expected: no)
- [ ] `PROTON_MODE` is decided as `"nm"` or `"app"`, with the observations that decided it
- [ ] `AUTH_HIDES_PANEL` is decided as `true` or `false`, with the observations, plus the exact D-Bus error text a cancelled prompt returns
- [ ] **If the interactive `SetTimezone` call never shows a dialog at all: stop and report to the user.** The Date & Region write design depends on it.

**Verify:** `sed -n '/^## Round 3: verified behaviour/,/^## Measurements/p' docs/settings-panel.md | grep -c '^### '` → `8`, and the section contains both `PROTON_MODE =` and `AUTH_HIDES_PANEL =`.

**Steps:**

- [ ] **Step 1: Baseline.** Close the panel, then run:

```bash
mkdir -p /tmp/claude-1000
req=$(jq -c '{op:"read",ids:[.rows[].id],monitors:true}' quickshell/settings-panel/catalog.json)
for i in 1 2 3 4 5; do s=$(date +%s%N); bash scripts/settings/panel-request.sh "$req" >/dev/null; echo $(( ($(date +%s%N)-s)/1000000 )) ms; done
```

- [ ] **Step 2: D-Bus cost.** timedated exits after about 30 s idle. Wait 40 s, then time the cold call, then time a warm one straight after:

```bash
sleep 40
for run in cold warm; do s=$(date +%s%N)
  gdbus call --system -d org.freedesktop.timedate1 -o /org/freedesktop/timedate1 -m org.freedesktop.DBus.Properties.Get org.freedesktop.timedate1 NTP >/dev/null
  gdbus call --system -d org.freedesktop.timedate1 -o /org/freedesktop/timedate1 -m org.freedesktop.timedate1.ListTimezones | wc -c
  echo "$run $(( ($(date +%s%N)-s)/1000000 )) ms"; done
```

- [ ] **Step 3: Does `nmcli monitor` report scans?**

```bash
out=/tmp/claude-1000/nm-monitor.txt; nmcli monitor > "$out" & pid=$!
sleep 1; nmcli device wifi rescan; sleep 8; kill $pid
wc -l < "$out"; cat "$out"
```

Record the count. If it is 0, Task 5's follow-up read after each scan (the `scanSettle` timer) is what refreshes the list. It is built either way.

- [ ] **Step 4: Quickshell stdin.** Write `/tmp/claude-1000/stdin-probe.qml`:

```qml
import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    Process {
        running: true
        stdinEnabled: true
        command: ["bash", "-c", "read -r line; printf 'got:%s\\n' \"$line\""]
        onStarted: write('{"op":"read"}\n')
        stdout: StdioCollector { onStreamFinished: { console.info("PROBE " + text.trim()); Qt.quit(); } }
    }
}
```

Run `timeout 5 qs -p /tmp/claude-1000/stdin-probe.qml 2>&1 | grep PROBE`. Expected: `PROBE got:{"op":"read"}`. If `onStarted` doesn't exist or nothing arrives, record it. Task 2 then writes the request right after `running = true`, and the probe is repeated with that form.

- [ ] **Step 5: Waybar include.** Write a probe include and a one-module probe bar:

```bash
mkdir -p ~/.local/state/waybar
printf '{ "clock": { "format": "PROBE {:%%I:%%M %%p}" } }\n' > ~/.local/state/waybar/clock-probe.jsonc
cat > /tmp/claude-1000/wb.jsonc <<'EOF'
{ "include": ["~/.local/state/waybar/clock-probe.jsonc"], "position": "bottom", "height": 30,
  "modules-center": ["clock"], "clock": { "tooltip": false } }
EOF
waybar -c /tmp/claude-1000/wb.jsonc -s ~/.config/waybar/style.css >/tmp/claude-1000/wb.log 2>&1 & pid=$!
sleep 2
h=$(hyprctl monitors -j | jq '.[0].height'); w=$(hyprctl monitors -j | jq '.[0].width')
grim -g "0,$((h - 40)) ${w}x40" /tmp/claude-1000/wb.png; kill $pid
rm ~/.local/state/waybar/clock-probe.jsonc
```

Read `/tmp/claude-1000/wb.png`. The clock must read `PROBE 08:26 PM`-style text. If it shows `20:26`, the include was ignored: repeat with the absolute path `/home/pwnjack/.local/state/…` to separate "no `~` expansion" from "no precedence", and record which. **If neither form works**, Task 7 switches to the spec's fallback (template `config.jsonc` into the cache like cava/starship). Record that decision.

- [ ] **Step 6: Proton VPN (ask the user first: "This drops the VPN for up to a minute. OK?").** Record every answer:

```bash
nmcli -t -f NAME,UUID,TYPE,ACTIVE connection show | grep -i proton        # before
curl -s -m 5 -o /dev/null -w '%{http_code}\n' https://1.1.1.1             # before: 200/301
nmcli connection down "ProtonVPN IT#113"
sleep 3
nmcli -t -f NAME,UUID,TYPE,ACTIVE connection show | grep -i proton        # does the profile survive?
ip -brief link | grep -E 'proton0|ipv6leak'
curl -s -m 5 -o /dev/null -w '%{http_code}\n' https://1.1.1.1             # does the kill switch block traffic?
```

Ask the user what the Proton window or tray now says (connected, disconnected, error). Then:

```bash
nmcli connection up "ProtonVPN IT#113"; sleep 5
nmcli -t -f NAME,ACTIVE connection show --active | grep -i proton
curl -s -m 5 -o /dev/null -w '%{http_code}\n' https://1.1.1.1
```

Ask again what the app shows. **If the profile is gone or `up` fails**, ask the user to reconnect from the Proton app before continuing.

Decision:
- `PROTON_MODE = "nm"` only if **all** of these hold:
  - the profile survives `down`;
  - traffic works while it's down (or is blocked only because the user's kill switch is set to "permanent", which is then the user's choice);
  - `up` works;
  - the app reflects both changes without an error.
- Otherwise it is `"app"`.

- [ ] **Step 7: Polkit dialog versus the overlay (ask the user first: "A password dialog will appear; please press Cancel, do not type your password.").**
  1. Write `/tmp/claude-1000/overlay-probe.qml`:

```qml
import QtQuick
import Quickshell
import Quickshell.Wayland
ShellRoot {
    PanelWindow {
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "settings-panel-probe"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        Rectangle { anchors.centerIn: parent; width: 1000; height: 740; radius: 24; color: "#05090c" }
    }
}
```

  2. Run `qs -p /tmp/claude-1000/overlay-probe.qml & probe=$!`.
  3. Then run:

```bash
gdbus call --system -d org.freedesktop.timedate1 -o /org/freedesktop/timedate1 \
  -m org.freedesktop.timedate1.SetTimezone "America/New_York" true 2>&1 | tee /tmp/claude-1000/polkit.txt &
sleep 3; grim /tmp/claude-1000/polkit.png
```

  The interactive flag is the call's second argument, `true`. A different zone is requested so timedated cannot short-circuit. The user **cancels**, so nothing changes.
  4. Read `polkit.png`.
  5. Ask the user whether they can see the dialog and click its Cancel.
  6. After the user cancels, run `kill $probe`, then confirm `timedatectl show -p Timezone --value` still prints `Europe/Rome`.

Decision:
- `AUTH_HIDES_PANEL = false` only if the dialog was visible above the rectangle and clickable.
- Otherwise it is `true`.

Record the exact error text from `polkit.txt`. Task 6's `cancelled` pattern must match it.

- [ ] **Step 8: Per-user locale.** Run:

```bash
systemctl --user show-environment | grep -E '^(LANG|LC_TIME)='
grep -n 'LANG' /etc/profile.d/locale.sh | head -3
```

If the user manager already has `LANG`, `profile.d` skips `~/.config/locale.conf` in every session started from it. Record "per-user formats: not effective under uwsm", and Task 6 keeps `SetLocale`. If it doesn't have `LANG`, record that Task 6 must write `~/.config/locale.conf` for `region.formats` instead (Task 6, Step 6 has the code).

- [ ] **Step 9: Record.** Add to `docs/settings-panel.md`, before `## Measurements`, filling every `…` with what you observed:

```markdown
## Round 3: verified behaviour

Probed 2026-09-28 on this machine; the plan's Task 1.

### Baseline
Full read, five runs: … ms median.

### D-Bus cold start
`NTP` + `ListTimezones`: cold … ms, warm … ms.

### nmcli monitor and scans
A completed scan printed … lines. (0 means the list refresh comes from the follow-up read.)

### Quickshell stdin
`write()` in `onStarted`: …

### Waybar include
…, screenshot /tmp/claude-1000/wb.png. Decision: include at `~/.local/state/waybar/clock.jsonc` | absolute path | template fallback.

### Proton VPN
Profile after `down`: … Traffic while down: … App display: … `up`: … Decision: `PROTON_MODE = "nm" | "app"`.

### Polkit dialog versus the overlay
Visible: … Clickable: … Cancel error: `…`. Decision: `AUTH_HIDES_PANEL = true | false`.

### Per-user locale
User manager `LANG`: … Decision: formats use SetLocale | ~/.config/locale.conf.
```

- [ ] **Step 10: Commit.**

```bash
git add docs/settings-panel.md
git commit -m "docs(settings): round 3 probes — Proton, polkit, Waybar include, baseline"
```

---

### Task 2: Requests reach the helper on stdin

**Goal:** `panel-request.sh -` reads one JSON line from stdin and hands it to `request.js` on stdin, and the panel sends every write that way, so no secret ever appears in any process's argv.

**Files:**
- Modify: `scripts/settings/panel-request.sh`
- Modify: `quickshell/settings-panel/request.js`
- Modify: `quickshell/settings-panel/shell.qml` (the `drain()` function and `writer` `Process`)
- Create: `quickshell/settings-panel/test/test-request-stdin.sh`
- Modify: `quickshell/settings-panel/test/run-tests.sh`

**Acceptance Criteria:**
- [ ] `printf '%s\n' '{"op":"read","ids":["startup.autologin"]}' | bash scripts/settings/panel-request.sh -` prints the same JSON as the argv form
- [ ] While a stdin request runs, no process's `/proc/*/cmdline` contains the request text (the test uses a marker)
- [ ] An empty stdin fails with `{"ok":false,"error":"Expected one JSON request on stdin"}`
- [ ] `shell.qml`'s writer command ends in `"-"` and the request is written followed by `\n`

**Verify:** `bash quickshell/settings-panel/test/test-request-stdin.sh` → `ok: stdin request equals argv request`, `ok: request text never in argv`, `ok: empty stdin is rejected`.

**Steps:**

- [ ] **Step 1: Write the failing test** `quickshell/settings-panel/test/test-request-stdin.sh`:

```bash
#!/bin/bash
# The panel sends writes on stdin so a Wi-Fi password never sits in argv.
set -euo pipefail
request_sh="$HOME/.config/scripts/settings/panel-request.sh"
req='{"op":"read","ids":["startup.autologin"]}'
by_argv=$(bash "$request_sh" "$req")
by_stdin=$(printf '%s\n' "$req" | bash "$request_sh" -)
[[ $by_argv == "$by_stdin" ]] || { echo "stdin reply differs: $by_stdin" >&2; exit 1; }
echo 'ok: stdin request equals argv request'

# A marker that only exists inside the request. grep reads it from a file, so
# grep's own argv never contains it.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
marker="stdin-marker-$$-$RANDOM"
printf '%s\n' "$marker" > "$tmp/pattern"
{ sleep 0.3; printf '{"op":"read","ids":["startup.autologin"],"note":"%s"}\n' "$marker"; } | bash "$request_sh" - >/dev/null &
job=$!
for _ in $(seq 1 40); do
    grep -l -a -F -f "$tmp/pattern" /proc/[0-9]*/cmdline >> "$tmp/found" 2>/dev/null || true
    sleep 0.02
done
wait "$job"
if [[ -s $tmp/found ]]; then echo "request text visible in argv: $(sort -u "$tmp/found")" >&2; exit 1; fi
echo 'ok: request text never in argv'

reply=$(bash "$request_sh" - < /dev/null || true)
[[ $reply == '{"ok":false,"error":"Expected one JSON request on stdin"}' ]] || { echo "empty stdin: $reply" >&2; exit 1; }
echo 'ok: empty stdin is rejected'
```

Add it to `run-tests.sh` after `test-persist.sh`:

```bash
bash "$test_dir/test-request-stdin.sh"
```

- [ ] **Step 2: Run it and watch it fail.** Run `bash quickshell/settings-panel/test/test-request-stdin.sh`. Expected: `stdin reply differs`, because `-` is currently parsed as JSON.

- [ ] **Step 3: Implement.** In `panel-request.sh`, replace the last line with the following. `exec` keeps stdin attached to gjs, and `flock` holds fd 9, so stdin is untouched:

```bash
# `-` means the request arrives on stdin (the panel's writes: they can carry a Wi-Fi password).
exec gjs -m "$HOME/.config/quickshell/settings-panel/request.js" "$1"
```

`request.js` becomes:

```js
import GLib from "gi://GLib"
import Gio from "gi://Gio"
import GioUnix from "gi://GioUnix"
import System from "system"
import { dispatch } from "./backend.js"

// One line, not EOF: the panel never has to close its end of the pipe.
function stdinLine() {
    const stream = new Gio.DataInputStream({ base_stream: new GioUnix.InputStream({ fd: 0, close_fd: false }) })
    const [line] = stream.read_line_utf8(null)
    if (!line || !line.trim()) throw new Error("Expected one JSON request on stdin")
    return line
}

const loop = new GLib.MainLoop(null, false)
let exitCode = 0
Promise.resolve().then(() => dispatch(JSON.parse(ARGV[0] === "-" ? stdinLine() : ARGV[0]))).then(result => {
    print(JSON.stringify({ ok: true, ...result }))
}).catch(error => {
    print(JSON.stringify({ ok: false, error: error.message }))
    exitCode = 1
}).finally(() => loop.quit())
loop.run()
System.exit(exitCode)
```

In `shell.qml`, add `property string writeRequest: ""`. In `drain()`, replace the two lines that set `writer.command` and `writer.running` with:

```qml
        writeRequest = JSON.stringify(request);
        writer.command = ["bash", configDir + "/scripts/settings/panel-request.sh", "-"];
        writer.running = true;
```

In the `writer` `Process`, add:

```qml
        stdinEnabled: true
        // The request travels on stdin, never argv: it may carry a Wi-Fi password.
        onStarted: { writer.write(root.writeRequest + "\n"); root.writeRequest = ""; }
```

If Task 1 Step 4 recorded that `onStarted` doesn't deliver, write immediately after `writer.running = true;` in `drain()` instead, and drop the `onStarted` handler.

- [ ] **Step 4: Run the tests.** Run `bash quickshell/settings-panel/test/test-request-stdin.sh`, then `bash quickshell/settings-panel/test/run-tests.sh`. Expected: all three `ok:` lines, and the whole suite passes.

- [ ] **Step 5: Live check.** With the session unlocked (`pgrep -x hyprlock` prints nothing):
  1. Note `cat options/randomwallpaper`.
  2. Open the panel (Super+I), toggle **Startup → Random Wallpaper** twice, and close it.
  3. `cat options/randomwallpaper` shows the original value.
  4. `grep -ci error ~/.cache/settings-panel/session.log` doesn't increase.

- [ ] **Step 6: Commit.**

```bash
git add scripts/settings/panel-request.sh quickshell/settings-panel/request.js quickshell/settings-panel/shell.qml quickshell/settings-panel/test/test-request-stdin.sh quickshell/settings-panel/test/run-tests.sh
git commit -m "feat(settings): send panel writes to the helper on stdin"
```

---

### Task 3: `network.mjs` pure helpers

**Goal:** A dependency-free module that turns a plain NetworkManager snapshot into the Network page model and validates every network request. Node, GJS and QML can all import it.

**Files:**
- Create: `quickshell/settings-panel/network.mjs`
- Create: `quickshell/settings-panel/test/network.mjs`
- Modify: `quickshell/settings-panel/test/run-tests.sh`

**Acceptance Criteria:**
- [ ] Networks are grouped by SSID, keeping the strongest AP; empty SSIDs are dropped; order is active, known, signal, then name
- [ ] `securityOf` returns `open` / `psk` / `sae` / `unsupported` for open, WPA2-PSK, WPA3-SAE-only, 802.1X and WEP, and `open` for OWE
- [ ] `vpnConnections` lists only `vpn`/`wireguard` types, never `dummy`, and marks Proton entries with `control: "app"` when the mode is `"app"`
- [ ] `connectPlan` covers a known network without a password (activate), an open new network, PSK validation (8–63 printable ASCII or 64 hex), a re-typed password for a saved network (add with `replace`), and refusals for enterprise/WEP networks and networks out of range
- [ ] `forgetPlan` returns every saved UUID for the SSID, and throws when there are none
- [ ] `vpnPlan` refuses unknown UUIDs, non-VPN connections, non-boolean values, and Proton in `"app"` mode
- [ ] `failureMessage("NO_SECRETS")` is `"Wrong password"`

**Verify:** `node quickshell/settings-panel/test/network.mjs` → seven lines, each starting `ok:`.

**Steps:**

- [ ] **Step 1: Write the failing test** `quickshell/settings-panel/test/network.mjs`:

```js
import assert from 'node:assert/strict'
import * as network from '../network.mjs'

// Flag values from libnm: PRIVACY=0x1; PSK=0x100, 802.1X=0x200, SAE=0x400, OWE=0x800.
// 392 (0x188) is what this machine's WPA2 access points report.
const snap = {
    running: true, wifiEnabled: true, wifiDevices: [{iface: 'wlan0'}],
    accessPoints: [
        {ssid: 'Home', strength: 40, flags: 1, wpaFlags: 0, rsnFlags: 392},
        {ssid: 'Home', strength: 84, flags: 1, wpaFlags: 0, rsnFlags: 392},
        {ssid: 'Cafe', strength: 90, flags: 0, wpaFlags: 0, rsnFlags: 0},
        {ssid: 'Office', strength: 70, flags: 1, wpaFlags: 0, rsnFlags: 0x200},
        {ssid: 'New3', strength: 60, flags: 1, wpaFlags: 0, rsnFlags: 0x400},
        {ssid: 'Old', strength: 20, flags: 1, wpaFlags: 0, rsnFlags: 0},
        {ssid: '', strength: 99, flags: 1, wpaFlags: 0, rsnFlags: 392},
        {ssid: 'Saved', strength: 10, flags: 1, wpaFlags: 0, rsnFlags: 392},
    ],
    wired: [{iface: 'eno1', carrier: true, speed: 1000, ip4: '192.168.1.10/24', gateway: '192.168.1.1'}],
    connections: [
        {uuid: 'u-saved', id: 'Saved', type: '802-11-wireless', ssid: 'Saved', state: null, iface: null},
        {uuid: 'u-saved2', id: 'Saved 1', type: '802-11-wireless', ssid: 'Saved', state: null, iface: null},
        {uuid: 'u-home', id: 'Home', type: '802-11-wireless', ssid: 'Home', state: 'activated', iface: 'wlan0'},
        {uuid: 'u-proton', id: 'ProtonVPN IT#113', type: 'wireguard', ssid: null, state: 'activated', iface: 'proton0'},
        {uuid: 'u-work', id: 'Work', type: 'vpn', ssid: null, state: null, iface: null},
        {uuid: 'u-kill', id: 'pvpn-killswitch-ipv6', type: 'dummy', ssid: null, state: 'activated', iface: 'ipv6leakintrf0'},
        {uuid: 'u-wired', id: 'Wired connection 1', type: '802-3-ethernet', ssid: null, state: 'activated', iface: 'eno1'},
    ],
}

const list = network.wifiNetworks(snap)
assert.deepEqual(list.map(n => n.ssid), ['Home', 'Saved', 'Cafe', 'Office', 'New3', 'Old'])
assert.equal(list[0].signal, 84)
assert.equal(list[0].active, true)
assert.equal(list[1].known, true)
assert.deepEqual(list.map(n => n.bars), [4, 1, 4, 3, 3, 1])
console.log('ok: networks grouped by SSID, hidden dropped, active/known/signal order')

assert.deepEqual(['Cafe', 'Home', 'Office', 'New3', 'Old'].map(ssid => list.find(n => n.ssid === ssid).security), ['open', 'psk', 'unsupported', 'sae', 'unsupported'])
assert.equal(network.securityOf({flags: 1, wpaFlags: 0, rsnFlags: 0x800}), 'open')
console.log('ok: security from AP flags (open, PSK, SAE, 802.1X, WEP, OWE)')

assert.deepEqual(network.vpnConnections(snap, 'app').map(v => [v.name, v.state, v.control]),
    [['ProtonVPN IT#113', 'activated', 'app'], ['Work', 'off', 'switch']])
assert.equal(network.vpnConnections(snap, 'nm')[0].control, 'switch')
console.log('ok: VPN list has vpn/wireguard only, Proton controlled by mode')

const view = network.networkView(snap, {protonApp: true, mode: 'app'})
assert.equal(view.running, true)
assert.equal(view.wifi.available, true)
assert.equal(view.proton.active, true)
assert.equal(view.wired[0].iface, 'eno1')
assert.deepEqual(network.networkView({running: false}), {running: false})
assert.equal(network.networkView({...snap, wifiDevices: []}).wifi.available, false)
assert.equal(network.networkView(snap, {protonApp: false}).proton, null)
console.log('ok: page model, including NM down and no Wi-Fi device')

assert.deepEqual(network.connectPlan(snap, {ssid: 'Saved'}), {kind: 'activate', uuid: 'u-saved'})
assert.deepEqual(network.connectPlan(snap, {ssid: 'Cafe'}), {kind: 'add', ssid: 'Cafe', psk: null, keyMgmt: null, replace: []})
assert.deepEqual(network.connectPlan(snap, {ssid: 'New3', psk: 'correct horse'}), {kind: 'add', ssid: 'New3', psk: 'correct horse', keyMgmt: 'sae', replace: []})
assert.deepEqual(network.connectPlan(snap, {ssid: 'Saved', psk: 'f'.repeat(64)}), {kind: 'add', ssid: 'Saved', psk: 'f'.repeat(64), keyMgmt: 'wpa-psk', replace: ['u-saved', 'u-saved2']})
for (const [request, message] of [
    [{ssid: 'Old'}, /not supported/],
    [{ssid: 'Office'}, /not supported/],
    [{ssid: 'Gone'}, /no longer in range/],
    [{ssid: 'Home', psk: 'short'}, /8–63/],
    [{ssid: 'Home', psk: 'x'.repeat(64)}, /8–63/],
    [{ssid: 'Home', psk: 'ok but\nnewline'}, /8–63/],
    [{ssid: 'New3'}, /Enter the network password/],
    [{ssid: ''}, /Invalid network name/],
    [{ssid: 'x'.repeat(33)}, /Invalid network name/],
    [{ssid: 42}, /Invalid network name/],
]) assert.throws(() => network.connectPlan(snap, request), message)
console.log('ok: connect plans and every refusal')

assert.deepEqual(network.forgetPlan(snap, 'Saved'), ['u-saved', 'u-saved2'])
assert.throws(() => network.forgetPlan(snap, 'Cafe'), /not saved/)
console.log('ok: forget removes every saved profile for the SSID')

assert.deepEqual(network.vpnPlan(snap, {uuid: 'u-work', active: true}, 'app'), {uuid: 'u-work', active: true})
assert.throws(() => network.vpnPlan(snap, {uuid: 'u-proton', active: false}, 'app'), /Proton VPN app/)
assert.deepEqual(network.vpnPlan(snap, {uuid: 'u-proton', active: false}, 'nm'), {uuid: 'u-proton', active: false})
assert.throws(() => network.vpnPlan(snap, {uuid: 'u-wired', active: false}, 'nm'), /not a VPN/)
assert.throws(() => network.vpnPlan(snap, {uuid: 'nope', active: true}, 'nm'), /no longer exists/)
assert.throws(() => network.vpnPlan(snap, {uuid: 'u-work', active: 'yes'}, 'nm'), /on\/off/)
assert.equal(network.failureMessage('NO_SECRETS'), 'Wrong password')
assert.equal(network.failureMessage('LOGIN_FAILED'), 'Wrong password')
assert.equal(network.failureMessage('CONNECT_TIMEOUT'), 'The network did not answer in time')
assert.equal(network.failureMessage('SOMETHING_NEW'), 'Connection failed (something new)')
console.log('ok: VPN plans and readable failure reasons')
```

Add to `run-tests.sh` after `node "$test_dir/monitor-lua.mjs"`:

```bash
node "$test_dir/network.mjs"
```

- [ ] **Step 2: Run it and watch it fail.** Run `node quickshell/settings-panel/test/network.mjs`. Expected: `ERR_MODULE_NOT_FOUND` for `../network.mjs`.

- [ ] **Step 3: Implement** `quickshell/settings-panel/network.mjs`:

```js
// Pure Network page logic: plain objects in, plain objects out. nm.js is the
// only file that touches libnm; everything decidable lives here and is tested
// under Node.

// Decided by the round-3 Task 1 probe (docs/settings-panel.md): "nm" lets the
// panel switch Proton's WireGuard profile like any VPN, "app" hands it to the
// Proton app because switching behind its back desyncs it.
export const PROTON_MODE = "app"

const WIFI = "802-11-wireless"
const VPN_TYPES = new Set(["vpn", "wireguard"])
// libnm NM80211ApFlags / NM80211ApSecurityFlags.
const PRIVACY = 0x1, PSK = 0x100, EAP = 0x200, SAE = 0x400, OWE = 0x800

export function securityOf(ap) {
    const all = ap.wpaFlags | ap.rsnFlags
    if (all & EAP) return "unsupported"
    if (all & PSK) return "psk"
    if (all & SAE) return "sae"
    if (all & OWE) return "open"
    // PRIVACY without WPA/RSN is WEP, which the page does not offer.
    return ap.flags & PRIVACY ? "unsupported" : "open"
}
const savedWifi = snap => snap.connections.filter(c => c.type === WIFI && c.ssid)

export function wifiNetworks(snap) {
    const saved = savedWifi(snap)
    const known = new Set(saved.map(c => c.ssid))
    const active = new Set(saved.filter(c => c.state === "activated").map(c => c.ssid))
    const best = new Map()
    for (const ap of snap.accessPoints) {
        if (!ap.ssid) continue
        const prev = best.get(ap.ssid)
        if (!prev || ap.strength > prev.strength) best.set(ap.ssid, ap)
    }
    return [...best.values()].map(ap => ({
        ssid: ap.ssid, signal: ap.strength, bars: Math.max(1, Math.min(4, Math.ceil(ap.strength / 25))),
        security: securityOf(ap), known: known.has(ap.ssid), active: active.has(ap.ssid),
    })).sort((a, b) => b.active - a.active || b.known - a.known || b.signal - a.signal || a.ssid.localeCompare(b.ssid))
}

export const isProton = connection => connection.id.startsWith("ProtonVPN ")
export function vpnConnections(snap, mode = PROTON_MODE) {
    return snap.connections.filter(c => VPN_TYPES.has(c.type)).map(c => ({
        uuid: c.uuid, name: c.id, state: c.state || "off", iface: c.iface, proton: isProton(c),
        control: isProton(c) && mode === "app" ? "app" : "switch",
    })).sort((a, b) => (b.state === "activated") - (a.state === "activated") || a.name.localeCompare(b.name))
}

export function networkView(snap, { protonApp = false, mode = PROTON_MODE } = {}) {
    if (!snap.running) return { running: false }
    const vpn = vpnConnections(snap, mode)
    return {
        running: true,
        wifi: { enabled: snap.wifiEnabled, available: snap.wifiDevices.length > 0, networks: snap.wifiDevices.length ? wifiNetworks(snap) : [] },
        wired: snap.wired,
        vpn,
        proton: protonApp ? { mode, active: vpn.some(v => v.proton && v.state === "activated") } : null,
    }
}

function validSsid(ssid) {
    if (typeof ssid !== "string" || !ssid || /[\0\r\n]/.test(ssid) || new TextEncoder().encode(ssid).length > 32) throw new Error("Invalid network name")
    return ssid
}
function validPsk(psk) {
    if (psk === undefined || psk === null) return null
    if (typeof psk !== "string" || !(/^[\x20-\x7e]{8,63}$/.test(psk) || /^[0-9a-fA-F]{64}$/.test(psk)))
        throw new Error("The password must be 8–63 characters, or 64 hexadecimal digits")
    return psk
}
export function connectPlan(snap, request) {
    const ssid = validSsid(request.ssid)
    const net = wifiNetworks(snap).find(n => n.ssid === ssid)
    if (!net) throw new Error("That network is no longer in range")
    if (net.security === "unsupported") throw new Error("Enterprise and WEP networks are not supported here; use Advanced…")
    const psk = validPsk(request.psk)
    const saved = savedWifi(snap).filter(c => c.ssid === ssid).map(c => c.uuid)
    if (saved.length && psk === null) return { kind: "activate", uuid: saved[0] }
    if (net.security === "open") return { kind: "add", ssid, psk: null, keyMgmt: null, replace: saved }
    if (psk === null) throw new Error("Enter the network password")
    return { kind: "add", ssid, psk, keyMgmt: net.security === "sae" ? "sae" : "wpa-psk", replace: saved }
}
export function forgetPlan(snap, ssid) {
    const name = validSsid(ssid)
    const uuids = savedWifi(snap).filter(c => c.ssid === name).map(c => c.uuid)
    if (!uuids.length) throw new Error("That network is not saved")
    return uuids
}
export function vpnPlan(snap, request, mode = PROTON_MODE) {
    if (typeof request.active !== "boolean") throw new Error("Expected an on/off value")
    const connection = snap.connections.find(c => c.uuid === request.uuid)
    if (!connection) throw new Error("That connection no longer exists")
    if (!VPN_TYPES.has(connection.type)) throw new Error("That connection is not a VPN")
    if (isProton(connection) && mode === "app") throw new Error("Use the Proton VPN app for this connection")
    return { uuid: connection.uuid, active: request.active }
}

const reasons = {
    NO_SECRETS: "Wrong password", LOGIN_FAILED: "Wrong password",
    CONNECT_TIMEOUT: "The network did not answer in time", SERVICE_START_TIMEOUT: "The VPN service did not start in time",
    DEVICE_DISCONNECTED: "The Wi-Fi device disconnected", CONNECTION_REMOVED: "The connection was removed",
    DEPENDENCY_FAILED: "A connection this one depends on failed",
}
export const failureMessage = name => reasons[name] || `Connection failed (${String(name).toLowerCase().replace(/_/g, " ")})`
```

- [ ] **Step 4: Run it.** Run `node quickshell/settings-panel/test/network.mjs`. Expected: seven `ok:` lines.

- [ ] **Step 5: Commit.**

```bash
git add quickshell/settings-panel/network.mjs quickshell/settings-panel/test/network.mjs quickshell/settings-panel/test/run-tests.sh
git commit -m "feat(settings): pure Wi-Fi and VPN model for the Network page"
```

---

### Task 4: libnm adapter and backend network ops

**Goal:** `nm.js` reads NetworkManager into the plain snapshot shape `network.mjs` expects and performs the page's writes. The backend exposes these through a `network` row source, a `network: true` read flag and the ops `networkScan`, `wifiConnect`, `wifiForget` and `vpn`, plus the actions `protonApp` and `networkEditor`.

**Files:**
- Create: `quickshell/settings-panel/nm.js`
- Modify: `quickshell/settings-panel/backend.js` (imports, `snapshot`, `change`, `dispatch`)
- Modify: `quickshell/settings-panel/catalog.json` (`network` category, `network.wifi` row)
- Modify: `quickshell/settings-panel/test/backend.mjs` (resolve hook, NM mock, cases)

**Acceptance Criteria:**
- [ ] `{"op":"read","ids":[],"network":true}` returns `network` in the `networkView` shape, and `ids:["network.wifi"]` returns `{value: true}` on this machine
- [ ] NM not running makes `network.wifi` a row error and returns `network: {running: false}`, and the read still succeeds
- [ ] `wifiConnect` activates a saved network and adds a new one. A failure is reported with the adapter's message
- [ ] A re-typed password removes the old profiles **only after** the new one activates
- [ ] `wifiForget`, `vpn`, `networkScan`, `action protonApp` and `action networkEditor` call exactly the expected adapter or spawn functions, and nothing else
- [ ] A pending display change refuses `wifiConnect` and `networkScan` (the existing rule)
- [ ] A real read on this machine: `bash scripts/settings/panel-request.sh '{"op":"read","ids":[],"network":true}' | jq -r '.network.vpn[0].name'` → `ProtonVPN IT#113`

**Verify:** `node quickshell/settings-panel/test/backend.mjs` prints the five new `ok: network …` lines along with all the old ones, and the live read above passes.

**Steps:**

- [ ] **Step 1: Add the NM mock and failing cases to `test/backend.mjs`.** In the `registerHooks` resolve function, add before `return next(specifier,context)`:

```js
    if (specifier === './nm.js') return {url:'data:text/javascript,'+encodeURIComponent('const m = () => globalThis.settingsMocks.nm; export const nmSnapshot = (...a) => m().nmSnapshot(...a), setWifiEnabled = (...a) => m().setWifiEnabled(...a), requestScan = (...a) => m().requestScan(...a), activate = (...a) => m().activate(...a), addAndActivate = (...a) => m().addAndActivate(...a), deactivate = (...a) => m().deactivate(...a), removeConnections = (...a) => m().removeConnections(...a)'),shortCircuit:true}
```

Before the `globalThis.settingsMocks = {` line, add:

```js
// Shape produced by nm.js on NetworkManager 1.58 (trimmed from this machine).
const nmState = {
    running: true, wifiEnabled: true, wifiDevices: [{iface:'wlan0'}],
    accessPoints: [{ssid:'Dimensione-E92F',strength:84,flags:1,wpaFlags:0,rsnFlags:392},{ssid:'Cafe',strength:60,flags:0,wpaFlags:0,rsnFlags:0}],
    wired: [{iface:'eno1',carrier:true,speed:1000,ip4:'192.168.1.10/24',gateway:'192.168.1.1'}],
    connections: [
        {uuid:'u-old',id:'Dimensione-E92F',type:'802-11-wireless',ssid:'Dimensione-E92F',state:null,iface:null},
        {uuid:'u-proton',id:'ProtonVPN IT#113',type:'wireguard',ssid:null,state:'activated',iface:'proton0'},
        {uuid:'u-kill',id:'pvpn-killswitch-ipv6',type:'dummy',ssid:null,state:'activated',iface:'ipv6leakintrf0'}],
}
let nmCalls = [], nmFailAdd = ''
const nmMock = {
    nmSnapshot: () => structuredClone(nmState),
    setWifiEnabled: async on => { nmCalls.push(['wifi', on]); nmState.wifiEnabled = on },
    requestScan: async () => { nmCalls.push(['scan']) },
    activate: async uuid => { nmCalls.push(['activate', uuid]) },
    addAndActivate: async plan => { nmCalls.push(['add', plan.ssid, plan.psk, plan.keyMgmt]); if (nmFailAdd) throw new Error(nmFailAdd) },
    deactivate: async uuid => { nmCalls.push(['deactivate', uuid]) },
    removeConnections: async uuids => { nmCalls.push(['remove', ...uuids]) },
}
```

Add `nm: nmMock,` inside `globalThis.settingsMocks`. Append these cases at the end of the file. If `PROTON_MODE` was set to `"nm"` in Task 5, the Proton line changes as Task 5 Step 6 says.

```js
nmCalls = []; events = []
result = await dispatch({op:'read',ids:['network.wifi'],network:true})
assert.equal(result.values['network.wifi'].value, true)
assert.deepEqual(result.network.wifi.networks.map(n => [n.ssid, n.known]), [['Dimensione-E92F', true], ['Cafe', false]])
assert.deepEqual(result.network.vpn.map(v => v.name), ['ProtonVPN IT#113'])
assert.equal(nmCalls.length, 0)
assert.equal(events.some(e => e[0] === 'write' || e[0] === 'spawn'), false)
console.log('ok: network read shapes the page and has no side effects')

nmState.running = false
result = await dispatch({op:'read',ids:['network.wifi'],network:true})
assert.match(result.values['network.wifi'].error, /not running/)
assert.deepEqual(result.network, {running:false})
nmState.running = true
console.log('ok: network — NetworkManager down is a row error, not a failed read')

await dispatch({op:'set',id:'network.wifi',value:false})
assert.deepEqual(nmCalls.at(-1), ['wifi', false])
await dispatch({op:'set',id:'network.wifi',value:true})
await dispatch({op:'networkScan'})
assert.deepEqual(nmCalls.at(-1), ['scan'])
console.log('ok: network radio switch and scan go through the adapter')

nmCalls = []
await dispatch({op:'wifiConnect',ssid:'Dimensione-E92F'})
assert.deepEqual(nmCalls, [['activate','u-old']])
nmCalls = []
await dispatch({op:'wifiConnect',ssid:'Dimensione-E92F',psk:'new password'})
assert.deepEqual(nmCalls, [['add','Dimensione-E92F','new password','wpa-psk'],['remove','u-old']])
nmCalls = []; nmFailAdd = 'Wrong password'
await assert.rejects(dispatch({op:'wifiConnect',ssid:'Dimensione-E92F',psk:'bad password'}), /Wrong password/)
assert.deepEqual(nmCalls, [['add','Dimensione-E92F','bad password','wpa-psk']])
nmFailAdd = ''; nmCalls = []
await dispatch({op:'wifiConnect',ssid:'Cafe'})
assert.deepEqual(nmCalls, [['add','Cafe',null,null]])
await assert.rejects(dispatch({op:'wifiConnect',ssid:'Cafe',psk:'short'}), /8–63/)
console.log('ok: network connect activates saved, adds new, replaces old only after success')

nmCalls = []
await dispatch({op:'wifiForget',ssid:'Dimensione-E92F'})
assert.deepEqual(nmCalls, [['remove','u-old']])
await assert.rejects(dispatch({op:'vpn',uuid:'u-proton',active:false}), /Proton VPN app/)
await assert.rejects(dispatch({op:'vpn',uuid:'u-kill',active:false}), /not a VPN/)
events = []
await dispatch({op:'action',id:'protonApp'})
await dispatch({op:'action',id:'networkEditor'})
assert.deepEqual(events.filter(e => e[0] === 'spawn').map(e => e[1][0]), ['protonvpn-app','nm-connection-editor'])
console.log('ok: network forget, VPN refusal in app mode, and the two launch actions')
```

Find the existing test that asserts requests are refused while a display change is pending (search for `Keep or Revert the display change first`). Add `{op:'wifiConnect',ssid:'Cafe'}` and `{op:'networkScan'}` to its list of refused requests.

- [ ] **Step 2: Add the catalog entries the test reads.** In `catalog.json`, insert a category after `sound`:

```json
    {
      "id": "network",
      "title": "Network",
      "description": "Wi-Fi, wired and VPN connections"
    },
```

Add this row before the first `notifications` row:

```json
    {
      "category": "network",
      "id": "network.wifi",
      "title": "Wi-Fi",
      "description": "Turn the Wi-Fi radio on or off",
      "keywords": ["wireless", "wlan", "radio"],
      "source": "network",
      "key": "wifi",
      "kind": "toggle",
      "live": "network",
      "inView": true
    },
```

`inView` means the Network page draws this control itself. Task 5 teaches `shell.qml` to leave it out of the row list on that page.

- [ ] **Step 3: Run it and watch it fail.** Run `node quickshell/settings-panel/test/backend.mjs`. Expected: FAIL at the first network assertion (`values['network.wifi'].value` is undefined, because there's no `network` source case).

- [ ] **Step 4: Implement `nm.js`.**

```js
import GLib from "gi://GLib"
import Gio from "gi://Gio"
import NM from "gi://NM"
import { failureMessage } from "./network.mjs"

// The only libnm user. It returns plain objects so everything else is testable
// without NetworkManager, and it waits for real activation, not just the D-Bus reply.
for (const [method, finish] of [["add_and_activate_connection_async", "add_and_activate_connection_finish"],
    ["activate_connection_async", "activate_connection_finish"], ["deactivate_connection_async", "deactivate_connection_finish"],
    ["dbus_set_property", "dbus_set_property_finish"]]) Gio._promisify(NM.Client.prototype, method, finish)
Gio._promisify(NM.RemoteConnection.prototype, "delete_async", "delete_finish")
Gio._promisify(NM.DeviceWifi.prototype, "request_scan_async", "request_scan_finish")

let client = null
function nm() {
    if (!client) client = NM.Client.new(null) // 7.5 ms, synchronous; the helper lives for one request.
    return client
}
const ssidText = bytes => bytes ? NM.utils_ssid_to_utf8(bytes.get_data()) : ""
const wifiDevices = () => nm().get_devices().filter(d => d instanceof NM.DeviceWifi)
function stateName(state) {
    if (state === NM.ActiveConnectionState.ACTIVATED) return "activated"
    if (state === NM.ActiveConnectionState.ACTIVATING) return "activating"
    return null
}

export function nmSnapshot() {
    let c
    try { c = nm() } catch (_) { return { running: false } }
    if (!c.get_nm_running()) return { running: false }
    const devices = c.get_devices()
    const wifi = devices.filter(d => d instanceof NM.DeviceWifi)
    const active = new Map(c.get_active_connections().map(a => [a.get_uuid(), a]))
    return {
        running: true,
        wifiEnabled: c.wireless_get_enabled(),
        wifiDevices: wifi.map(d => ({ iface: d.get_iface() })),
        accessPoints: wifi.flatMap(d => d.get_access_points().map(ap => ({
            ssid: ssidText(ap.get_ssid()), strength: ap.get_strength(),
            flags: ap.get_flags(), wpaFlags: ap.get_wpa_flags(), rsnFlags: ap.get_rsn_flags(),
        }))),
        wired: devices.filter(d => d instanceof NM.DeviceEthernet).map(d => {
            const ip = d.get_ip4_config()
            const address = ip?.get_addresses()[0]
            return { iface: d.get_iface(), carrier: d.get_carrier(), speed: d.get_speed(),
                ip4: address ? `${address.get_address()}/${address.get_prefix()}` : null, gateway: ip?.get_gateway() || null }
        }),
        connections: c.get_connections().map(r => {
            const a = active.get(r.get_uuid())
            const wireless = r.get_setting_wireless()
            return { uuid: r.get_uuid(), id: r.get_id(), type: r.get_connection_type(),
                ssid: wireless ? ssidText(wireless.get_ssid()) : null,
                state: a ? stateName(a.get_state()) : null, iface: a?.get_devices()[0]?.get_iface() || null }
        }),
    }
}

const reasonName = reason => Object.keys(NM.ActiveConnectionStateReason).find(key => NM.ActiveConnectionStateReason[key] === reason) || "UNKNOWN"
// Resolves once the connection is really up; rejects with a readable reason.
function settled(active, timeoutMs = 30000) {
    return new Promise((resolve, reject) => {
        let handler = 0, timer = 0
        const finish = error => {
            if (handler) active.disconnect(handler)
            if (timer) GLib.source_remove(timer)
            handler = timer = 0
            if (error) reject(error); else resolve()
        }
        const check = (state, reason) => {
            if (state === NM.ActiveConnectionState.ACTIVATED) finish()
            else if (state === NM.ActiveConnectionState.DEACTIVATED) finish(new Error(failureMessage(reasonName(reason))))
        }
        handler = active.connect("state-changed", (_active, state, reason) => check(state, reason))
        timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, timeoutMs, () => { timer = 0; finish(new Error(failureMessage("CONNECT_TIMEOUT"))); return GLib.SOURCE_REMOVE })
        check(active.get_state(), active.get_state_reason())
    })
}
function remote(uuid) {
    const connection = nm().get_connection_by_uuid(uuid)
    if (!connection) throw new Error("That connection no longer exists")
    return connection
}

export async function setWifiEnabled(on) {
    await nm().dbus_set_property(NM.DBUS_PATH, NM.DBUS_INTERFACE, "WirelessEnabled", GLib.Variant.new_boolean(on), -1, null)
}
export async function requestScan() {
    // NM refuses scans that come too soon after the last one; that is not a failure.
    await Promise.all(wifiDevices().map(d => d.request_scan_async(null).catch(error => {
        if (!/not allowed|already|too/i.test(error.message)) throw error
    })))
}
export async function activate(uuid) {
    const active = await nm().activate_connection_async(remote(uuid), null, null, null)
    try { await settled(active) }
    catch (error) { await deactivate(uuid).catch(() => {}); throw error }
}
export async function addAndActivate({ ssid, psk, keyMgmt }) {
    const device = wifiDevices()[0]
    if (!device) throw new Error("No Wi-Fi device")
    const ap = device.get_access_points().filter(a => ssidText(a.get_ssid()) === ssid).sort((a, b) => b.get_strength() - a.get_strength())[0]
    if (!ap) throw new Error("That network is no longer in range")
    const connection = NM.SimpleConnection.new()
    connection.add_setting(new NM.SettingConnection({ id: ssid, uuid: NM.utils_uuid_generate(), type: "802-11-wireless", autoconnect: true }))
    connection.add_setting(new NM.SettingWireless({ ssid: new GLib.Bytes(new TextEncoder().encode(ssid)), mode: "infrastructure" }))
    // keyMgmt is "wpa-psk", "sae" or "owe" (network.mjs); a truly open network has none.
    if (keyMgmt) connection.add_setting(new NM.SettingWirelessSecurity(psk !== null ? { key_mgmt: keyMgmt, psk } : { key_mgmt: keyMgmt }))
    const active = await nm().add_and_activate_connection_async(connection, device, ap.get_path(), null)
    try { await settled(active) }
    catch (error) {
        // A wrong password must not leave a "Saved" network behind.
        await active.get_connection()?.delete_async(null).catch(() => {})
        throw error
    }
}
export async function deactivate(uuid) {
    const active = nm().get_active_connections().find(a => a.get_uuid() === uuid)
    if (active) await nm().deactivate_connection_async(active, null)
}
export async function removeConnections(uuids) {
    for (const uuid of uuids) await remote(uuid).delete_async(null)
}
```

- [ ] **Step 5: Wire the backend.** In `backend.js`:
  - Imports, after the existing ones:

```js
import { nmSnapshot, setWifiEnabled, requestScan, activate, addAndActivate, deactivate, removeConnections } from "./nm.js"
import * as network from "./network.mjs"
```

  - A value reader, next to `readOption`:

```js
function networkValue(key, snap) {
    if (!snap.running) throw new Error("NetworkManager is not running")
    if (key !== "wifi") throw new Error("Unknown network setting")
    if (!snap.wifiDevices.length) throw new Error("No Wi-Fi device")
    return snap.wifiEnabled
}
const networkPage = snap => network.networkView(snap, { protonApp: !!GLib.find_program_in_path("protonvpn-app") })
```

  - In `snapshot`'s `switch (row.source)`, add:

```js
            case "network": value = networkValue(row.key, await once("nm", nmSnapshot)); break
```

  - Change the signature to `async function snapshot(ids, includeMonitors, views = {})`, and before `return result` add:

```js
    if (views.network) result.network = networkPage(await once("nm", nmSnapshot))
```

  - In `change`'s switch:

```js
    case "network": return setWifiEnabled(value)
```

  - In `dispatch`, pass the flags on the read path:

```js
        return snapshot([...new Set(request.ids)], request.monitors === true, { network: request.network === true, startup: request.startup === true })
```

  - The ops, before `if (request.op === "action")`:

```js
    if (request.op === "networkScan") { await requestScan(); return {} }
    if (request.op === "wifiConnect") {
        const plan = network.connectPlan(nmSnapshot(), request)
        if (plan.kind === "activate") await activate(plan.uuid)
        else {
            await addAndActivate(plan)
            // Only once the new profile works are the old ones for this SSID removed.
            if (plan.replace.length) await removeConnections(plan.replace)
        }
        return {}
    }
    if (request.op === "wifiForget") { await removeConnections(network.forgetPlan(nmSnapshot(), request.ssid)); return {} }
    if (request.op === "vpn") {
        const plan = network.vpnPlan(nmSnapshot(), request)
        if (plan.active) await activate(plan.uuid); else await deactivate(plan.uuid)
        return {}
    }
```

  - Inside the `action` branch, before `const scripts = …`:

```js
        if (request.id === "protonApp") { detached(["protonvpn-app"]); return {} }
        if (request.id === "networkEditor") { detached(["nm-connection-editor"]); return {} }
```

  Read `detached` (around line 137) first. It must spawn through `GLib.spawn_async` with `SEARCH_PATH`, which the mock records as `['spawn', argv]`.

- [ ] **Step 6: Run the tests and the live read.**

```bash
node quickshell/settings-panel/test/backend.mjs
bash scripts/settings/panel-request.sh '{"op":"read","ids":["network.wifi"],"network":true}' | jq -c '{wifi:.values["network.wifi"], n:(.network.wifi.networks|length), vpn:[.network.vpn[].name], proton:.network.proton}'
```

Expected: every `ok:` line, and live output like `{"wifi":{"value":true,"reset":false},"n":6,"vpn":["ProtonVPN IT#113"],"proton":{"mode":"app","active":true}}`.

Time the read against an empty one:

```bash
for r in '{"op":"read","ids":[]}' '{"op":"read","ids":[],"network":true}'; do
  for i in 1 2 3 4 5; do s=$(date +%s%N); bash scripts/settings/panel-request.sh "$r" >/dev/null; echo $(( ($(date +%s%N)-s)/1000000 )); done | sort -n | sed -n 3p; done
```

The second median must be at most 30 ms above the first.

- [ ] **Step 7: Commit.**

```bash
git add quickshell/settings-panel/nm.js quickshell/settings-panel/backend.js quickshell/settings-panel/catalog.json quickshell/settings-panel/test/backend.mjs
git commit -m "feat(settings): NetworkManager backend through libnm"
```

---

### Task 5: Network page UI, live refresh, Proton mode and the Waybar click

**Goal:** The Network page is on screen, and it:
- lists Wi-Fi networks with connect, password entry and forget;
- shows wired status and VPN switches (or "Open Proton VPN");
- refreshes live only while visible, and rescans every 20 s.

Waybar's network icon opens this page.

**Files:**
- Create: `quickshell/settings-panel/NetworkView.qml`
- Modify: `quickshell/settings-panel/SettingsView.qml` (host the view)
- Modify: `quickshell/settings-panel/shell.qml` (`network` state, `inView` rows, live tag, `nmcli monitor`, rescan, page env, `open` IPC)
- Modify: `quickshell/settings-panel/network.mjs` (`PROTON_MODE` from Task 1)
- Modify: `scripts/hyprland/settings-panel.sh` (page argument)
- Modify: `waybar/config.jsonc` (`network.on-click`)
- Modify: `quickshell/settings-panel/test/tst_Settings.qml`

**Acceptance Criteria:**
- [ ] With `category: "network"`, the view shows every network from `controller.network.wifi.networks` with its SSID, bars glyph, lock and "Connected"/"Saved"
- [ ] Clicking a known or open network submits `{op:"wifiConnect", ssid}`. Clicking a secured unknown one shows a password field (echo mode Password), and Connect submits `{op:"wifiConnect", ssid, psk}` and clears the field
- [ ] Clicking an enterprise/WEP network submits nothing and offers **Advanced…**
- [ ] **Forget** exists only on known networks and submits `{op:"wifiForget", ssid}`
- [ ] A VPN switch submits `{op:"vpn", uuid, active}`, and a `control: "app"` entry has no switch. **Open Proton VPN** calls `action("protonApp")`
- [ ] The `network.wifi` row is not drawn as a normal row on the Network page, but searching "wi-fi" still finds it
- [ ] `network.running === false` shows "NetworkManager is not running."
- [ ] Live: on the Network page, `pgrep -fc '^nmcli monitor$'` is 1; on any other page, or with the panel closed, it is 0
- [ ] `settings-panel.sh network` opens the panel on Network when it's closed, and switches to Network when it's open
- [ ] `network.mjs`'s `PROTON_MODE` equals Task 1's decision

**Verify:** `bash quickshell/settings-panel/test/run-tests.sh` passes, including `test_network_*`, and so do the live checks in Step 7.

**Steps:**

- [ ] **Step 1: Write the failing QML tests.** In `tst_Settings.qml`'s mock `controller`:
  - Add `property var network: null`.
  - Add `{id:"network",title:"Network",description:"Connections"}` to `catalog.categories`.
  - Add the row `{id:"wifi-radio",category:"network",title:"Wi-Fi",description:"Radio",kind:"toggle",inView:true}` to `catalog.rows`, and `"wifi-radio": {value: true}` to the values literal in both places.
  - Hide `inView` rows when the query is empty:

```qml
        readonly property var visibleRows: catalog.rows.filter(row => query ? row.title.toLowerCase().includes(query.toLowerCase()) : row.category === category && !row.inView)
```

  In `init()`, add `controller.network = null;`. Add these tests:

```qml
        function networkFixture() {
            return {running: true,
                wifi: {enabled: true, available: true, networks: [
                    {ssid: "Home", signal: 84, bars: 4, security: "psk", known: true, active: true},
                    {ssid: "Cafe", signal: 60, bars: 3, security: "open", known: false, active: false},
                    {ssid: "Neighbour", signal: 40, bars: 2, security: "psk", known: false, active: false},
                    {ssid: "Office", signal: 30, bars: 2, security: "unsupported", known: false, active: false}]},
                wired: [{iface: "eno1", carrier: true, speed: 1000, ip4: "192.168.1.10/24", gateway: "192.168.1.1"}],
                vpn: [{uuid: "u-proton", name: "ProtonVPN IT#113", state: "activated", iface: "proton0", proton: true, control: "app"},
                      {uuid: "u-work", name: "Work", state: "off", iface: null, proton: false, control: "switch"}],
                proton: {mode: "app", active: true}};
        }
        function openNetwork() { controller.network = networkFixture(); controller.category = "network"; waitForRendering(view); }
        function test_network_lists_and_connects() {
            openNetwork();
            verify(findChild(view, "wifi-Home")); verify(findChild(view, "wifi-Office"));
            verify(!findChild(view, "toggle-wifi-radio"), "the radio row is drawn by the view, not the row list");
            verify(findChild(view, "wifiRadio"));
            mouseClick(findChild(view, "wifi-Home"));
            compare(controller.calls.at(-1), {op: "wifiConnect", ssid: "Home"});
            mouseClick(findChild(view, "wifi-Cafe"));
            compare(controller.calls.at(-1), {op: "wifiConnect", ssid: "Cafe"});
            const before = controller.calls.length;
            mouseClick(findChild(view, "wifi-Neighbour"));
            compare(controller.calls.length, before, "a secured unknown network asks for a password first");
            const field = findChild(view, "psk-Neighbour");
            verify(field && field.visible);
            compare(field.echoMode, TextInput.Password);
            field.forceActiveFocus();
            for (const c of "secret123") keyClick(c);
            mouseClick(findChild(view, "connect-Neighbour"));
            compare(controller.calls.at(-1), {op: "wifiConnect", ssid: "Neighbour", psk: "secret123"});
            compare(field.text, "");
        }
        function test_network_enterprise_is_not_connectable() {
            openNetwork();
            const before = controller.calls.length;
            mouseClick(findChild(view, "wifi-Office"));
            compare(controller.calls.length, before);
            verify(findChild(view, "advanced-Office"));
        }
        function test_network_forget_only_known() {
            openNetwork();
            verify(findChild(view, "forget-Home"));
            verify(!findChild(view, "forget-Cafe"));
            mouseClick(findChild(view, "forget-Home"));
            compare(controller.calls.at(-1), {op: "wifiForget", ssid: "Home"});
        }
        function test_network_vpn_switch_and_proton_app() {
            openNetwork();
            verify(!findChild(view, "vpn-u-proton"), "Proton in app mode has no switch");
            mouseClick(findChild(view, "protonApp"));
            compare(controller.calls.at(-1), {action: "protonApp"});
            mouseClick(findChild(view, "vpn-u-work"));
            compare(controller.calls.at(-1), {op: "vpn", uuid: "u-work", active: true});
        }
        function test_network_down_and_search() {
            controller.network = {running: false}; controller.category = "network"; waitForRendering(view);
            verify(findChild(view, "networkDown").visible);
            controller.query = "wi-fi"; waitForRendering(view);
            verify(findChild(view, "toggle-wifi-radio"), "search still finds the radio row");
        }
```

- [ ] **Step 2: Run and watch them fail.** Run `bash quickshell/settings-panel/test/run-tests.sh`. Expected: the `test_network_*` tests FAIL (`findChild` returns null).

- [ ] **Step 3: Implement `NetworkView.qml`.** First confirm the signal glyph code points against Waybar's `format-icons`: run `grep -o '"format-icons": \["[^]]*' waybar/config.jsonc | head -1 | iconv -f utf-8 -t utf-32be | xxd -p -c4`. Expect `000f091f`, `000f0922`, `000f0925` and `000f0928`, and use whatever it prints.

```qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Wi-Fi, wired and VPN in one view. Every write goes through controller.submit,
// so the queue, the stdin path and the post-write refresh are the ones every row uses.
ColumnLayout {
    id: page
    required property var controller
    required property var theme
    readonly property var model: controller.network
    readonly property var radio: controller.values["network.wifi"] || ({})
    property string expanded: ""
    spacing: 8
    // Nerd Font glyphs by code point: pasted private-use characters vanish. Index = bars (1-4).
    readonly property var bars: ["", String.fromCodePoint(0xF091F), String.fromCodePoint(0xF0922), String.fromCodePoint(0xF0925), String.fromCodePoint(0xF0928)]
    readonly property string lock: String.fromCodePoint(0xF033E)

    Label { objectName: "networkDown"; visible: !!page.model && !page.model.running; text: "NetworkManager is not running."; color: page.theme.foreground }
    Label { visible: !page.model; text: "Reading connections…"; color: page.theme.foreground; opacity: 0.75 }

    RowLayout {
        visible: !!page.model?.running
        Layout.fillWidth: true
        Label { text: "Wi-Fi"; color: page.theme.foreground; font.pixelSize: 16; font.bold: true; Layout.fillWidth: true }
        Label { visible: !!page.radio.error; text: page.radio.error || ""; color: page.theme.foreground; opacity: 0.75 }
        PanelButton { objectName: "networkEditor"; theme: page.theme; text: "Advanced…"; onClicked: page.controller.action("networkEditor") }
        Switch {
            objectName: "wifiRadio"
            visible: page.radio.value !== undefined
            checked: page.radio.value === true
            enabled: !page.controller.busy
            Accessible.name: "Wi-Fi"
            onToggled: page.controller.change("network.wifi", checked)
        }
    }
    Repeater {
        model: page.model?.running && page.model.wifi.enabled ? page.model.wifi.networks : []
        delegate: Rectangle {
            id: entry
            required property var modelData
            readonly property bool secured: modelData.security === "psk" || modelData.security === "sae"
            readonly property bool askPassword: page.expanded === modelData.ssid
            objectName: "wifi-" + modelData.ssid
            Layout.fillWidth: true
            implicitHeight: entryColumn.implicitHeight + 16
            radius: 10
            color: page.theme.plate
            border.color: modelData.active ? page.theme.accent : "transparent"
            MouseArea {
                anchors.fill: parent
                enabled: !page.controller.busy && entry.modelData.security !== "unsupported" && !entry.modelData.activating
                onClicked: {
                    if (entry.modelData.known || !entry.secured) {
                        page.expanded = "";
                        page.controller.submit({op: "wifiConnect", ssid: entry.modelData.ssid});
                    } else page.expanded = entry.askPassword ? "" : entry.modelData.ssid;
                }
            }
            ColumnLayout {
                id: entryColumn
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 8
                RowLayout {
                    Label { text: page.bars[entry.modelData.bars]; color: page.theme.foreground; font.pixelSize: 18 }
                    Label { text: entry.modelData.ssid; color: page.theme.foreground; font.bold: entry.modelData.active; elide: Text.ElideRight; Layout.fillWidth: true }
                    Label { visible: entry.modelData.security !== "open" && entry.modelData.security !== "owe"; text: page.lock; color: page.theme.foreground; opacity: 0.75 }
                    Label { text: entry.modelData.active ? "Connected" : entry.modelData.activating ? "Connecting…" : entry.modelData.known ? "Saved" : ""; color: page.theme.foreground; opacity: 0.75 }
                    Loader {
                        active: entry.modelData.known
                        sourceComponent: PanelButton {
                            objectName: "forget-" + entry.modelData.ssid
                            theme: page.theme; text: "Forget"
                            enabled: !page.controller.busy
                            onClicked: page.controller.submit({op: "wifiForget", ssid: entry.modelData.ssid})
                        }
                    }
                    Loader {
                        active: entry.modelData.security === "unsupported"
                        sourceComponent: PanelButton {
                            objectName: "advanced-" + entry.modelData.ssid
                            theme: page.theme; text: "Advanced…"
                            onClicked: page.controller.action("networkEditor")
                        }
                    }
                }
                RowLayout {
                    visible: entry.askPassword
                    TextField {
                        id: psk
                        objectName: "psk-" + entry.modelData.ssid
                        Layout.fillWidth: true
                        echoMode: TextInput.Password
                        placeholderText: "Password"
                        color: page.theme.foreground
                        Accessible.name: "Password for " + entry.modelData.ssid
                        onAccepted: { if (connectButton.enabled) connectButton.clicked(); }
                    }
                    PanelButton {
                        id: connectButton
                        objectName: "connect-" + entry.modelData.ssid
                        theme: page.theme; text: "Connect"
                        // WPA2 needs 8–63 characters; WPA3-SAE accepts any non-empty password (network.mjs validates both).
                        enabled: (entry.modelData.security === "sae" ? psk.text.length > 0 : psk.text.length >= 8) && !page.controller.busy
                        onClicked: {
                            page.controller.submit({op: "wifiConnect", ssid: entry.modelData.ssid, psk: psk.text});
                            psk.text = "";
                            page.expanded = "";
                        }
                    }
                }
            }
        }
    }

    Label { visible: !!page.model?.running && page.model.wired.length > 0; text: "Wired"; color: page.theme.foreground; font.pixelSize: 16; font.bold: true; Layout.topMargin: 8 }
    Repeater {
        model: page.model?.running ? page.model.wired : []
        delegate: Label {
            required property var modelData
            Layout.fillWidth: true
            color: page.theme.foreground
            text: modelData.carrier
                ? modelData.iface + " · " + modelData.speed + " Mb/s · " + (modelData.ip4 || "no address") + (modelData.gateway ? " via " + modelData.gateway : "")
                : modelData.iface + " · Cable unplugged"
        }
    }

    RowLayout {
        visible: !!page.model?.running && (page.model.vpn.length > 0 || !!page.model.proton)
        Layout.fillWidth: true; Layout.topMargin: 8
        Label { text: "VPN"; color: page.theme.foreground; font.pixelSize: 16; font.bold: true; Layout.fillWidth: true }
        PanelButton {
            objectName: "protonApp"
            visible: !!page.model?.proton
            theme: page.theme; text: "Open Proton VPN"
            onClicked: page.controller.action("protonApp")
        }
    }
    Repeater {
        model: page.model?.running ? page.model.vpn : []
        delegate: RowLayout {
            id: vpnRow
            required property var modelData
            Layout.fillWidth: true
            Label {
                Layout.fillWidth: true
                color: page.theme.foreground
                text: vpnRow.modelData.name + " · " + (vpnRow.modelData.state === "activated" ? "Connected" + (vpnRow.modelData.iface ? " on " + vpnRow.modelData.iface : "")
                    : vpnRow.modelData.state === "activating" ? "Connecting…" : "Off")
            }
            Loader {
                active: vpnRow.modelData.control === "switch"
                sourceComponent: Switch {
                    objectName: "vpn-" + vpnRow.modelData.uuid
                    checked: vpnRow.modelData.state !== "off"
                    enabled: !page.controller.busy
                    Accessible.name: vpnRow.modelData.name
                    onToggled: page.controller.submit({op: "vpn", uuid: vpnRow.modelData.uuid, active: checked})
                }
            }
        }
    }
}
```

- [ ] **Step 4: Host the view in `SettingsView.qml`.** Inside the scroll `ColumnLayout`, after the Displays `Flow` and before the "No settings match" `Label`, add:

```qml
                        NetworkView {
                            visible: view.controller.category === "network" && !view.controller.query.trim()
                            Layout.fillWidth: true
                            controller: view.controller
                            theme: view
                        }
```

- [ ] **Step 5: Wire `shell.qml`.**
  - Properties:

```qml
    property var network: null
    readonly property string initialPage: Quickshell.env("SETTINGS_PAGE") || ""
```

  - In the catalog `FileView.onLoaded`, before `root.refresh()`:

```qml
            if (root.catalog.categories.some(c => c.id === root.initialPage)) root.category = root.initialPage;
```

  - `visibleRows`: change the no-query branch to `if (!words.length) return row.category === category && !row.inView;`.
  - `liveTags`: the radio row is no longer in `visibleRows` on its page, so the tag comes from the category:

```qml
        if (category === "network" && !query.trim()) tags.add("network");
```

  - `refresh()`: add `network: category === "network"` to the request object.
  - `readLive()`: build the request as:

```qml
        liveReader.command = ["bash", configDir + "/scripts/settings/panel-request.sh", JSON.stringify({op: "read", ids: ids, monitors: tags.includes("displays"), network: tags.includes("network")})];
```

  - In both `reader.onExited` and `liveReader.onExited`, after the values merge, add `if (result.network) root.network = result.network;`.
  - An immediate read when the page appears, with no 300 ms debounce:

```qml
    property var shownTags: []
    onLiveTagsChanged: {
        const added = liveTags.filter(tag => !shownTags.includes(tag));
        shownTags = liveTags;
        if (added.includes("network") && opened && !busy) { liveDirty = Object.assign({}, liveDirty, {network: true}); readLive(); }
    }
```

  - The event source, rescan and follow-up read, next to `audioEvents`:

```qml
    Process {
        id: networkEvents
        running: root.opened && root.liveTags.includes("network")
        command: ["nmcli", "monitor"]
        stdout: SplitParser { onRead: _line => root.markLive("network") }
    }
    // Scans only while the page is on screen; NM's own background scanning is untouched.
    Timer {
        interval: 20000; repeat: true; triggeredOnStart: true
        running: root.opened && root.liveTags.includes("network")
        onTriggered: { if (!root.busy && !scanner.running) scanner.running = true; }
    }
    Process {
        id: scanner
        command: ["bash", root.configDir + "/scripts/settings/panel-request.sh", JSON.stringify({op: "networkScan"})]
        onExited: scanSettle.restart()
    }
    // A scan completes a few seconds later, and `nmcli monitor` may not report it (Task 1).
    Timer { id: scanSettle; interval: 5000; onTriggered: root.markLive("network") }
```

  - In the `IpcHandler`:

```qml
        function open(category: string): void {
            root.closing = false; root.opened = true;
            if (root.catalog.categories.some(c => c.id === category)) root.select(category);
        }
```

  - In `status()`'s JSON, add `network: root.network ? (root.network.running ? "up" : "down") : "none"`.

- [ ] **Step 6: The launcher, Waybar and the Proton mode.**
  - In `scripts/hyprland/settings-panel.sh`, after the binary-check loop:

```bash
page="${1:-}"
[[ -z $page || $page =~ ^[a-z]+$ ]] || { echo "Unknown settings page: $page" >&2; exit 2; }
```

  Replace the existing `toggle` line with:

```bash
if [[ -n $page ]]; then
    if qs -p "$entry" ipc call settings open "$page" >/dev/null 2>&1 9>&-; then exit 0; fi
elif qs -p "$entry" ipc call settings toggle >/dev/null 2>&1 9>&-; then exit 0; fi
export SETTINGS_PAGE="$page"
```

  - In `waybar/config.jsonc`, in `"network"`, set `"on-click": "~/.config/scripts/hyprland/settings-panel.sh network",`.
  - In `network.mjs`, set `PROTON_MODE` to the value Task 1 recorded. **If it's `"nm"`:**
    - In `test/backend.mjs`, replace the `/Proton VPN app/` rejection with `await dispatch({op:'vpn',uuid:'u-proton',active:false}); assert.deepEqual(nmCalls.at(-1), ['deactivate','u-proton'])`.
    - In `test/network.mjs`, the `networkView(snap, {protonApp: false})` default-mode checks remain valid, because every other call passes the mode explicitly.

- [ ] **Step 7: Run the tests, then check live.**

```bash
bash quickshell/settings-panel/test/run-tests.sh
pgrep -x hyprlock && echo LOCKED   # must print nothing before continuing
entry=quickshell/settings-panel/shell.qml
bash scripts/hyprland/settings-panel.sh network; sleep 1
qs -p $entry ipc call settings status | jq -c '{category,liveTags,network}'   # network, ["network"], "up"
pgrep -fc '^nmcli monitor$'                                                # 1
grim /tmp/claude-1000/network-page.png                                     # read it: list, Wired, VPN
qs -p $entry ipc call settings page appearance; sleep 0.5
pgrep -fc '^nmcli monitor$' || true                                        # 0
bash scripts/hyprland/settings-panel.sh network; sleep 0.5
qs -p $entry ipc call settings status | jq -r .category                    # network
qs -p $entry ipc call settings close; sleep 1
pgrep -af '^nmcli monitor$|settings-panel/shell.qml' || echo none          # none
```

Then run `pkill -USR2 -x waybar`, click the Waybar network icon, and confirm the panel opens on Network.

- [ ] **Step 8: Commit.**

```bash
git add quickshell/settings-panel/NetworkView.qml quickshell/settings-panel/SettingsView.qml quickshell/settings-panel/shell.qml quickshell/settings-panel/network.mjs quickshell/settings-panel/test scripts/hyprland/settings-panel.sh waybar/config.jsonc
git commit -m "feat(settings): Network page with live Wi-Fi list, VPN and Waybar entry"
```

---

### Task 6: Date & Region rows, the privilege flow and a searchable dropdown

**Goal:** Time zone, NTP, language and formats rows that read cheaply and write through polkit. While a prompt is open the panel releases keyboard focus (and hides, if Task 1 said so). A cancelled prompt changes nothing and says so. Long dropdowns get a filter field.

**Files:**
- Create: `quickshell/settings-panel/dbus.js`
- Create: `quickshell/settings-panel/region.js`
- Modify: `quickshell/settings-panel/backend.js`
- Modify: `quickshell/settings-panel/catalog.json` (`region` category, four rows)
- Modify: `quickshell/settings-panel/shell.qml` (`authPending`, focus, visibility)
- Modify: `quickshell/settings-panel/SettingsView.qml` (auth banner)
- Modify: `quickshell/settings-panel/SettingControl.qml` (`note`)
- Modify: `quickshell/settings-panel/PanelCombo.qml` (filter)
- Modify: `quickshell/settings-panel/test/backend.mjs`, `test/tst_Settings.qml`

**Acceptance Criteria:**
- [ ] A read of the four region rows on this machine returns `Europe/Rome`, `true` (with a note), `en_US.UTF-8` and `it_IT.UTF-8`
- [ ] Time-zone choices number 598 on this machine, and locale choices are exactly the `*.UTF-8` lines of `localectl list-locales`
- [ ] Writes call `SetTimezone(sb)`, `SetNTP(bb)` and `SetLocale(asb)` with `interactive: true`. Formats keeps `LANG` and every unrelated `LC_*`, and Language keeps every `LC_*`
- [ ] A polkit denial or cancellation rejects with exactly `Authentication was cancelled; nothing changed.`
- [ ] Changing an `auth` row sets `authPending`, which releases keyboard focus and shows the banner (objectName `authPending`). It's cleared when the write returns, success or failure
- [ ] `PanelCombo` with more than 20 choices shows a filter field (objectName `filter-<key>`). Typing narrows the popup case-insensitively, and Return picks the highlighted entry
- [ ] The full read stays within Task 1's baseline + 20 ms. If it doesn't, the zone-list cache (Step 7) is implemented, and then it does

**Verify:** `bash quickshell/settings-panel/test/run-tests.sh` passes, as does the live read in Step 9. One real time-zone change and revert is done with the user present.

**Steps:**

- [ ] **Step 1: Failing backend tests.** Add to the resolve hook:

```js
    if (specifier === './dbus.js') return {url:'data:text/javascript,'+encodeURIComponent('const m = () => globalThis.settingsMocks.dbus; export const callSystem = (...a) => m().callSystem(...a), getProperty = (...a) => m().getProperty(...a); export const CANCELLED = "Authentication was cancelled; nothing changed."'),shortCircuit:true}
```

Add the mock and fixtures before `globalThis.settingsMocks`:

```js
files.set('/etc/locale.conf', 'LANG=en_US.UTF-8\nLC_TIME=it_IT.UTF-8\nLC_NUMERIC=it_IT.UTF-8\nLC_COLLATE=C.UTF-8\n')
let dbusCalls = [], dbusDeny = false
const dbusMock = {
    getProperty: async (_name, _path, _iface, property) => ({NTP: true, NTPSynchronized: false}[property]),
    callSystem: async (_name, _path, _iface, method, signature, args, options = {}) => {
        if (method === 'ListTimezones') return [['Europe/Rome', 'America/New_York', 'America/Argentina/Buenos_Aires']]
        dbusCalls.push([method, signature, args, options.interactive === true])
        if (dbusDeny) throw new Error('Authentication was cancelled; nothing changed.')
        return []
    },
}
```

Then make three more mock changes:
  - Add `dbus: dbusMock,` to `settingsMocks`.
  - Add `file_read_link: path => path === '/etc/localtime' ? '/usr/share/zoneinfo/Europe/Rome' : null,` to the `GLib` mock.
  - In the `execAsync` mock, return `'C.UTF-8\nen_US.UTF-8\nit_IT.UTF-8\nde_DE.ISO-8859-1'` when `args[0] === 'localectl' && args[1] === 'list-locales'`.

Append:

```js
dbusCalls = []
result = await dispatch({op:'read',ids:['region.timezone','region.ntp','region.language','region.formats']})
assert.equal(result.values['region.timezone'].value, 'Europe/Rome')
assert.deepEqual(result.values['region.timezone'].choices.map(c => c.value), ['America/Argentina/Buenos_Aires','America/New_York','Europe/Rome'])
assert.equal(result.values['region.timezone'].choices[0].label, 'America / Argentina / Buenos Aires')
assert.equal(result.values['region.ntp'].value, true)
assert.equal(result.values['region.ntp'].note, 'Not synchronized yet')
assert.equal(result.values['region.language'].value, 'en_US.UTF-8')
assert.equal(result.values['region.formats'].value, 'it_IT.UTF-8')
assert.deepEqual(result.values['region.formats'].choices.map(c => c.value), ['C.UTF-8','en_US.UTF-8','it_IT.UTF-8'])
assert.equal(dbusCalls.length, 0)
console.log('ok: region reads come from files and D-Bus properties, without writes')

await dispatch({op:'set',id:'region.timezone',value:'America/New_York'})
await dispatch({op:'set',id:'region.ntp',value:false})
await dispatch({op:'set',id:'region.formats',value:'en_US.UTF-8'})
await dispatch({op:'set',id:'region.language',value:'it_IT.UTF-8'})
assert.deepEqual(dbusCalls, [
    ['SetTimezone','(sb)',['America/New_York',true],true],
    ['SetNTP','(bb)',[false,true],true],
    ['SetLocale','(asb)',[['LANG=en_US.UTF-8','LC_TIME=en_US.UTF-8','LC_NUMERIC=en_US.UTF-8','LC_COLLATE=C.UTF-8','LC_MONETARY=en_US.UTF-8','LC_PAPER=en_US.UTF-8','LC_NAME=en_US.UTF-8','LC_ADDRESS=en_US.UTF-8','LC_TELEPHONE=en_US.UTF-8','LC_MEASUREMENT=en_US.UTF-8','LC_IDENTIFICATION=en_US.UTF-8'],true],true],
    ['SetLocale','(asb)',[['LANG=it_IT.UTF-8','LC_TIME=it_IT.UTF-8','LC_NUMERIC=it_IT.UTF-8','LC_COLLATE=C.UTF-8'],true],true],
])
await assert.rejects(dispatch({op:'set',id:'region.timezone',value:'Mars/Olympus'}), /Unknown choice/)
await assert.rejects(dispatch({op:'set',id:'region.formats',value:'de_DE.ISO-8859-1'}), /Unknown choice/)
dbusDeny = true
await assert.rejects(dispatch({op:'set',id:'region.ntp',value:true}), {message: 'Authentication was cancelled; nothing changed.'})
dbusDeny = false
console.log('ok: region writes are interactive, merge locale keys, and report a cancelled prompt')
```

The mock's locale file doesn't change between the two `SetLocale` calls. That's intended: each write merges into what's on disk at that moment.

- [ ] **Step 2: Catalog.** Add a category after `power`:

```json
    {
      "id": "region",
      "title": "Date & Region",
      "description": "Time zone, clock and regional formats. System-wide changes ask for your password."
    },
```

Add these rows (Task 7 adds `region.clock` between NTP and Language):

```json
    {
      "category": "region",
      "id": "region.timezone",
      "title": "Time Zone",
      "description": "Used by the clock, calendars and logs",
      "keywords": ["timezone", "time", "zone", "tz"],
      "source": "region",
      "key": "timezone",
      "kind": "select",
      "choices": "timezones",
      "auth": true
    },
    {
      "category": "region",
      "id": "region.ntp",
      "title": "Set Time Automatically",
      "description": "Keep the clock in sync with internet time servers",
      "keywords": ["ntp", "sync", "time"],
      "source": "region",
      "key": "ntp",
      "kind": "toggle",
      "auth": true
    },
    {
      "category": "region",
      "id": "region.language",
      "title": "Language",
      "description": "System language (LANG). Applies to programs started after your next login.",
      "keywords": ["locale", "lang"],
      "source": "region",
      "key": "language",
      "kind": "select",
      "choices": "locales",
      "auth": true
    },
    {
      "category": "region",
      "id": "region.formats",
      "title": "Formats",
      "description": "Dates, numbers, currency, paper and units. Applies to programs started after your next login.",
      "keywords": ["locale", "date", "number", "currency", "units", "metric"],
      "source": "region",
      "key": "formats",
      "kind": "select",
      "choices": "locales",
      "auth": true
    },
```

- [ ] **Step 3: Run it and watch it fail.** Run `node quickshell/settings-panel/test/backend.mjs`. Expected: FAIL at the first region assertion.

- [ ] **Step 4: Implement `dbus.js`.** Extend `cancelled` so it matches the exact error text Task 1 recorded:

```js
import Gio from "gi://Gio"
import GLib from "gi://GLib"

export const CANCELLED = "Authentication was cancelled; nothing changed."
// Polkit refusals as systemd's daemons report them; Task 1 recorded the one a dismissed dialog returns.
const cancelled = /AccessDenied|NotAuthorized|InteractiveAuthorizationRequired|PolicyKit1\.Error/

// Plain JS in, fully unpacked JS out; `interactive` lets polkit show its dialog.
export function callSystem(name, path, iface, method, signature, args, { interactive = false } = {}) {
    return new Promise((resolve, reject) => {
        Gio.DBus.system.call(name, path, iface, method, signature ? new GLib.Variant(signature, args) : null, null,
            interactive ? Gio.DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION : Gio.DBusCallFlags.NONE,
            interactive ? 120000 : 5000, null, (connection, result) => {
                try { resolve(connection.call_finish(result).recursiveUnpack()) }
                catch (error) { reject(cancelled.test(error.message) ? new Error(CANCELLED) : error) }
            })
    })
}
export async function getProperty(name, path, iface, property) {
    const [value] = await callSystem(name, path, "org.freedesktop.DBus.Properties", "Get", "(ss)", [iface, property])
    return value
}
```

- [ ] **Step 5: Implement `region.js`.**

```js
import GLib from "gi://GLib"
import { execAsync } from "./process.js"
import { callSystem, getProperty } from "./dbus.js"

const timedate = ["org.freedesktop.timedate1", "/org/freedesktop/timedate1", "org.freedesktop.timedate1"]
const locale1 = ["org.freedesktop.locale1", "/org/freedesktop/locale1", "org.freedesktop.locale1"]
// Everything a "Formats" choice sets; LANG, LC_CTYPE, LC_COLLATE and LC_MESSAGES are left alone.
export const FORMAT_KEYS = ["LC_NUMERIC", "LC_TIME", "LC_MONETARY", "LC_PAPER", "LC_NAME", "LC_ADDRESS", "LC_TELEPHONE", "LC_MEASUREMENT", "LC_IDENTIFICATION"]

export function parseLocaleConf(text) {
    const vars = {}
    for (const line of text.split("\n")) {
        const match = line.match(/^\s*([A-Z_]+)=("?)([^"]*)\2\s*$/)
        if (match) vars[match[1]] = match[3]
    }
    return vars
}
// Order-preserving: existing keys keep their place, new ones are appended.
export function localeAssignments(current, key, value) {
    const next = { ...current }
    if (key === "language") next.LANG = value
    else for (const name of FORMAT_KEYS) next[name] = value
    return Object.entries(next).filter(([, v]) => v).map(([k, v]) => `${k}=${v}`)
}
function timezoneOf(link) {
    const match = link?.match(/zoneinfo\/(.+)$/)
    if (!match) throw new Error("The time zone is not set")
    return match[1]
}
// Files first: /etc/localtime and /etc/locale.conf cost nothing; D-Bus only for NTP.
export async function regionState(read) {
    const [ntp, synced] = await Promise.all([getProperty(...timedate, "NTP"), getProperty(...timedate, "NTPSynchronized")])
    return { timezone: timezoneOf(GLib.file_read_link("/etc/localtime")), ntp, synced, locale: parseLocaleConf(read("/etc/locale.conf")) }
}
export function regionValue(key, state) {
    switch (key) {
    case "timezone": return { value: state.timezone }
    case "ntp": return { value: state.ntp, note: state.synced ? "Synchronized with a time server" : "Not synchronized yet" }
    case "language": return { value: state.locale.LANG || "C.UTF-8" }
    case "formats": return { value: state.locale.LC_TIME || state.locale.LANG || "C.UTF-8" }
    }
    throw new Error("Unknown region setting")
}
export const regionEnumerators = {
    timezones: async (_row, _current, once) => (await once("timezones", async () => (await callSystem(...timedate, "ListTimezones", null, null))[0]))
        .slice().sort().map(zone => ({ label: zone.replace(/_/g, " ").replace(/\//g, " / "), value: zone })),
    locales: async (_row, _current, once) => (await once("locales", async () => (await execAsync(["localectl", "list-locales"])).split("\n")))
        .map(line => line.trim()).filter(line => /\.UTF-8$/i.test(line)).map(line => ({ label: line, value: line })),
}
export function setRegion(key, value, state) {
    if (key === "timezone") return callSystem(...timedate, "SetTimezone", "(sb)", [value, true], { interactive: true })
    if (key === "ntp") return callSystem(...timedate, "SetNTP", "(bb)", [value, true], { interactive: true })
    return callSystem(...locale1, "SetLocale", "(asb)", [localeAssignments(state.locale, key, value), true], { interactive: true })
}
```

- [ ] **Step 6: Wire the backend.**
  - Add `import { regionState, regionValue, regionEnumerators, setRegion, parseLocaleConf, localeAssignments } from "./region.js"`, and add `...regionEnumerators,` to `enumerators`.
  - In `snapshot`, change `let value, reset = false` to `let value, reset = false, note`, and add:

```js
            case "region": ({ value, note } = regionValue(row.key, await once("region", () => regionState(read)))); break
```

  - Replace the `values[id] = …` line with:

```js
            const extra = note ? { note } : {}
            values[id] = row.choices ? { value, reset, ...extra, choices: await choicesFor(row, value, once) } : { value, reset, ...extra }
```

  - In `change`'s switch:

```js
    case "region": return setRegion(row.key, value, await once("region", () => regionState(read)))
```

  **Only if Task 1 decided per-user formats work** (not expected):
  - Add `const PER_USER_FORMATS = true` near the top of `backend.js`, with a comment citing Task 1.
  - At the start of `change` after validation, add:

```js
    if (row.source === "region" && row.key === "formats" && PER_USER_FORMATS) {
        const path = configDir + "/locale.conf", current = exists(path) ? parseLocaleConf(read(path)) : {}
        return write(path, localeAssignments(current, "formats", value).filter(line => !line.startsWith("LANG=")).join("\n") + "\n")
    }
```

  - Remove `"auth": true` from `region.formats`.
  - Add `locale.conf` to `.gitignore`.
  - Add a `backend.mjs` case asserting the file content and that no `SetLocale` call happens.

- [ ] **Step 7: Zone-list cache, only if Step 9's timing exceeds baseline + 20 ms.** In `region.js`, add:

```js
// ListTimezones starts timedated; the list only changes when tzdata does.
export async function cachedZones(fetch, io) {
    const stamp = io.mtime("/usr/share/zoneinfo/tzdata.zi")
    try { const cached = JSON.parse(io.read(io.cachePath)); if (cached.stamp === stamp) return cached.zones } catch (_) {}
    const zones = await fetch()
    io.write(io.cachePath, JSON.stringify({ stamp, zones }))
    return zones
}
```

In `regionEnumerators.timezones`, wrap the fetch in `cachedZones(() => …, io)`. `io` is passed in through the `row`-independent third parameter: change `once` usage to `once("timezones", () => cachedZones(fetch, zoneIo))`. Export a `setZoneIo(io)` that `backend.js` calls once at import with:
- `{ cachePath: GLib.get_user_cache_dir() + "/settings-panel/timezones.json", read, write, mtime }`
- `mtime = path => Gio.File.new_for_path(path).query_info("time::modified", Gio.FileQueryInfoFlags.NONE, null).get_attribute_uint64("time::modified")`

Add a `backend.mjs` case: with an unchanged mtime, a second read makes no `ListTimezones` call. The mock `callSystem` must count that method for this case.

- [ ] **Step 8: QML — failing tests, then the UI.** Add to the mock controller:
  - `property bool authPending: false`
  - two rows:

```qml
            {id:"zone",category:"input",title:"Zone",description:"Time zone",kind:"select",choices:"timezones",auth:true},
            {id:"ntp",category:"input",title:"NTP",description:"Sync",kind:"toggle",auth:true}
```

  - values (in both the property and the `init()` literal): `zone: {value: "Europe/Rome", choices: Array.from({length: 30}, (_, i) => i === 7 ? {label: "Europe / Rome", value: "Europe/Rome"} : {label: "Zone " + i, value: "Z" + i})}` and `ntp: {value: true, note: "Synchronized with a time server"}`
  - `controller.authPending = false;` in `init()`

  Tests:

```qml
        function test_note_replaces_description() {
            controller.category = "input"; waitForRendering(view);
            const note = findChild(view, "note-ntp");
            verify(note);
            compare(note.text, "Synchronized with a time server");
        }
        function test_long_select_filters() {
            controller.category = "input"; waitForRendering(view);
            const combo = findChild(view, "select-zone");
            mouseClick(combo); waitForRendering(view);
            const filter = findChild(view, "filter-zone");
            verify(filter && filter.visible);
            for (const c of "rome") keyClick(c);
            compare(combo.shown.length, 1);
            compare(combo.shown[0].value, "Europe/Rome");
            keyClick(Qt.Key_Down); keyClick(Qt.Key_Return);
            compare(controller.calls.at(-1), {id: "zone", value: "Europe/Rome"});
        }
        function test_short_select_has_no_filter() {
            controller.category = "input"; waitForRendering(view);
            mouseClick(findChild(view, "select-focus")); waitForRendering(view);
            const filter = findChild(view, "filter-focus");
            verify(!filter || !filter.visible);
            keyClick(Qt.Key_Escape);
        }
        function test_auth_banner_and_disabled_controls() {
            controller.category = "input"; controller.authPending = true; controller.busy = true; waitForRendering(view);
            verify(findChild(view, "authPending").visible);
            verify(!findChild(view, "toggle-ntp").enabled);
        }
```

  Implementation:
  - **`SettingControl.qml`:** the description `Label` becomes:

```qml
                Label { objectName: control.settingState.note ? "note-" + control.row.id : ""; text: control.settingState.error || control.settingState.note || control.row.description; color: control.theme.foreground; opacity: 0.75; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
```

  - **`SettingsView.qml`:** after the `problem` rectangle, add:

```qml
                Rectangle {
                    objectName: "authPending"
                    visible: !!view.controller.authPending
                    Layout.fillWidth: true
                    implicitHeight: authLabel.implicitHeight + 24
                    radius: 10; color: view.plate; border.color: view.accent; border.width: 2
                    Label { id: authLabel; anchors.fill: parent; anchors.margins: 12; text: "Waiting for authentication…"; color: view.foreground; wrapMode: Text.WordWrap; Accessible.role: Accessible.AlertMessage }
                }
```

  - **`PanelCombo.qml`:** replace `model`, `currentIndex`, `displayText` and `onActivated` with:

```qml
    property string filter: ""
    readonly property bool filterable: combo.choices.length > 20
    readonly property var shown: {
        const words = combo.filter.toLocaleLowerCase().trim();
        return words ? combo.choices.filter(item => String(item.label).toLocaleLowerCase().includes(words)) : combo.choices;
    }
    model: combo.shown
    currentIndex: combo.shown.findIndex(item => String(item.value) === String(combo.value))
    displayText: currentIndex < 0 ? (combo.choices.find(item => String(item.value) === String(combo.value))?.label ?? String(combo.value ?? "")) : currentText
    onActivated: index => { combo.picked(combo.shown[index].value); combo.filter = ""; }
```

  Replace the popup's `contentItem` with this, keeping the `Popup`'s existing `implicitHeight` cap of 320:

```qml
        contentItem: ColumnLayout {
            spacing: 4
            TextField {
                id: filterField
                objectName: "filter-" + combo.key
                visible: combo.filterable
                Layout.fillWidth: true
                placeholderText: "Type to filter"
                text: combo.filter
                onTextEdited: { combo.filter = text; combo.highlightedIndex = -1; }
                color: combo.theme.foreground
                Keys.onDownPressed: combo.highlightedIndex = Math.min(combo.highlightedIndex + 1, combo.shown.length - 1)
                Keys.onUpPressed: combo.highlightedIndex = Math.max(combo.highlightedIndex - 1, 0)
                Keys.onReturnPressed: { if (combo.highlightedIndex >= 0) { combo.activated(combo.highlightedIndex); combo.popup.close(); } }
                Keys.onEscapePressed: combo.popup.close()
            }
            ListView {
                clip: true
                Layout.fillWidth: true
                implicitHeight: Math.min(contentHeight, combo.filterable ? 272 : 312)
                model: combo.popup.visible ? combo.delegateModel : null
                currentIndex: combo.highlightedIndex
                boundsBehavior: Flickable.StopAtBounds
            }
        }
```

  Add `onOpened: { combo.filter = ""; if (combo.filterable) filterField.forceActiveFocus(); }` to the `Popup`.

  The existing `test_dropdown_popup_theme_and_keyboard_selection`, `test_long_select_popup_height_is_capped` and `test_unknown_select_value_is_displayed` must still pass.
  - **`shell.qml`:**

```qml
    property bool authPending: false
    // Task 1: whether hyprpolkitagent's dialog can be seen and used over this Overlay surface.
    readonly property bool authHidesPanel: true
```

  Set `authHidesPanel` to the value Task 1 recorded. `change()` becomes:

```qml
    function change(id, value) {
        if (catalog.rows.find(row => row.id === id)?.auth) authPending = true;
        submit({op: "set", id: id, value: value});
    }
```

  Add `root.authPending = false;` as the first line of `writer.onExited`. On the `PanelWindow`:

```qml
        visible: root.opened && !(root.authPending && root.authHidesPanel)
        WlrLayershell.keyboardFocus: root.opened && !root.authPending ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
```

  A cancelled prompt reaches `problem` through the existing writer error path, because the backend throws `CANCELLED`.

- [ ] **Step 9: Run the tests, then check live.**

```bash
bash quickshell/settings-panel/test/run-tests.sh
bash scripts/settings/panel-request.sh '{"op":"read","ids":["region.timezone","region.ntp","region.language","region.formats"]}' | jq -c '[.values[] | {value, note, n:(.choices|length?)}]'
req=$(jq -c '{op:"read",ids:[.rows[].id],monitors:true}' quickshell/settings-panel/catalog.json)
for i in 1 2 3 4 5; do s=$(date +%s%N); bash scripts/settings/panel-request.sh "$req" >/dev/null; echo $(( ($(date +%s%N)-s)/1000000 )); done | sort -n | sed -n 3p
```

Expected: `Europe/Rome`, `true` with a note, `en_US.UTF-8` and `it_IT.UTF-8`, 598 zones, and the UTF-8 locales. The median must be within Task 1's baseline + 20 ms. If it isn't, do Step 7 and re-measure.

**With the user present** (check `pgrep -x hyprlock` first):
1. Open **Date & Region** and pick time zone `Europe / London`.
2. The panel releases focus (and hides, if configured), and the dialog appears. The user authenticates.
3. `timedatectl show -p Timezone --value` prints `Europe/London`.
4. Pick `Europe / Rome` again. It shouldn't prompt within about 5 minutes (`auth_admin_keep`).
5. Tell the user to press Cancel if a dialog appears, and pick `Europe / London`. If it prompts, the panel reappears with "Authentication was cancelled; nothing changed." and the zone is still `Europe/Rome`. If the cached authorization skipped the prompt, set it back to `Europe/Rome` and record that the cancel path was covered by the unit test only.

- [ ] **Step 10: Commit.**

```bash
git add quickshell/settings-panel/dbus.js quickshell/settings-panel/region.js quickshell/settings-panel/backend.js quickshell/settings-panel/catalog.json quickshell/settings-panel/shell.qml quickshell/settings-panel/SettingsView.qml quickshell/settings-panel/SettingControl.qml quickshell/settings-panel/PanelCombo.qml quickshell/settings-panel/test
git commit -m "feat(settings): Date & Region rows with polkit-authorized writes"
```

---

### Task 7: 12/24 h clock

**Goal:** `options/clock` (`24h`/`12h`) drives the Waybar clock through a rendered `include` and the hyprlock hour label directly, and a catalog row edits it.

**Files:**
- Create: `options/clock` (content `24h`)
- Create: `scripts/waybar/clock-format.sh`
- Create: `scripts/waybar/test-clock-format.sh`
- Modify: `waybar/config.jsonc` (top-level `include`; clock `format` removed)
- Modify: `hypr/hyprlock.conf` (hour label)
- Modify: `install.sh` (render once)
- Modify: `quickshell/settings-panel/catalog.json` (`region.clock`)
- Modify: `quickshell/settings-panel/backend.js` (run the script after the option write)
- Modify: `quickshell/settings-panel/test/backend.mjs`

**Acceptance Criteria:**
- [ ] `clock-format.sh` writes `{ "clock": { "format": "{:%H:%M}" } }` for `24h`, a missing option or a garbage option, and `{ "clock": { "format": "{:%I:%M %p}" } }` for `12h`
- [ ] It always leaves the output existing, writes it through a temporary file and rename, and signals Waybar unless `--no-reload` is given
- [ ] `region.clock` is a select with `24h`/`12h`, and a write runs `clock-format.sh` exactly once
- [ ] Waybar shows AM/PM time after switching to 12 h and 24-hour time after switching back (screenshot check)
- [ ] The hyprlock hour label uses `%I` in 12 h and `%H` in 24 h
- [ ] `./doctor.sh` reports no new ERROR

**Verify:** `bash scripts/waybar/test-clock-format.sh` → three `ok:` lines. `node quickshell/settings-panel/test/backend.mjs` → `ok: clock row renders the Waybar include`. Plus the screenshot checks in Step 6.

**Steps:**

- [ ] **Step 1: Failing script test** `scripts/waybar/test-clock-format.sh`:

```bash
#!/bin/bash
set -euo pipefail
script="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/clock-format.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
run() { CLOCK_OPTION="$tmp/clock" CLOCK_INCLUDE="$tmp/out/clock.jsonc" bash "$script" --no-reload; cat "$tmp/out/clock.jsonc"; }
[[ $(run) == '{ "clock": { "format": "{:%H:%M}" } }' ]] || { echo 'missing option should render 24 h' >&2; exit 1; }
printf '12h\n' > "$tmp/clock"
[[ $(run) == '{ "clock": { "format": "{:%I:%M %p}" } }' ]] || { echo '12h not rendered' >&2; exit 1; }
echo 'ok: 12h renders the 12-hour format'
printf 'banana\n' > "$tmp/clock"
[[ $(run) == '{ "clock": { "format": "{:%H:%M}" } }' ]] || { echo 'garbage should fall back to 24 h' >&2; exit 1; }
echo 'ok: anything else falls back to 24 h'
[[ -z $(find "$tmp/out" -name 'clock.jsonc.*') ]] || { echo 'temporary file left behind' >&2; exit 1; }
echo 'ok: output always exists and no temporary file is left'
```

Run it. Expected: FAIL (`clock-format.sh: No such file`).

- [ ] **Step 2: Implement** `scripts/waybar/clock-format.sh`, and `chmod +x` both new scripts:

```bash
#!/bin/bash
# Render Waybar's clock format from options/clock into the include that
# waybar/config.jsonc names. Always leaves the include in place (24 h unless the
# option says 12h), so a fresh checkout or a garbled option still shows a clock.
set -euo pipefail
option="${CLOCK_OPTION:-$HOME/.config/options/clock}"
include="${CLOCK_INCLUDE:-${XDG_STATE_HOME:-$HOME/.local/state}/waybar/clock.jsonc}"
format='{:%H:%M}'
if [[ -r $option && $(<"$option") == 12h ]]; then format='{:%I:%M %p}'; fi
mkdir -p "${include%/*}"
tmp=$(mktemp "$include.XXXXXX")
printf '{ "clock": { "format": "%s" } }\n' "$format" > "$tmp"
mv -f "$tmp" "$include"
if [[ ${1:-} != --no-reload ]]; then pkill -USR2 -x waybar 2>/dev/null || true; fi
```

Run the test. Expected: three `ok:` lines.

- [ ] **Step 3: Consumers.**
  - `printf '24h\n' > options/clock`. `git check-ignore options/clock` must print nothing, so the file is tracked.
  - `waybar/config.jsonc`: add this as the first key of the top-level object, using the path form Task 1 Step 5 recorded:

```jsonc
  // The clock's format lives here (options/clock, rendered by
  // scripts/waybar/clock-format.sh). Waybar's own default is {:%H:%M}.
  "include": ["~/.local/state/waybar/clock.jsonc"],
```

  Then delete the `"format": "{:%H:%M}",` line inside `"clock"`.
  - `hypr/hyprlock.conf`: the hour label's `text` line becomes:

```
    text = cmd[update:1000] echo -e "$(date +"%$([ "$(cat ~/.config/options/clock 2>/dev/null)" = 12h ] && echo I || echo H)")"
```

  - `install.sh`: right after the `apply-wal.sh` block (line ~238–239), add:

```bash
if ! execute bash "$CONFIG_DIR/scripts/waybar/clock-format.sh" --no-reload; then
    warning "Could not render the Waybar clock format"
fi
```

  - **If Task 1 recorded that the include doesn't work**, do this instead of the include:
    1. `git mv waybar/config.jsonc waybar/config.jsonc.in`, and put `@CLOCK_FORMAT@` where the format was.
    2. Have `clock-format.sh` render it to `~/.cache/waybar/config.jsonc` with `sed "s|@CLOCK_FORMAT@|$format|"`, keeping the temp-and-rename.
    3. Make the tracked `waybar/config.jsonc` a symlink to `~/.cache/waybar/config.jsonc`, the cava/starship pattern.
    4. Change the test to check the rendered config (`CLOCK_TEMPLATE`, `CLOCK_OUTPUT` overrides).

- [ ] **Step 4: Catalog row and backend.** In `catalog.json`, after `region.ntp`, add:

```json
    {
      "category": "region",
      "id": "region.clock",
      "title": "Clock Format",
      "description": "Bar and lock screen clock",
      "keywords": ["12", "24", "hour", "am", "pm", "time"],
      "source": "option",
      "key": "clock",
      "kind": "select",
      "items": [{ "label": "24-hour (20:30)", "value": "24h" }, { "label": "12-hour (8:30 PM)", "value": "12h" }]
    },
```

In `backend.js`'s `option` apply callback, next to the font line, add:

```js
            if (row.key === "clock") await execAsync(["bash", configDir + "/scripts/waybar/clock-format.sh"])
```

In `test/backend.mjs`, right after the options fixture loop, add `files.set(base+'/options/clock','24h\n')`. Look at how the existing font test detects `apply-font.sh` in the `execAsync` mock, and record `bash` calls the same way. Then append:

```js
events = []
await dispatch({op:'set',id:'region.clock',value:'12h'})
assert.equal(files.get(base+'/options/clock'), '12h\n')
assert.equal(events.filter(e => e[0] === 'bash' && String(e[1]).endsWith('/scripts/waybar/clock-format.sh')).length, 1)
await assert.rejects(dispatch({op:'set',id:'region.clock',value:'13h'}), /Unknown choice/)
console.log('ok: clock row renders the Waybar include')
```

Adapt the `events` filter to the shape that mock records.

- [ ] **Step 5: Run the tests and the doctor.**

```bash
bash scripts/waybar/test-clock-format.sh && node quickshell/settings-panel/test/backend.mjs && ./doctor.sh | tail -5
```

Expected: all pass, and the doctor summary shows no new ERROR. If `references.sh` flags the include path as missing, run `bash scripts/waybar/clock-format.sh --no-reload` once to create it, as `install.sh` now does.

- [ ] **Step 6: Live check.**
  1. Run `bash scripts/waybar/clock-format.sh`, then take a screenshot of the bar:

```bash
geo=$(hyprctl layers -j | jq -r '[.. | objects | select(.namespace? == "waybar")][0] | "\(.x),\(.y) \(.w)x\(.h)"')
grim -g "$geo" /tmp/claude-1000/bar-24.png
```

  Read the screenshot. Expected: 24-hour time.
  2. Set **Date & Region → Clock Format** to 12-hour in the panel, take the screenshot again into `bar-12.png`, and expect `AM`/`PM`.
  3. Set it back to 24-hour.

  Hyprlock is checked in Task 11.

- [ ] **Step 7: Commit.**

```bash
git add options/clock scripts/waybar/clock-format.sh scripts/waybar/test-clock-format.sh waybar/config.jsonc hypr/hyprlock.conf install.sh quickshell/settings-panel/catalog.json quickshell/settings-panel/backend.js quickshell/settings-panel/test/backend.mjs
git commit -m "feat(settings): 12/24 h clock for Waybar and hyprlock"
```

---

### Task 8: `autostart.mjs` pure rules

**Goal:** A dependency-free module that reproduces systemd's XDG autostart generator rules for the files it's given, computes unit names and statuses, produces the minimal override, edits `Hidden` in place, and extracts the session commands from `autostart.lua`.

**Files:**
- Create: `quickshell/settings-panel/autostart.mjs`
- Create: `quickshell/settings-panel/test/autostart.mjs`
- Modify: `quickshell/settings-panel/test/run-tests.sh`

**Acceptance Criteria:**
- [ ] A user file replaces the system file with the same id, and origin is `system` / `user` / `override`
- [ ] `Hidden=true` and `X-GNOME-Autostart-enabled=false` mean disabled. `OnlyShowIn`/`NotShowIn` excluding `Hyprland`, or `X-systemd-skip=true`, set a `scope` reason instead
- [ ] A minimal override shows the system entry's name and binary
- [ ] `installed` is false when `TryExec`, or the first `Exec` word (quoted or not), is not on `PATH`
- [ ] `unitName("nm-applet.desktop")` is `app-nm\x2dapplet@autostart.service`, and `unitName("org.kde.discover.notifier.desktop")` keeps its dots
- [ ] Status is `missing` / `running` / `finished` / `failed` / `none`, with labels
- [ ] `setHidden` changes only `[Desktop Entry]`'s `Hidden` (and, on enable, `X-GNOME-Autostart-enabled=false`), leaving every other line and every other group untouched
- [ ] `isMinimalOverride` recognizes exactly the four-line form (comments and blank lines ignored)
- [ ] `sessionCommands` returns the literal commands from this repo's `autostart.lua`, with `…` after a concatenation and commented lines skipped

**Verify:** `node quickshell/settings-panel/test/autostart.mjs` → ten lines, each starting `ok:`.

**Steps:**

- [ ] **Step 1: Write the failing test** `quickshell/settings-panel/test/autostart.mjs`:

```js
import assert from 'node:assert/strict'
import fs from 'node:fs'
import * as autostart from '../autostart.mjs'

const system = [
    {id: 'nm-applet.desktop', text: '[Desktop Entry]\nName=Network\nExec=nm-applet\nNotShowIn=KDE;GNOME;\nIcon=nm-device-wireless\n'},
    {id: 'blueman.desktop', text: '[Desktop Entry]\nName=Blueman Applet\nExec=blueman-applet\n'},
    {id: 'gnome-only.desktop', text: '[Desktop Entry]\nName=GNOME thing\nExec=gnome-thing\nOnlyShowIn=GNOME;\n'},
    {id: 'skipped.desktop', text: '[Desktop Entry]\nName=Skipped\nExec=skip\nX-systemd-skip=true\n'},
    {id: 'kde.desktop', text: '[Desktop Entry]\nName=KDE thing\nExec=kde-thing\nNotShowIn=Hyprland;\n'},
]
const user = [
    {id: 'blueman.desktop', text: '[Desktop Entry]\nType=Application\nName=Blueman Applet\nHidden=true\n'},
    {id: 'arch-update-tray.desktop', text: '[Desktop Entry]\nName=Arch-Update Systray Applet\nExec=arch-update --tray\n'},
    {id: 'quoted.desktop', text: '[Desktop Entry]\nName=Quoted\nExec="/opt/My App/run" --flag\n'},
    {id: 'gnome-off.desktop', text: '[Desktop Entry]\nName=Gnome off\nExec=blueman-applet\nX-GNOME-Autostart-enabled=false\n'},
]
const onPath = binary => ['nm-applet', 'blueman-applet', 'gnome-thing', 'skip', 'kde-thing', '/opt/My App/run'].includes(binary)
const entries = autostart.autostartEntries({system, user, desktops: ['Hyprland'], onPath})
const byId = Object.fromEntries(entries.map(e => [e.id, e]))

assert.equal(byId['nm-applet.desktop'].origin, 'system')
assert.equal(byId['blueman.desktop'].origin, 'override')
assert.equal(byId['arch-update-tray.desktop'].origin, 'user')
console.log('ok: user files replace system files by id')

assert.equal(byId['nm-applet.desktop'].enabled, true)
assert.equal(byId['nm-applet.desktop'].scope, '')
assert.equal(byId['blueman.desktop'].enabled, false)
assert.equal(byId['gnome-off.desktop'].enabled, false)
assert.match(byId['gnome-only.desktop'].scope, /Only for GNOME/)
assert.match(byId['kde.desktop'].scope, /Not for Hyprland/)
assert.match(byId['skipped.desktop'].scope, /systemd/)
console.log('ok: Hidden, GNOME flag, OnlyShowIn, NotShowIn and X-systemd-skip')

assert.equal(byId['blueman.desktop'].name, 'Blueman Applet')
assert.equal(byId['blueman.desktop'].binary, 'blueman-applet')
assert.equal(byId['arch-update-tray.desktop'].installed, false)
assert.equal(byId['arch-update-tray.desktop'].binary, 'arch-update')
assert.equal(byId['quoted.desktop'].binary, '/opt/My App/run')
assert.equal(byId['quoted.desktop'].installed, true)
console.log('ok: overrides describe the system entry; binaries are resolved')

assert.deepEqual(entries.slice(0, 2).map(e => e.id), ['arch-update-tray.desktop', 'nm-applet.desktop'])
console.log('ok: enabled-and-applicable first, then by name')

assert.equal(autostart.unitName('nm-applet.desktop'), 'app-nm\\x2dapplet@autostart.service')
assert.equal(autostart.unitName('org.kde.discover.notifier.desktop'), 'app-org.kde.discover.notifier@autostart.service')
assert.equal(autostart.unitName('a b.desktop'), 'app-a\\x20b@autostart.service')
console.log('ok: unit names use systemd escaping')

const units = [
    {unit: 'app-nm\\x2dapplet@autostart.service', active: 'active', sub: 'running'},
    {unit: 'app-gnome\\x2doff@autostart.service', active: 'failed', sub: 'failed'},
    {unit: 'app-quoted@autostart.service', active: 'inactive', sub: 'dead'},
]
const status = Object.fromEntries(autostart.withStatus(entries, units).map(e => [e.id, e.status]))
assert.deepEqual(status['nm-applet.desktop'], {state: 'running', label: 'Running'})
assert.deepEqual(status['gnome-off.desktop'], {state: 'failed', label: 'Failed'})
assert.deepEqual(status['quoted.desktop'], {state: 'finished', label: 'Finished'})
assert.deepEqual(status['arch-update-tray.desktop'], {state: 'missing', label: 'Not installed: arch-update'})
assert.deepEqual(status['blueman.desktop'], {state: 'none', label: ''})
console.log('ok: status from list-units, missing binaries first')

assert.equal(autostart.minimalOverride('Blueman\nApplet'), '[Desktop Entry]\nType=Application\nName=Blueman Applet\nHidden=true\n')
assert.equal(autostart.isMinimalOverride(user[0].text), true)
assert.equal(autostart.isMinimalOverride('# note\n\n' + user[0].text), true)
assert.equal(autostart.isMinimalOverride(user[0].text + 'Comment=mine\n'), false)
assert.equal(autostart.isMinimalOverride(user[1].text), false)
console.log('ok: minimal override text and recognition')

const full = '# keep\n[Desktop Entry]\nName=X\nExec=x\nX-GNOME-Autostart-enabled=false\n\n[Desktop Action new]\nHidden=true\nExec=x --new\n'
const hidden = autostart.setHidden(full, true)
assert.equal(hidden, '# keep\n[Desktop Entry]\nName=X\nExec=x\nX-GNOME-Autostart-enabled=false\nHidden=true\n\n[Desktop Action new]\nHidden=true\nExec=x --new\n')
assert.equal(autostart.setHidden(hidden, false), '# keep\n[Desktop Entry]\nName=X\nExec=x\n\n[Desktop Action new]\nHidden=true\nExec=x --new\n')
assert.equal(autostart.setHidden('[Desktop Entry]\nName=Y\nHidden = true\n', true), '[Desktop Entry]\nName=Y\nHidden=true\n')
console.log('ok: setHidden edits only the main group and only Hidden / the GNOME flag')

const parsed = autostart.parseEntry('[Desktop Entry]\nName=A\nName=B\n[Other]\nExec=no\n')
assert.deepEqual(parsed, {Name: 'A'})
console.log('ok: parseEntry keeps the first key and only the main group')

const lua = fs.readFileSync(new URL('../../../hypr/config/setup/autostart.lua', import.meta.url), 'utf8')
const commands = autostart.sessionCommands(lua)
assert.equal(commands[0], 'waybar')
assert.ok(commands.includes('systemctl --user start …'))
assert.ok(commands.includes('wl-paste --type text --watch cliphist store'))
assert.deepEqual(autostart.sessionCommands('-- hl.exec_cmd("commented")\nhl.exec_cmd("a \\"q\\"")'), ['a "q"'])
console.log('ok: session commands parsed from autostart.lua')
```

Add `node "$test_dir/autostart.mjs"` to `run-tests.sh`. Run it. Expected: `ERR_MODULE_NOT_FOUND`.

- [ ] **Step 2: Implement** `quickshell/settings-panel/autostart.mjs`:

```js
// The rules systemd-xdg-autostart-generator applies, over file contents handed
// in by the backend. Pure, so the whole Startup page logic runs under Node.

export function parseEntry(text) {
    const entry = {}
    let main = false
    for (const raw of text.split("\n")) {
        const line = raw.trim()
        if (line.startsWith("[")) { main = line === "[Desktop Entry]"; continue }
        if (!main || !line || line.startsWith("#")) continue
        const eq = line.indexOf("=")
        if (eq < 0) continue
        const key = line.slice(0, eq).trim()
        if (!(key in entry)) entry[key] = line.slice(eq + 1).trim()
    }
    return entry
}
const list = value => (value || "").split(";").map(s => s.trim()).filter(Boolean)
export function execBinary(entry) {
    if (entry.TryExec) return entry.TryExec
    const match = (entry.Exec || "").match(/^\s*(?:"((?:[^"\\]|\\.)*)"|(\S+))/)
    return match ? (match[1] ?? match[2]).replace(/\\(.)/g, "$1") : ""
}
function scopeOf(entry, desktops) {
    if (entry["X-systemd-skip"] === "true") return "Skipped by systemd"
    const only = list(entry.OnlyShowIn), not = list(entry.NotShowIn)
    if (only.length && !only.some(d => desktops.includes(d))) return `Only for ${only.join(", ")}`
    const excluded = not.filter(d => desktops.includes(d))
    if (excluded.length) return `Not for ${excluded.join(", ")}`
    return ""
}
export function autostartEntries({ system, user, desktops, onPath }) {
    const sys = new Map(system.map(f => [f.id, f.text]))
    const usr = new Map(user.map(f => [f.id, f.text]))
    return [...new Set([...sys.keys(), ...usr.keys()])].map(id => {
        const own = usr.get(id), base = sys.get(id)
        const effective = parseEntry(own ?? base)
        // A minimal override carries no Name/Exec of its own: describe the file it masks.
        const described = own !== undefined && base !== undefined && isMinimalOverride(own) ? parseEntry(base) : effective
        const binary = execBinary(described)
        return {
            id, name: described.Name || id.replace(/\.desktop$/, ""),
            origin: base === undefined ? "user" : own === undefined ? "system" : "override",
            enabled: effective.Hidden !== "true" && effective["X-GNOME-Autostart-enabled"] !== "false",
            scope: scopeOf(described, desktops), binary, installed: !binary || onPath(binary), unit: unitName(id),
        }
    }).sort((a, b) => (b.enabled && !b.scope) - (a.enabled && !a.scope) || a.name.localeCompare(b.name))
}

// systemd unit-name escaping: keep [A-Za-z0-9:_.], everything else becomes \xNN per byte.
export function unitName(id) {
    const escaped = [...new TextEncoder().encode(id.replace(/\.desktop$/, ""))]
        .map(byte => /[A-Za-z0-9:_.]/.test(String.fromCharCode(byte)) ? String.fromCharCode(byte) : "\\x" + byte.toString(16).padStart(2, "0")).join("")
    return `app-${escaped}@autostart.service`
}
export function withStatus(entries, units) {
    const byUnit = new Map(units.map(u => [u.unit, u]))
    return entries.map(entry => {
        const unit = byUnit.get(entry.unit)
        let status
        if (!entry.installed) status = { state: "missing", label: `Not installed: ${entry.binary}` }
        else if (!unit) status = { state: "none", label: entry.enabled && !entry.scope ? "Not started this session" : "" }
        else if (unit.active === "failed") status = { state: "failed", label: "Failed" }
        else if (unit.active === "active" || unit.active === "activating") status = { state: "running", label: "Running" }
        else status = { state: "finished", label: "Finished" }
        return { ...entry, status }
    })
}

export const minimalOverride = name => `[Desktop Entry]\nType=Application\nName=${name.replace(/[\r\n]+/g, " ")}\nHidden=true\n`
export function isMinimalOverride(text) {
    const lines = text.split("\n").map(l => l.trim()).filter(l => l && !l.startsWith("#"))
    return lines.length === 4 && lines[0] === "[Desktop Entry]" && lines.includes("Type=Application")
        && lines.includes("Hidden=true") && lines.some(l => l.startsWith("Name="))
}
// Only [Desktop Entry]'s Hidden (and on enable the GNOME flag) changes; every other line is kept.
export function setHidden(text, hidden) {
    const out = []
    let main = false, lastMain = -1
    for (const line of text.split("\n")) {
        const trimmed = line.trim()
        if (trimmed.startsWith("[")) { main = trimmed === "[Desktop Entry]"; out.push(line); if (main) lastMain = out.length - 1; continue }
        if (main && /^Hidden\s*=/.test(trimmed)) continue
        if (main && !hidden && /^X-GNOME-Autostart-enabled\s*=\s*false$/.test(trimmed)) continue
        out.push(line)
        if (main && trimmed) lastMain = out.length - 1
    }
    if (hidden) out.splice(lastMain + 1, 0, "Hidden=true")
    return out.join("\n")
}

export function sessionCommands(lua) {
    const code = lua.split("\n").filter(line => !line.trim().startsWith("--")).join("\n")
    return [...code.matchAll(/hl\.exec_cmd\(\s*"((?:[^"\\]|\\.)*)"(\s*\.\.)?/g)]
        .map(match => match[1].replace(/\\(.)/g, "$1").trimEnd() + (match[2] ? " …" : ""))
}
```

- [ ] **Step 3: Run it.** Run `node quickshell/settings-panel/test/autostart.mjs`. Expected: ten `ok:` lines. When something fails, fix the implementation. Change an expectation only if it contradicts the spec.

- [ ] **Step 4: Commit.**

```bash
git add quickshell/settings-panel/autostart.mjs quickshell/settings-panel/test/autostart.mjs quickshell/settings-panel/test/run-tests.sh
git commit -m "feat(settings): pure XDG autostart rules for the Startup page"
```

---

### Task 9: Startup page (backend and view)

> **Updated after the Task 8 review (systemd 262 generator verified against fixtures).** Apply these on top of the code below:
> - List files with `autostart.isAutostartFileName(name)`, not only `.endsWith(".desktop")` (dotfiles and backup files are skipped by the generator).
> - `desktops` and `onPath` must use the **systemd user manager's** environment, not the helper's: read `systemctl --user show-environment` once per read and take `XDG_CURRENT_DESKTOP` (split on `:`) and `PATH` from it; resolve a bare binary by searching that PATH (absolute paths: `exists`).
> - Enabling deletes the user file only when `entry.origin === "override"` and it is exactly the minimal override; a minimal-looking file that is the only copy (`origin === "user"`) is edited in place instead, never deleted.
> - Entries now carry `ignoredGnomeFlag` (systemd ignores `X-GNOME-Autostart-enabled=false`); the view shows "X-GNOME-Autostart-enabled has no effect under systemd" in that entry's status line. Entries with a `scope` (wrong desktop, not an Application, no Exec, skipped) get no switch.

**Goal:** The Startup page lists Hyprland's own session commands (read-only), then the XDG autostart apps with status, enable/disable, remove and add, then the three existing option rows.

**Files:**
- Modify: `quickshell/settings-panel/backend.js` (`startup` read flag, `autostart` and `autostartAdd` ops, `autostart-file` action)
- Create: `quickshell/settings-panel/StartupView.qml`
- Modify: `quickshell/settings-panel/SettingsView.qml` (host)
- Modify: `quickshell/settings-panel/shell.qml` (`startup` state; `startup` flag on reads; `select` reads the page's data)
- Modify: `quickshell/settings-panel/catalog.json` (the `startup` category description)
- Modify: `quickshell/settings-panel/test/backend.mjs`, `test/tst_Settings.qml`

**Acceptance Criteria:**
- [ ] `{"op":"read","ids":[],"startup":true}` on this machine lists `nm-applet.desktop` as `Running`, `arch-update-tray.desktop` as `Not installed: arch-update`, the session commands starting with `waybar`, and an `available` list of installed apps not already present
- [ ] Disabling a system entry writes exactly the minimal override, and enabling it again deletes that file
- [ ] Enabling a hand-edited override that has `Exec` removes only `Hidden`. One without `Exec` is refused with a message naming `~/.config/autostart/<id>`, and nothing is written
- [ ] Remove works only for `origin: "user"`. Add copies the app's desktop file byte for byte, and refuses ids already present
- [ ] Unknown ids and actions are refused before any file is touched
- [ ] The view shows the Session group, each app with its name and status, a switch only when the entry applies to Hyprland, Remove only on user entries, an **Add an app…** filterable dropdown, and "Takes effect at next login"
- [ ] The `startup` part of a read is requested only while the Startup page is current

**Verify:** `bash quickshell/settings-panel/test/run-tests.sh` passes. The live read in Step 6 prints the expected entries, and its median is ≤ 40 ms above an empty read.

**Steps:**

- [ ] **Step 1: Failing backend tests.** Add fixtures to `test/backend.mjs`, next to the other `files.set` calls:

```js
files.set(base + '/hypr/config/setup/autostart.lua', 'return function(apps)\n    hl.exec_cmd("waybar")\n    hl.exec_cmd("systemctl --user start " .. apps.polkitAgent)\nend\n')
files.set('/etc/xdg/autostart/nm-applet.desktop', '[Desktop Entry]\nName=Network\nExec=nm-applet\n')
files.set('/etc/xdg/autostart/blueman.desktop', '[Desktop Entry]\nName=Blueman Applet\nExec=blueman-applet\n')
files.set('/etc/xdg/autostart/manual.desktop', '[Desktop Entry]\nName=Manual\nExec=manual\n')
files.set(base + '/autostart/arch-update-tray.desktop', '[Desktop Entry]\nName=Arch-Update Systray Applet\nExec=arch-update --tray\n')
files.set(base + '/autostart/manual.desktop', '[Desktop Entry]\nName=Manual\nHidden=true\nComment=written by hand\n')
files.set('/usr/share/applications/firefox.desktop', '[Desktop Entry]\nName=Firefox\nExec=firefox %u\n')
dirs.set('/etc/xdg/autostart', ['nm-applet.desktop', 'blueman.desktop', 'manual.desktop'])
dirs.set(base + '/autostart', ['arch-update-tray.desktop', 'manual.desktop'])
```

Extend the mocks:
  - `find_program_in_path` returns `null` for `arch-update` as well as `missing-app`.
  - `getenv` returns `'Hyprland'` for `XDG_CURRENT_DESKTOP`.
  - Add `get_all` to `Gio.AppInfo`:

```js
        get_all: () => [
            {get_id: () => 'firefox.desktop', get_name: () => 'Firefox', should_show: () => true, get_filename: () => '/usr/share/applications/firefox.desktop'},
            {get_id: () => 'nm-applet.desktop', get_name: () => 'Network', should_show: () => false, get_filename: () => '/etc/xdg/autostart/nm-applet.desktop'}],
```

  - `execAsync` returns `JSON.stringify([{unit:'app-nm\\x2dapplet@autostart.service',active:'active',sub:'running'}])` when `args[0] === 'systemctl' && args[2] === 'list-units'`.
  - Check that the `File` mock's `delete` removes the path from `files` and records `['delete', path]`, and add that if missing. `write` must already record `['write', path]`.

Append:

```js
events = []
result = await dispatch({op:'read',ids:[],startup:true})
const apps = Object.fromEntries(result.startup.apps.map(a => [a.id, a]))
assert.deepEqual(result.startup.session, ['waybar', 'systemctl --user start …'])
assert.equal(apps['nm-applet.desktop'].status.state, 'running')
assert.equal(apps['arch-update-tray.desktop'].status.label, 'Not installed: arch-update')
assert.equal(apps['manual.desktop'].origin, 'override')
assert.deepEqual(result.startup.available, [{id:'firefox.desktop', name:'Firefox'}])
assert.equal(events.some(e => e[0] === 'write' || e[0] === 'delete'), false)
console.log('ok: startup read lists session, apps with status, and addable apps')

await dispatch({op:'autostart',action:'disable',id:'blueman.desktop'})
assert.equal(files.get(base+'/autostart/blueman.desktop'), '[Desktop Entry]\nType=Application\nName=Blueman Applet\nHidden=true\n')
dirs.get(base+'/autostart').push('blueman.desktop')
await dispatch({op:'autostart',action:'enable',id:'blueman.desktop'})
assert.equal(files.has(base+'/autostart/blueman.desktop'), false)
dirs.set(base+'/autostart', dirs.get(base+'/autostart').filter(n => n !== 'blueman.desktop'))
console.log('ok: disabling a system entry writes the minimal override; enabling deletes it')

const manualBefore = files.get(base+'/autostart/manual.desktop')
await assert.rejects(dispatch({op:'autostart',action:'enable',id:'manual.desktop'}), /~\/\.config\/autostart\/manual\.desktop/)
assert.equal(files.get(base+'/autostart/manual.desktop'), manualBefore)
await assert.rejects(dispatch({op:'autostart',action:'remove',id:'nm-applet.desktop'}), /Only apps you added/)
await assert.rejects(dispatch({op:'autostart',action:'disable',id:'../../etc/passwd'}), /no longer exists/)
await assert.rejects(dispatch({op:'autostart',action:'explode',id:'nm-applet.desktop'}), /Unknown startup action/)
console.log('ok: hand-edited overrides, system removals, unknown ids and actions are refused')

await dispatch({op:'autostartAdd',app:'firefox.desktop'})
assert.equal(files.get(base+'/autostart/firefox.desktop'), files.get('/usr/share/applications/firefox.desktop'))
dirs.get(base+'/autostart').push('firefox.desktop')
await assert.rejects(dispatch({op:'autostartAdd',app:'firefox.desktop'}), /Already in startup apps/)
await assert.rejects(dispatch({op:'autostartAdd',app:'nm-applet.desktop'}), /not installed/)
await dispatch({op:'autostart',action:'remove',id:'firefox.desktop'})
assert.equal(files.has(base+'/autostart/firefox.desktop'), false)
console.log('ok: add copies the desktop file; remove deletes only user entries')
```

The mock stores file contents as strings while `readBytes`/`writeBytes` work with bytes. Check how the existing mock handles `load_contents`/`replace_contents`, and compare with the same representation it uses. Run `node quickshell/settings-panel/test/backend.mjs`. Expected: FAIL, because `result.startup` is undefined.

- [ ] **Step 2: Implement the backend.** In `backend.js`:

```js
import * as autostart from "./autostart.mjs"

const autostartUser = `${configDir}/autostart`
const autostartSystem = "/etc/xdg/autostart"
const desktopFiles = dir => children(dir).filter(name => name.endsWith(".desktop") && !/[\r\n/]/.test(name)).map(id => ({ id, text: read(`${dir}/${id}`) }))
const onPath = binary => binary.startsWith("/") ? exists(binary) : !!GLib.find_program_in_path(binary)

async function startupState() {
    const entries = autostart.autostartEntries({
        system: desktopFiles(autostartSystem), user: desktopFiles(autostartUser),
        desktops: (GLib.getenv("XDG_CURRENT_DESKTOP") || "Hyprland").split(":"), onPath,
    })
    let units = []
    // Unit state is informative only; a systemd hiccup must not blank the page.
    try { units = JSON.parse(await execAsync(["systemctl", "--user", "list-units", "--all", "--output=json", "app-*@autostart.service"])) } catch (_) {}
    const present = new Set(entries.map(e => e.id))
    return {
        session: autostart.sessionCommands(read(configDir + "/hypr/config/setup/autostart.lua")),
        apps: autostart.withStatus(entries, units),
        available: Gio.AppInfo.get_all().filter(app => app.should_show() && !present.has(app.get_id()))
            .map(app => ({ id: app.get_id(), name: app.get_name() })).sort((a, b) => a.name.localeCompare(b.name)),
    }
}
async function autostartChange(request) {
    if (!["enable", "disable", "remove"].includes(request.action)) throw new Error("Unknown startup action")
    const entry = (await startupState()).apps.find(app => app.id === request.id)
    if (!entry) throw new Error("That startup app no longer exists")
    const path = `${autostartUser}/${entry.id}`
    if (request.action === "remove") {
        if (entry.origin !== "user") throw new Error("Only apps you added can be removed")
        return remove(path)
    }
    if (request.action === "disable") {
        if (entry.origin === "system") { makeParent(path); return write(path, autostart.minimalOverride(entry.name)) }
        return write(path, autostart.setHidden(read(path), true))
    }
    if (entry.origin === "system") return
    const text = read(path)
    if (entry.origin === "override" && autostart.isMinimalOverride(text)) return remove(path)
    // Without Exec the override would mask the system entry with nothing to run.
    if (!autostart.parseEntry(text).Exec) throw new Error(`~/.config/autostart/${entry.id} was edited by hand; remove it there to restore the system entry`)
    return write(path, autostart.setHidden(text, false))
}
function autostartAdd(request) {
    const app = Gio.AppInfo.get_all().find(candidate => candidate.get_id() === request.app && candidate.should_show())
    if (!app || !app.get_filename()) throw new Error("That application is not installed")
    const path = `${autostartUser}/${app.get_id()}`
    if (exists(path) || exists(`${autostartSystem}/${app.get_id()}`)) throw new Error("Already in startup apps")
    makeParent(path)
    writeBytes(path, readBytes(app.get_filename()))
}
```

`write`/`writeBytes` use `replace_contents`, which writes a temporary file and renames it, so every write is atomic.

In `snapshot`, before `return result`, add `if (views.startup) result.startup = await startupState()`. In `dispatch`, before the `action` branch:

```js
    if (request.op === "autostart") { await autostartChange(request); return {} }
    if (request.op === "autostartAdd") { autostartAdd(request); return {} }
```

Inside the `action` branch:

```js
        if (request.id === "autostart-file") {
            detached([readOption("terminal") || "ghostty", "-e", ...(readOption("editor") || "nvim").split(/\s+/), configDir + "/hypr/config/setup/autostart.lua"])
            return {}
        }
```

Run `node quickshell/settings-panel/test/backend.mjs`. Expected: the four new `ok:` lines.

- [ ] **Step 3: Failing QML tests.** Add to the mock controller:
  - `property var startup: null`
  - the category `{id:"startup",title:"Startup",description:"Login"}`
  - the row `{id:"opt-lock",category:"startup",title:"Lock",description:"Lock on autologin",kind:"toggle"}`
  - `"opt-lock": {value: false}` in both values literals
  - `controller.startup = null;` in `init()`

  Tests:

```qml
        function startupFixture() {
            return {session: ["waybar", "systemctl --user start …"],
                apps: [
                    {id: "nm-applet.desktop", name: "Network", origin: "system", enabled: true, scope: "", installed: true, status: {state: "running", label: "Running"}},
                    {id: "mine.desktop", name: "Mine", origin: "user", enabled: true, scope: "", installed: true, status: {state: "none", label: "Not started this session"}},
                    {id: "kde.desktop", name: "KDE thing", origin: "system", enabled: true, scope: "Not for Hyprland", installed: true, status: {state: "none", label: ""}},
                    {id: "arch-update-tray.desktop", name: "Arch-Update", origin: "user", enabled: true, scope: "", installed: false, status: {state: "missing", label: "Not installed: arch-update"}}],
                available: [{id: "firefox.desktop", name: "Firefox"}]};
        }
        function test_startup_view() {
            controller.startup = startupFixture(); controller.category = "startup"; waitForRendering(view);
            compare(findChild(view, "session-0").text, "waybar");
            verify(findChild(view, "startup-nm-applet.desktop"));
            verify(!findChild(view, "startupSwitch-kde.desktop"), "an entry that does not apply to Hyprland has no switch");
            verify(!findChild(view, "startupRemove-nm-applet.desktop"), "system entries cannot be removed");
            mouseClick(findChild(view, "startupSwitch-nm-applet.desktop"));
            compare(controller.calls.at(-1), {op: "autostart", action: "disable", id: "nm-applet.desktop"});
            mouseClick(findChild(view, "startupRemove-mine.desktop"));
            compare(controller.calls.at(-1), {op: "autostart", action: "remove", id: "mine.desktop"});
            verify(findChild(view, "startupStatus-arch-update-tray.desktop").text.indexOf("arch-update") >= 0);
            verify(findChild(view, "toggle-opt-lock"), "the option rows still render below the view");
        }
        function test_startup_add() {
            controller.startup = startupFixture(); controller.category = "startup"; waitForRendering(view);
            const combo = findChild(view, "select-startupAdd");
            mouseClick(combo); waitForRendering(view);
            combo.highlightedIndex = 0;
            keyClick(Qt.Key_Return);
            compare(controller.calls.at(-1), {op: "autostartAdd", app: "firefox.desktop"});
        }
```

Run them. Expected: FAIL.

- [ ] **Step 4: Implement `StartupView.qml`.**

```qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Hyprland's own session (read-only, parsed from autostart.lua) and the XDG
// autostart set that uwsm's systemd generator launches at login.
ColumnLayout {
    id: page
    required property var controller
    required property var theme
    readonly property var model: controller.startup
    spacing: 8

    Label { visible: !page.model; text: "Reading startup apps…"; color: page.theme.foreground; opacity: 0.75 }

    RowLayout {
        visible: !!page.model
        Layout.fillWidth: true
        Label { text: "Started by Hyprland's config"; color: page.theme.foreground; font.pixelSize: 16; font.bold: true; Layout.fillWidth: true }
        PanelButton { objectName: "editAutostartLua"; theme: page.theme; text: "Edit file"; onClicked: page.controller.action("autostart-file") }
    }
    Repeater {
        model: page.model ? page.model.session : []
        delegate: Label {
            required property var modelData
            required property int index
            objectName: "session-" + index
            text: modelData
            color: page.theme.foreground; opacity: 0.85; font.family: "monospace"; font.pixelSize: 12
            Layout.fillWidth: true; elide: Text.ElideRight
        }
    }

    RowLayout {
        visible: !!page.model
        Layout.fillWidth: true; Layout.topMargin: 12
        Label { text: "Apps"; color: page.theme.foreground; font.pixelSize: 16; font.bold: true; Layout.fillWidth: true }
        Label { text: "Takes effect at next login"; color: page.theme.foreground; opacity: 0.75; font.pixelSize: 12 }
    }
    Repeater {
        model: page.model ? page.model.apps : []
        delegate: Rectangle {
            id: app
            required property var modelData
            objectName: "startup-" + modelData.id
            Layout.fillWidth: true
            implicitHeight: appRow.implicitHeight + 16
            radius: 10; color: page.theme.plate
            RowLayout {
                id: appRow
                anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.margins: 8
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Label { text: app.modelData.name; color: page.theme.foreground; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                    Label {
                        objectName: "startupStatus-" + app.modelData.id
                        text: [app.modelData.scope, app.modelData.status.label, app.modelData.origin === "user" ? "Added by you" : ""].filter(Boolean).join(" · ")
                        color: page.theme.foreground; opacity: 0.75; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true
                    }
                }
                Loader {
                    active: app.modelData.origin === "user"
                    sourceComponent: PanelButton {
                        objectName: "startupRemove-" + app.modelData.id
                        theme: page.theme; text: "Remove"
                        enabled: !page.controller.busy
                        onClicked: page.controller.submit({op: "autostart", action: "remove", id: app.modelData.id})
                    }
                }
                Loader {
                    active: !app.modelData.scope
                    sourceComponent: Switch {
                        objectName: "startupSwitch-" + app.modelData.id
                        checked: app.modelData.enabled
                        enabled: !page.controller.busy
                        Accessible.name: app.modelData.name
                        onToggled: page.controller.submit({op: "autostart", action: checked ? "enable" : "disable", id: app.modelData.id})
                    }
                }
            }
        }
    }
    PanelCombo {
        visible: !!page.model && page.model.available.length > 0
        Layout.fillWidth: true
        theme: page.theme
        key: "startupAdd"
        choices: page.model ? page.model.available.map(item => ({label: item.name, value: item.id})) : []
        value: ""
        displayText: "Add an app…"
        Accessible.name: "Add a startup app"
        onPicked: value => page.controller.submit({op: "autostartAdd", app: value})
    }
}
```

Setting `displayText` here overrides `PanelCombo`'s internal binding, so the combo always reads "Add an app…".

- [ ] **Step 5: Host it and read it.** In `SettingsView.qml`, next to `NetworkView`, add:

```qml
                        StartupView {
                            visible: view.controller.category === "startup" && !view.controller.query.trim()
                            Layout.fillWidth: true
                            controller: view.controller
                            theme: view
                        }
```

In `shell.qml`:
  - Add `property var startup: null`.
  - In `refresh()`, add `startup: category === "startup"` to the read request.
  - In `reader.onExited`, add `if (result.startup) root.startup = result.startup;`.
  - Replace `select(id)` with:

```qml
    function select(id) {
        query = ""; category = id;
        // A page's own data is read when the page is first shown, and after every edit.
        if ((id === "startup" && !startup) || (id === "network" && !network)) refresh();
    }
```

In `catalog.json`, change the `startup` category description to `"Apps started at login, and what Hyprland itself starts"`.

- [ ] **Step 6: Run the tests, then check live.**

```bash
bash quickshell/settings-panel/test/run-tests.sh
bash scripts/settings/panel-request.sh '{"op":"read","ids":[],"startup":true}' | jq -c '{session:.startup.session[0:3], apps:[.startup.apps[] | [.id,.origin,.status.label]], available:(.startup.available|length)}'
for r in '{"op":"read","ids":[]}' '{"op":"read","ids":[],"startup":true}'; do
  for i in 1 2 3 4 5; do s=$(date +%s%N); bash scripts/settings/panel-request.sh "$r" >/dev/null; echo $(( ($(date +%s%N)-s)/1000000 )); done | sort -n | sed -n 3p; done
```

Expected: `waybar` first, `nm-applet.desktop` Running, `arch-update-tray.desktop` "Not installed: arch-update", and the second median at most 40 ms above the first.

Live UI (check `pgrep -x hyprlock` first):
1. Open **Startup**.
2. Disable **Blueman Applet**. `cat ~/.config/autostart/blueman.desktop` shows the four-line override.
3. Enable it again. The file is gone.

Nothing is started or stopped now.

- [ ] **Step 7: Commit.**

```bash
git add quickshell/settings-panel/backend.js quickshell/settings-panel/StartupView.qml quickshell/settings-panel/SettingsView.qml quickshell/settings-panel/shell.qml quickshell/settings-panel/catalog.json quickshell/settings-panel/test
git commit -m "feat(settings): Startup page manages XDG autostart apps"
```

---

### Task 10: Doctor check for per-user autostart entries

**Goal:** `./doctor.sh` warns about per-user autostart entries that would start a program that isn't installed, and notes minimal overrides that mask a system entry that no longer exists.

**Files:**
- Create: `scripts/doctor/checks/autostart.sh`
- Create: `scripts/doctor/test/test-autostart.sh`
- Modify: `doctor.sh` (module list and call)

**Acceptance Criteria:**
- [ ] One WARN per non-hidden `~/.config/autostart/*.desktop` whose `TryExec`, or first `Exec` word, isn't on `PATH`. On this machine that's `arch-update-tray.desktop`
- [ ] One INFO per minimal Hidden override with no `/etc/xdg/autostart` counterpart
- [ ] `ok` is printed only when there are no findings (including a missing directory)
- [ ] There's no `| while`, every path in a hint goes through `doctor_q`, helpers are prefixed `_as_`, and `_as_have_cmd`, `DOCTOR_AUTOSTART_DIR` and `DOCTOR_AUTOSTART_SYSTEM` can be stubbed
- [ ] `bash scripts/doctor/test/run-tests.sh` passes

**Verify:** `bash scripts/doctor/test/run-tests.sh` passes, and `./doctor.sh | sed -n '/Autostart/,/^$/p'` shows the arch-update-tray WARN.

**Steps:**

- [ ] **Step 1: Failing test** `scripts/doctor/test/test-autostart.sh`. First read `scripts/doctor/test/run-tests.sh` and one existing test file. Use their exact assertion helper names, the variable holding the temp dir, and the `ok` glyph `lib.sh` prints (below: `assert_eq`, `assert_contains`, `assert_not_contains`, `$DOCTOR_TEST_TMP`, `✓`). Run the check once into a file, never inside `$(…)`, or the counters are lost.

```bash
# Tests for scripts/doctor/checks/autostart.sh — sourced by run-tests.sh
# shellcheck shell=bash

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/autostart.sh"

as_out_file="$DOCTOR_TEST_TMP/autostart.out"
as_root="$DOCTOR_TEST_TMP/autostart"
mkdir -p "$as_root/user" "$as_root/system"
printf '[Desktop Entry]\nName=Tray\nExec=not-installed-tool --tray\n' > "$as_root/user/tray.desktop"
printf '[Desktop Entry]\nName=Fine\nExec=bash -c true\n' > "$as_root/user/fine.desktop"
printf '[Desktop Entry]\nName=Quoted\nExec="/nonexistent dir/run"\n' > "$as_root/user/quoted.desktop"
printf '[Desktop Entry]\nType=Application\nName=Gone\nHidden=true\n' > "$as_root/user/gone.desktop"
printf '[Desktop Entry]\nType=Application\nName=Kept\nHidden=true\n' > "$as_root/user/kept.desktop"
printf '[Desktop Entry]\nName=Kept\nExec=kept\n' > "$as_root/system/kept.desktop"
printf '[Desktop Entry]\nName=Off\nExec=also-missing\nHidden=true\nComment=hand\n' > "$as_root/user/off.desktop"

DOCTOR_AUTOSTART_DIR="$as_root/user"
DOCTOR_AUTOSTART_SYSTEM="$as_root/system"
doctor_reset
check_autostart > "$as_out_file" 2>&1
assert_eq "autostart: two warnings" "2" "$DOCTOR_WARNINGS"
assert_eq "autostart: one notice" "1" "$DOCTOR_NOTICES"
assert_contains "autostart: names the missing binary" "not-installed-tool" "$(cat "$as_out_file")"
assert_contains "autostart: handles a quoted Exec" "/nonexistent dir/run" "$(cat "$as_out_file")"
assert_contains "autostart: notes the orphaned override" "gone.desktop" "$(cat "$as_out_file")"
assert_not_contains "autostart: hidden entries are not checked for binaries" "also-missing" "$(cat "$as_out_file")"
assert_not_contains "autostart: no all-clear with findings" "✓" "$(cat "$as_out_file")"

DOCTOR_AUTOSTART_DIR="$as_root/absent"
doctor_reset
check_autostart > "$as_out_file" 2>&1
assert_eq "autostart: a missing directory is clean" "0" "$((DOCTOR_WARNINGS + DOCTOR_NOTICES))"
DOCTOR_AUTOSTART_DIR="" DOCTOR_AUTOSTART_SYSTEM=""
```

Run `bash scripts/doctor/test/run-tests.sh`. Expected: FAIL (`checks/autostart.sh` doesn't exist).

- [ ] **Step 2: Implement** `scripts/doctor/checks/autostart.sh`:

```bash
#!/bin/bash
#
# Per-user XDG autostart entries: the settings panel's Startup page writes
# them, and systemd's generator silently skips an entry whose program is not
# installed (arch-update-tray.desktop did exactly that). Everything is derived
# from the files themselves; nothing is listed here.
#
# These files are untracked (.gitignore: autostart/**), so this check reads
# live state rather than git. Severity is WARN: a missing tray applet never
# breaks the session.

DOCTOR_AUTOSTART_DIR="${DOCTOR_AUTOSTART_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/autostart}"
DOCTOR_AUTOSTART_SYSTEM="${DOCTOR_AUTOSTART_SYSTEM:-/etc/xdg/autostart}"

# _as_key <file> <key> -> the value in [Desktop Entry], first occurrence.
_as_key() {
    awk -v key="$2" '
        /^[[:space:]]*\[/ { main = ($0 ~ /^[[:space:]]*\[Desktop Entry\][[:space:]]*$/); next }
        main && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" { sub(/^[^=]*=[[:space:]]*/, ""); print; exit }
    ' "$1"
}

# _as_have_cmd <binary> — host probe, its own function so tests can stub it.
_as_have_cmd() { command -v -- "$1" >/dev/null 2>&1; }

# _as_binary <file> -> TryExec, else the first Exec word (double quotes honoured).
_as_binary() {
    local value
    value="$(_as_key "$1" TryExec)"
    if [ -n "$value" ]; then printf '%s\n' "$value"; return; fi
    value="$(_as_key "$1" Exec)"
    if [ "${value#\"}" != "$value" ]; then value="${value#\"}"; printf '%s\n' "${value%%\"*}"; return; fi
    printf '%s\n' "${value%% *}"
}

# _as_minimal <file> — exactly the four-line override the panel writes.
_as_minimal() {
    local lines
    lines="$(grep -v -e '^[[:space:]]*$' -e '^[[:space:]]*#' "$1")"
    [ "$(printf '%s\n' "$lines" | wc -l)" -eq 4 ] &&
        printf '%s\n' "$lines" | grep -qx '\[Desktop Entry\]' &&
        printf '%s\n' "$lines" | grep -qx 'Type=Application' &&
        printf '%s\n' "$lines" | grep -qx 'Hidden=true' &&
        printf '%s\n' "$lines" | grep -q '^Name='
}

check_autostart() {
    group "Autostart"
    local file name binary before=$((DOCTOR_WARNINGS + DOCTOR_NOTICES))
    if [ -d "$DOCTOR_AUTOSTART_DIR" ]; then
        while IFS= read -r -d '' file; do
            name="${file##*/}"
            if [ "$(_as_key "$file" Hidden)" = "true" ]; then
                if _as_minimal "$file" && [ ! -e "$DOCTOR_AUTOSTART_SYSTEM/$name" ]; then
                    note "$name hides a system autostart entry that no longer exists" "rm $(doctor_q "$file")"
                fi
                continue
            fi
            binary="$(_as_binary "$file")"
            [ -n "$binary" ] || continue
            if ! _as_have_cmd "$binary"; then
                warn "$name starts $binary, which is not installed, so it never runs" "Install $binary, or rm $(doctor_q "$file")"
            fi
        done < <(find "$DOCTOR_AUTOSTART_DIR" -maxdepth 1 -name '*.desktop' -print0 | sort -z)
    fi
    if [ $((DOCTOR_WARNINGS + DOCTOR_NOTICES)) -eq "$before" ]; then ok "Every per-user autostart entry resolves"; fi
}
```

`_as_minimal` pipes `printf` into `grep`. That's allowed, because the harness rule forbids `| while` loops, which would lose counter updates. In `doctor.sh`, append `autostart` to the module `for` list, and add `check_autostart` after `check_hardware`.

- [ ] **Step 3: Run the tests, shellcheck and the doctor.**

```bash
bash scripts/doctor/test/run-tests.sh
shellcheck scripts/doctor/checks/autostart.sh scripts/doctor/test/test-autostart.sh doctor.sh
./doctor.sh | sed -n '/Autostart/,/^$/p'
```

Expected: all pass, shellcheck prints nothing, and there's one WARN naming `arch-update-tray.desktop` and `arch-update`.

- [ ] **Step 4: Commit.**

```bash
git add scripts/doctor/checks/autostart.sh scripts/doctor/test/test-autostart.sh doctor.sh
git commit -m "feat(doctor): warn about autostart entries whose program is missing"
```

---

### Task 11: Docs, smoke test, performance budget and review

**Goal:** Round 3 is documented, the idle-cost and read budgets are measured and met, hyprlock is checked once, and the whole branch has an independent cross-family review with its findings fixed.

**Files:**
- Modify: `docs/settings-panel.md` (Network, Date & Region, Startup sections; measurements)
- Modify: `CLAUDE.md` (the settings panel section; doctor tree; `options/` list gains `clock`)
- Modify: `quickshell/settings-panel/test/live-smoke.sh`

**Acceptance Criteria:**
- [ ] `live-smoke.sh` also:
  - opens the Network page and asserts exactly one `nmcli monitor`;
  - asserts zero after switching page and after closing, and no panel process after closing;
  - asserts the `network` (≤ 30 ms) and `startup` (≤ 40 ms) read budgets over an empty read
- [ ] With the panel closed, `pgrep -af '^nmcli monitor$|settings-panel/shell.qml'` prints nothing
- [ ] The full-read median is within the Task 1 baseline + 20 ms, and all numbers are recorded in `docs/settings-panel.md` → `## Measurements`
- [ ] Hyprlock checked once, with the user: 12 h shows a 1–12 hour and 24 h shows 0–23, then it's set back to the user's choice
- [ ] `CLAUDE.md` describes the three new pages, the stdin write path, `options/clock`, and the doctor's `autostart.sh` (`_as_` prefix)
- [ ] `delegate-review` ran on `ee1ab1d..HEAD`, its findings were verified, and every confirmed one is fixed with a test
- [ ] `./test.sh` passes

**Verify:** `./test.sh` passes, `bash quickshell/settings-panel/test/live-smoke.sh` exits 0, and `git log --oneline ee1ab1d..HEAD` shows every task's commit.

**Steps:**

- [ ] **Step 1: Extend `live-smoke.sh`.** Change its `ipc` helper to `ipc() { qs -p "$entry" ipc call settings "$@"; }`. Before the final full-read query, add:

```bash
# Network page: exactly one event source while visible, none after leaving or closing.
bash "$config_dir/scripts/hyprland/settings-panel.sh" network
for ((attempt=0; attempt<100; attempt++)); do
    status=$(ipc status 2>/dev/null || true)
    if jq -e '.loading == false and .category == "network"' <<< "$status" >/dev/null 2>&1; then break; fi
    sleep 0.05
done
sleep 0.5
monitors=$(pgrep -fc '^nmcli monitor$' || true)
[[ $monitors == 1 ]] || { echo "Expected one nmcli monitor on the Network page, found $monitors" >&2; exit 1; }
ipc page appearance >/dev/null; sleep 0.5
[[ $(pgrep -fc '^nmcli monitor$' || true) == 0 ]] || { echo 'nmcli monitor kept running off the Network page' >&2; exit 1; }
ipc close >/dev/null; sleep 1
if pgrep -af '^nmcli monitor$|settings-panel/shell.qml'; then echo 'Something survived close' >&2; exit 1; fi
echo 'Network page: one monitor while visible, none after leaving or closing.'

# Page entry while another read is in flight must still load the network view
# (shell.qml readerNetwork/liveTimer path; SettingsView tests use a mock controller).
bash "$config_dir/scripts/hyprland/settings-panel.sh"
ipc page network >/dev/null
for ((attempt=0; attempt<60; attempt++)); do
    [[ $(ipc status | jq -r .network) == up ]] && break
    sleep 0.05
done
[[ $(ipc status | jq -r .network) == up ]] || { echo 'Network page entered during the first read never loaded' >&2; exit 1; }
ipc close >/dev/null; sleep 1

median() { sort -n | sed -n 3p; }
time_request() { for _ in 1 2 3 4 5; do s=$(date +%s%N); bash "$config_dir/scripts/settings/panel-request.sh" "$1" >/dev/null; echo $(( ($(date +%s%N)-s)/1000000 )); done | median; }
empty=$(time_request '{"op":"read","ids":[]}')
network=$(time_request '{"op":"read","ids":[],"network":true}')
startup=$(time_request '{"op":"read","ids":[],"startup":true}')
printf 'Empty %s ms, network %s ms, startup %s ms\n' "$empty" "$network" "$startup"
(( network - empty <= 30 )) || { echo 'network read over budget' >&2; exit 1; }
(( startup - empty <= 40 )) || { echo 'startup read over budget' >&2; exit 1; }
```

- [ ] **Step 2: Measure.** Run `pgrep -x hyprlock` (it must print nothing), then `bash quickshell/settings-panel/test/live-smoke.sh`. Then re-run Task 1 Step 1's full-read loop. Record in `docs/settings-panel.md` → `## Measurements`:
  - the full-read median against Task 1's
  - the empty/network/startup medians
  - the RSS of `nmcli monitor` while on the page (`ps -o rss= -C nmcli`)
  - "closed: no process"

  **If any budget fails, stop and fix it before continuing.** The zone-list cache (Task 6 Step 7) is the first lever for the full read.

- [ ] **Step 3: Hyprlock, with the user.**
  1. Set **Clock Format** to 12-hour in the panel and tell the user: "Locking now; check whether the hour shows 1–12, then unlock."
  2. Run `loginctl lock-session`.
  3. After unlock, set 24-hour and repeat, checking for 0–23.
  4. Record both answers in the docs, then leave the setting on whichever the user prefers.

- [ ] **Step 4: Docs.**
  - **`docs/settings-panel.md`:** add `## Network`, `## Date & Region` and `## Startup` sections. Each covers what it reads and writes, its live behaviour, and its traps:
    - the PSK only travels on stdin
    - a failed new connection is deleted
    - `PROTON_MODE` and why
    - polkit focus/visibility and the cancel error text
    - the `timedated` cold start
    - the Waybar include
    - the generator's rules and the minimal override
    - hand-edited overrides are never deleted
    - `arch-update-tray` was silently skipped
  - **`CLAUDE.md`, under "Settings panel (Super+I)":** add one paragraph covering:
    - Network (libnm via `nm.js`, pure `network.mjs`, `nmcli monitor` only while the page is visible, 20 s rescan, `PROTON_MODE`)
    - Date & Region (polkit through `dbus.js`, `authPending` releases focus, `options/clock` → `scripts/waybar/clock-format.sh` → `~/.local/state/waybar/clock.jsonc` include, hyprlock reads the option)
    - Startup (XDG autostart via uwsm's generator; `~/.config/autostart` is per-machine and gitignored; minimal `Hidden=true` overrides)
    - panel writes reach the helper on stdin
  - **The `options/` list:** add `clock`.
  - **The Doctor Architecture tree:** add `│   ├── autostart.sh         # check_autostart  — per-user XDG autostart entries whose program is missing`, and add `_as_` to the prefix list.

- [ ] **Step 5: Full test run.** Run `./test.sh`. Expected: every suite passes.

- [ ] **Step 6: Commit the docs and smoke test.**

```bash
git add docs/settings-panel.md CLAUDE.md quickshell/settings-panel/test/live-smoke.sh
git commit -m "docs(settings): round 3 Network, Date & Region, Startup; smoke test and budgets"
```

- [ ] **Step 7: Independent review.** Invoke the `delegate-review` skill on `ee1ab1d..HEAD`, with the goal and acceptance criteria taken from this plan and the spec. It deduplicates by diff hash. Following `CLAUDE.md`, the reviewer is from the other model family and doesn't see the implementers' reports. Verify every finding against the code yourself. For each confirmed one, add a failing test, fix it, and commit it as `fix(settings): …`, then re-run `./test.sh` and the smoke test. Record rejected findings, with the reason, in the final report.

- [ ] **Step 8: Update the memory note** `settings-panel-rounds.md`: record round 3 as done on the branch, the new traps, and the `PROTON_MODE`/`AUTH_HIDES_PANEL` decisions. Do not merge or push. The user decides that through `superpowers-extended-cc:finishing-a-development-branch`.
