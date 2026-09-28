# Settings Panel Round 2: Sound and Displays — Design

Approved 2026-09-28. Implementation plan:
`docs/superpowers/plans/2026-09-28-settings-panel-round-2.md`.

## Goal

Add a native **Sound** page and make the **Displays** page (today's `monitors`
category) editable, replacing `scripts/settings/advanced/monitor.sh`, which
appends machine-specific `hl.monitor()` lines to the tracked
`hypr/config/hardware/monitor.lua`.

**Performance is the first priority.** The panel adds nothing to the idle
system, and nothing to an open panel unless the Sound or Displays page is on
screen.

## Out of scope (owned elsewhere or deferred)

- Output volume, mute and per-app volume belong to the SwayNC sidebar and Waybar.
- The global `misc:vrr` row stays as it is, and there is no per-monitor VRR.
- Mirroring, bit depth, colour management/HDR and ICC profiles.
- A doctor check for state-file lines that name absent outputs.
- **Follow-up (recorded, not in this round):** the nine File Types rows fork
  `xdg-mime` on every full read, which is most of the ~280 ms open cost.

## Facts this design rests on (verified on this machine, 2026-09-28)

| Fact | How it was checked |
|---|---|
| PipeWire 1.6.9 with the pulse shim. There are two cards: onboard analog (Headphones / Line Out ports, 19 profiles) and NVIDIA HDMI. All three analog mic ports report `not available` | `pactl -f json info` / `list sinks` / `list sources` / `list cards` |
| Each `pactl -f json` call takes about 4 ms, and all four in parallel take 6 ms. `hyprctl monitors all -j` takes 3 ms | timed, 5 runs each |
| `pactl subscribe` uses about 5.7 MB RSS and fires on unrelated activity: a `notify-send` produced `Event 'change' on client` | sampled for 5 s |
| Quickshell 0.3.1 `Services.Pipewire` has nodes, defaults and volume but **no ports or card profiles** | `quickshell-service-pipewire.qmltypes` |
| `Quickshell.Hyprland` is already imported by `shell.qml` and exposes `Hyprland.rawEvent(event)` with `event.name`/`event.data` | `quickshell-hyprland-ipc.qmltypes` |
| `HL.MonitorSpec` keys: `output`, `mode`, `position`, `scale`, `transform`, `disabled` (plus others out of scope) | `/usr/share/hypr/stubs/hl.meta.lua` |
| `dofile`, `io.open` and `os.getenv` are available under the Lua provider; `XDG_STATE_HOME` is set in Hyprland's environment to `~/.local/state` | `hyprctl eval 'assert(...)'` → `ok` |
| `hyprctl eval` reports Lua errors as `error: …` | `hyprctl eval 'assert(false, "probe")'` |
| The systemd user manager has `HYPRLAND_INSTANCE_SIGNATURE` (UWSM session) | `systemctl --user show-environment` |
| `availableModes` entries look like `2560x1440@144.00Hz`; `hyprctl monitors all -j` includes disabled outputs with `disabled: true` | live JSON |

**Checked in plan Task 1 before anything is built**, because checking needs a
visible display change: that `eval` of an `hl.monitor()` for one output applies
immediately, that `hyprctl reload` puts back the file's rule, how Hyprland
treats a scale that doesn't divide the mode, and what a disabled output
reports.

## Design

### 1. Sound page

This is a new `sound` category, placed after Accessibility. It has six catalog
rows backed by a new `pulse` source, in a new module
`quickshell/settings-panel/pulse.js`.

| Row id | Kind | Choices | Write |
|---|---|---|---|
| `sound.output` | select | every sink, labelled by `description` | `pactl set-default-sink` |
| `sound.output-port` | select | ports of the default sink, excluding `availability == "not available"`, current one always kept | `pactl set-sink-port <default sink>` |
| `sound.output-profile` | select | profiles of the default sink's card with `available: true`, excluding `off` | `pactl set-card-profile <card>` |
| `sound.input` | select | sources whose `monitor_source` is `""`, which excludes sink monitors | `pactl set-default-source` |
| `sound.input-port` | select | same rule as output port, for the default source | `pactl set-source-port <default source>` |
| `sound.mic-level` | slider 0–100 | — | `pactl set-source-volume <default source> N%` |

- Each read request makes the four `pactl -f json` calls (`info`, `list sinks`,
  `list sources`, `list cards`) **once, in parallel**, through the snapshot's
  existing `once()` cache. All six rows share the result.
- Ports and profile always describe the **current default** device, so a
  change to the default device re-reads them as part of the normal refresh
  after the edit.
- `off` is excluded because selecting it would remove the device the row
  describes. Because the choices come from the same enumerator that validates
  writes, a device that has disappeared is rejected.
- No sound row has a reset. WirePlumber already persists defaults, ports and
  profiles in its own state, so no repo file is written.
- When there is no default source, or its port list is empty, the row shows an
  error in place of a value ("No input device"), and the rest of the page
  still loads.

