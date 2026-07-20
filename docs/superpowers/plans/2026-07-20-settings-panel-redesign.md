# Settings Panel Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the AGS Super+I settings panel into a grouped-sidebar, searchable settings app whose Hyprland tweaks persist across reboots via a panel-owned `overrides.conf`.

**Architecture:** AGS v3 (astal, GTK4, TSX) app at `ags/`. A row registry (`lib/registry.ts` + `widget/components/rows.tsx` factories) declares every setting once; category pages and search results both render from it. Hyprland settings write through `lib/persist.ts` (instant `hyprctl keyword` + upsert into `hypr/config/overrides.conf`, sourced last). The shell rebuilds content on window show for freshness.

**Tech Stack:** AGS/astal GTK4 TSX, GJS (GLib/Gio), pywal CSS-in-TS, bash verification.

**Spec:** `docs/superpowers/specs/2026-07-20-settings-panel-redesign-design.md`

**Build gate note:** there is no node_modules/tsc here; `ags bundle app.ts <out>` (esbuild) is the compile check, plus runtime launch. Verified working: `cd ~/.config/ags && ags bundle app.ts /tmp/out.js` → exit 0.

**Spec deviations (already noted in spec):** pseudotile omitted (removed in Hyprland 0.55); Misc logo/splash toggles dropped.

**Panel relaunch command (used throughout):**
```bash
astal -i settings-panel --quit 2>/dev/null; hyprctl dispatch exec "ags run $HOME/.config/ags/app.ts"; sleep 2; astal --list
# Expected: "settings-panel"
```

---

## File structure

```
hypr/hyprland.conf                       MODIFY  add `source = config/overrides.conf` as last source line
hypr/config/overrides.conf               CREATE  panel-managed, header comment only (tracked)
ags/app.ts                               MODIFY  slim entry; CSS from style.ts
ags/style.ts                             CREATE  all CSS (pywal-templated)
ags/lib/persist.ts                       CREATE  overrides read/upsert/remove, DEFAULTS, reset
ags/lib/monitors.ts                      CREATE  hyprctl monitors -j, main-monitor writes
ags/lib/registry.ts                      CREATE  CategoryDef/RowSpec types, category registry, search, refresh hook
ags/lib/options.ts                       MODIFY  extend OPTIONS list
ags/lib/swaync.ts                        MODIFY  add SWAYNC_DEFAULTS
ags/lib/hypridle.ts                      keep    (defaults already in file)
ags/widget/SettingsPanel.tsx             REWRITE shell: grouped nav, search, footer, rebuild-on-show
ags/widget/components/CategoryNav.tsx    REWRITE grouped sections
ags/widget/components/SettingRow.tsx     CREATE  icon+title+desc+control+reset row
ags/widget/components/controls.tsx       CREATE  ToggleControl/SliderControl/DropdownControl/EntryControl (replaces Toggle/Slider/Dropdown/TextEntry)
ags/widget/components/rows.tsx           CREATE  RowSpec factories wiring controls to persist/options
ags/widget/components/SearchEntry.tsx    CREATE
ags/widget/components/ActionChip.tsx     CREATE
ags/widget/components/MonitorCard.tsx    CREATE
ags/widget/components/Toggle.tsx         DELETE  (superseded by controls.tsx)
ags/widget/components/Slider.tsx         DELETE
ags/widget/components/Dropdown.tsx       DELETE
ags/widget/categories/{Appearance,Animations,Windows,Input,Notifications,Monitors,Power,Startup,DefaultApps}.tsx  CREATE/REWRITE (data-driven)
ags/widget/categories/{Toggles,Misc,Layout,Apps,AnimationSettings}.tsx  DELETE
```

---

### Task 1: Persistence lib (`persist.ts` + `overrides.conf` wiring)

**Goal:** Hyprland keyword changes apply instantly and survive reboot via a panel-owned overrides file sourced last.

**Files:**
- Create: `hypr/config/overrides.conf`, `ags/lib/persist.ts`
- Modify: `hypr/hyprland.conf` (add source line after `config/software/rules.conf`)

**Acceptance Criteria:**
- [ ] `overrides.conf` sourced last; `hyprctl reload` clean with it present
- [ ] A `general:gaps_in = 13` line in overrides.conf survives `hyprctl reload` (getoption returns 13)
- [ ] `persist.ts` bundles: setPersistent / resetSetting / hasOverride / getOverride / setAnimationPersistent + DEFAULTS mirror tracked configs
- [ ] Writes are atomic (Gio `replace_contents`)

**Verify:**
```bash
hyprctl reload && echo "general:gaps_in = 13" >> ~/.config/hypr/config/overrides.conf && hyprctl reload && hyprctl getoption general:gaps_in -j | grep '"int": 13' && sed -i '/general:gaps_in = 13/d' ~/.config/hypr/config/overrides.conf && hyprctl reload && hyprctl getoption general:gaps_in -j | grep '"int": 4' && echo MECHANISM-OK
```
→ `MECHANISM-OK`

**Steps:**

- [ ] **Step 1: Create `hypr/config/overrides.conf`**

```
#
# PANEL-MANAGED OVERRIDES
# Written by the Super+I settings panel (ags/lib/persist.ts).
# Sourced last from hyprland.conf so these lines win over the tracked configs.
# One `keyword = value` or `animation = ...` per line. Do not edit by hand;
# use the panel, or delete a line to fall back to the tracked default.
#
```

- [ ] **Step 2: Wire into `hypr/hyprland.conf`** — after the `source = config/software/rules.conf` line, add:

```
## Panel-managed overrides (must stay last so they win)
source = config/overrides.conf
```

- [ ] **Step 3: Verify the mechanism** — run the **Verify** command above; expect `MECHANISM-OK`.

- [ ] **Step 4: Write `ags/lib/persist.ts`**

```typescript
import GLib from "gi://GLib"
import Gio from "gi://Gio"
import { execAsync } from "ags/process"

const OVERRIDES_PATH = GLib.get_home_dir() + "/.config/hypr/config/overrides.conf"

const HEADER = `#
# PANEL-MANAGED OVERRIDES
# Written by the Super+I settings panel (ags/lib/persist.ts).
# Sourced last from hyprland.conf so these lines win over the tracked configs.
# One \`keyword = value\` or \`animation = ...\` per line. Do not edit by hand;
# use the panel, or delete a line to fall back to the tracked default.
#
`

// Mirrors the tracked repo configs (decor.conf, general.conf, input.conf, envvars).
export const DEFAULTS: Record<string, string> = {
    "general:gaps_in": "4",
    "general:gaps_out": "10",
    "general:border_size": "1",
    "general:resize_on_border": "true",
    "general:allow_tearing": "false",
    "general:layout": "dwindle",
    "decoration:rounding": "18",
    "decoration:active_opacity": "1.0",
    "decoration:inactive_opacity": "1.0",
    "decoration:shadow:enabled": "false",
    "decoration:blur:enabled": "true",
    "decoration:blur:size": "6",
    "decoration:blur:passes": "4",
    "animations:enabled": "true",
    "input:sensitivity": "0",
    "input:follow_mouse": "1",
    "input:numlock_by_default": "true",
    "input:touchpad:natural_scroll": "false",
    "input:touchpad:scroll_factor": "0.6",
    "dwindle:preserve_split": "true",
    "dwindle:smart_split": "false",
    "misc:vrr": "0",
    "misc:key_press_enables_dpms": "true",
    "misc:mouse_move_enables_dpms": "true",
    "xwayland:enabled": "true",
    "cursor:enable_hyprcursor": "true",
    "cursor:size": "24",
}

function readLines(): string[] {
    try {
        const [ok, contents] = GLib.file_get_contents(OVERRIDES_PATH)
        if (!ok || !contents) return []
        return new TextDecoder().decode(contents).split("\n")
    } catch {
        return []
    }
}

function writeLines(lines: string[]): void {
    const body = lines.filter(l => l.trim() !== "" && !l.startsWith("#")).join("\n")
    const text = HEADER + (body ? body + "\n" : "")
    try {
        const file = Gio.File.new_for_path(OVERRIDES_PATH)
        // replace_contents is atomic (writes temp file, then renames)
        file.replace_contents(new TextEncoder().encode(text), null, false,
            Gio.FileCreateFlags.NONE, null)
    } catch (e) {
        console.error("Failed to write overrides.conf:", e)
    }
}

export function getOverride(keyword: string): string | null {
    for (const line of readLines()) {
        const m = line.match(/^([^#=]+?)\s*=\s*(.*)$/)
        if (m && m[1].trim() === keyword) return m[2].trim()
    }
    return null
}

export function hasOverride(keyword: string): boolean {
    return getOverride(keyword) !== null
}

function upsert(keyword: string, value: string): void {
    const lines = readLines().filter(l => {
        const m = l.match(/^([^#=]+?)\s*=/)
        return !(m && m[1].trim() === keyword)
    })
    lines.push(`${keyword} = ${value}`)
    writeLines(lines)
}

function removeLine(keyword: string): void {
    writeLines(readLines().filter(l => {
        const m = l.match(/^([^#=]+?)\s*=/)
        return !(m && m[1].trim() === keyword)
    }))
}

function apply(keyword: string, value: string): void {
    execAsync(["hyprctl", "keyword", keyword, value]).catch(console.error)
}

/** Apply now via hyprctl AND persist to overrides.conf. */
export function setPersistent(keyword: string, value: string | number | boolean): void {
    const val = typeof value === "boolean" ? (value ? "true" : "false") : String(value)
    apply(keyword, val)
    upsert(keyword, val)
}

/** Remove the override and re-apply the tracked default (if known). */
export function resetSetting(keyword: string): void {
    removeLine(keyword)
    const def = DEFAULTS[keyword]
    if (def !== undefined) apply(keyword, def)
}

/**
 * Persist a full animation line, e.g. "windows,1,6,default".
 * Stored as `animation = windows,...`; matched/replaced by animation name.
 */
export function setAnimationPersistent(name: string, line: string): void {
    const lines = readLines().filter(l =>
        !l.match(new RegExp(`^animation\\s*=\\s*${name},`)))
    lines.push(`animation = ${line}`)
    writeLines(lines)
    execAsync(["hyprctl", "keyword", "animation", line]).catch(console.error)
}

export function hasAnimationOverride(name: string): boolean {
    return readLines().some(l => l.match(new RegExp(`^animation\\s*=\\s*${name},`)))
}

export function resetAnimation(name: string): void {
    writeLines(readLines().filter(l =>
        !l.match(new RegExp(`^animation\\s*=\\s*${name},`))))
    // No hyprctl re-apply: tracked animations.conf value returns on next reload.
    execAsync(["hyprctl", "reload"]).catch(console.error)
}
```

