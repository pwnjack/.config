# Settings Panel Round 3: Network, Date & Region, Startup — Design

Approved 2026-09-28. Implementation plan:
`docs/superpowers/plans/2026-09-28-settings-panel-round-3.md`.

## Goal

Add three pages to the Super+I settings panel:

1. **Network**: a Wi-Fi list with connect and forget, wired status, and VPN
   status with up/down, including Proton VPN.
2. **Date & Region**: time zone, NTP, 12/24 h clock, language and regional
   formats.
3. **Startup**: real startup-app management in place of the three option
   toggles the category holds today, which stay.

**Performance is the first priority**, as in round 2. The panel adds nothing
to the idle system. A live list only updates while its page is on screen, and
closing the panel ends every process it started.

## Out of scope (owned elsewhere or deferred)

- Hidden SSIDs, 802.1X/enterprise Wi-Fi, hotspots, and DNS or IP editing.
  `nm-connection-editor` owns them, and the page links to it.
- Importing or creating VPN profiles. The Proton app and `nm-connection-editor`
  create them.
- Setting the clock manually (NTP owns time), RTC-in-local-time, and hostname.
- Keyboard layouts, which are already Input rows.
- Generating new locales, which needs root `locale-gen`. The rows point to
  `/etc/locale.gen`.
- Starting or stopping an autostart app *now*. Changes take effect at next
  login, and systemd's generator stays the only launcher.
- Volume, bar icons and notifications stay with Waybar and SwayNC. The
  Waybar network icon only gains a new click target.

## Facts this design rests on (verified on this machine, 2026-09-28)

| Fact | How it was checked |
|---|---|
| NetworkManager 1.58.1. `eno1` is up, `wlan0` is disconnected with no saved Wi-Fi connection, and there is an active WireGuard connection `ProtonVPN IT#113` (`proton0`, `permissions user:pwnjack`, autoconnect yes) plus a `dummy` kill-switch connection `pvpn-killswitch-ipv6` | `nmcli -t … device`, `connection show` |
| Our user's NM permissions are `network-control`, `settings.modify.system`, `settings.modify.own`, `wifi.scan` and `enable-disable-wifi`, all **yes**. Network writes need no password | `nmcli general permissions` |
| libnm is available to GJS (`NM-1.0.typelib`). `NM.Client.new(null)` takes **7.5 ms** and exposes devices, access points (SSID bytes, strength, flags, WPA/RSN flags), active and saved connections, `add_and_activate_connection_async`, `deactivate_connection_async` and `dbus_set_property` | `gjs -m` probe |
| `nmcli device wifi list --rescan no` and `connection show` each take about 8 ms. `nmcli monitor` runs until it is killed | timed |
| Quickshell 0.3.1 has `Quickshell.Networking` (Wi-Fi/Wired only, no VPN). **Not used**: one data path through the backend is testable with mocks | `quickshell-network.qmltypes` |
| Proton VPN runs as three parts: the root daemon `proton.VPN.service` (split tunnelling only), the GTK app `protonvpn-app` 4.18.1 (started by `startup.sh` when `options/protonvpn` is enabled), and an NM WireGuard connection named after the server. There is **no Proton CLI** | `pgrep`, `busctl`, `pacman -Ql` |
| nm-applet (the tray Wi-Fi/VPN menu) runs as the XDG autostart unit `app-nm\x2dapplet@autostart.service`. Waybar's `network` module shows only an icon and tooltip, and its click runs `nm-connection-editor`. SwayNC and Rofi have nothing network-related | process cgroups, `waybar/config.jsonc` |
| Time zone Europe/Rome, NTP active and synchronized. `/etc/localtime` → `/usr/share/zoneinfo/Europe/Rome`. `/etc/locale.conf` has `LANG=en_US.UTF-8` and every other set `LC_*` is `it_IT.UTF-8`. Generated locales are `C.UTF-8`, `en_US.UTF-8` and `it_IT.UTF-8`. `ListTimezones` returns 598 zones | `timedatectl`, `localectl`, `readlink` |
| `timedate1.set-timezone`, `set-ntp` and `locale1.set-locale` are all **`auth_admin_keep`**. `hyprpolkitagent` is running as a user unit | `pkaction -v` |
| A cold `timedatectl show` plus `localectl status` takes about 100 ms, because both daemons are socket-activated | timed |
| The session runs under **uwsm**. systemd's XDG autostart generator turns `/etc/xdg/autostart` and `~/.config/autostart` into `app-<id>@autostart.service` units at login. `~/.config/autostart` is gitignored (`.gitignore:270`) | cgroups, `git check-ignore` |
| `~/.config/autostart/arch-update-tray.desktop` gets **no unit**: the generator logs "Exec binary 'arch-update' does not exist" | `journalctl --user -b` |
| `systemctl --user list-units --all --output=json 'app-*@autostart.service'` returns unit, load, active and sub state as JSON (systemd 262) | run |
| The panel is an Overlay layer surface with `WlrKeyboardFocus.Exclusive` while open | `shell.qml` |
| Waybar 0.15.0's clock uses a hard-coded `{:%H:%M}`, and hyprlock's hour label uses `date +"%H"` | config files |
| `/etc/profile.d/locale.sh` reads `~/.config/locale.conf` **only if `$LANG` is unset** | file contents |

