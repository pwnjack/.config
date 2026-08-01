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

**No charge state for peripherals.** Within two minutes of probing, sysfs reported `STATUS=Discharging` and then `Unknown` for the mouse, with upower agreeing (`state: unknown`). Percentage is the only field that holds still for a device battery, so peripheral entries show only percentage and ignore `STATUS`. System batteries are the exception: their `STATUS` is trustworthy, and charging there suppresses the alert classes — which is what the old `#battery.critical:not(.charging)` rule encoded.

**No state file.** For peripherals the module is hidden above the threshold, so *the module appearing is the notification*. Nothing has to remember that it already warned, and nothing has to expire — the same stateless-by-construction property `nightlight.sh` has. (On a machine with a system battery the module is always present, so there the appearing-is-the-signal property does not apply; the colour change carries it instead. Still no state.)

## Design

### 1. New module: `scripts/waybar/battery.sh`

One script, one consumer, no sourced lib. (The `medialib.sh` split exists because two consumers — display and transport — had to agree on one choice; here there is one.)

Named `battery`, not `devicebattery`: it reports every battery on the machine, peripheral or not, and a name covering half its job would mislead the next reader. There is no collision with waybar's built-in module — that one is being deleted, and even alongside it the CSS ids differ (`#battery` vs `#custom-battery`).

**Scan.** A single pass over `$BATTERY_SYSFS/*/uevent`, default `/sys/class/power_supply`. Keep entries with `POWER_SUPPLY_TYPE=Battery` and a numeric `POWER_SUPPLY_CAPACITY`.

Skip any entry whose `POWER_SUPPLY_ONLINE` is **present and `0`**. Verified by switching the mouse off: the sysfs node persists and `CAPACITY` holds its last reading (75), so a stale percentage would otherwise be reported forever — a mouse left in a drawer at 8% would pin a critical badge to the bar for a device not in use. `ONLINE` flipped `1 → 0` and is the only field that did. The test is present-and-`0` rather than "not 1", because a laptop's internal battery generally carries no `ONLINE` attribute at all (it lives on the `Mains` adapter), and such a battery must not be skipped.

**`SCOPE` selects behaviour, it does not filter.** Every battery is in scope; the attribute decides how it is shown:

| `POWER_SUPPLY_SCOPE` | meaning | behaviour |
|---|---|---|
| `Device` | a peripheral — mouse, keyboard, headset | **auto-hiding**: contributes nothing until it drops below `LOW` |
| `System`, or absent | the machine's own battery | **always visible**, at every level |

A laptop battery is a permanent status readout, not an alert — you want to glance at it at 80%. A peripheral battery is the opposite: it is noise at 80% and only earns bar space when it is nearly out. One module covers both, so host layering (chunk C) never has to add a battery module back per-host, and no host list is involved — the kernel's own attribute drives it.

**Choice and output.** The module renders, in order: **every** system battery, then any peripheral below `LOW`, e.g. `󰁽 64%  󰍽 18%`.

> **Amended 2026-08-01 after code review.** This section originally said "the system battery", singular, and the first implementation followed it literally — assigning rather than accumulating, so on a dual-battery machine the last one scanned won and could mask a nearly-flat sibling as `ok`. System batteries accumulate; the alert class takes the **minimum across discharging ones**. Do not re-derive the singular form from this document. If neither applies the script prints nothing and exits 0, so waybar hides the module — the same idiom `custom/media` uses. Otherwise it emits one line of JSON, `{text, tooltip, class}`, and the tooltip lists every device with its level, including ones not shown in the text.

`class` is taken from the **most urgent** entry being displayed. Both comparisons are strictly-less-than: `capacity < 10` gives `critical`, else `capacity < 25` gives `low`, else `ok`. Exactly 25 is not low; exactly 10 is `low`, not critical.

**Charging suppresses the alert classes, for system batteries only.** A system battery at 8% on AC is not an emergency, which is what the deleted `#battery.critical:not(.charging)` rule encoded and why it is worth preserving. It applies only where charge state is trustworthy: `STATUS` is reliable for a system battery, and demonstrably not for this mouse, which reported `Discharging` and then `Unknown` minutes apart while sitting still. Peripheral entries ignore `STATUS` entirely. Rendering goes through `jq`, as in `mediaexec.sh`, because model names are vendor strings and `Corsair HS80 & Mouse` would be malformed Pango markup.

Thresholds and the glyph map are constants at the top of the script, the same shape as `MAXLEN`/`DEFAULT_ICON` in `mediaexec.sh`. They are deliberately **not** `options/` entries: that would mean an AGS panel row and a `settings.sh` case for a number nobody tunes twice.