- [ ] **Step 5: Bundle check**

Run: `cd ~/.config/ags && ags bundle app.ts /tmp/claude-panel-build.js; echo $?`
Expected: `0` (persist.ts not imported yet, but must not break the tree if imported by a scratch import test — optionally `echo 'import "./lib/persist"' >> app.ts`, bundle, then revert).

- [ ] **Step 6: Commit**

```bash
cd ~/.config && git add hypr/hyprland.conf hypr/config/overrides.conf ags/lib/persist.ts
git commit -m "feat(panel): persistence lib + panel-owned overrides.conf sourced last"
```

---

### Task 2: Component library (controls, SettingRow, chips, search, monitor card) + registry

**Goal:** Reusable widgets for descriptive rows and the data-driven row/category registry.

**Files:**
- Create: `ags/widget/components/controls.tsx`, `SettingRow.tsx`, `SearchEntry.tsx`, `ActionChip.tsx`, `MonitorCard.tsx`, `rows.tsx`, `ags/lib/registry.ts`, `ags/lib/monitors.ts`
- Modify: `ags/lib/options.ts`, `ags/lib/swaync.ts`
- Delete (in Task 4 when last usage goes): `Toggle.tsx`, `Slider.tsx`, `Dropdown.tsx`

**Acceptance Criteria:**
- [ ] SettingRow renders icon plate + title + description + control + reset (reset shown only when `resetVisible`)
- [ ] SliderControl updates its value label via closure — no widget-tree walking
- [ ] Row factories wire persist/options/reset + refresh automatically
- [ ] `ags bundle` passes with all new files imported

**Verify:** `cd ~/.config/ags && ags bundle app.ts /tmp/claude-panel-build.js; echo $?` → `0`

**Steps:**

- [ ] **Step 1: `ags/lib/registry.ts`**

```typescript
import Gtk from "gi://Gtk?version=4.0"

export interface RowSpec {
    id: string           // unique, e.g. "appearance.blur"
    title: string
    description: string
    icon: string
    keywords?: string[]  // extra search terms
    build: () => Gtk.Widget
}

export interface CategoryDef {
    id: string
    label: string
    group: "Look & Feel" | "Behavior" | "Hardware" | "System"
    icon: string
    description: string
    rows: () => RowSpec[]          // called on every (re)build → fresh values
    extra?: () => Gtk.Widget[]     // non-row widgets (monitor cards) above rows
}

let categories: CategoryDef[] = []
export const setCategories = (defs: CategoryDef[]) => { categories = defs }
export const allCategories = (): CategoryDef[] => categories

export function searchRows(query: string): { cat: CategoryDef; row: RowSpec }[] {
    const q = query.toLowerCase().trim()
    if (!q) return []
    const out: { cat: CategoryDef; row: RowSpec }[] = []
    for (const cat of categories) {
        for (const row of cat.rows()) {
            const hay = [row.title, row.description, cat.label, ...(row.keywords ?? [])]
                .join(" ").toLowerCase()
            if (q.split(/\s+/).every(w => hay.includes(w))) out.push({ cat, row })
        }
    }
    return out
}

// Shell registers its rebuild function; rows call requestRefresh() after resets.
let refreshFn: (() => void) | null = null
export const setRefreshHandler = (fn: () => void) => { refreshFn = fn }
export const requestRefresh = () => refreshFn?.()
```

- [ ] **Step 2: `ags/widget/components/controls.tsx`** — control-only widgets used inside SettingRow.

```tsx
import Gtk from "gi://Gtk?version=4.0"

export function ToggleControl(p: { active: boolean; onToggled: (v: boolean) => void }): Gtk.Widget {
    const sw = new Gtk.Switch({ active: p.active, valign: Gtk.Align.CENTER })
    sw.connect("state-set", (_s: Gtk.Switch, state: boolean) => { p.onToggled(state); return false })
    return sw
}

export interface SliderControlProps {
    value: number; min: number; max: number; step: number
    format?: (v: number) => string
    onChanged: (v: number) => void
}

export function SliderControl(p: SliderControlProps): Gtk.Widget {
    let debounce: ReturnType<typeof setTimeout> | null = null
    const fmt = p.format ?? ((v: number) => String(v))
    const valueLabel = new Gtk.Label({
        label: fmt(p.value), cssClasses: ["slider-value"], widthChars: 6, xalign: 1,
    })
    const scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, p.min, p.max, p.step)
    scale.set_value(p.value)
    scale.set_draw_value(false)
    scale.set_size_request(180, -1)
    scale.add_css_class("settings-scale")
    scale.set_valign(Gtk.Align.CENTER)
    // Wheel must scroll the panel, not the slider
    const ctrls = scale.observe_controllers()
    for (let i = 0; i < ctrls.get_n_items(); i++) {
        const c = ctrls.get_item(i)
        if (c instanceof Gtk.EventControllerScroll) scale.remove_controller(c)
    }
    scale.connect("value-changed", () => {
        const val = Math.round(scale.get_value() * 100) / 100
        valueLabel.label = fmt(val)                     // same closure — no tree walking
        if (debounce) clearTimeout(debounce)
        debounce = setTimeout(() => p.onChanged(val), 150)
    })
    const box = new Gtk.Box({ spacing: 8, valign: Gtk.Align.CENTER })
    box.append(scale); box.append(valueLabel)
    return box
}

export interface DropdownItem { label: string; value: string }

export function DropdownControl(p: { items: DropdownItem[]; active: string; onChanged: (value: string) => void }): Gtk.Widget {
    const dd = new Gtk.DropDown({
        model: Gtk.StringList.new(p.items.map(i => i.label)),
        valign: Gtk.Align.CENTER, cssClasses: ["settings-dropdown"],
    })
    const idx = p.items.findIndex(i => i.value === p.active)
    if (idx >= 0) dd.set_selected(idx)
    dd.connect("notify::selected", () => {
        const i = dd.get_selected()
        if (i < p.items.length && p.items[i].value !== p.active) p.onChanged(p.items[i].value)
    })
    return dd
}

export function EntryControl(p: { text: string; placeholder?: string; onCommit: (text: string) => void }): Gtk.Widget {
    const entry = new Gtk.Entry({
        text: p.text, hexpand: false, widthChars: 18,
        placeholderText: p.placeholder ?? "", cssClasses: ["app-entry"],
        valign: Gtk.Align.CENTER,
    })
    entry.connect("activate", () => p.onCommit(entry.get_text()))
    const focus = new Gtk.EventControllerFocus()
    focus.connect("leave", () => p.onCommit(entry.get_text()))
    entry.add_controller(focus)
    return entry
}
```

- [ ] **Step 3: `ags/widget/components/SettingRow.tsx`**