**Checked in plan Task 1 before anything is built**, because each needs you
present or would visibly change the session:

- **Proton:** does deactivating `ProtonVPN IT#113` through NM keep the app in
  sync? Can it be brought back up, and what does the kill switch do to traffic
  in between?
- **Polkit:** whether hyprpolkitagent's dialog is usable while the panel is
  open with its focus released.
- **Per-user locale:** whether a per-user `~/.config/locale.conf` changes
  anything in a uwsm session.
- **Waybar:** whether `include` can supply `clock.format` when the main file
  omits it.
- **Timing:** the cold D-Bus cost of the Date & Region reads, and the
  round-3 baseline.

## Design

### 1. Shared shape

Everything follows round 2's pattern:

- `catalog.json` stays the only list of categories and rows.
- The short-lived GJS helper (`panel-request.sh` → `request.js` →
  `backend.js`) does every read and write.
- Pages that don't fit rows get a custom view, like the Displays cards.
- Live pages are driven by tags. `shell.qml` derives the live tags on screen,
  runs **one** event source per tag only while that tag is visible, and does
  debounced (300 ms), single-flight re-reads.

New backend modules. Only the adapters touch system APIs, so the logic can be
tested in Node:

| File | Role | Talks to |
|---|---|---|
| `nm.js` | libnm adapter: returns plain snapshots and performs operations | `gi://NM` (its only importer) |
| `network.mjs` | pure: SSID grouping, security, sort, VPN shaping, request validation | nothing |
| `dbus.js` | `callSystem(name, path, iface, method, args, {interactive})` | `Gio.DBus.system` |
| `region.js` | reads and writes for time and locale | files and `dbus.js` |
| `autostart.mjs` | pure: desktop-entry parse, effective-set rules, override text, unit names | nothing |

`backend.js` gains two row sources (`network`, `region`) and the view ops
`network`, `networkScan`, `wifiConnect`, `wifiForget`, `vpn`, `startup` and
`autostart`. It keeps round 2's rule that a pending display change blocks
every other op.

### 2. Network page (category `network`, placed after Sound)

A custom view, `NetworkView.qml`, shown when the category is selected and the
search box is empty. Catalog rows exist only for things that are real settings
(the Wi-Fi radio switch), so search still finds "Wi-Fi". The view has three
sections:

**Wi-Fi**
- The radio toggle is the catalog row `network.wifi`, source `network`, key
  `wifi`, kind `toggle`, live `network`. It writes `WirelessEnabled` through
  `dbus_set_property`.
- The list comes from one `op:"network"` read. Networks are **grouped by SSID**
  with the strongest access point kept. Hidden (empty) SSIDs are dropped.
  Sort order: active first, then known, then signal, highest first.
- Each entry shows the SSID, a four-step signal glyph, a lock when secured, and
  "Connected" / "Saved" / nothing.
- Security comes from the AP flags: `open`, `psk` (WPA/RSN PSK or SAE), or
  `unsupported` (802.1X). An `unsupported` network gets a hint to use
  `nm-connection-editor` and no Connect button.
