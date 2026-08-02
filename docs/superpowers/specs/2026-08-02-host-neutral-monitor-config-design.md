# Host-Neutral Monitor Config — Design

**Date:** 2026-08-02
**Status:** Approved, ready for planning
**Backlog chunk:** C (host-specific config layering)

## Problem

Three tracked files bake this desktop's monitor into the repo, and they are
maintained by three different writers:

| File | Value | Written by |
|------|-------|------------|
| `hypr/config/hardware/monitor.conf` | `monitor=DP-1,2560x1440@144,auto,1` | `scripts/settings/advanced/monitor.sh` (appends) |
| `hypr/config/hardware/primary.conf` | `$monitor = DP-1` | `scripts/settings/settings.sh`, `ags/lib/monitors.ts` |
| `options/mainmonitor` | `DP-1` | the same two |

`install.sh` touches none of them, so a clean checkout on new hardware ships
`DP-1`. The catch-all `monitor=,preferred,auto,1` keeps the screen from going
blank, but `hyprlock` then draws all six of its widgets on a monitor that does
not exist, and `wall.sh`, `restore-wallpaper.sh` and both SDDM scripts target a
dead output.

### The fallback line is itself a bug

Measured live on 2026-08-02, by applying each keyword with `hyprctl keyword`
and reading the rate back from `hyprctl monitors -j`:

```
DP-1,preferred,auto,1   ->  2560x1440@59.951
DP-1,highrr,auto,1      ->  2560x1440@143.998
```

`availableModes` lists `2560x1440@59.95Hz` **before** `@144.00Hz`, and
`preferred` takes the EDID preferred timing, which on this ROG PG279Q is the
60 Hz one. So today's catch-all rule is a 60 Hz trap: any *second* monitor
plugged into this machine already comes up at its EDID rate rather than its
best. Replacing the hardcoded line with a generic one fixes the fallback in the
same edit.

Both `highrr` and `highres` are present in the Hyprland 0.56.1 binary
(`strings $(command -v Hyprland)`), so this is not a documentation claim.

## Decision

**Make the tracked config genuinely host-neutral and let each consumer fall
back sanely.** No detection, at install time or at startup.

This was chosen over detecting the output name from `/sys/class/drm` during
`install.sh`, and over detecting it from `hyprctl monitors` in an `exec-once`.
Both were rejected as unnecessary machinery: this stays a one-machine repo, and
every consumer either already has a "first monitor" fallback or is one branch
away from one.

`options/mainmonitor` and `primary.conf` hold a genuine *user preference* —
which of several screens is the main one — not merely a hardware fact.
**Empty means "no preference"**, and every consumer resolves that to "all
monitors" or "any monitor" as fits. The preference is not removed: `settings.sh`
and the AGS panel keep writing a real name the moment the user picks one, and
neither writer changes.

## Scope

In scope: the three tracked files, the four scripts that consume
`options/mainmonitor`, one new doctor check with its test module, and the docs
those changes falsify.

Out of scope, decided explicitly:

- **Detection of any kind.** No sysfs probe in `install.sh`, no `exec-once`
  monitor script.
- **Multi-host layering.** No hostname-keyed configs, no gitignored local
  overrides. This is a one-machine repo.
- **Moving monitor rules into `overrides.conf`.** The panel-owned override file
  could host them, but the TUI wizard's append-to-`monitor.conf` flow works and
  is not what this chunk is about.
- **Changing `settings.sh` or `ags/lib/monitors.ts`.** Both already write a real
  connector name into both files; that path is correct and stays.
- **The `eDP-1` default in the two SDDM scripts is removed, not relocated.**
  Nothing gains a different hardcoded default.

## Design

### 1. `hypr/config/hardware/monitor.conf`

Both lines collapse into one:

```
monitor=,highrr,auto,1
```

Every connected output, native resolution, highest refresh rate. No connector
is named, so a fresh checkout is correct on any hardware.

`scripts/settings/advanced/monitor.sh` appends host-specific `monitor=` lines
to this file and continues to work unchanged: Hyprland applies a named rule to
its output regardless of where the catch-all sits, so ordering is not load
bearing. A line the wizard appends is a local edit to a tracked file on a
one-machine repo — that is expected, and check 5 below flags it if the
connector later disappears.

### 2. `hypr/config/hardware/primary.conf`

```
$monitor =
```

with a header comment recording that empty means "every monitor", that this is
hyprlock's own default, and that the file is written by `settings.sh` and the
Super+I panel.

`hypr/hyprlock.conf` sources this file and uses `monitor = $monitor` on six
widgets. Its `background {}` block already carries a bare `monitor =` and
renders on every output, so "empty means all" is the behaviour that file
already relies on.

**Open risk:** that `$monitor =` (empty) survives hyprlang variable expansion
into `monitor = $monitor`. This is unverified. `hyprlock -c <file>` aborts at
the Wayland connect (`hyprlock.cpp:63`) before it parses the config, so it
cannot be probed without a real session. It must be confirmed by launching
hyprlock once for real during implementation.

**Fallback if it does not hold:** put a bare `monitor =` on the six widgets, as
`background {}` already has, and let `primary.conf` matter only when a name is
actually set. The preference still works; only the empty case changes shape.

### 3. `options/mainmonitor`

Ships empty. Same contract as `primary.conf`: empty means no preference.