```tsx
import Gtk from "gi://Gtk?version=4.0"

export interface SettingRowProps {
    icon: string
    title: string
    description: string
    control: Gtk.Widget
    onReset?: () => void
    resetVisible?: boolean
    breadcrumb?: string   // set in search results: category label
}

export default function SettingRow(p: SettingRowProps): Gtk.Widget {
    const row = new Gtk.Box({ cssClasses: ["setting-row"], spacing: 12 })

    const plate = new Gtk.Box({ cssClasses: ["row-icon"], valign: Gtk.Align.CENTER })
    plate.append(new Gtk.Image({ iconName: p.icon }))
    row.append(plate)

    const text = new Gtk.Box({
        orientation: Gtk.Orientation.VERTICAL, hexpand: true, valign: Gtk.Align.CENTER,
    })
    const title = new Gtk.Label({ label: p.title, xalign: 0, cssClasses: ["row-title"] })
    text.append(title)
    if (p.breadcrumb) {
        title.label = p.title
        const crumb = new Gtk.Label({ label: p.breadcrumb, xalign: 0, cssClasses: ["row-crumb"] })
        text.append(crumb)
    }
    text.append(new Gtk.Label({
        label: p.description, xalign: 0, cssClasses: ["row-desc"], wrap: true,
    }))
    row.append(text)

    if (p.onReset) {
        const reset = new Gtk.Button({
            iconName: "edit-undo-symbolic", cssClasses: ["reset-btn"],
            valign: Gtk.Align.CENTER, tooltipText: "Reset to default",
            visible: p.resetVisible ?? false,
        })
        reset.connect("clicked", () => p.onReset!())
        row.append(reset)
    }
    row.append(p.control)
    return row
}
```

- [ ] **Step 4: `ags/widget/components/rows.tsx`** — RowSpec factories.

```tsx
import SettingRow from "./SettingRow"
import { ToggleControl, SliderControl, DropdownControl, EntryControl, DropdownItem } from "./controls"
import { getOptionBool, getOptionInt, getOptionFloat, getOption } from "../../lib/hyprctl"
import { setPersistent, resetSetting, hasOverride } from "../../lib/persist"
import { readOption, writeOption } from "../../lib/options"
import { RowSpec, requestRefresh } from "../../lib/registry"

interface Base { id: string; title: string; description: string; icon: string; keywords?: string[] }

const resetProps = (keyword: string) => ({
    onReset: () => { resetSetting(keyword); requestRefresh() },
    resetVisible: hasOverride(keyword),
})

export function kwToggle(b: Base & { keyword: string }): RowSpec {
    return { ...b, build: () => SettingRow({
        icon: b.icon, title: b.title, description: b.description,
        control: ToggleControl({
            active: getOptionBool(b.keyword),
            onToggled: v => setPersistent(b.keyword, v),
        }),
        ...resetProps(b.keyword),
    }) }
}

export function kwSlider(b: Base & {
    keyword: string; min: number; max: number; step: number
    float?: boolean; format?: (v: number) => string
}): RowSpec {
    return { ...b, build: () => SettingRow({
        icon: b.icon, title: b.title, description: b.description,
        control: SliderControl({
            value: b.float ? getOptionFloat(b.keyword) : getOptionInt(b.keyword),
            min: b.min, max: b.max, step: b.step, format: b.format,
            onChanged: v => setPersistent(b.keyword, b.float ? v : Math.round(v)),
        }),
        ...resetProps(b.keyword),
    }) }
}

export function kwDropdown(b: Base & { keyword: string; items: DropdownItem[] }): RowSpec {
    return { ...b, build: () => SettingRow({
        icon: b.icon, title: b.title, description: b.description,
        control: DropdownControl({
            items: b.items, active: getOption(b.keyword),
            onChanged: v => setPersistent(b.keyword, v),
        }),
        ...resetProps(b.keyword),
    }) }
}

/** options/<name> free-text entry (persists by nature; no reset). */
export function optionEntry(b: Base & { option: string; placeholder?: string; onCommit?: (v: string) => void }): RowSpec {
    return { ...b, build: () => SettingRow({
        icon: b.icon, title: b.title, description: b.description,
        control: EntryControl({
            text: readOption(b.option), placeholder: b.placeholder,
            onCommit: v => { writeOption(b.option, v); b.onCommit?.(v) },
        }),
    }) }
}

/** options/<name> enabled/disabled toggle with optional side effects. */
export function optionToggle(b: Base & { option: string; onChange?: (enabled: boolean) => void }): RowSpec {
    return { ...b, build: () => SettingRow({
        icon: b.icon, title: b.title, description: b.description,
        control: ToggleControl({
            active: readOption(b.option) === "enabled",
            onToggled: v => { writeOption(b.option, v ? "enabled" : "disabled"); b.onChange?.(v) },
        }),
    }) }
}

/** Fully custom control row (swaync, hypridle, animations, monitors). */
export function customRow(b: Base & {
    control: () => import("gi://Gtk?version=4.0").default.Widget
    onReset?: () => void; resetVisible?: () => boolean
}): RowSpec {
    return { ...b, build: () => SettingRow({
        icon: b.icon, title: b.title, description: b.description,
        control: b.control(),
        onReset: b.onReset ? () => { b.onReset!(); requestRefresh() } : undefined,
        resetVisible: b.resetVisible?.() ?? false,
    }) }
}
```

- [ ] **Step 5: `SearchEntry.tsx`, `ActionChip.tsx`, `MonitorCard.tsx`**

```tsx
// ags/widget/components/SearchEntry.tsx
import Gtk from "gi://Gtk?version=4.0"

export default function SearchEntry(p: { onChanged: (q: string) => void }): Gtk.SearchEntry {
    const entry = new Gtk.SearchEntry({
        placeholderText: "Search settings…", cssClasses: ["search-entry"], hexpand: true,
    })
    entry.connect("search-changed", () => p.onChanged(entry.get_text()))
    return entry
}
```

```tsx
// ags/widget/components/ActionChip.tsx
import Gtk from "gi://Gtk?version=4.0"

export default function ActionChip(p: { icon: string; label: string; onClicked: () => void }): Gtk.Widget {
    const btn = new Gtk.Button({ cssClasses: ["action-chip"], valign: Gtk.Align.CENTER })
    const box = new Gtk.Box({ spacing: 6 })
    box.append(new Gtk.Image({ iconName: p.icon }))
    box.append(new Gtk.Label({ label: p.label }))
    btn.set_child(box)
    btn.connect("clicked", p.onClicked)
    return btn
}
```

```tsx
// ags/widget/components/MonitorCard.tsx
import Gtk from "gi://Gtk?version=4.0"
import { MonitorInfo } from "../../lib/monitors"

export default function MonitorCard(p: { monitor: MonitorInfo; isMain: boolean; onSetMain: () => void }): Gtk.Widget {
    const card = new Gtk.Box({
        cssClasses: ["monitor-card"], orientation: Gtk.Orientation.VERTICAL, spacing: 4,
    })
    const head = new Gtk.Box({ spacing: 8 })
    head.append(new Gtk.Image({ iconName: "video-display-symbolic" }))
    head.append(new Gtk.Label({ label: p.monitor.name, cssClasses: ["monitor-name"], xalign: 0, hexpand: true }))
    if (p.isMain) {
        head.append(new Gtk.Label({ label: "MAIN", cssClasses: ["monitor-main-badge"] }))
    } else {
        const btn = new Gtk.Button({ label: "Set as main", cssClasses: ["monitor-set-main"] })
        btn.connect("clicked", p.onSetMain)
        head.append(btn)
    }
    card.append(head)
    const m = p.monitor
    card.append(new Gtk.Label({
        label: `${m.model}   ${m.width}x${m.height}@${Math.round(m.refreshRate)}Hz   scale ${m.scale}   at ${m.x},${m.y}`,
        cssClasses: ["monitor-detail"], xalign: 0,
    }))
    return card
}
```

- [ ] **Step 6: `ags/lib/monitors.ts`**

```typescript
import GLib from "gi://GLib"
import Gio from "gi://Gio"

export interface MonitorInfo {
    name: string; model: string
    width: number; height: number; refreshRate: number
    scale: number; x: number; y: number; focused: boolean
}

export function listMonitors(): MonitorInfo[] {
    try {
        const [ok, stdout] = GLib.spawn_command_line_sync("hyprctl monitors -j")
        if (!ok || !stdout) return []
        const raw = JSON.parse(new TextDecoder().decode(stdout))
        return raw.map((m: any) => ({
            name: m.name, model: m.model || "unknown",
            width: m.width, height: m.height, refreshRate: m.refreshRate,
            scale: m.scale, x: m.x, y: m.y, focused: m.focused,
        }))
    } catch (e) {
        console.error("listMonitors failed:", e)
        return []
    }
}

const MAIN_PATH = GLib.get_home_dir() + "/.config/options/mainmonitor"
const PRIMARY_CONF = GLib.get_home_dir() + "/.config/hypr/config/hardware/primary.conf"

export function getMainMonitor(): string {
    try {
        const [ok, c] = GLib.file_get_contents(MAIN_PATH)
        return ok && c ? new TextDecoder().decode(c).trim() : ""
    } catch { return "" }
}

/** Mirrors scripts/settings/settings.sh monitorselect(). */
export function setMainMonitor(name: string): void {
    const write = (path: string, text: string) => {
        try {
            Gio.File.new_for_path(path).replace_contents(
                new TextEncoder().encode(text), null, false, Gio.FileCreateFlags.NONE, null)
        } catch (e) { console.error(`write ${path} failed:`, e) }
    }
    write(MAIN_PATH, name + "\n")
    write(PRIMARY_CONF, `$monitor = ${name}\n`)
}
```

