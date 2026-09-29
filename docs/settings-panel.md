# On-demand settings panel

Super+I and Waybar's settings button open `quickshell/settings-panel/shell.qml`.
The panel starts a fresh process, renders its frame, then reads all settings
asynchronously into a small session snapshot. Tab switches and search use those
values immediately, without starting another helper. Edits refresh the snapshot;
closing discards it, so reopening always reads current values. Escape, Close,
clicking outside, or Super+I closes it.
Once pending saves finish, the process exits. Failed saves keep the error visible
by reopening the panel. Text fields require Enter or Save; sliders save on release.

`catalog.json` is the only list of settings (95 rows in twelve categories on
September 28, 2026), with search, editable display cards, per-row resets and
the footer actions. Things another surface already owns stay there: the
keybind cheatsheet (Super+H), Do Not Disturb, output volume, mute and per-app
volume (SwayNC),
updates (Waybar), screenshot options (Rofi) and wallpapers (the carousel).
The palette is read through `scripts/theming/palette.sh` on every launch. The
wallpaper carousel remains a separate application with its existing lifecycle.

## Implementation

- `catalog.json` owns setting metadata, accepted ranges and dropdown choices.
  Each category's `icon` is a hex codepoint of a Material Design glyph in
  Symbols Nerd Font (`ttf-nerd-fonts-symbols`), drawn in the nav rail and beside
  the page title. It is text, so it follows the selection and palette colors —
  the Papirus symbolic icons would not (see the night light notes). Look names
  up in the font's cmap (`md-<name>`) rather than retyping glyphs.
- `SettingsView.qml` and `SettingControl.qml` build only visible category/search
  rows. Reads and writes never run synchronously on the QML thread. The first
  rows appear with their real values; loading never inserts/removes a layout row.
  Dropdown popups, option rows and selection highlights use the panel palette.
- `request.js` runs the GTK-free GJS backend for one JSON request and exits.
  `panel-request.sh` holds a lock across the complete request. Arguments stay
  argument arrays, including text containing quotes or shell metacharacters.
- `persist.js` and `hyprctl.js` own the shared persistence layer. Apply/save
  waits for Hyprland's `ok`; failed writes reload the saved config;
  resets remove just the selected override and reload the actual Lua defaults.
- The backend updates hypridle/sunset fields in place, preserving unrelated
  content, and restores files if applying them fails. SwayNC retains unrelated
  keys. Night light liveness uses `nightlight.sh`, never an identity getter.
- Rows may declare `choices` instead of fixed `items`. An enumerator in
  `backend.js` lists what is installed now (GTK, icon, cursor and Kvantum
  themes, power profiles, apps per MIME type); every read returns the list with
  the value and every write is validated against the same enumerator, so the
  dropdown and validation cannot disagree and no list of names is tracked.
  GTK's built-in themes (Adwaita, HighContrast, HighContrastInverse) are
  libgtk resources with no directory and are added explicitly.
- Text rows may declare `check`: `xkb-layout`/`xkb-variant`/`xkb-options`
  (checked against `localectl list-x11-keymap-*`, because a rejected keymap
  leaves Hyprland on the old one with only a log line), `font` (`fc-list`) and
  `command` (on `PATH`). `optional` rows accept an empty value; app rows with
  `reload` reload Hyprland, which reads `options/` at parse time. A layout
  reset is refused while a variant override exists.
- Sources: `gtk` writes gsettings, and for rows that declare an `ini` key also
  both tracked `settings.ini` files (GTK 3 on Wayland reads some keys from
  each; Text Size is gsettings-only); `kvantum` edits `theme=` under
  `[General]`; `mime` writes `xdg-mime default` into the tracked
  `mimeapps.list`, only for the row's types the chosen app declares or declares a
  parent of (never via `application/octet-stream`, which everything is),
  falling back to the row's first type when it declares none, and restores
  the file byte-for-byte on failure; `powerprofile` drives
  `powerprofilesctl`; the `idle` source adds, retimes and removes only the
  suspend listener it marked, and refuses to change a hand-written one;
  `pulse` (`pulse.js`) serves the six Sound rows from four `pactl -f json`
  reads (`info`, `list sinks/sources/cards`) made once per request in
  parallel. PipeWire's pulse server reports `card: null` on every sink, so a
  sink's card is the one whose name equals `properties["device.name"]`. Sink
  monitors are sources too and are left out of Input Device; unplugged ports
  and profiles without a sink (`off`, input-only) are left out of the
  choices. With no valid default, the device selector keeps its choices so
  the panel can recover, while ports, profile and level report the error.
