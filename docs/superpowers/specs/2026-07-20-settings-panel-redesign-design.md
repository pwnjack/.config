# Settings Panel Redesign — Design

Date: 2026-07-20
Status: approved by user (layout, rows, IA, persistence, behavior)

## Goal

Rebuild the AGS Super+I settings panel (`ags/`) into a complete, polished settings
app for these dotfiles: reorganized navigation, self-documenting rows, settings that
persist across reboots, fresh values on every open, and search — without duplicating
features that already have a home (waypaper for wallpapers, rofi menus for
cheatsheet/powermenu/clipboard/emoji, `resources` for task manager, the TUI
`scripts/settings/` for advanced wizards and updates).

## User-validated decisions

- **Layout A — grouped sidebar**: section headers in the sidebar, search on top,
  quick-action chips in the panel footer.
- **Rows B — descriptive rows**: each setting row has an icon, a title, a one-line
  description, the control, and a reset-to-default button.
- **Persistence via `hypr/config/overrides.conf`**: panel-owned file sourced last.
- **Instant apply, no Apply button**: per-row reset is the undo.

## Information architecture

Sidebar (search field above, groups with uppercase headers):

| Group | Category | Contents |
|-------|----------|----------|
| Look & Feel | Appearance | blur (toggle+size+passes), shadows, corner rounding, border width, gaps in/out, active/inactive opacity, main font, GTK font, cursor theme+size |
| Look & Feel | Animations | animations master toggle, per-animation speed sliders (windows, in, out, move, fade, workspaces, border) |
| Behavior | Windows | layout mode (dwindle/master), preserve split, smart split, allow tearing, resize on border, XWayland (pseudotile omitted — option removed in Hyprland 0.55; the old Misc logo/splash toggles are dropped as never-visible under a wallpaper daemon) |
| Behavior | Input | mouse sensitivity, follow mouse, numlock, natural scroll, touchpad scroll factor |
| Behavior | Notifications | swaync position X/Y, timeouts, notification/control-center width, transition time |
| Hardware | Monitors (new) | read-only per-monitor cards from `hyprctl monitors -j` (name, model, resolution, scale, refresh), main-monitor picker (writes `options/mainmonitor` + `hypr/config/hardware/primary.conf`), VRR dropdown (moved from Power), "Advanced setup" chip launching the TUI monitor wizard in the user's terminal |
| Hardware | Power | lock timeout, screen-off timeout (hypridle), DPMS on key press / mouse move |
| System | Startup (new) | lock on autologin (`options/autologin`), desktop clock (`options/clock`, starts/stops eww like `settings.sh` does), random wallpaper on startup (`options/randomwallpaper`, moved out of Misc) |
| System | Default Apps | browser, terminal, editor, media player (+icon), launcher type (vertical/horizontal dropdown) |

Footer quick actions (chips): Reload Hyprland (`hyprctl reload`), Restart Waybar
(`scripts/waybar/waybar.sh`), Update System (opens `options/terminal` running
`scripts/settings/update.sh`), Advanced (opens terminal running
`scripts/settings/settings.sh`).

The old "Toggles" and "Misc" categories dissolve into the categories above.

### Search

The search entry filters a flat registry of all rows (category, title, description,
keywords). Typing switches the content area to a results list of matching rows
(fully functional controls, with a "category" breadcrumb on each). Clearing the
search restores the normal category view. Esc clears search first, closes panel
second.

## Architecture