- **Connect:**
  - A known network activates its saved connection.
  - An open network, or a PSK network after you type its password in an
    inline field, is created with `add_and_activate_connection_async`. The
    PSK is handed to libnm in memory.
  - **Trap:** `panel-request.sh` receives the request as `$1`, so a PSK would
    be readable in `/proc/<pid>/cmdline` for the helper's life. Requests
    therefore reach the helper on **stdin** whenever `$1` is `-`, and
    `shell.qml` uses that form for every write.
  - A new connection that doesn't reach `activated` within 30 s is
    **deleted**, so a wrong password never leaves a "Saved" network behind.
    The reason (wrong password, timeout, network gone) is shown.
- **Forget** deletes every saved Wi-Fi connection for that SSID.
- **Rescan:** the view asks for a scan when the page opens, then every 20 s
  while it stays visible (`op:"networkScan"` → `request_scan_async`). A scan
  that NM rejects as too frequent counts as success.

**Wired:** status only. Interface, carrier, speed, IPv4 address and gateway
for each ethernet device. A device without carrier shows "Cable unplugged".

**VPN:** every saved connection of type `vpn` or `wireguard`, showing its
name, state (active / activating / off) and the interface when active, with
an up/down switch (`op:"vpn"`, `{uuid, active}`). `dummy` connections, such as
Proton's kill switch, are never listed.

**Proton VPN special case** (decided by Task 1). A connection whose name
starts with `ProtonVPN ` is Proton's.
- **Case A**, Task 1 shows NM up/down keeps the app consistent and doesn't
  break traffic: it behaves like any other VPN.
- **Case B**, any desync or traffic block: its switch is replaced by **Open
  Proton VPN**, which launches `protonvpn-app` (single-instance, so it raises
  the running window). The state stays read-only.

`network.mjs` exports `PROTON_MODE`, which Task 4 sets to `"nm"` or `"app"`
from the recorded result.

**Live:** the Wi-Fi radio row and the view carry the live tag `network`.
While the tag is on screen, `shell.qml` runs `nmcli monitor`. Any line from it
marks `network` dirty, and the debounced live read re-reads the radio row and
the `op:"network"` state together. The 20 s rescan `Timer` runs only while the
view is visible. Leaving the page or closing the panel stops both.

**Waybar:** the `network` module's `on-click` becomes
`~/.config/scripts/hyprland/settings-panel.sh network`. The launcher gains an
optional page argument: with the panel closed it starts the panel on that
page, and with the panel open it switches to that page. The tooltip and icons
are unchanged.

### 3. Date & Region (category `region`, placed after Power)

These are ordinary rows with source `region`:

| Row id | Kind | Read | Write | Auth |
|---|---|---|---|---|
| `region.timezone` | select (searchable) | `readlink /etc/localtime` | `SetTimezone(tz, true)` | polkit |
| `region.ntp` | toggle | D-Bus `NTP`, with `NTPSynchronized` shown as the row's `note` | `SetNTP(b, true)` | polkit |
| `region.clock` | select `24h`/`12h` | `options/clock` | option file, then `clock-format.sh` | none |
| `region.language` | select over generated locales | `LANG` from `/etc/locale.conf` | `SetLocale(merged, true)` | polkit |
| `region.formats` | select over generated locales | `LC_TIME` from `/etc/locale.conf` (falling back to `LANG`) | `SetLocale`, setting the nine format categories (`LC_NUMERIC`, `LC_TIME`, `LC_MONETARY`, `LC_PAPER`, `LC_NAME`, `LC_ADDRESS`, `LC_TELEPHONE`, `LC_MEASUREMENT`, `LC_IDENTIFICATION`) to the choice and keeping `LANG` and the rest | polkit |

- **Choices:**
  - Time zones come from `ListTimezones` over D-Bus. That starts `timedated`
    once per read, and Task 1 measures the cost. If the region rows add more
    than 20 ms to a full read, the zone list is cached in
    `~/.cache/settings-panel/timezones.json` keyed on the mtime of
    `/usr/share/zoneinfo/tzdata.zi`.
  - Locales come from `localectl list-locales`, filtered to `*.UTF-8`.
- **Reads are file-first:** `/etc/localtime` and `/etc/locale.conf` cost
  nothing. D-Bus is used only for `NTP` and `NTPSynchronized` and for the
  zone list.
- **Per-user formats (Task 1 decides).** If the probe shows that
  `~/.config/locale.conf` takes effect under uwsm, `region.formats` writes that
  file instead and needs no auth. The expected result is that it does
  **not**, because `LANG` is already set when `profile.d` runs. Either way the
  language and formats descriptions say "Applies to programs started after
  your next login".