- [ ] **Step 7: Extend `ags/lib/options.ts`** — replace the `OPTIONS` block:

```typescript
export const OPTIONS = [
    "browser", "terminal", "editor", "mediaplayer", "mediaicon",
    "launchertype", "font", "font-gtk", "cursortheme",
    "autologin", "clock", "randomwallpaper", "mainmonitor",
] as const
```

- [ ] **Step 8: Add to `ags/lib/swaync.ts`** (top-level export):

```typescript
export const SWAYNC_DEFAULTS: Record<string, string | number> = {
    "positionX": "right", "positionY": "top",
    "timeout": 5, "timeout-low": 3,
    "notification-window-width": 400, "control-center-width": 358,
    "transition-time": 100,
}
```

- [ ] **Step 9: Bundle check** — imports are still unused by app.ts; add a temporary import block to `app.ts`, bundle, revert. Run **Verify** → `0`.

- [ ] **Step 10: Commit**

```bash
cd ~/.config && git add ags/lib ags/widget/components
git commit -m "feat(panel): component library, row factories, registry, monitors lib"
```

---

### Task 3: Panel shell (grouped sidebar, search, footer, freshness) + style.ts

**Goal:** New shell per approved layout A: grouped nav, top search, footer action chips, content rebuilt on every show.

**Files:**
- Create: `ags/style.ts`
- Rewrite: `ags/widget/SettingsPanel.tsx`, `ags/widget/components/CategoryNav.tsx`
- Modify: `ags/app.ts`

**Acceptance Criteria:**
- [ ] Sidebar: search on top, groups Look & Feel / Behavior / Hardware / System with uppercase headers
- [ ] Typing in search shows flat results (breadcrumbed rows) from the registry; clearing restores category view
- [ ] Esc clears search first, closes panel second
- [ ] Footer chips: Reload Hyprland, Restart Waybar, Update System, Advanced (TUI) — Update/Advanced open `options/terminal` (fallback ghostty) running the existing scripts
- [ ] Content rebuilt on `notify::visible` → fresh values on every open
- [ ] Panel 880x640, pywal styling preserved

**Verify:** relaunch panel (command in header), open via Super+I → categories render, search works, no console errors: `journalctl --user -t ags -n 20 --no-pager` (or check `hyprctl dispatch exec` output) shows no exceptions.

**Steps:**

- [ ] **Step 1: `ags/style.ts`** — move the CSS template out of app.ts and extend it. Export `buildCss()`; content = the existing CSS from `app.ts` (unchanged classes: `.settings-window`, `.panel-backdrop`, `.panel-container`, `.settings-scale`, `switch`, `.settings-dropdown`, `.app-entry`, scrollbar rules) **plus** the new classes below, all using the same `c = loadColors()` pywal values:

```typescript
import { loadColors } from "./lib/colors"

export function buildCss(): string {
    const c = loadColors()
    return `
/* … existing classes from app.ts kept verbatim … */

.panel-layout { min-width: 880px; min-height: 640px; }

.nav-section {
    font-size: 10px; letter-spacing: 1.5px; font-weight: bold;
    color: alpha(${c.colors[8]}, 0.9);
    margin: 10px 8px 2px 8px;
}
.search-entry {
    background-color: alpha(${c.colors[0]}, 0.6);
    color: ${c.foreground};
    border: 1px solid alpha(${c.colors[8]}, 0.3);
    border-radius: 8px; padding: 4px 8px; font-size: 13px;
    margin-bottom: 8px;
}
.search-entry:focus-within { border-color: ${c.colors[4]}; }

.setting-row { padding: 8px; border-radius: 10px; }
.setting-row:hover { background-color: alpha(${c.colors[4]}, 0.08); }
.row-icon {
    min-width: 32px; min-height: 32px; border-radius: 8px;
    background-color: alpha(${c.colors[4]}, 0.18);
    color: ${c.colors[6]};
}
.row-title { font-size: 14px; color: ${c.foreground}; }
.row-desc { font-size: 11px; color: alpha(${c.colors[8]}, 0.95); }
.row-crumb { font-size: 10px; color: ${c.colors[4]}; }
.reset-btn {
    background: transparent; border: none; padding: 4px;
    color: alpha(${c.colors[8]}, 0.6); opacity: 0;
}
.setting-row:hover .reset-btn { opacity: 1; }
.reset-btn:hover { color: ${c.colors[6]}; }

.panel-footer {
    border-top: 1px solid alpha(${c.colors[8]}, 0.2);
    padding: 10px 16px;
}
.action-chip {
    background-color: alpha(${c.colors[0]}, 0.6);
    color: ${c.colors[7]};
    border: 1px solid alpha(${c.colors[8]}, 0.3);
    border-radius: 99px; padding: 4px 12px; font-size: 12px;
}
.action-chip:hover { border-color: ${c.colors[4]}; color: ${c.colors[6]}; }

.monitor-card {
    background-color: alpha(${c.colors[0]}, 0.5);
    border: 1px solid alpha(${c.colors[8]}, 0.25);
    border-radius: 10px; padding: 10px 12px;
}
.monitor-name { font-size: 14px; font-weight: bold; color: ${c.foreground}; }
.monitor-detail { font-size: 11px; font-family: monospace; color: alpha(${c.colors[8]}, 0.95); }
.monitor-main-badge {
    font-size: 9px; font-weight: bold; color: ${c.background};
    background-color: ${c.colors[4]}; border-radius: 99px; padding: 2px 8px;
}
.monitor-set-main {
    font-size: 11px; border-radius: 99px; padding: 2px 10px;
    background-color: alpha(${c.colors[4]}, 0.2); color: ${c.colors[6]}; border: none;
}
.results-empty { font-size: 13px; color: alpha(${c.colors[8]}, 0.9); margin-top: 24px; }
`
}
```

- [ ] **Step 2: Rewrite `CategoryNav.tsx`** — grouped sections driven by the registry:

```tsx
import Gtk from "gi://Gtk?version=4.0"
import { allCategories } from "../../lib/registry"

const GROUP_ORDER = ["Look & Feel", "Behavior", "Hardware", "System"] as const

export default function CategoryNav(p: { active: string; onSelect: (id: string) => void }): Gtk.Widget {
    const buttons = new Map<string, Gtk.Button>()
    const nav = new Gtk.Box({
        cssClasses: ["category-nav"], orientation: Gtk.Orientation.VERTICAL, spacing: 2,
    })
    const setActive = (id: string) => {
        buttons.forEach((btn, catId) =>
            btn.set_css_classes(catId === id ? ["nav-button", "nav-active"] : ["nav-button"]))
        p.onSelect(id)
    }
    for (const group of GROUP_ORDER) {
        const cats = allCategories().filter(c => c.group === group)
        if (cats.length === 0) continue
        nav.append(new Gtk.Label({ label: group.toUpperCase(), cssClasses: ["nav-section"], xalign: 0 }))
        for (const cat of cats) {
            const btn = new Gtk.Button({
                cssClasses: cat.id === p.active ? ["nav-button", "nav-active"] : ["nav-button"],
            })
            const box = new Gtk.Box({ spacing: 8 })
            box.append(new Gtk.Image({ iconName: cat.icon }))
            box.append(new Gtk.Label({ label: cat.label }))
            btn.set_child(box)
            btn.connect("clicked", () => setActive(cat.id))
            buttons.set(cat.id, btn)
            nav.append(btn)
        }
    }
    return nav
}
```

- [ ] **Step 3: Rewrite `SettingsPanel.tsx`**

