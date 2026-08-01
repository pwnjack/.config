# Hardware Truth — Design

**Date:** 2026-08-01
**Repo:** `~/.config` (Hyprland dotfiles, Arch/CachyOS)
**Chunk A of four.** The other three — unwired tools (hyprpicker/swappy/checkupdates), host-specific config layering, and the repo-wide script test harness + waybar doctor check — are separate designs and are out of scope here.

## Problem

Three surfaces ship configuration for hardware this desktop does not have, and one real device is surfaced nowhere.

1. **waybar's `battery` module** logs `No batteries.` on every start and renders nothing. `style.css` already documents the consequence: with bluetooth and battery hidden, "network and volume ... collided."
2. **The two `XF86MonBrightness*` binds** call `brightnessctl`, which on this machine has no backlight class device at all. `/sys/class/backlight/` is empty; the only devices are `input24::compose`, `input24::capslock` and `input24::scrolllock`. The binds either no-op or toggle a keyboard LED.
3. **swaync's `backlight` widget** is configured in `swaync/config.json` (`widgets[]` plus a `widget-config` block) for that same absent device. swaync silently omits it — verified by screenshot of the control center.
4. **The Logitech G Pro Wireless mouse battery is invisible.** It is a real, readable supply that waybar skips because waybar only counts `SCOPE=System`:

```
POWER_SUPPLY_MODEL_NAME=G Pro Wireless Gaming Mouse
POWER_SUPPLY_CAPACITY=76
POWER_SUPPLY_SCOPE=Device
```

## Decisions taken during design

**Not swaync.** A live readout in the notification sidebar is not achievable in swaync 0.12.6. Its widget set is fixed (`notifications`, `title`, `dnd`, `label`, `mpris`, `menubar`, `buttons-grid`, `slider`, `volume`, `backlight`, `inhibitors`) and the only text widget, `label`, takes `text` as a static string from `config.json`. A live value would mean rewriting a tracked config on a timer and reloading the daemon — the precise thing the repo's cache-symlink invariant exists to prevent.

**Not upower.** `upower -i` does expose a device type (`mouse`) that sysfs lacks, but it costs a daemon dependency, human-shaped output, and a fork plus D-Bus round trip per device per poll. Its own `icon-name` for this device is `battery-missing-symbolic`, which is simply wrong. A `case` over the model string covers mouse/keyboard/headset with a generic fallback that is merely unspecific rather than incorrect. Moving to upower later is a change inside one function.

**No charge state.** Within two minutes of probing, sysfs reported `STATUS=Discharging` and then `Unknown`, with upower agreeing (`state: unknown`). Percentage is the only field that holds still, so the module shows only percentage. There is no counterpart to the old `#battery.critical:not(.charging)` rule.

**No state file.** The module is hidden above the threshold, so *the module appearing is the notification*. Nothing has to remember that it already warned, and nothing has to expire — the same stateless-by-construction property `nightlight.sh` has.

## Design

### 1. New module: `scripts/waybar/devicebattery.sh`

One script, one consumer, no sourced lib. (The `medialib.sh` split exists because two consumers — display and transport — had to agree on one choice; here there is one.)

**Scan.** A single pass over `$DEVBAT_SYSFS/*/uevent`, default `/sys/class/power_supply`. Keep entries with `POWER_SUPPLY_TYPE=Battery` and a numeric `POWER_SUPPLY_CAPACITY`.

There is deliberately **no `SCOPE` filter**. Filtering to `SCOPE=Device` would make this desktop-only, and since waybar's `battery` module is being deleted, a laptop host would then show nothing at all. Taking every battery keeps one module truthful on any machine, so host layering (chunk C) never has to add a battery module back per-host.

**Choice.** Lowest capacity wins the `text`. The tooltip lists every device with its level, not only the lowest.

**Output.** The script prints nothing and exits 0 unless some device is below `LOW=25`, so waybar hides the module — the same idiom `custom/media` uses. Otherwise it emits one line of JSON, `{text, tooltip, class}`. Both comparisons are strictly-less-than, on the lowest device: `capacity < 10` gives `class: critical`, else `capacity < 25` gives `class: low`. Exactly 25 is silent and exactly 10 is `low`. Rendering goes through `jq`, as in `mediaexec.sh`, because model names are vendor strings and `Corsair HS80 & Mouse` would be malformed Pango markup.

Thresholds and the glyph map are constants at the top of the script, the same shape as `MAXLEN`/`DEFAULT_ICON` in `mediaexec.sh`. They are deliberately **not** `options/` entries: that would mean an AGS panel row and a `settings.sh` case for a number nobody tunes twice.