- **Searchable select:** `PanelCombo` gains a filter field at the top of its
  popup, which appears when there are more than 20 choices. Typing filters
  labels case-insensitively. This is the only change to `PanelCombo` and it
  also benefits the existing long lists (icon themes, file-type apps).

**12/24 h clock.** `options/clock` holds `24h` (the tracked default) or `12h`.
Its consumers:
- **Waybar:** the tracked `config.jsonc` drops the clock's `format` key and
  gains `"include": ["~/.cache/waybar/clock.jsonc"]`.
  `scripts/waybar/clock-format.sh` renders that include from the option:
  `{"clock": {"format": "{:%H:%M}"}}` or `{"clock": {"format": "{:%I:%M %p}"}}`.
  It always writes the file, falling back to 24 h, and signals Waybar
  (`SIGUSR2`) only if it's running. Waybar's built-in clock default is
  already `{:%H:%M}`, so even a missing include shows a sane clock.
  `install.sh` and the panel both call the script. Task 1 verifies the
  include works first. If it doesn't, the fallback is templating
  `config.jsonc` into the cache like cava/starship, **not** a per-second exec
  module.
- **Hyprlock:** the hour label's command reads the option itself:
  `date +"%$([ "$(cat ~/.config/options/clock 2>/dev/null)" = 12h ] && echo I || echo H)"`.
  Hyprlock can't be dry-run, so it is verified by locking once in the final
  task.

**Privilege flow.**
1. Rows carrying `"auth": true` in the catalog are the privileged ones. When
   one is changed, `shell.qml` sets `authPending` before submitting.
2. `authPending` binds the panel's `keyboardFocus` to `None` and shows a
   banner, "Waiting for authentication…", and every control is disabled.
3. The backend's `dbus.js` call uses
   `Gio.DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION` with a 120 s timeout.
   `panel-request.sh`'s `flock -w 30` doesn't matter, because the panel sends
   nothing else while `authPending` is set.
4. A reply clears `authPending`:
   - Success refreshes as usual.
   - A dismissed or denied prompt (`org.freedesktop.DBus.Error.AccessDenied`,
     `org.freedesktop.PolicyKit1.Error.NotAuthorized`,
     `org.freedesktop.DBus.Error.InteractiveAuthorizationRequired`) leaves the
     value unchanged, and the backend reports "Authentication was cancelled;
     nothing changed."
5. `auth_admin_keep` means a second change within about 5 minutes doesn't
   prompt again.
6. **If Task 1 shows the agent dialog renders under the Overlay layer** even
   with focus released, `authPending` also hides the overlay
   (`visible: false`) until the reply arrives. The process stays alive, so
   nothing is lost. Task 1 records which, and Task 5 implements it.

### 4. Startup (category `startup`, same place)

`StartupView.qml` sits above the three existing option rows, which remain
catalog rows unchanged. It has two groups.

**Session (read-only).** The commands started by
`hypr/config/setup/autostart.lua`, parsed from the tracked file on each read.
Each `hl.exec_cmd(` argument's leading string literal is shown, followed by
`…` when a `..` concatenation follows it. The group is labelled "Started by
Hyprland's config". It has no toggles, and an **Edit file** button opens the
file in `options/editor`, as round 2's Displays **Edit file** does.

**Apps (the XDG set, managed).** This is exactly what the generator launches.
`autostart.mjs` implements its rules:

- Entries come from `/etc/xdg/autostart/*.desktop` and
  `~/.config/autostart/*.desktop`. A user file with the same file id replaces
  the system one.
- An entry is **enabled** unless `Hidden=true`,
  `X-GNOME-Autostart-enabled=false`, or `X-systemd-skip=true` is set, or
  `OnlyShowIn`/`NotShowIn` excludes `Hyprland` (taken from
  `XDG_CURRENT_DESKTOP`).
- An entry whose `TryExec`, or first `Exec` word, isn't on `PATH` shows "Not
  installed: `<binary>`". That is what currently hides arch-update-tray.
- Status comes from one `systemctl --user list-units --all --output=json
  'app-*@autostart.service'` per read:
  - `running` (active/running)
  - `finished` (inactive/dead)
  - `failed`
  - `not started` (no unit, with the reason above if known)

  Unit names use systemd's escaping of the file id (`-` → `\x2d`), computed
  by `autostart.mjs`.