- Live refresh: rows tagged `"live": "audio"`, and the unsearched Displays
  page, are re-read while they are on screen and nothing else is.
  `shell.qml` runs `pactl subscribe` only while an audio row is visible and
  counts only `sink`/`source`/`card`/`server` events (`sink-input` and
  `client` fire for every stream and notification); Displays listens to
  `Hyprland.rawEvent` monitor and reload events. Reads are debounced
  (300 ms), single-flight, limited to the tagged rows, dropped while a write
  or full read runs, and never overwrite the control being dragged or
  opened. Waking a suspended sink is a real `change on sink`, so the first
  sound after silence costs one or two reads while the Sound page is shown.
  The IPC call that switches page is `page`, not `show`: qs parses `show` as
  its own `ipc show` subcommand even inside `ipc call`.
- `hyprctl getoption -j` names the value field after its type (`bool`, `int`,
  `float`, `str`, `css`, `custom`); `set` only says whether the config assigns the
  option and is never a value. The Lua provider rejects legacy hyphenated
  names: use `input:touchpad:tap_to_click`, not `tap-to-click`.
- AGS no longer starts at login or after wallpaper changes. Its retired source
  and AGS/Astal packages are gone; GJS remains an explicit backend dependency.

## Displays

Per-machine display rules live outside the repo in
`${XDG_STATE_HOME:-~/.local/state}/hypr/monitors.lua`, one `hl.monitor()` per
output, written only by the Displays page. Edit file opens it in
`options/editor`; Hyprland does not watch it, so run Reload Hyprland after a
hand edit. The tracked `hypr/config/hardware/monitor.lua` keeps its
host-neutral catch-all and loads that file if present, in an environment that
can only record `hl.monitor()` calls; every value must be plain data (keys
are Hyprland's to judge, so a hand-added `vrr` or `bitdepth` applies), and
rules are applied only once the whole file has run, so a broken file leaves
the catch-all and shows a notification. A missing file means all automatic. A line the panel did not
write, or a second line for the same output, locks that output ("edited by
hand"). The main display cannot be turned off (hyprlock draws its password
field there); choose another main display first. While Hyprland loads its config,
`hl.monitor()` does not raise for a value it rejects (transform 9, a mode it
cannot parse): it records a config error and skips that one rule, so such a
hand edit shows in Hyprland's error banner instead.

Edits are staged on each card and one Apply sends them together. Apply arms
`systemd-run --user --collect --unit=settings-display-revert --on-active=20
… hyprctl reload`, then `hyprctl eval`s the new line, confirms the guard is
still armed, and only then records the pending change in
`$XDG_RUNTIME_DIR/settings-panel/display-pending.json`. The panel's banner
counts down 15 s; Revert, timeout, Escape and Close reload Hyprland (the
state file only changes on Keep, so a reload restores the last kept layout)
before disarming the guard. Keep writes the evaluated line while the guard is
still armed, stops it, and reloads so the live layout always equals the saved
file. If the panel dies or its screen goes dark, the guard reverts at 20 s.
While a change is pending every other setting and button waits, and the backend refuses every request but reads and the
display operations, since a reset or reload would silently undo it.

Verified on DP-1 (ROG PG279Q, 2560×1440) with Hyprland 0.56.2:

- `hyprctl eval 'hl.monitor({ output = "DP-1", ... })'` applies at once
  (143.998 → 119.998 Hz within 1 s); `hyprctl reload` restores the file's rule.
- Apply then nothing: the panel reverts at 15 s. Apply then `kill -9` of the
  panel: the guard reverts at about 21 s. Apply then Close: reverted in about
  140 ms. None leaves a unit, a pending record or a panel process.
- Scales, each accepted by `eval` with `ok` and no config error: `1.25` →
  1.25; `1.3333333333333333` → 1.3333334; `1.5` → **1.6, silently**. Hyprland
  substitutes a nearby scale when the logical size is not whole, so the panel
  offers only `k/120` scales that divide the staged mode.
- The systemd user manager of the UWSM session carries
  `HYPRLAND_INSTANCE_SIGNATURE`, which the guard inherits when a request has
  none. `systemctl stop` of an unloaded unit says `Unit … not loaded.`

## Round 3: verified behaviour

Probed 2026-09-28 on this machine (round-3 plan, Task 1).

### Baseline
Full read (every row plus monitors), five runs: 275, 275, 278, 281, 288 ms. Median **278 ms**.

### D-Bus cold start
`gdbus` `Get NTP` + `ListTimezones` (598 zones, 10.9 kB) after 40 s idle: cold **62 ms**, warm **14 ms**.
Both figures include two `gdbus` process starts, so the in-process cost is lower.

### nmcli monitor and scans
`nmcli monitor` prints `NetworkManager is running` once at start, then **nothing** for a
completed `nmcli device wifi rescan` (8 s watched). The list refresh after a scan therefore
comes from the panel's follow-up read (`scanSettle`). The banner line causes one extra
debounced read when the page opens, which is harmless.

### Quickshell stdin
A `Process` with `stdinEnabled: true` that calls `write()` in `onStarted` delivers the line:
the probe printed `got:{"op":"read"}`.

### Waybar include
Waybar 0.15 expands `~` in `include` (`Found config file: /home/you/.local/state/...`) and
merges key by key: with `"format": "MAIN"` in the main file, the trace says
`Option format is already set; ignoring value "PROBE ..."`, while the include's `interval`
was taken. A main `clock` object without `format` therefore takes the include's format.
Decision: **include at `~/.local/state/waybar/clock.jsonc`**. The screenshot check is deferred
to plan Task 7 (the session was locked during the probe).

### Proton VPN
Probed 2026-09-29 with the user present. `nmcli connection down "ProtonVPN IT#113"` deactivated
the tunnel, and the Proton app then **deleted** both the WireGuard profile and the
`pvpn-killswitch-ipv6` dummy, so there is nothing for `nmcli connection up` to bring back. Traffic
kept flowing over the real IP (the kill switch is not in permanent mode). The app showed a clean
"Disconnected", and reconnecting from the app created a new profile named after the new server
("ProtonVPN IT#116"). Decision: **`PROTON_MODE = "app"`**: the panel shows the state and opens the
Proton app, and never switches Proton's profile itself.

### Polkit dialog versus the overlay
Probed 2026-09-29 with the user present: with a panel-shaped Overlay surface up (keyboard focus
None), an interactive `SetTimezone` opened hyprpolkitagent's dialog (Waybar's title read
"Authentication Required") but the dialog was completely hidden behind the overlay and could not
be clicked. Decision: **`AUTH_HIDES_PANEL = true`**: the panel hides while a prompt is open.
A dismissed dialog returns `org.freedesktop.DBus.Error.AccessDenied: Permission denied`, which
`authError.mjs` maps to "Authentication was cancelled; nothing changed." (checked: the time zone
stayed Europe/Rome).

