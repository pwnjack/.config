# Unwired Tools — Design

**Date:** 2026-08-02
**Status:** Approved, ready for planning
**Backlog chunk:** B (unwired tools) — the last of the four

## Problem

Three programs are installed on this machine and reachable from nothing:

| Tool | Installed at | References in the repo |
|------|--------------|------------------------|
| `hyprpicker` | `/usr/bin/hyprpicker` | `install.sh:92`, `README.md:247`, CHANGELOG — **bound to nothing** |
| `swappy` | `/usr/bin/swappy` | **none**, not even in `install.sh` |
| `checkupdates` | `/usr/bin/checkupdates` | **none** — no updates surface anywhere |

`hyprpicker` is the starkest case: it is *installed by* `install.sh` and
advertised in the README, so a fresh machine pays for it and gets nothing.

### There is no update notifier already in place

Two candidates exist on this system and both are dead, verified 2026-08-02:

- `~/.config/autostart/arch-update-tray.desktop` runs `arch-update --tray`, but
  `pacman -Qs arch-update` returns nothing and `command -v arch-update` fails —
  the binary is not installed. The entry is an orphan, and `.gitignore:283`
  excludes `autostart/**`, so the repo does not track it either way.
- `/etc/xdg/autostart/org.kde.discover.notifier.desktop` carries
  `OnlyShowIn=KDE`, so it never starts under Hyprland. Nothing matching it is
  running.

### The updater already exists

`scripts/settings/update.sh` runs whatever `options/aurhelper` holds
(`paru -Syu`) then flatpak, and is already reachable from `settings.sh` and
from `ags/widget/SettingsPanel.tsx`. This design adds **visibility**, not a
second updater, and reuses that script unchanged.

## Shape

Three independent slices. No shared state, no state files, nothing one slice
can break in another. Each follows patterns the repo already uses:

- **One script owns the behaviour; every surface calls that script.** This is
  the `nightlight.sh` rule — it is what keeps a keybind and a menu entry from
  drifting apart.
- **Each script is a no-op when its binary is missing**, per the repo's
  existing convention that scripts check for commands before running.
- **Nothing writes a tracked file** and nothing keeps state on disk.

## Slice 1 — hyprpicker

New `scripts/hyprland/colorpicker.sh`. Picks a colour, copies the hex, notifies:

```bash
color=$(hyprpicker -f hex) || exit 0     # ESC cancels -> exit silently
printf '%s' "$color" | wl-copy
notify-send -i color-select 'Colour copied' "$color"
```

`wl-copy` is not a new dependency — the `$Mod, C` clipboard-history bind
already requires it.

One new keybind in `hypr/config/software/keybinds.conf`:

```
bind = $Mod SHIFT, C, exec, ~/.config/scripts/hyprland/colorpicker.sh   # Colour picker (copies hex)
```

`$Mod SHIFT, C` is free, and sits next to `$Mod, C` (clipboard history) because
both end in the clipboard. The trailing `#` comment is the cheatsheet label, so
the Super+H row costs nothing extra.

### Two defects in the module this replaces

A `custom/hyprpicker` waybar module existed until `d952dfa` deleted it as
defined-but-unreferenced. Its `on-click` was:

```
color=$(hyprpicker 2>/dev/null) && echo -n $color | wl-copy && notify-send -i color-select-symbolic 'Color copied to clipboard!' $color
```

Do not restore it verbatim. It is wrong twice:

1. **`color-select-symbolic` renders as nothing.** swaync 0.12.6 reserves the
   icon slot for Papirus-Dark symbolic icons and leaves it blank. The
   non-symbolic `color-select.svg` is present at 16x16, 22x22 and 24x24 under
   `~/.local/share/icons/Papirus-Dark/*/actions/`, verified 2026-08-02.
   (Papirus is installed by hand into `~/.local/share/icons`, not by pacman.
   Noted, not in scope.)
2. **Title and body are swapped.** The colour — the only part worth reading —
   goes in the body, which is where a toast renders it as content rather than
   as a heading.

## Slice 2 — swappy

New `scripts/hyprland/screenshot-annotate.sh`:

```bash
hyprshot -m region -r -s | swappy -f -
```

`-r` streams raw PNG to stdout and `-s` suppresses hyprshot's "saved"
notification, which would otherwise fire for a file that was never written.
`swappy -f -` reads that stream.

Two surfaces call this one script:

- `bind = $Mod ALT, S, exec, ~/.config/scripts/hyprland/screenshot-annotate.sh   # Screenshot a region and annotate`
- a fourth entry in `rofi/screenshot.sh`, between *selection* and *settings*.

`$Mod, S` (region straight to disk) and `$Mod SHIFT, S` (the rofi menu) keep
their current behaviour exactly. Annotation is opt-in.

### swappy has no config at all

`~/.config/swappy/` does not exist, so swappy currently defaults its save
directory to the desktop. A tracked `swappy/config` fixes that and matches the
naming the rest of the repo uses:

```ini
[Default]
save_dir=$HOME/Pictures/Screenshots
save_filename_format=Screenshot_%Y-%m-%d_%H:%M:%S.png
```

Written with `$HOME` rather than `/home/pwnjack`, per the host-neutral rule
established in chunk C.

`swappy` is added to the package array in `install.sh`, where it is missing
today, and to the README's package list.

### Both open questions are now closed

Resolved by probing during planning rather than left for implementation:

- **`$HOME` does expand.** `/usr/bin/swappy` links `wordexp`, and its own
  built-in default for `save_dir` is the literal string `$HOME/Desktop` — it
  cannot work at all unless it expands. The implementation still confirms with
  a real save rather than resting on `strings`.