```tsx
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import GLib from "gi://GLib"
import { execAsync } from "ags/process"
import CategoryNav from "./components/CategoryNav"
import SearchEntry from "./components/SearchEntry"
import ActionChip from "./components/ActionChip"
import SettingRow from "./components/SettingRow"
import { allCategories, searchRows, setCategories, setRefreshHandler } from "../lib/registry"
import { readOption } from "../lib/options"
import { CATEGORIES } from "./categories"           // Task 4 barrel; stub in this task

const HOME = GLib.get_home_dir()

function terminalExec(script: string) {
    const term = readOption("terminal") || "ghostty"
    execAsync(["hyprctl", "dispatch", "exec", `${term} -e ${script}`]).catch(console.error)
}

function categoryPage(catId: string): Gtk.Widget {
    const cat = allCategories().find(c => c.id === catId)!
    const page = new Gtk.Box({
        cssClasses: ["category-content"], orientation: Gtk.Orientation.VERTICAL, spacing: 6,
    })
    page.append(new Gtk.Label({ label: cat.label, cssClasses: ["category-title"], xalign: 0 }))
    page.append(new Gtk.Label({ label: cat.description, cssClasses: ["category-desc"], xalign: 0 }))
    page.append(new Gtk.Box({ cssClasses: ["content-separator"] }))
    for (const w of cat.extra?.() ?? []) page.append(w)
    for (const row of cat.rows()) page.append(row.build())
    return page
}

function resultsPage(query: string): Gtk.Widget {
    const page = new Gtk.Box({
        cssClasses: ["category-content"], orientation: Gtk.Orientation.VERTICAL, spacing: 6,
    })
    const matches = searchRows(query)
    page.append(new Gtk.Label({
        label: `Results for “${query}”`, cssClasses: ["category-title"], xalign: 0,
    }))
    page.append(new Gtk.Box({ cssClasses: ["content-separator"] }))
    if (matches.length === 0) {
        page.append(new Gtk.Label({ label: "No settings match.", cssClasses: ["results-empty"], xalign: 0 }))
    }
    for (const { cat, row } of matches) {
        const built = row.build()
        // rebuild with breadcrumb: rows.build() returns SettingRow; simplest is a
        // wrapper label above — categories are few, keep the row and prefix a crumb:
        const wrap = new Gtk.Box({ orientation: Gtk.Orientation.VERTICAL })
        wrap.append(new Gtk.Label({ label: cat.label, cssClasses: ["row-crumb"], xalign: 0 }))
        wrap.append(built)
        page.append(wrap)
    }
    return page
}

export default function SettingsPanel() {
    setCategories(CATEGORIES)

    let activeCategory = allCategories()[0].id
    let query = ""
    let searchWidget: Gtk.SearchEntry

    const scroll = new Gtk.ScrolledWindow({
        hscrollbarPolicy: Gtk.PolicyType.NEVER, vscrollbarPolicy: Gtk.PolicyType.AUTOMATIC,
        hexpand: true, vexpand: true, cssClasses: ["content-scroll"],
    })

    const render = () => {
        scroll.set_child(query ? resultsPage(query) : categoryPage(activeCategory))
    }
    setRefreshHandler(render)

    const sidebar = new Gtk.Box({
        cssClasses: ["category-nav"], orientation: Gtk.Orientation.VERTICAL, spacing: 2,
    })
    const rebuildSidebar = () => {
        let child = sidebar.get_first_child()
        while (child) { const next = child.get_next_sibling(); sidebar.remove(child); child = next }
        searchWidget = SearchEntry({ onChanged: q => { query = q; render() } })
        sidebar.append(searchWidget)
        sidebar.append(CategoryNav({
            active: activeCategory,
            onSelect: id => { activeCategory = id; query = ""; searchWidget.set_text(""); render() },
        }))
    }

    const footer = new Gtk.Box({ cssClasses: ["panel-footer"], spacing: 8 })
    footer.append(ActionChip({ icon: "view-refresh-symbolic", label: "Reload Hyprland",
        onClicked: () => execAsync(["hyprctl", "reload"]).catch(console.error) }))
    footer.append(ActionChip({ icon: "media-playlist-repeat-symbolic", label: "Restart Waybar",
        onClicked: () => execAsync(["bash", `${HOME}/.config/scripts/waybar/waybar.sh`]).catch(console.error) }))
    footer.append(ActionChip({ icon: "software-update-available-symbolic", label: "Update System",
        onClicked: () => terminalExec(`${HOME}/.config/scripts/settings/update.sh`) }))
    footer.append(ActionChip({ icon: "utilities-terminal-symbolic", label: "Advanced (TUI)",
        onClicked: () => terminalExec(`${HOME}/.config/scripts/settings/settings.sh`) }))

    const content = new Gtk.Box({
        orientation: Gtk.Orientation.VERTICAL, hexpand: true, vexpand: true,
        cssClasses: ["content-area"],
    })
    content.append(scroll)
    content.append(footer)

    const layout = new Gtk.Box({ orientation: Gtk.Orientation.HORIZONTAL, cssClasses: ["panel-layout"] })
    layout.append(sidebar)
    layout.append(content)

    const keyController = new Gtk.EventControllerKey()

    return (
        <window
            name="settings-panel"
            namespace="settings-panel"
            application={app}
            cssClasses={["settings-window"]}
            anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.BOTTOM | Astal.WindowAnchor.LEFT | Astal.WindowAnchor.RIGHT}
            exclusivity={Astal.Exclusivity.NORMAL}
            layer={Astal.Layer.OVERLAY}
            keymode={Astal.Keymode.EXCLUSIVE}
            visible
            $={(self: Astal.Window) => {
                keyController.connect("key-pressed", (_c, keyval: number) => {
                    if (keyval === Gdk.KEY_Escape) {
                        if (query) { query = ""; searchWidget.set_text(""); render() }
                        else self.visible = false
                    }
                    return false
                })
                self.add_controller(keyController)
                // Freshness: rebuild everything each time the panel is shown
                self.connect("notify::visible", () => {
                    if (self.visible) { rebuildSidebar(); render() }
                })
                rebuildSidebar()
                render()
            }}
        >
            <box cssClasses={["panel-backdrop"]} halign={Gtk.Align.CENTER} valign={Gtk.Align.CENTER}>
                <box cssClasses={["panel-container"]} widthRequest={880} heightRequest={640}>
                    {layout}
                </box>
            </box>
        </window>
    )
}
```

- [ ] **Step 4: Slim `ags/app.ts`**

```typescript
import app from "ags/gtk4/app"
import SettingsPanel from "./widget/SettingsPanel"
import { buildCss } from "./style"

app.start({
    instanceName: "settings-panel",
    css: buildCss(),
    main() {
        SettingsPanel()
        const win = app.get_window("settings-panel")
        if (win) win.visible = false
    },
})
```

- [ ] **Step 5: Temporary categories barrel** — until Task 4, create `ags/widget/categories/index.ts` exporting `CATEGORIES: CategoryDef[]` that wraps ONLY the existing Appearance sliders through the new factories (proves the pipeline end-to-end):

```typescript
import { CategoryDef } from "../../lib/registry"
import { kwSlider, kwToggle } from "../components/rows"

export const CATEGORIES: CategoryDef[] = [{
    id: "appearance", label: "Appearance", group: "Look & Feel",
    icon: "preferences-desktop-display-symbolic",
    description: "Borders, blur, gaps and opacity",
    rows: () => [
        kwToggle({ id: "appearance.blur", title: "Blur", icon: "weather-fog-symbolic",
            description: "Frosted-glass effect behind windows", keyword: "decoration:blur:enabled" }),
        kwSlider({ id: "appearance.rounding", title: "Corner Rounding", icon: "object-select-symbolic",
            description: "Window corner radius in pixels", keyword: "decoration:rounding",
            min: 0, max: 30, step: 1 }),
    ],
}]
```

- [ ] **Step 6: Bundle + relaunch + functional check.** Bundle → `0`. Relaunch, Super+I: grouped sidebar (one group), search finds "blur", toggling Blur writes `decoration:blur:enabled` into `hypr/config/overrides.conf` (check `cat`), reset row restores.

- [ ] **Step 7: Commit**

```bash
cd ~/.config && git add ags && git commit -m "feat(panel): new shell — grouped sidebar, search, footer chips, rebuild-on-show"
```

---

### Task 4: Migrate all categories to the new IA

**Goal:** All nine categories per spec IA table, data-driven; old category files deleted.

**Files:**
- Rewrite `ags/widget/categories/index.ts` (full barrel), create `Appearance.tsx`, `Animations.tsx`, `Windows.tsx`, `Input.tsx`, `Notifications.tsx`, `Power.tsx`, `DefaultApps.tsx` (Monitors/Startup in Task 5 — barrel imports them; create stub exports here)
- Delete: `Toggles.tsx`, `Misc.tsx`, `Layout.tsx`, `Apps.tsx`, `AnimationSettings.tsx`, `components/Toggle.tsx`, `components/Slider.tsx`, `components/Dropdown.tsx`

**Acceptance Criteria:**
- [ ] Every setting from the spec IA table present with icon + description (pseudotile/logo/splash dropped per spec)
- [ ] All Hyprland rows persist via overrides.conf; fonts run `scripts/fonts/apply-font.sh`; cursor theme writes option + `hypr/config/cursortheme.conf` + gsettings + keyword
- [ ] swaync/hypridle rows keep file persistence; swaync rows reset to `SWAYNC_DEFAULTS`
- [ ] Old files deleted; bundle passes