### Per-user locale
The systemd user manager already has `LANG=en_US.UTF-8` and `LC_TIME=it_IT.UTF-8`, and
`/etc/profile.d/locale.sh` reads `~/.config/locale.conf` only when `LANG` is unset.
Decision: **formats use SetLocale** (system-wide, polkit).

## Network

Reads: libnm through `nm.js` (`NM.Client.new(null)`, about 7.5 ms) for devices, access
points, saved profiles and VPN connections; `network.mjs` is pure and turns that
snapshot into the view (security grouping is under "Network: security rules").
Writes: connect/disconnect, forget, Wi-Fi radio, and new connections. **Advanced…**
opens `nm-connection-editor`; hidden SSIDs, enterprise Wi-Fi, WEP, hotspots and IP/DNS
editing are out of scope.

Live behaviour: while the page is on screen, exactly one `nmcli monitor` runs
(`/usr/bin/nmcli monitor`; pattern `^(/usr/bin/)?nmcli monitor$`) and a 20 s rescan timer
runs. Leaving the page or closing stops both. The monitor prints only a startup banner
and nothing on scans, so the list refresh after a rescan comes from the follow-up read.

Traps:

- **The PSK only travels on stdin.** Panel writes reach `panel-request.sh -` as one JSON
  line on the helper's stdin, never in argv, so a password cannot show in `ps` or a log.
- **A failed new connection is deleted.** A wrong password leaves no half-made profile.
- **`PROTON_MODE = "app"`.** The Proton app deletes its WireGuard profile on disconnect
  and creates a new one per server, so the panel shows the state and opens the app; it
  never brings a Proton profile up or down.
- **Nothing runs when closed:** no `nmcli monitor`, no timer, no panel process.
- `pgrep -f '^nmcli monitor$'` finds nothing: the real command line is
  `/usr/bin/nmcli monitor`.

## Date & Region

Reads `timedatectl show` and `localectl status` (both daemons are socket-activated:
about 100 ms cold). Writes time zone, NTP, language and formats through `timedated` and
`localed` over D-Bus (`dbus.js`), authorised by polkit. Clock format is not system-wide:
`options/clock` (`12h` or `24h`) is rendered by `scripts/waybar/clock-format.sh` into
`~/.local/state/waybar/clock.jsonc`, which Waybar merges through `include`; hyprlock reads
the option too.