### 2. Live refresh (Sound and Displays only)

- Catalog rows declare `"live": "audio"`. The Displays cards are tagged
  `displays`. `shell.qml` derives the set of *live tags on screen* from
  `visibleRows`, plus `displays` when the Displays page is shown with no
  search. The code never lists ids.
- `pactl subscribe` is a `Process` whose `running` is bound to "`audio` tag on
  screen and panel open". It stops when you leave the page and when the panel
  exits. Only `new|change|remove` events on `sink`, `source`, `card` or
  `server` count (the regex matches ` on (sink|source|card|server)( #|$)`);
  `sink-input`, `source-output`, `client` and `module` are ignored.
- Displays use a `Connections` on `Hyprland.rawEvent` that is active only
  while the page is shown. It reacts to `monitoradded`, `monitorremoved` and
  `configreloaded`, the last of which covers the guard's revert.
- Refreshes are **single-flight with a dirty flag**. At most one live read runs
  at a time, and events during it cause exactly one follow-up. A 300 ms
  debounce coalesces bursts. Echoes of the panel's own writes are absorbed:
  events that arrive while a write is queued or running are dropped, because
  the post-write refresh already re-reads everything.
- A live read asks only for the rows with that tag, not the full catalog. A
  row the user is interacting with (slider pressed, dropdown popup open) keeps
  its on-screen value. `SettingControl` reports that through
  `controller.interacting`, and the merge skips that id.

### 3. Displays page

**Where the configuration lives.** `hypr/config/hardware/monitor.lua` keeps its
host-neutral catch-all and then runs:

```lua
local state = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/hypr/monitors.lua"
local file = io.open(state, "r")
if file then file:close(); dofile(state) end
```

`~/.local/state/hypr/monitors.lua` is untracked, machine-specific and written
only by the panel. It holds a header comment and one `hl.monitor()` line per
output, in one exact format:

```lua
hl.monitor({ output = "DP-1", mode = "2560x1440@120.00", position = "auto-left", scale = 1.25, transform = 0 })
hl.monitor({ output = "HDMI-A-1", disabled = true })
```

A missing file means "all automatic", which is exactly today's behaviour. A
line for an output that doesn't match that format was edited by hand. The
panel then refuses to change that output and says so, the same rule it
applies to hypridle's hand-written suspend listener. An **Edit file** button
opens the state file in `options/editor` (via `options/terminal`) for anything
the page can't express. That replaces `monitor.sh`'s "edit directly" item.

**Removed:** `scripts/settings/advanced/monitor.sh`, the "Advanced display
setup" button, the `monitors` entry in `backend.js`'s `action` scripts, and the
references in `monitor.lua`, `README.md` and `scripts/doctor/checks/references.sh`.

**The cards.** The category keeps the id `monitors` and is retitled
"Displays". The backend reads `hyprctl monitors all -j`, the same single call
the panel already makes, with `all` added. It returns, for each output:
`saved` (the parsed state line, or `null` for Automatic), `handEdited`, and
`choices`:

- **Mode:** `Automatic` (`highres@highrr`) followed by `availableModes` with
  `Hz` removed, e.g. `2560x1440@144.00`, labelled `2560 × 1440 · 144 Hz`.
- **Scale:** every `k/120` for k = 120…360 where the logical width and height
  of the chosen mode are both whole numbers (for 2560×1440: 1, 1.07, 1.25,
  1.33, 1.6, 1.67, 2, 2.13, 2.5, 2.67), labelled as percentages. For
  Automatic, the largest mode's resolution is used. The UI recomputes the list
  locally when the staged mode changes, using the same function shared via
  `displays.mjs`.
- **Position:** Automatic (`auto`), Left / Right / Above / Below the other
  displays (`auto-left`, `auto-right`, `auto-up`, `auto-down`). Hyprland's
  keywords place a display relative to the whole layout. With two displays
  that is identical to "left of that display", and no pixel offsets are stored
  that would go stale when the other display's mode changes.
- **Rotation:** Normal, 90°, 180°, 270°, and Flipped for each (`transform` 0–7).
- **Enabled:** a switch. Turning off the last enabled output is refused.

Edits are **staged on the card**. One **Apply** submits all of them together,
so changing mode and scale produces one countdown, not two. **Automatic**
applies the catch-all values to that output and, on Keep, deletes its line.
**Set as main** stays as it is today.

### 4. Apply with revert

```
Apply ─▶ validate ─▶ arm guard (20 s) ─▶ hyprctl eval hl.monitor{new}
                                           │
   banner: "Keep this display layout? Reverting in 15 s   [Keep] [Revert]"
                                           │
   Keep ─────────────▶ guard still armed? stop it ─▶ write that output's line
   Revert / Esc / Close / 15 s ─▶ stop guard ─▶ hyprctl reload
   panel crash, screen black ───▶ guard fires hyprctl reload at 20 s
```