**Verify:** bundle → 0; relaunch; every category renders; spot-check one row per category round-trips its backing store (overrides.conf / config.json / hypridle.conf / options file).

**Steps:**

- [ ] **Step 1: `Appearance.tsx`** (pattern for all category files — a single `CategoryDef` export):

```tsx
import { CategoryDef } from "../../lib/registry"
import { kwToggle, kwSlider, optionEntry, customRow } from "../components/rows"
import { SliderControl } from "../components/controls"
import { getOptionInt } from "../../lib/hyprctl"
import { setPersistent, resetSetting, hasOverride } from "../../lib/persist"
import { writeOption, readOption } from "../../lib/options"
import GLib from "gi://GLib"
import Gio from "gi://Gio"
import { execAsync } from "ags/process"

function applyFonts() {
    execAsync(["bash", GLib.get_home_dir() + "/.config/scripts/fonts/apply-font.sh"]).catch(console.error)
}

function applyCursorTheme(theme: string) {
    setPersistent("cursor:theme", theme)
    writeOption("cursortheme", theme)
    try {
        Gio.File.new_for_path(GLib.get_home_dir() + "/.config/hypr/config/cursortheme.conf")
            .replace_contents(new TextEncoder().encode(`$cursortheme = ${theme}\n`),
                null, false, Gio.FileCreateFlags.NONE, null)
    } catch (e) { console.error(e) }
    execAsync(["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", theme]).catch(console.error)
}

const Appearance: CategoryDef = {
    id: "appearance", label: "Appearance", group: "Look & Feel",
    icon: "preferences-desktop-display-symbolic",
    description: "Borders, blur, gaps, opacity, fonts and cursor",
    rows: () => [
        kwToggle({ id: "appearance.blur", title: "Blur", icon: "weather-fog-symbolic",
            description: "Frosted-glass effect behind windows", keyword: "decoration:blur:enabled" }),
        kwSlider({ id: "appearance.blur-size", title: "Blur Size", icon: "zoom-fit-best-symbolic",
            description: "Blur kernel radius", keyword: "decoration:blur:size", min: 1, max: 20, step: 1 }),
        kwSlider({ id: "appearance.blur-passes", title: "Blur Passes", icon: "view-continuous-symbolic",
            description: "More passes, smoother and costlier blur", keyword: "decoration:blur:passes", min: 1, max: 6, step: 1 }),
        kwToggle({ id: "appearance.shadows", title: "Shadows", icon: "weather-clear-night-symbolic",
            description: "Drop shadow under windows", keyword: "decoration:shadow:enabled" }),
        kwSlider({ id: "appearance.rounding", title: "Corner Rounding", icon: "object-select-symbolic",
            description: "Window corner radius in pixels", keyword: "decoration:rounding", min: 0, max: 30, step: 1 }),
        kwSlider({ id: "appearance.border", title: "Border Width", icon: "view-frame-symbolic",
            description: "Window border thickness", keyword: "general:border_size", min: 0, max: 5, step: 1 }),
        kwSlider({ id: "appearance.gaps-in", title: "Gaps Inner", icon: "view-grid-symbolic",
            description: "Space between tiled windows", keyword: "general:gaps_in", min: 0, max: 20, step: 1 }),
        kwSlider({ id: "appearance.gaps-out", title: "Gaps Outer", icon: "view-fullscreen-symbolic",
            description: "Space between windows and screen edge", keyword: "general:gaps_out", min: 0, max: 30, step: 1 }),
        kwSlider({ id: "appearance.opacity-active", title: "Active Opacity", icon: "view-reveal-symbolic",
            description: "Opacity of the focused window", keyword: "decoration:active_opacity",
            min: 0.1, max: 1.0, step: 0.05, float: true }),
        kwSlider({ id: "appearance.opacity-inactive", title: "Inactive Opacity", icon: "view-conceal-symbolic",
            description: "Opacity of unfocused windows", keyword: "decoration:inactive_opacity",
            min: 0.1, max: 1.0, step: 0.05, float: true }),
        optionEntry({ id: "appearance.font", title: "Main Font", icon: "font-x-generic-symbolic",
            description: "Applied to rofi, waybar, terminals via apply-font.sh", option: "font",
            keywords: ["typeface"], onCommit: applyFonts }),
        optionEntry({ id: "appearance.font-gtk", title: "GTK Font", icon: "font-x-generic-symbolic",
            description: "Font for GTK applications", option: "font-gtk", onCommit: applyFonts }),
        optionEntry({ id: "appearance.cursor-theme", title: "Cursor Theme", icon: "input-mouse-symbolic",
            description: "Cursor theme name (takes full effect after restart)", option: "cursortheme",
            onCommit: applyCursorTheme }),
        customRow({ id: "appearance.cursor-size", title: "Cursor Size", icon: "input-mouse-symbolic",
            description: "Pointer size in pixels",
            control: () => SliderControl({ value: getOptionInt("cursor:size") || 24,
                min: 16, max: 48, step: 2, onChanged: v => setPersistent("cursor:size", Math.round(v)) }),
            onReset: () => resetSetting("cursor:size"),
            resetVisible: () => hasOverride("cursor:size") }),
    ],
}
export default Appearance
```

- [ ] **Step 2: `Animations.tsx`**

```tsx
import { CategoryDef } from "../../lib/registry"
import { kwToggle, customRow } from "../components/rows"
import { SliderControl } from "../components/controls"
import { setAnimationPersistent, hasAnimationOverride, resetAnimation } from "../../lib/persist"
import GLib from "gi://GLib"

function getAnim(name: string): { enabled: boolean; speed: number; bezier: string; style: string } {
    try {
        const [ok, stdout] = GLib.spawn_command_line_sync("hyprctl animations -j")
        if (ok && stdout) {
            const anims = JSON.parse(new TextDecoder().decode(stdout))
            // hyprctl animations -j returns [animations[], beziers[]]
            const list = Array.isArray(anims[0]) ? anims[0] : anims
            for (const a of list) if (a.name === name)
                return { enabled: !!a.enabled, speed: a.speed || 5, bezier: a.bezier || "default", style: a.style || "" }
        }
    } catch (e) { console.error(e) }
    return { enabled: true, speed: 5, bezier: "default", style: "" }
}

function setSpeed(name: string, speed: number) {
    const a = getAnim(name)
    const base = `${name},${a.enabled ? 1 : 0},${Math.round(speed)},${a.bezier}`
    setAnimationPersistent(name, a.style ? `${base},${a.style}` : base)
}

const ANIMS: { label: string; name: string; desc: string }[] = [
    { label: "Windows", name: "windows", desc: "Open/close scale animation" },
    { label: "Windows In", name: "windowsIn", desc: "Window opening" },
    { label: "Windows Out", name: "windowsOut", desc: "Window closing" },
    { label: "Windows Move", name: "windowsMove", desc: "Drag and tile movement" },
    { label: "Fade", name: "fade", desc: "Opacity transitions" },
    { label: "Workspaces", name: "workspaces", desc: "Workspace switch slide" },
    { label: "Border", name: "border", desc: "Border color transitions" },
]

const Animations: CategoryDef = {
    id: "animations", label: "Animations", group: "Look & Feel",
    icon: "starred-symbolic",
    description: "Master switch and per-animation speeds",
    rows: () => [
        kwToggle({ id: "anim.master", title: "Animations", icon: "starred-symbolic",
            description: "Master switch for all animations", keyword: "animations:enabled" }),
        ...ANIMS.map(a => customRow({
            id: `anim.${a.name}`, title: a.label, icon: "media-playback-start-symbolic",
            description: a.desc,
            control: () => SliderControl({ value: getAnim(a.name).speed, min: 1, max: 10, step: 1,
                onChanged: v => setSpeed(a.name, v) }),
            onReset: () => resetAnimation(a.name),
            resetVisible: () => hasAnimationOverride(a.name),
        })),
    ],
}
export default Animations
```

- [ ] **Step 3: `Windows.tsx`**