Traps:

- **Polkit focus and visibility.** `AUTH_HIDES_PANEL = true` (`authHidesPanel` in
  `shell.qml`): a panel-shaped Overlay hid hyprpolkitagent's dialog completely, so the
  panel hides while `authPending` is set and comes back after the answer. A dismissed
  dialog returns `org.freedesktop.DBus.Error.AccessDenied: Permission denied`, shown as
  "Authentication was cancelled; nothing changed."
- **`timedated` cold start.** A first call after idle costs tens of ms more; the zone
  list (598 zones) is read once per full read.
- **The Waybar include** merges key by key and the main file's `clock` has no `format`,
  so the include's format wins; the include path is fixed (`~/.local/state/waybar/`).
- **Formats use `SetLocale`** (system-wide, polkit): a per-user `locale.conf` is not
  effective because the systemd user manager already exports `LANG`/`LC_TIME`.
- **Stale hyprlock is not a lock.** `pgrep -x hyprlock` alone is not a lock test: stale
  instances (0 CPU time) linger for a day, and they also defeat hypridle's
  `pidof`-guarded `lock_cmd`. Check `ps -o time= -p PID` before any synthetic input.

## Startup

Lists what Hyprland's `autostart.lua` starts (parsed, read-only, with **Edit file**) and
the XDG autostart apps. The apps follow uwsm's generator rules (`autostart.mjs` is pure):
later `Show-In` lists win, condition keys parse strictly, and `TryExec` is verbatim.
Changes take effect at the next login; nothing is started or stopped immediately.
`~/.config/autostart` is per-machine and gitignored.

Traps:

- **Generator rules and the minimal override.** Disabling a system entry writes only a
  minimal `Hidden=true` override with the same file name; removing a stub restores the entry.
- **Hand-edited overrides are never deleted.** Only stubs the panel wrote and apps it
  added are removable; a customised override is left alone and a broken one names its file.
- **Never write through symlinks;** a symlinked entry is not edited or replaced.
- **`arch-update-tray` was silently skipped:** its `TryExec` names a program that is
  not installed, so the generator drops it without a message. The page says "Not installed"
  and `doctor.sh`'s `check_autostart` warns about it.

## Network: security rules

`network.mjs`'s `groupSecurity` groups every BSS sharing an SSID and picks the
security **fail-closed**: any 802.1X-only/WEP BSS wins outright (unsupported
here); otherwise any SAE-capable BSS (a PSK+SAE transition BSS included) beats
plain PSK, which beats OWE, which beats open. A weaker BSS sharing the SSID can
therefore never downgrade what the panel offers to connect to, and `nm.js`'s
`addAndActivate` re-derives this from the *live* access points immediately
before connecting — refusing with "The network changed; try again" if a scan
landed in between and the group's security no longer matches the plan.

A **saved profile activates as saved** regardless of this grouping: its own
key management was the user's trust decision when it was created (including
through *Advanced…*), and NetworkManager autoconnects it the same way. The
grouping only governs new connections.

A lone WPA2/WPA3 **transition-mode** AP (advertising both PSK and SAE)
connects with SAE, the stronger of the two — a device whose Wi-Fi hardware
lacks SAE support must use `nm-connection-editor` to force PSK instead.

Display SSIDs are libnm's UTF-8 rendering of the AP's raw bytes
(`NM.utils_ssid_to_utf8`); two different non-UTF-8 byte sequences that render
to the same escaped string are indistinguishable in the network list. This is
an accepted limitation, not a bug: the panel only ever compares and connects
by display SSID.

## Measurements

Measured September 19, 2026 with Quickshell 0.3.1 / Qt 6.11.2 on this host,
2560×1440 at scale 1. Original baseline before the session-snapshot refinement,
six consecutive fresh process launches (OS caches warm):

| Measurement | Observed |
| --- | --- |
| Launcher timestamp to first frame swap | 221–291 ms |
| Launcher timestamp to initial 14 values ready | 348–418 ms |
| Open Quickshell process PSS, last three runs | 105–107 MiB |
| Panel process after closing | Absent (verified via IPC and `/proc`) |
| Previous resident AGS + GJS PSS snapshot | About 137 MiB |