**Poll interval 60s**, matching `custom/nightlight`. A battery that moves a percent an hour does not need a faster tick, and each `interval` costs a fork.

### 2. Placement and the bar's rhythm

`style.css` documents the group map and warns that a hidden module leaves its neighbours colliding. An auto-hiding module must therefore not be load-bearing for any gap.

The module takes `battery`'s old slot between `bluetooth` and `pulseaudio`, and **both `bluetooth` and `custom/devicebattery` become self-contained groups** at 15px on each side. Every neighbouring gap is then 30px whether the module is showing or not, so its appearance never reflows the bar. The `bt·bat` pair in the header map dissolves:

```
right  cpu·mem·gpu·disk | net | bt | [devbat] | vol | tray | night·set·notif·power
```

`style.css` gains `#custom-devicebattery.low` (palette) and `#custom-devicebattery.critical` (fixed red), the latter under the existing ALERT EXCEPTION rationale: pywal cannot guarantee any palette slot reads as "danger."

The header's `gap-glyph` table lists `volume, battery` as the two-space cases, because those glyphs carry ink to the right. Whether the new glyph needs one space or two is decided by looking at a screenshot during implementation, and the table is updated to match.

### 3. Deletions

| target | what goes |
|---|---|
| `waybar/config.jsonc` | the `battery` entry in `modules-right`, and the whole `"battery": {...}` config block |
| `waybar/style.css` | `#battery` in the three grouped selectors (lines ~88, ~121, ~145), the `#battery.critical:not(.charging)` rule, and the `bt·bat` group map + prose in the header |
| `swaync/config.json` | `"backlight"` in `widgets[]` and the `"backlight": {...}` block in `widget-config` |
| `hypr/config/software/keybinds.conf` | both `XF86MonBrightnessUp/Down` binds |

The two brightness binds disappear from the Super+H cheatsheet automatically, since `rofi/keybinds-cheatsheet.sh` renders from `keybinds.conf`.

## Failure modes

| case | behaviour |
|---|---|
| no power supplies at all (VM) | silent, exit 0 |
| `CAPACITY` empty or non-numeric | skip that device — otherwise `[ "$cap" -lt 25 ]` throws into waybar's log every 60s |
| `uevent` unreadable, or device unplugged mid-scan | `2>/dev/null`, skip |
| charge status | ignored entirely (see Decisions) |

**Open question, resolved by probing before code is written:** what a powered-off mouse reports. If the sysfs node disappears, nothing more is needed. If it lingers at `CAPACITY=0`, the module would scream critical every time the mouse is switched off, and the rule becomes "skip 0." Implementation begins by switching the mouse off and looking.

## Testing

`DEVBAT_SYSFS` (default `/sys/class/power_supply`) is the whole testability seam: one line, and the suite needs neither hardware nor root — tests point it at a temp directory of fake `uevent` files.

`scripts/waybar/test-devicebattery.sh`, dependency-free and exit-1-on-failure, following the conventions of `scripts/doctor/test/run-tests.sh` so chunk D can discover it unchanged. Cases:

- nothing present → silent
- one device above threshold → silent
- exactly 25 → silent (the rule is `< LOW`)
- 24 → `class: low`
- exactly 10 → `class: low` (the rule is `< CRITICAL`)
- 9 → `class: critical`
- two devices → lowest wins the text, both appear in the tooltip
- non-numeric capacity → skipped, no error output
- model containing `&` → escaped, valid Pango

This is not ceremony: on 2026-08-01 the media module shipped two bugs — a tab-collapse field shift and a ranking rule that blanked the bar — that were caught only by exactly this kind of fixture, and neither was visible by reading the code.

## Verification

- `shellcheck -S warning` clean (the pre-commit hook's level).
- `./doctor.sh` exits 0 with no new findings.
- waybar restarted, log free of `No batteries.` and of module errors.
- Screenshot of the bar with the module forced visible, confirming glyph spacing and that gaps are unchanged when it hides.
- Screenshot of the swaync control center, confirming nothing changed visually when the dead `backlight` widget is removed.

## Out of scope

- DDC/CI monitor brightness via `ddcutil` (rejected: system-level change beyond dotfiles, unverifiable until installed, laggy on key repeat). Deleting the binds is reversible if this is ever wanted.
- Any battery presence in the AGS settings panel or the swaync sidebar.
- Chunks B, C and D.