**Poll interval 60s**, matching `custom/nightlight`. A battery that moves a percent an hour does not need a faster tick, and each `interval` costs a fork.

### 2. Placement and the bar's rhythm

`style.css` documents the group map and warns that a hidden module leaves its neighbours colliding. An auto-hiding module must therefore not be load-bearing for any gap.

The module takes `battery`'s old slot between `bluetooth` and `pulseaudio`, and **both `bluetooth` and `custom/battery` become self-contained groups** at 15px on each side. Every neighbouring gap is then 30px whether the module is showing or not, so its appearance never reflows the bar. The `bt·bat` pair in the header map dissolves:

```
right  cpu·mem·gpu·disk | net | bt | [bat] | vol | tray | night·set·notif·power
```

`style.css` gains `#custom-battery.low` (palette) and `#custom-battery.critical` (fixed red), the latter under the existing ALERT EXCEPTION rationale: pywal cannot guarantee any palette slot reads as "danger." `class: ok` deliberately gets **no rule** — it inherits `@foreground` from the grouped selector the module already belongs to, so a healthy system battery looks like every other readout on the bar.

On this desktop the module is auto-hiding; on a laptop host it would be permanently present. The self-contained 15px grouping is what makes both cases correct without a second layout.

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
| `uevent` unreadable | `[ -r ]` guard, skip (verified with a `chmod 000` fixture) |
| device unplugged between the glob and the read | the field reset leaves `u_type` empty, so the entry is skipped; bash may print one redirection error into waybar's log. Sub-millisecond window against a 60s tick, accepted |
| peripheral powered off (`ONLINE=0`) | skipped; its stale `CAPACITY` is never reported |
| peripheral charge status | ignored entirely (see Decisions) |
| system battery on AC | alert classes suppressed, percentage still shown |

**Resolved 2026-08-01 by probing, before any code:** a powered-off mouse does *not* drop its sysfs node, and does *not* report `CAPACITY=0`. It keeps its last reading (75) and flips `POWER_SUPPLY_ONLINE` from `1` to `0`. Both branches anticipated in the first draft of this spec were wrong, which is the argument for having probed rather than picked one.

## Testing

`BATTERY_SYSFS` (default `/sys/class/power_supply`) is the whole testability seam: one line, and the suite needs neither hardware nor root — tests point it at a temp directory of fake `uevent` files.

`scripts/waybar/test-battery.sh`, dependency-free and exit-1-on-failure, following the conventions of `scripts/doctor/test/run-tests.sh` so chunk D can discover it unchanged. Cases:

*Peripherals (`SCOPE=Device`)*

- nothing present → silent
- one device above threshold → silent
- exactly 25 → silent (the rule is `< LOW`)
- 24 → shown, `class: low`
- exactly 10 → `class: low` (the rule is `< CRITICAL`)
- 9 → `class: critical`
- `ONLINE=0` at 9% → silent, and absent from the text
- two low devices → both in the text, `class` from the lower
- one low, one healthy → only the low one in the text, both in the tooltip

*System battery (`SCOPE=System` or absent)*

- 64%, discharging → **shown**, `class: ok` — this is the "does not disappear" requirement
- 64% with no `ONLINE` attribute → shown, not skipped by the `ONLINE` rule
- 8%, discharging → `class: critical`
- 8%, `STATUS=Charging` → shown, `class: ok` (charging suppresses the alert)

*Both present*

- system 64% + peripheral 18% → text shows both, system first
- system 64% + peripheral 80% → text shows the system battery only

*Parsing*

- non-numeric capacity → skipped, no error output
- model containing `&` → escaped, valid Pango

This is not ceremony: on 2026-08-01 the media module shipped two bugs — a tab-collapse field shift and a ranking rule that blanked the bar — that were caught only by exactly this kind of fixture, and neither was visible by reading the code.

## Verification

- `shellcheck -S warning` clean (the pre-commit hook's level).
- `./doctor.sh` exits 0 with no new findings.
- waybar restarted, log free of `No batteries.` and of module errors.
- Screenshot of the bar with the module forced visible, confirming glyph spacing and that gaps are unchanged when it hides.
- Mouse switched off with `BATTERY_SYSFS` pointed at real sysfs: module silent, despite `CAPACITY=75` still sitting in the node.
- Screenshot of the swaync control center, confirming nothing changed visually when the dead `backlight` widget is removed.

## Out of scope

- DDC/CI monitor brightness via `ddcutil` (rejected: system-level change beyond dotfiles, unverifiable until installed, laggy on key repeat). Deleting the binds is reversible if this is ever wanted.
- Any battery presence in the AGS settings panel or the swaync sidebar.
- Chunks B, C and D.