```tsx
import { CategoryDef } from "../../lib/registry"
import { kwToggle, kwDropdown } from "../components/rows"

const Windows: CategoryDef = {
    id: "windows", label: "Windows", group: "Behavior",
    icon: "view-grid-symbolic",
    description: "Tiling layout and window behavior",
    rows: () => [
        kwDropdown({ id: "win.layout", title: "Layout Mode", icon: "view-grid-symbolic",
            description: "Dwindle splits like a binary tree; master keeps one main window",
            keyword: "general:layout",
            items: [{ label: "Dwindle", value: "dwindle" }, { label: "Master", value: "master" }] }),
        kwToggle({ id: "win.preserve-split", title: "Preserve Split", icon: "object-flip-horizontal-symbolic",
            description: "Keep split direction when windows close", keyword: "dwindle:preserve_split" }),
        kwToggle({ id: "win.smart-split", title: "Smart Split", icon: "object-rotate-right-symbolic",
            description: "Split direction follows cursor position", keyword: "dwindle:smart_split" }),
        kwToggle({ id: "win.tearing", title: "Allow Tearing", icon: "video-display-symbolic",
            description: "Reduces latency in games; may cause glitches", keyword: "general:allow_tearing" }),
        kwToggle({ id: "win.resize-border", title: "Resize on Border", icon: "view-restore-symbolic",
            description: "Drag window edges to resize", keyword: "general:resize_on_border" }),
        kwToggle({ id: "win.xwayland", title: "XWayland", icon: "application-x-executable-symbolic",
            description: "Support for X11-only applications", keyword: "xwayland:enabled" }),
    ],
}
export default Windows
```

- [ ] **Step 4: `Input.tsx`**

```tsx
import { CategoryDef } from "../../lib/registry"
import { kwToggle, kwSlider, kwDropdown } from "../components/rows"

const Input: CategoryDef = {
    id: "input", label: "Input", group: "Behavior",
    icon: "input-mouse-symbolic",
    description: "Mouse, keyboard and touchpad",
    rows: () => [
        kwSlider({ id: "input.sensitivity", title: "Mouse Sensitivity", icon: "input-mouse-symbolic",
            description: "-1 slow … +1 fast (libinput accel)", keyword: "input:sensitivity",
            min: -1.0, max: 1.0, step: 0.1, float: true }),
        kwDropdown({ id: "input.follow-mouse", title: "Focus Follows Mouse", icon: "focus-windows-symbolic",
            description: "How window focus follows the pointer", keyword: "input:follow_mouse",
            items: [
                { label: "Disabled", value: "0" }, { label: "Full", value: "1" },
                { label: "Loose", value: "2" }, { label: "Detached", value: "3" },
            ] }),
        kwToggle({ id: "input.numlock", title: "Numlock by Default", icon: "input-keyboard-symbolic",
            description: "Enable numlock at startup", keyword: "input:numlock_by_default" }),
        kwToggle({ id: "input.natural-scroll", title: "Natural Scroll (Touchpad)", icon: "touchpad-symbolic",
            description: "Content follows finger direction", keyword: "input:touchpad:natural_scroll" }),
        kwSlider({ id: "input.scroll-factor", title: "Touchpad Scroll Factor", icon: "touchpad-symbolic",
            description: "Scroll speed multiplier", keyword: "input:touchpad:scroll_factor",
            min: 0.1, max: 2.0, step: 0.1, float: true }),
    ],
}
export default Input
```

- [ ] **Step 5: `Notifications.tsx`** (swaync-backed with defaults reset):

```tsx
import { CategoryDef } from "../../lib/registry"
import { customRow } from "../components/rows"
import { SliderControl, DropdownControl } from "../components/controls"
import { readConfig, updateAndReload, SWAYNC_DEFAULTS } from "../../lib/swaync"

function snSlider(id: string, title: string, icon: string, desc: string, key: string,
    min: number, max: number, step: number) {
    return customRow({
        id, title, icon, description: desc,
        control: () => SliderControl({
            value: Number(readConfig()[key] ?? SWAYNC_DEFAULTS[key]),
            min, max, step, onChanged: v => updateAndReload(key, Math.round(v)),
        }),
        onReset: () => updateAndReload(key, SWAYNC_DEFAULTS[key]),
        resetVisible: () => readConfig()[key] !== undefined
            && readConfig()[key] !== SWAYNC_DEFAULTS[key],
    })
}

const Notifications: CategoryDef = {
    id: "notifications", label: "Notifications", group: "Behavior",
    icon: "preferences-system-notifications-symbolic",
    description: "SwayNC toasts and control center",
    rows: () => [
        customRow({ id: "notif.pos-x", title: "Position X", icon: "object-flip-horizontal-symbolic",
            description: "Horizontal screen edge for toasts",
            control: () => DropdownControl({
                items: [{ label: "Left", value: "left" }, { label: "Center", value: "center" }, { label: "Right", value: "right" }],
                active: String(readConfig()["positionX"] ?? SWAYNC_DEFAULTS["positionX"]),
                onChanged: v => updateAndReload("positionX", v),
            }) }),
        customRow({ id: "notif.pos-y", title: "Position Y", icon: "object-flip-vertical-symbolic",
            description: "Vertical screen edge for toasts",
            control: () => DropdownControl({
                items: [{ label: "Top", value: "top" }, { label: "Bottom", value: "bottom" }],
                active: String(readConfig()["positionY"] ?? SWAYNC_DEFAULTS["positionY"]),
                onChanged: v => updateAndReload("positionY", v),
            }) }),
        snSlider("notif.timeout", "Default Timeout", "alarm-symbolic",
            "Seconds a toast stays on screen", "timeout", 1, 15, 1),
        snSlider("notif.timeout-low", "Low Priority Timeout", "alarm-symbolic",
            "Seconds for low-priority toasts", "timeout-low", 1, 10, 1),
        snSlider("notif.width", "Notification Width", "object-flip-horizontal-symbolic",
            "Toast width in pixels", "notification-window-width", 200, 600, 10),
        snSlider("notif.cc-width", "Control Center Width", "sidebar-show-symbolic",
            "Sidebar width in pixels", "control-center-width", 200, 600, 10),
        snSlider("notif.transition", "Transition Time", "media-playback-start-symbolic",
            "Animation duration in ms", "transition-time", 0, 500, 25),
    ],
}
export default Notifications
```

- [ ] **Step 6: `Power.tsx`** (hypridle + DPMS; VRR moved to Monitors):

```tsx
import { CategoryDef } from "../../lib/registry"
import { kwToggle, customRow } from "../components/rows"
import { SliderControl } from "../components/controls"
import { readTimeouts, writeTimeouts } from "../../lib/hypridle"

const fmtMin = (v: number) => {
    const m = Math.floor(v / 60), s = Math.round(v % 60)
    return s ? `${m}m${s}s` : `${m}m`
}

const Power: CategoryDef = {
    id: "power", label: "Power", group: "Hardware",
    icon: "battery-symbolic",
    description: "Idle timeouts and display power",
    rows: () => [
        customRow({ id: "power.lock", title: "Lock Timeout", icon: "system-lock-screen-symbolic",
            description: "Idle time before hyprlock engages",
            control: () => SliderControl({ value: readTimeouts().lock, min: 60, max: 1800, step: 30,
                format: fmtMin, onChanged: v => writeTimeouts({ ...readTimeouts(), lock: Math.round(v) }) }),
            onReset: () => writeTimeouts({ ...readTimeouts(), lock: 180 }),
            resetVisible: () => readTimeouts().lock !== 180 }),
        customRow({ id: "power.dpms", title: "Screen Off Timeout", icon: "video-display-symbolic",
            description: "Idle time before displays power down",
            control: () => SliderControl({ value: readTimeouts().dpms, min: 120, max: 3600, step: 60,
                format: fmtMin, onChanged: v => writeTimeouts({ ...readTimeouts(), dpms: Math.round(v) }) }),
            onReset: () => writeTimeouts({ ...readTimeouts(), dpms: 600 }),
            resetVisible: () => readTimeouts().dpms !== 600 }),
        kwToggle({ id: "power.dpms-key", title: "Wake on Key Press", icon: "input-keyboard-symbolic",
            description: "Screens power on when a key is pressed", keyword: "misc:key_press_enables_dpms" }),
        kwToggle({ id: "power.dpms-mouse", title: "Wake on Mouse Move", icon: "input-mouse-symbolic",
            description: "Screens power on when the mouse moves", keyword: "misc:mouse_move_enables_dpms" }),
    ],
}
export default Power
```

- [ ] **Step 7: `DefaultApps.tsx`**

```tsx
import { CategoryDef } from "../../lib/registry"
import { optionEntry, customRow } from "../components/rows"
import { DropdownControl } from "../components/controls"
import { readOption, writeOption } from "../../lib/options"

const DefaultApps: CategoryDef = {
    id: "apps", label: "Default Apps", group: "System",
    icon: "system-run-symbolic",
    description: "Applications used by keybinds and scripts",
    rows: () => [
        optionEntry({ id: "apps.browser", title: "Browser", icon: "web-browser-symbolic",
            description: "Launched with Super+B", option: "browser", placeholder: "firefox" }),
        optionEntry({ id: "apps.terminal", title: "Terminal", icon: "utilities-terminal-symbolic",
            description: "Launched with Super+Return", option: "terminal", placeholder: "ghostty" }),
        optionEntry({ id: "apps.editor", title: "TUI Editor", icon: "accessories-text-editor-symbolic",
            description: "Used by Super+N and the TUI settings", option: "editor", placeholder: "nvim" }),
        optionEntry({ id: "apps.mediaplayer", title: "Media Player", icon: "multimedia-player-symbolic",
            description: "playerctl identifier for waybar media controls", option: "mediaplayer",
            placeholder: "spotify" }),
        optionEntry({ id: "apps.mediaicon", title: "Media Icon", icon: "emblem-music-symbolic",
            description: "Nerd Font icon shown in waybar for the player", option: "mediaicon", placeholder: "" }),
        customRow({ id: "apps.launcher", title: "Launcher Style", icon: "view-app-grid-symbolic",
            description: "Rofi layout used by Super+Space",
            control: () => DropdownControl({
                items: [{ label: "Vertical", value: "vertical" }, { label: "Horizontal", value: "horizontal" }],
                active: readOption("launchertype") || "vertical",
                onChanged: v => writeOption("launchertype", v),
            }) }),
    ],
}
export default DefaultApps
```