- **The rofi theme does need a change.** `rofi/themes/screenshot/main.rasi`
  hardcodes `columns: 4; lines: 1`, so a fifth entry wraps out of view. It
  becomes `columns: 5`; window width stays 600.

## Slice 3 — checkupdates

New `scripts/waybar/updates.sh`, a sibling of `battery.sh` emitting the same
`jq -nc` JSON shape, and a `custom/updates` module in `waybar/config.jsonc`
placed between `disk` and `network` in `modules-right`.

That slot is chosen by the stylesheet's own rule, not by taste. `style.css`
warns that "a module that comes and goes cannot be load-bearing for a gap",
which is why `#custom-battery` is styled as a self-contained group with 15px
on both sides. `#disk` already closes its group with `padding-right: 15px` and
`#network` already carries 15px on both sides, so a self-contained
`#custom-updates` between them yields a 30px gap whether it is showing or not.
It belongs to the **text** tier (14px), not the icon tier, because it renders
digits beside its glyph.

### Counting

Repo count comes from `checkupdates`. The AUR count comes from the helper
**derived** from `options/aurhelper` — take its first word (`paru` from
`paru -Syu`) and run `<helper> -Qua`. No helper name is hardcoded anywhere;
a list would be a second source of truth, which is the same rule the doctor
modules follow. If `options/aurhelper` is empty or names a binary that is not
installed, the AUR count is skipped and the tooltip reports repo only.

### The correctness trap, measured

Both commands use exit status to mean "nothing found". Measured live
2026-08-02 on this machine:

| Command | Situation | Exit |
|---------|-----------|------|
| `checkupdates` | 16 updates pending | `0` |
| `checkupdates` | no updates | `2` (documented) |
| `paru -Qua` | no AUR updates | `1` |

So the count must **ignore exit status entirely and count lines**. Any `&&`
chain, any `set -e`, any `if cmd; then count; fi` reports zero forever and
looks perfectly healthy while doing it. This is the single defect most likely
to ship unnoticed, because the failure mode is silence.

### Rendering

Zero updates **prints nothing and exits 0**, which hides the module. This is
the established idiom here, not a new one: `battery.sh:155` does exactly this
(`[ "${#parts[@]}" -eq 0 ] && exit 0`) and its comment names `custom/media` as
the module it copied it from. The module appearing *is* the signal, which is
what keeps it stateless.

Non-zero renders the nerd-font glyph `󰚰` (`nf-md-update`) followed by the
combined total, with a tooltip of `N repo · M AUR`. When no helper is
available the tooltip is `N repo` alone and the total is the repo count.
`text` is our own glyph and digits; package names go only in the tooltip, and
are escaped there the way `battery.sh` escapes vendor strings.

### Interaction

```jsonc
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

`interval` is 1800s because `checkupdates` syncs a private pacman DB over the
network on every run; polling mirrors more often than half-hourly is rude and
buys nothing. The `update` verb opens `scripts/settings/update.sh` in
`$(cat ~/.config/options/terminal)` and signals `RTMIN+9` when it exits, so the
count clears the moment the update finishes instead of waiting out the
interval. Right-click forces a refresh through the same signal. This mirrors
`custom/nightlight`, which uses signal 8 for the same reason.

## Error handling

Every script exits quietly and successfully when its own binary is absent, so a
partial install degrades to a missing feature rather than a broken keybind or a
module that spams errors into the waybar log. A cancelled `hyprpicker` (ESC)
and a cancelled `slurp` region are ordinary outcomes, not errors, and produce
no notification. Nothing here writes state, so nothing can be left stale.

## Doctor

**No doctor edits are required, by construction.** `checks/binaries.sh` derives
its targets from `keybinds.conf`'s `exec,` lines and from autostart, and
`checks/waybar.sh` derives its targets from `config.jsonc`'s `modules-*` arrays
and handler values. Declaring the two keybinds and the module is what puts all
three slices under the doctor's eye.

Acceptance: `./doctor.sh` still reports 0 errors, 0 warnings, and the single
known notice about which daemon owns `org.freedesktop.Notifications`. Any new
finding is a real regression in this work.

## Testing

New `scripts/waybar/test-updates.sh`, modelled on `test-battery.sh`: standalone,
runs the script under test as a subprocess the way waybar does, reads fields
back with `jq`. `test.sh` discovers `test-*.sh` by name, so there is no
registration step, and `scripts/hooks/pre-commit` picks it up through
`test.sh --for`.

Command overrides (the seam `BATTERY_SYSFS` provides for `battery.sh`) let the
suite run with no network and no pending updates. Cases:

- zero repo and zero AUR emits empty `text` — the module hides
- a helper exiting non-zero with no output still yields a correct zero, and a
  helper exiting non-zero *with* output still counts its lines
- `checkupdates` exiting `2` is not treated as failure
- empty or missing `options/aurhelper` gives a repo-only tooltip
- an `aurhelper` naming an uninstalled binary gives a repo-only tooltip
- both counts non-zero produce `N repo · M AUR` and a correct total

Manual verification, which the automated suite cannot cover:

- both new keybinds fire, and the rofi menu's fourth entry reaches swappy
- swappy saves into `~/Pictures/Screenshots` with the expected filename
- **a screenshot of the actual colour-picker toast.** A `notify-send` that
  exits 0 is not evidence the icon rendered, and an icon that renders in the
  panel is not evidence it renders in a toast — that exact gap is what the
  night-light work found in swaync 0.12.6.
- `./test.sh` passes every suite

## Out of scope

- The orphaned `arch-update-tray.desktop`. It lives in a gitignored directory
  and this repo does not manage it.
- Anything that replaces `scripts/settings/update.sh`. The module surfaces
  counts and hands off to the existing updater.
- Restoring a `custom/hyprpicker` bar module. The keybind is the chosen
  surface; the right cluster already carries thirteen modules.