A full backend read of every row (`panel-request.sh` with all ids) took about
70 ms with 56 rows and about 280 ms with 89 on September 28, 2026; most of the
increase is the nine File Types rows forking `xdg-mime`. The frame is drawn
before values arrive, so this delays values, not the panel. With round 2's
Sound rows and the richer display read it measured 286 ms median (279–292 ms,
five runs) against 282 ms before, inside the +10 ms budget. With the panel
closed there is no `pactl subscribe`, no `settings-display-*` unit and no
panel process. On the Sound page, audio playback on an awake sink plus three
notifications caused no live read; each default-device change caused one.
Follow-up: the nine File Types rows fork `xdg-mime` on every full read and are
most of the open cost.

Task 6's full read on September 29, 2026 measured **302 ms cold** after 40
seconds idle. Five immediate warm runs were 291, 298, 296, 300 and 291 ms,
for a **296 ms median**. Each run used:

```bash
req=$(jq -c '{op:"read",ids:[.rows[].id],monitors:true}' quickshell/settings-panel/catalog.json)
bash scripts/settings/panel-request.sh "$req"
```

Round 3 (September 29, 2026), measured with `live-smoke.sh` and the loop above:

| Measurement | Observed |
| --- | --- |
| Full read, five runs (median) | 292, 293, 299, 301, 307 ms (**299 ms**) against Task 1's 278 ms; two more sets 295 and 299 ms |
| Full read at `ee1ab1d` (round 2 code, same session) | 296, 295, 292, 288, 296 and 301, 298, 288, 291, 293 ms (median about 294 ms), so round 3 adds about 5 ms; the +21 ms against Task 1 is machine drift, not code |
| Empty read (`ids: []`) median | 44 ms |
| Network read median | 48 ms (+4, budget 30) |
| Startup read median | 69 ms (+25, budget 40) |
| `nmcli monitor` RSS on the Network page | 10.9 MB (about 10.7 MB in a second run), one process |
| Off the Network page / closed | `nmcli monitor`: 0; `pgrep -af 'nmcli monitor\|settings-panel/shell.qml'`: no process |

Live checks deferred earlier, done September 29, 2026 with screenshots: the Network
page shows the Wi-Fi list, Wired and VPN with "Open Proton VPN"; the Waybar clock shows
`12:08` in 24 h, `12:08 PM` after `region.clock=12h`, and `options/clock` was set back to
`24h`; the Startup and Date & Region pages render (nothing was toggled or changed).
Hyprlock's 12/24 h check ran with the user on 2026-09-29: with `options/clock` at 24h the lock screen showed 15:56, and at 12h the hour label showed 03 at 15:59. The option was set back to 24h afterwards.

The timestamp starts after the launcher's lock, IPC probe and palette load, so
these are not full keypress-to-display measurements. A frame swap is a render
milestone, not a physical screen latency measurement. PSS apportions shared
pages; these values exclude GPU memory and are not a guarantee of an identical
drop in total system usage. Short-lived GJS reads can add memory while loading.
The saving at idle comes from exiting, not from keeping a Qt runtime hidden.

## Verification

```bash
bash quickshell/settings-panel/test/run-tests.sh
node quickshell/settings-panel/test/displays.mjs
node quickshell/settings-panel/test/monitor-lua.mjs # runs monitor.lua under Lua
bash quickshell/settings-panel/test/live-smoke.sh # opens/closes on the desktop
bash scripts/hyprland/test-wallpaper.sh
/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml quickshell/settings-panel/*.qml
scripts/docs/generate-keybindings.sh --check
./test.sh
./doctor.sh
```

`./test.sh` runs this suite. Tests cover keyboard/search/close,
no writes while building controls, slider release and explicit text saves,
backend validation (XKB, fonts, commands, choices), GTK/Kvantum ini
round-trips, File Types subtype handling and rollback, suspend listener
round-trips, animation preservation, notification rollback, main-monitor
write failure, the shared apply/save/reset transactions, Sound choices and
writes, interaction locking, display staging, the pending banner, and every
Apply/Keep/Revert ordering and failure path against a mocked systemd guard. The desktop smoke
check reads every catalog setting without changing them, captures
`/tmp/settings-panel-live.png`, measures opening, and verifies process exit.
Qt's linter reports four Quickshell metadata warnings (PanelWindow
creatability and three Process exit-status handlers); live loading succeeds. Multiple physical monitors and fractional scaling have not been tested.

Logs and launch/request locks live in `~/.cache/settings-panel/`. Quickshell's
own session logs can be read with:

```bash
qs -p ~/.config/quickshell/settings-panel/shell.qml log -t 50
qs -p ~/.config/quickshell/settings-panel/shell.qml ipc call settings status
```