- **Guard:** `systemd-run --user --collect --unit=settings-display-revert
  --on-active=20 --timer-property=AccuracySec=100ms
  --setenv=HYPRLAND_INSTANCE_SIGNATURE=… <absolute hyprctl> reload`.
  - The unit name makes a second pending Apply impossible: `systemd-run`
    fails and the backend reports "A display change is waiting for Keep or
    Revert".
  - `--collect` leaves no failed unit behind.
- **Revert = reload.** The state file is written only on Keep, so reloading
  restores the last kept layout. Revert stops the guard first. Stopping a
  guard that already fired is not an error.
- **Keep** checks `systemctl --user is-active settings-display-revert.timer`.
  If the guard has already fired, Keep fails with "The change was already
  reverted" and writes nothing. Otherwise it stops the timer and then writes
  the file. The line written is **the same string** that was evaluated.
  Between Apply and Keep the backend keeps that string in
  `$XDG_RUNTIME_DIR/settings-panel/display-pending.json` (output, line, deadline), a tmpfs file removed
  on Keep and Revert.
- **The panel's timer (15 s) is shorter than the guard's (20 s)**, so normally
  the panel reverts cleanly and the guard is only the backstop. Closing the
  panel with a change pending queues a Revert before it quits, since
  `drain()` quits only after the queue empties.
- `hyprctl eval` errors (`error: …`) fail the Apply and stop the guard.
  Nothing was written, so nothing needs undoing.

### 5. Performance budget (acceptance criteria)

| State | Budget |
|---|---|
| Panel closed | No new process, unit, timer or autostart. `pgrep -f "pactl subscribe"` is empty. `systemctl --user list-units 'settings-display-*' --all` is empty with no change pending |
| Panel open, another page | No `pactl subscribe`; the Hyprland handler is inactive |
| Opening the panel | A full read of every row stays within the pre-round-2 time + 10 ms (measured before Task 2 and after Task 9) |
| Sound page visible, audio playing / notifications arriving | **Zero** backend reads (checked by counting `panel-request.sh` invocations) |
| A device change | One live read of the six sound rows |

## Units and interfaces

| Unit | Responsibility | Depends on |
|---|---|---|
| `pulse.js` (new) | `pulseState()`, `pulseValue(key, state)`, `pulseEnumerators`, `setPulse(key, value, state)` | `process.js` (`execAsync`) |
| `displays.mjs` (new; an ES module, the extension QML requires, imported by GJS, QML and Node) | Pure functions: `scaleChoices(w, h)`, `modeChoices(monitor)`, `monitorLine(config)`, `parseStateFile(text)`, `stateFileWith(text, output, line)` | nothing |
| `backend.js` | `pulse` source cases; the existing `monitors: true` read switched to `monitors all` and decorated with `saved`/`handEdited`/`choices`; `displayApply` / `displayKeep` / `displayRevert` ops (guard, eval, file); removal of the `monitors` action | the two modules above |
| `catalog.json` | `sound` category and six rows with `"live": "audio"`; the `monitors` category retitled "Displays" | — |
| `shell.qml` | Live tags, the `pactl subscribe` Process, the `rawEvent` Connections, single-flight live reads, `pendingDisplay`, revert-on-close, `interacting` | — |
| `DisplayCard.qml` (new) | One output: staged fields, Apply / Automatic / Set as main | `displays.mjs` for scale choices |
| `SettingsView.qml` | Hosts the cards, the pending banner and Edit file; drops the old inline card | — |
| `SettingControl.qml` | Reports `interacting` for pressed sliders and open popups | — |
| `hypr/config/hardware/monitor.lua` | Catch-all, then `dofile` of the state file if present | — |

## Testing

- `backend.mjs` gains mocks for `pactl -f json …`, `hyprctl monitors all -j`,
  `hyprctl eval`, `systemd-run` and `systemctl`, using JSON shapes copied from
  this machine. The cases:
  - enumerator filtering (unavailable ports, `off`, monitor sources);
  - write validation;
  - the four `pactl` calls made once per read;
  - `displayApply` refusing a bad mode, a bad scale, disabling the last
    output, a hand-edited line and a second pending change;
  - Keep writing exactly the evaluated line; Automatic deleting it;
  - Keep after the guard fired writing nothing;
  - Revert running `reload` and removing the pending file.
- `test/displays.mjs` covers the pure functions, including a state-file round trip
  that is byte-identical after add then remove.
- `tst_Settings.qml` covers staged card edits producing a single request, the
  banner countdown submitting Revert at 0, Keep, the hand-edited lock, and
  interaction reporting; revert on Escape/close is checked live.
- Live, on this machine:
  - switch the output to HDMI and back;
  - apply `2560x1440@120.00` and let it time out, then check 144 Hz is back;
  - apply again and Keep, then check the state file;
  - Automatic, then check the file has no DP-1 line;
  - `kill -9` the panel while a change is pending, then check the guard
    reverts at 20 s;
  - the performance-budget checks above.