```
ags/
├── app.ts                    # entry; loads CSS from style.ts
├── style.ts                  # pywal-driven CSS (moved out of app.ts)
├── lib/
│   ├── colors.ts             # (existing) pywal palette
│   ├── hyprctl.ts            # (existing) keyword get/set
│   ├── persist.ts            # NEW: overrides.conf read/upsert/remove + defaults
│   ├── options.ts            # (existing) options/ files; extended option list
│   ├── hypridle.ts           # (existing)
│   ├── swaync.ts             # (existing)
│   ├── monitors.ts           # NEW: hyprctl monitors -j parsing, main-monitor write
│   └── registry.ts           # NEW: row metadata (category, title, description,
│                             #   control builder) declared once per row; category
│                             #   pages and search results both render from it
├── widget/
│   ├── SettingsPanel.tsx     # shell: sidebar + search + stack + footer;
│   │                         #   rebuilds content on window show (freshness)
│   ├── components/
│   │   ├── SettingRow.tsx    # NEW: icon + title + description + control + reset
│   │   ├── Toggle.tsx        # control-only variants used inside SettingRow
│   │   ├── Slider.tsx
│   │   ├── Dropdown.tsx
│   │   ├── TextEntry.tsx     # NEW: extracted from the repeated entry blocks
│   │   ├── SearchEntry.tsx   # NEW
│   │   ├── ActionChip.tsx    # NEW: footer buttons
│   │   ├── MonitorCard.tsx   # NEW
│   │   └── CategoryNav.tsx   # grouped sections + active state
│   └── categories/           # one file per category above
```

### Persistence (`lib/persist.ts`)

- `hypr/config/overrides.conf` — created by the panel, sourced as the **last** line
  of `hyprland.conf` (`source = ~/.config/hypr/config/overrides.conf`); header
  comment marks it panel-managed. Add the source line and an empty tracked file in
  this project.
- `setPersistent(keyword, value)`: `hyprctl keyword` (instant) + upsert
  `keyword = value` in overrides.conf.
- `resetSetting(keyword)`: remove the line from overrides.conf, re-apply the
  default via `hyprctl keyword`.
- Defaults come from a `DEFAULTS` table in `persist.ts` mirroring the tracked repo
  configs (decor.conf, input.conf, etc.). A row shows its reset button only when an
  override line exists.
- Non-Hyprland settings keep their existing persistence (options files, swaync
  config.json, hypridle.conf) and their reset uses the same DEFAULTS table.
- Animation speeds persist as `animation = name,enabled,speed,bezier[,style]` lines
  in overrides.conf, preserving bezier/style read at change time.

### Freshness

The window's `notify::visible` handler rebuilds the active category's content each
time the panel is shown, so values always reflect current system state (external
edits, wal changes, hyprctl reload).

## Visual design

Keep the pywal glass identity: blurred dark floating panel, 16px radius, pywal
accent (`colors[4]`) for active states. Refinements: sidebar section headers
(small uppercase, muted), descriptive rows with 32px icon plate, hover-revealed
reset button, footer chip bar separated by a hairline, consistent 8px spacing
grid. All CSS stays pywal-templated in `style.ts`; panel grows to ~880x640 to
accommodate descriptions.

## Error handling

- Every external read keeps the guarded pattern: missing file/command → sane
  default, log to console, panel still opens.
- overrides.conf writes are atomic (write temp + replace via Gio) to avoid a
  corrupt file breaking Hyprland startup; parse errors → treat as empty and
  regenerate.
- Terminal-launching chips read `options/terminal` and fall back to `ghostty`;
  missing scripts disable the chip.

## Verification

1. `tsc --noEmit` in `ags/` passes.
2. Panel relaunch (`astal --quit` + `hyprctl dispatch exec "ags run …"`), open via
   Super+I: all categories render, no console errors.
3. Persistence round-trip: change gaps → confirm overrides.conf line → `hyprctl
   reload` → value survives; reset → line removed, default restored.
4. Freshness: change a value externally, reopen panel, row shows current value.
5. Search: query matches rows across categories; controls in results work.
6. Startup toggles round-trip their options files; random wallpaper toggle drives
   `restore-wallpaper.sh` behavior (already verified in sandbox).

## Non-goals

- No wallpaper picker (waypaper), no keybind cheatsheet (rofi Super+H), no power
  menu, no clipboard/emoji, no task manager, no package-update UI beyond
  launching the existing TUI updater, no monitor add/remove wizard (TUI keeps it).
- No live monitor reconfiguration writes to monitor.conf from the panel.