- Entries are listed enabled-first, then by name.

Writes (`op:"autostart"`), each atomic (temporary file, then rename):
- **Disable a system entry:** write `~/.config/autostart/<id>.desktop`
  containing exactly
  `[Desktop Entry]\nType=Application\nName=<name>\nHidden=true\n`. The
  generator treats that as masking the system file.
- **Enable a system entry:** if the user file is exactly that minimal
  override, delete it. An override with anything more was written by hand or
  by another tool. It is never deleted; instead its `Hidden` key is set to
  `false`, and every other line is kept.
- **Disable or enable a user-only entry:** set or remove `Hidden=true` in
  place, keeping every other line.
- **Add…:** a searchable picker over the installed applications
  (`Gio.AppInfo.get_all()` filtered by `should_show()`), excluding ids already
  in the list. Picking one copies its desktop file into `~/.config/autostart/`
  unchanged.
- **Remove:** only for entries that exist *only* in `~/.config/autostart`.
  Deletes the file.

After any write, the view shows "Takes effect at next login". There is **no
live tag**: unit state only changes at login or on a crash. The page reads
once when it's shown and again after each edit.

**The Proton option row stays.** `startup.sh` still launches `protonvpn-app`
when `options/protonvpn` is enabled. Moving it to XDG would be a behaviour
change that this round doesn't need.

### 5. Doctor

New module `scripts/doctor/checks/autostart.sh` (`check_autostart`, prefix
`_as_`):
- **WARN** for each `~/.config/autostart/*.desktop` that isn't `Hidden=true`
  and whose `TryExec`, or first `Exec` word, isn't on `PATH`. That catches
  arch-update-tray today.
- **NOTE** for each minimal Hidden override whose system counterpart no longer
  exists.

Everything is derived from the files. It follows the module rules in
`CLAUDE.md` (no pipelines into `while`, `doctor_q` in hints, host probes in
tiny stub-able functions) and comes with `test-autostart.sh`.

### 6. Error handling summary

| Situation | Behaviour |
|---|---|
| NM not running | Network view shows "NetworkManager is not running", and the other pages still load |
| No Wi-Fi device | Wi-Fi section hidden, and the radio row reports "No Wi-Fi device" |
| Wrong password, timeout | New connection deleted; the problem banner names the reason |
| Scan too frequent | Ignored |
| Polkit cancelled or denied | Value unchanged; "Authentication was cancelled; nothing changed." |
| timedated/localed unavailable | Those rows show a row error, and the rest load |
| `~/.config/autostart` missing | Created on first write |
| Hand-edited override | Kept; only its `Hidden` key changes |
| Pending display change | Every new op refused (existing rule) |

### 7. Performance budget (acceptance criteria)

| State | Budget |
|---|---|
| Panel closed | No new process, timer or file watch. `pgrep -f 'nmcli monitor'` prints nothing |
| Panel open on a page other than Network | No `nmcli monitor`, no rescan timer |
| Network page visible | One `nmcli monitor`, one helper call per debounced change, and one rescan per 20 s |
| Full read (every row, on each open) | Within **+20 ms** of the Task 1 baseline median (five runs) |
| `op:"network"` read | ≤ 30 ms median |
| `op:"startup"` read | ≤ 40 ms median |

### 8. Testing

- `test/network.mjs`: pure shaping (grouping, sort, security, VPN filter,
  Proton detection, validation of SSID and PSK, which must be 8–63 printable
  ASCII or 64 hex).
- `test/autostart.mjs`: parse, merge, all the enable rules, override text
  round-trips, unit-name escaping, the hand-edited-override rule, and session
  command extraction.
- `test/backend.mjs`: mocks `./nm.js` and `./dbus.js` through the existing
  resolve hook. It covers every new op, auth errors mapped to the cancelled
  message, deletion of a failed new connection, and the region and startup
  reads.
- `test/tst_Settings.qml`:
  - `authPending` releases keyboard focus and disables controls.
  - The `network` tag starts `nmcli monitor` only on the Network page, and the
    rescan timer stops when leaving it.
  - Search filtering in `PanelCombo` works.
- `scripts/doctor/test/test-autostart.sh`.
- `test/live-smoke.sh`:
  - Opens the Network page and asserts `nmcli monitor` is running.
  - Closes the panel and asserts that it and every child have exited.
  - Asserts that full read, network read and startup read are within budget.
