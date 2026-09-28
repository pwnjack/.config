# On-demand settings panel

Super+I and Waybar's settings button open `quickshell/settings-panel/shell.qml`.
The panel starts a fresh process, renders its frame, then reads all settings
asynchronously into a small session snapshot. Tab switches and search use those
values immediately, without starting another helper. Edits refresh the snapshot;
closing discards it, so reopening always reads current values. Escape, Close,
clicking outside, or Super+I closes it.
Once pending saves finish, the process exits. Failed saves keep the error visible
by reopening the panel. Text fields require Enter or Save; sliders save on release.

`catalog.json` is the only list of settings (89 rows in eleven categories on
September 28, 2026), with search, monitor selection, per-row resets and the
four footer actions. Things another surface already owns stay there: the
keybind cheatsheet (Super+H), Do Not Disturb and per-app volume (SwayNC),
updates (Waybar), screenshot options (Rofi) and wallpapers (the carousel).
The palette is read through `scripts/theming/palette.sh` on every launch. The
wallpaper carousel remains a separate application with its existing lifecycle.

## Implementation

- `catalog.json` owns setting metadata, accepted ranges and dropdown choices.
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
- Sources: `gtk` writes gsettings **and** both tracked `settings.ini` files
  (GTK 3 on Wayland reads some keys from each); `kvantum` edits `theme=` under
  `[General]`; `mime` writes `xdg-mime default` into the tracked
  `mimeapps.list`, only for the row's types the chosen app declares or is a
  parent of (never via `application/octet-stream`, which everything is), and
  restores the file byte-for-byte on failure; `powerprofile` drives
  `powerprofilesctl`; the `idle` source adds, retimes and removes only the
  suspend listener it marked.
- `hyprctl getoption -j` names the value field after its type (`bool`, `int`,
  `float`, `str`, `css`); `set` only says whether the config assigns the
  option and is never a value. The Lua provider rejects legacy hyphenated
  names: use `input:touchpad:tap_to_click`, not `tap-to-click`.
- AGS no longer starts at login or after wallpaper changes. Its retired source
  and AGS/Astal packages are gone; GJS remains an explicit backend dependency.

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
before values arrive, so this delays values, not the panel.

The timestamp starts after the launcher's lock, IPC probe and palette load, so
these are not full keypress-to-display measurements. A frame swap is a render
milestone, not a physical screen latency measurement. PSS apportions shared
pages; these values exclude GPU memory and are not a guarantee of an identical
drop in total system usage. Short-lived GJS reads can add memory while loading.
The saving at idle comes from exiting, not from keeping a Qt runtime hidden.

## Verification

```bash
bash quickshell/settings-panel/test/run-tests.sh
bash quickshell/settings-panel/test/live-smoke.sh # opens/closes on the desktop
bash scripts/hyprland/test-wallpaper.sh
/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml quickshell/settings-panel/*.qml
scripts/docs/generate-keybindings.sh --check
./test.sh
./doctor.sh
```

The new suite must be run explicitly until its files are tracked: `test.sh`
intentionally discovers tracked files only. Tests cover keyboard/search/close,
no writes while building controls, slider release and explicit text saves,
backend validation (XKB, fonts, commands, choices), GTK/Kvantum ini
round-trips, File Types subtype handling and rollback, suspend listener
round-trips, animation preservation, notification rollback, main-monitor
write failure, and the shared apply/save/reset transactions. The desktop smoke
check reads every catalog setting without changing them, captures
`/tmp/settings-panel-live.png`, measures opening, and verifies process exit.
Qt's linter reports the same three Quickshell metadata warnings as the carousel
(PanelWindow creatability and two Process exit-status handlers); live loading
succeeds. Multiple physical monitors and fractional scaling have not been tested.

Logs and launch/request locks live in `~/.cache/settings-panel/`. Quickshell's
own session logs can be read with:

```bash
qs -p ~/.config/quickshell/settings-panel/shell.qml log -t 50
qs -p ~/.config/quickshell/settings-panel/shell.qml ipc call settings status
```