- [ ] **Step 8: Barrel `ags/widget/categories/index.ts`** (Monitors/Startup stubs until Task 5):

```typescript
import { CategoryDef } from "../../lib/registry"
import Appearance from "./Appearance"
import Animations from "./Animations"
import Windows from "./Windows"
import Input from "./Input"
import Notifications from "./Notifications"
import Monitors from "./Monitors"     // Task 5
import Power from "./Power"
import Startup from "./Startup"       // Task 5
import DefaultApps from "./DefaultApps"

export const CATEGORIES: CategoryDef[] = [
    Appearance, Animations,               // Look & Feel
    Windows, Input, Notifications,        // Behavior
    Monitors, Power,                      // Hardware
    Startup, DefaultApps,                 // System
]
```

For this task create minimal `Monitors.tsx`/`Startup.tsx` stubs (`rows: () => []` with correct id/label/group/icon/description) so the barrel compiles; Task 5 fills them.

- [ ] **Step 9: Delete superseded files**

```bash
cd ~/.config && git rm ags/widget/categories/{Toggles,Misc,Layout,Apps,AnimationSettings}.tsx \
  ags/widget/components/{Toggle,Slider,Dropdown}.tsx
```

- [ ] **Step 10: Bundle, relaunch, verify per **Verify** above, commit**

```bash
cd ~/.config && git add ags && git commit -m "feat(panel): migrate all categories to data-driven IA"
```

---

### Task 5: Monitors and Startup categories

**Goal:** The two new categories, filling the stubs.

**Files:**
- Rewrite: `ags/widget/categories/Monitors.tsx`, `ags/widget/categories/Startup.tsx`

**Acceptance Criteria:**
- [ ] Monitors: card per monitor (name, model, res@hz, scale, position), MAIN badge / "Set as main" button, VRR dropdown, "Advanced setup" chip → TUI wizard in terminal
- [ ] Set-as-main writes `options/mainmonitor` + `hypr/config/hardware/primary.conf` and refreshes
- [ ] Startup: lock-on-autologin, desktop clock (starts/stops eww), random wallpaper toggles round-trip their options files

**Verify:**
```bash
cat ~/.config/options/mainmonitor ~/.config/hypr/config/hardware/primary.conf   # after clicking Set as main
cat ~/.config/options/{autologin,clock,randomwallpaper}                          # after flipping toggles
```

**Steps:**

- [ ] **Step 1: `Monitors.tsx`**

```tsx
import { CategoryDef, requestRefresh } from "../../lib/registry"
import { kwDropdown, customRow } from "../components/rows"
import MonitorCard from "../components/MonitorCard"
import ActionChip from "../components/ActionChip"
import { listMonitors, getMainMonitor, setMainMonitor } from "../../lib/monitors"
import { readOption } from "../../lib/options"
import { execAsync } from "ags/process"
import GLib from "gi://GLib"

const HOME = GLib.get_home_dir()

const Monitors: CategoryDef = {
    id: "monitors", label: "Monitors", group: "Hardware",
    icon: "video-display-symbolic",
    description: "Connected displays and adaptive sync",
    extra: () => {
        const main = getMainMonitor()
        const cards = listMonitors().map(m => MonitorCard({
            monitor: m, isMain: m.name === main,
            onSetMain: () => { setMainMonitor(m.name); requestRefresh() },
        }))
        const term = readOption("terminal") || "ghostty"
        cards.push(ActionChip({
            icon: "utilities-terminal-symbolic", label: "Advanced setup (resolution, position, rotation)",
            onClicked: () => execAsync(["hyprctl", "dispatch", "exec",
                `${term} -e ${HOME}/.config/scripts/settings/advanced/monitor.sh`]).catch(console.error),
        }))
        return cards
    },
    rows: () => [
        kwDropdown({ id: "monitors.vrr", title: "VRR (Adaptive Sync)", icon: "video-display-symbolic",
            description: "Variable refresh rate", keyword: "misc:vrr",
            items: [
                { label: "Off", value: "0" }, { label: "On", value: "1" },
                { label: "Fullscreen only", value: "2" },
            ] }),
    ],
}
export default Monitors
```

- [ ] **Step 2: `Startup.tsx`**

```tsx
import { CategoryDef } from "../../lib/registry"
import { optionToggle } from "../components/rows"
import { execAsync } from "ags/process"

const Startup: CategoryDef = {
    id: "startup", label: "Startup", group: "System",
    icon: "system-restart-symbolic",
    description: "What happens when Hyprland starts",
    rows: () => [
        optionToggle({ id: "startup.autologin", title: "Lock on Autologin", icon: "system-lock-screen-symbolic",
            description: "Run hyprlock at startup when logged in automatically", option: "autologin" }),
        optionToggle({ id: "startup.clock", title: "Desktop Clock", icon: "preferences-system-time-symbolic",
            description: "eww clock widget on the desktop", option: "clock",
            onChange: v => {
                if (v) execAsync(["bash", "-c", "command -v eww >/dev/null && eww open clock"]).catch(console.error)
                else execAsync(["bash", "-c", "pkill eww"]).catch(console.error)
            } }),
        optionToggle({ id: "startup.randomwallpaper", title: "Random Wallpaper", icon: "preferences-desktop-wallpaper-symbolic",
            description: "Pick a random wallpaper (and palette) on each login", option: "randomwallpaper",
            keywords: ["waypaper", "pywal"] }),
    ],
}
export default Startup
```

- [ ] **Step 3: Bundle, relaunch, run **Verify**, commit**

```bash
cd ~/.config && git add ags/widget/categories && git commit -m "feat(panel): Monitors and Startup categories"
```

---

### Task 6: Final verification pass

**Goal:** All six spec verification items pass with captured evidence.

**Files:** none (fixes only if checks fail)

**Acceptance Criteria:** spec §Verification items 1-6, adapted: build gate = `ags bundle` (no tsc here).

**Verify (run all, capture output):**

- [ ] **Step 1: Build** — `cd ~/.config/ags && ags bundle app.ts /tmp/claude-panel-build.js; echo $?` → `0`
- [ ] **Step 2: Relaunch + render** — relaunch command; open each of the 9 categories via Super+I; no errors in `ags` output.
- [ ] **Step 3: Persistence round-trip** — set Gaps Inner to 13 in the panel, then:
```bash
grep "general:gaps_in = 13" ~/.config/hypr/config/overrides.conf && hyprctl reload && sleep 1 && hyprctl getoption general:gaps_in -j | grep '"int": 13' && echo PERSIST-OK
```
Then click the row's reset: line disappears, `getoption` returns 4.
- [ ] **Step 4: Freshness** — `hyprctl keyword general:border_size 3` externally, close+reopen panel → Border Width shows 3. Reset it: `hyprctl keyword general:border_size 1`.
- [ ] **Step 5: Search** — query "blur" → 3 Appearance rows; "timeout" → Power + Notifications rows; toggling a result row works.
- [ ] **Step 6: Startup round-trip** — flip all three Startup toggles on and off; `cat ~/.config/options/{autologin,clock,randomwallpaper}` tracks each flip.
- [ ] **Step 7: Commit any fixes; final commit**

```bash
cd ~/.config && git add -A ags && git commit -m "fix(panel): final verification pass" || echo "nothing to fix"
```

---

## Self-review notes

- Spec coverage: IA table → Tasks 4-5 (all rows present; pseudotile/logo/splash dropped per amended spec); persistence → Task 1; freshness/search/footer → Task 3; components → Task 2; verification → Task 6. Spec's `TextEntry.tsx`/separate control files consolidated into `controls.tsx` (fewer, focused files — same interfaces).
- Type consistency: `RowSpec.build(): Gtk.Widget`; factories in rows.tsx return `RowSpec`; `CategoryDef.rows: () => RowSpec[]`; `SWAYNC_DEFAULTS` typing matches usage; `setAnimationPersistent(name, line)` signature consistent between Task 1 and Task 4.
- No placeholder patterns remain.