`ags/lib/monitors.ts:getMainMonitor()` already returns `""` on a read failure,
so an empty file needs no AGS change — the MAIN badge simply does not appear
until a monitor is chosen.

### 4. The four consumers of `options/mainmonitor`

| Script | Behaviour today with an empty value | Change |
|--------|--------------------------------------|--------|
| `scripts/hyprland/wall.sh` | greps `"^: :"`, matches nothing, existing first-monitor fallback catches it | correct already; skip the named lookup outright when empty, rather than running a grep that cannot match |
| `scripts/hyprland/restore-wallpaper.sh` | `\|\| echo "eDP-1"` substitutes a wrong name; the awww cache glob misses and falls through to the wallpaper symlink | drop the `eDP-1` default; glob `*/*` when the preference is empty, so the newest cache entry for *any* monitor is used |
| `sddm/update_sddm_root.sh` | same as above | same as above |
| `sddm/watch_wallpaper.sh` | **breaks silently** — see below | empty accepts any filename in the inotify guard, and globs any monitor in the poll branch |

`watch_wallpaper.sh` is the one that fails rather than degrades. Its inotify
loop compares each changed filename against `$monitor`:

```bash
[[ "$file" == "$monitor" ]] || continue
```

With an empty preference that comparison never matches, so SDDM wallpaper sync
stops with no error anywhere. The poll fallback branch has the same problem via
`ls -t "$cache_dir"/*/"$monitor"`. Both need an explicit empty case.

**On the duplication.** `restore-wallpaper.sh`, `update_sddm_root.sh` and the
poll branch of `watch_wallpaper.sh` all run the same `ls -t <cache>/*/<mon>`
plus `grep -oE '/.+$'` pair, and a shared helper is the obvious move. It is
deliberately not done: `update_sddm_root.sh` runs **as root against another
user's home**, and sourcing a helper out of a user-writable
`$USER_HOME/.config/scripts/` as root is privilege escalation. The duplication
stays, and each copy carries a comment saying why.

### 5. `scripts/doctor/checks/hardware.sh`

A sixth check module, so this class of drift cannot come back silently.

- Public function `check_hardware`; private helpers prefixed `_hw_`.
- One host probe in its own function, `_hw_connected_outputs`, so tests can stub
  it. It reads `/sys/class/drm/card*-*/status` and returns the names whose
  status is `connected`. Deliberately not `hyprctl`: the doctor must work
  without a compositor, and sysfs does. Verified on this host — `card1-DP-1:
  connected`, four others `disconnected`.
- Occurrences come from `git ls-files -z` with `while IFS= read -r -d ''`, per
  the repo convention, never a hand-written path list.
- For each tracked file it finds tokens matching the DRM connector *shape*
  (`DP-N`, `HDMI-A-N`, `eDP-N`, `DVI-*`, `LVDS-*`) and reports any that names a
  connector not in the connected set. A shape regex is a kernel-defined
  namespace, not an inventory of this repo's paths, so it does not violate
  "derive, don't list".
- **Severity is WARN, not ERROR.** Naming a connector that is currently
  unplugged is legitimate.
- **Markdown files are skipped.** `README.md:277` and `QUICKSTART.md:68` carry
  `DP-1` and `HDMI-A-1` as deliberate examples, exactly the case that already
  excludes `docs/` from the literal-path scan.
- Loops use `while read ...; do ... done < <(cmd)`, never a pipeline, or the
  severity counters are lost in a subshell and every finding is discarded.
- `ok` is printed only when the check finds nothing at all.
- Every path in a fix hint goes through `doctor_q`, and no hint contains
  `<placeholder>` text.

`scripts/doctor/test/test-hardware.sh` accompanies it, one module per check, and
is picked up automatically by `run-tests.sh` and therefore by `./test.sh` and
the pre-commit hook — no registration step.

### 6. Documentation

- `README.md:277` — the `# DP-1` comment on the `mainmonitor` tree entry.
- `QUICKSTART.md:68` — the "Change primary monitor" block, which should state
  that leaving the file empty means "no preference".
- `CLAUDE.md` — the `options/` paragraph, to record the empty-means-no-
  preference contract, and the doctor architecture tree, to list the sixth
  module.
- `CHANGELOG.md` — an entry.

## Verification

Several surfaces here fail silently, so each is checked directly rather than
inferred. This follows the repo's established habit of verifying every surface a
change touches.

| What | How |
|------|-----|
| Hyprland still at 144 Hz | `hyprctl reload; hyprctl monitors -j \| jq -r '.[].refreshRate'` |
| Empty `$monitor` expands | **launch hyprlock for real**, confirm the input field and clock render, unlock |
| Wallpaper pipeline intact | run `wall.sh`, confirm the palette propagates and the bar restarts |
| Wallpaper restore intact | run `restore-wallpaper.sh` with `options/mainmonitor` empty |
| SDDM sync intact | change the wallpaper with an empty preference, confirm `watch_wallpaper.sh` fires the update |
| Preference still round-trips | pick a monitor in `settings.sh`, confirm both files gain the name and hyprlock honours it |
| No regressions | `./doctor.sh` — 0 errors, 0 warnings, and the one pre-existing D-Bus notice |
| Suites green | `./test.sh` |

The doctor baseline before this work is 0 errors, 0 warnings, 1 notice, where
the notice only reports which daemon owns `org.freedesktop.Notifications`. Any
new finding is a real regression.
