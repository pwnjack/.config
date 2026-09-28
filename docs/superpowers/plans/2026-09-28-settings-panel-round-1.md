# Settings Panel Round 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fill the Super+I settings panel's quick-win gaps (keyboard, pointer, window, accessibility, GTK/Qt appearance, default apps, file types, power) and fix the wrong values it shows today, without duplicating anything another surface already owns.

**Architecture:** Every setting is a row in `quickshell/settings-panel/catalog.json`, read and written by the GJS helper `backend.js` (run per request through `scripts/settings/panel-request.sh`). New rows reuse the existing `keyword` source (Hyprland options persisted to `hypr/config/overrides.lua` by `persist.js`) wherever possible. Four small sources are new: `gtk` (gsettings plus both tracked `settings.ini` files), `kvantum`, `mime` (`xdg-mime` against the tracked `mimeapps.list`) and `powerprofile`. One generic mechanism is new too: rows can declare `choices`, so the backend sends a list of valid values with each read and validates writes against it.

**Tech Stack:** GJS (`gi://Gio`, `gi://GLib`), Quickshell/QML (Qt 6), bash, Node for the backend unit tests (`node:assert`), `qmltestrunner` for UI tests.

---

## Context the engineer needs

- **Run all tests:** `./test.sh` from `~/.config`. The panel suite is `quickshell/settings-panel/test/run-tests.sh`: the QML tests (`tst_Settings.qml`), then `persist.mjs`, then `backend.mjs`. `backend.mjs` runs the real `backend.js` against in-memory mocks of Gio/GLib/`execAsync`. **Every backend change gets a case in `backend.mjs`.**
- **Talk to the real backend without the UI:** `bash scripts/settings/panel-request.sh '<json>'`. Reads are side-effect free: `{"op":"read","ids":["input.kb-layout"]}`.
- **The pre-commit hook** runs shellcheck plus the suites that own the staged paths. Never bypass it.
- **Nothing in the repo may be a second source of truth** (see `CLAUDE.md` → Conventions). The catalog is the single list of settings. Do not add parallel lists of keys in JS or bash.
- **Hyprland 0.56 Lua gotcha (verified):** the legacy name `input:touchpad:tap-to-click` is **rejected** by `hyprctl eval` ("unknown config key"). Use `input:touchpad:tap_to_click`, which both `getoption` and `eval` accept. All other keys in this plan were verified with `hyprctl eval`.
- **`hyprctl getoption -j` names the value field after its type**: `bool`, `int`, `float`, `str`, `css`, `custom`. `set` only says whether the config assigns the option. It is never the value. An empty string is reported as `"[[EMPTY]]"`.
- **Glyphs in shell scripts** must be written as `$'\uXXXX'` escapes, never pasted (see `rofi/powermenu.sh:10`).
- **Measured on this machine:** a full panel read takes 0.07 s; `fc-list : family` 0.03 s; `localectl list-x11-keymap-*` <0.01 s.

## What is deliberately NOT in this plan (already owned elsewhere)

Shortcuts list (Super+H), Do Not Disturb and per-app volume (SwayNC sidebar), updates (Waybar module and the existing panel button), night light (complete), wallpaper (carousel/random), screenshot freeze and delay (Rofi screenshot menu), Bluetooth (no adapter). The Browser row stays "what Super+B launches"; the new **File Types → Web Links** row is what other apps open links with. Both descriptions say so.

## File map

| File | Responsibility | Tasks |
|---|---|---|
| `quickshell/settings-panel/backend.js` | Read/validate/apply every source | 1–8 |
| `quickshell/settings-panel/catalog.json` | The rows | 2–8 |
| `quickshell/settings-panel/hyprctl.js` | Delete dead `getOption*` helpers (same bug, zero callers) | 1 |
| `quickshell/settings-panel/SettingControl.qml` | Dynamic choices, capped popup, `zeroLabel`/`seconds` formats | 2, 3 |
| `quickshell/settings-panel/test/backend.mjs` | Backend cases and mocks | 1–8 |
| `quickshell/settings-panel/test/tst_Settings.qml` | UI cases | 2, 3 |
| `quickshell/settings-panel/test/live-smoke.sh` | Derive the appearance row count | 10 |
| `scripts/fonts/apply-font.sh` + new `scripts/fonts/test-apply-font.sh` | GTK font also reaches gsettings | 4 |
| `hypr/config/apptype.lua`, `hypr/config/software/keybinds.lua`, `scripts/lib/hypr-vars.sh`, `test/test-docs.sh`, new `options/filemanager` | File manager preference | 6 |
| new `rofi/clipboard.sh` + `rofi/test-clipboard.sh` | Clear clipboard history from Super+C | 9 |
| `docs/settings-panel.md`, `CLAUDE.md`, `docs/keybindings.md` (generated) | Docs | 6, 10 |

`persist.js` needs no changes.

---

### Task 1: Read Hyprland option values correctly

**Goal:** Toggles and gap sliders show the real Hyprland value instead of whether the option is set.

**Background (verified live 2026-09-28):** `panel-request.sh` reports Shadows, Smart Split, Allow Tearing and Natural Scroll as **on** while all four are off, and both gap sliders as `null`. Cause: `backend.js:99` reads `data.int ?? data.float ?? data.str ?? data.custom ?? data.set`, which lacks `bool` and `css` and falls back to `set`. The mock in `backend.mjs` always answers `{int:1}`, so no test could see it.

**Files:**
- Modify: `quickshell/settings-panel/backend.js:97-106`
- Modify: `quickshell/settings-panel/hyprctl.js` (delete `execSync`, `getOption`, `getOptionBool`, `getOptionInt`, `getOptionFloat`)
- Test: `quickshell/settings-panel/test/backend.mjs`

**Acceptance Criteria:**
- [ ] `backend.mjs` mocks `getoption` per key with the real field shapes (`bool`, `css`, `str: "[[EMPTY]]"`)
- [ ] A read of `appearance.shadows` with `{bool:false,set:true}` returns `false`; `appearance.gaps-in` with `{css:"4 4 4 4"}` returns `4`
- [ ] Live: `panel-request.sh` returns `false` for `appearance.shadows`, `win.smart-split`, `win.tearing`, `input.natural-scroll` and a number for both gaps rows
- [ ] `rg -n "getOption" quickshell/` returns nothing

**Verify:** `bash quickshell/settings-panel/test/run-tests.sh` → all pass; then `bash scripts/settings/panel-request.sh '{"op":"read","ids":["appearance.shadows","win.smart-split","win.tearing","input.natural-scroll","appearance.gaps-in","appearance.gaps-out"]}'` → `false,false,false,false,4,10`

**Steps:**

- [ ] **Step 1: Make the mock realistic and write the failing test.** In `backend.mjs`, replace the line `if (args[1] === 'getoption') return JSON.stringify({int:1})` with:

```js
        if (args[1] === 'getoption') return JSON.stringify(hyprOptions[args[2]] ?? {int:1,set:true})
```

and declare, next to `let events = []`:

```js
// Shapes copied from `hyprctl getoption -j` on Hyprland 0.56: the value field
// is named after its type, and `set` is only whether the config assigns it.
const hyprOptions = {
    'decoration:blur:enabled': {bool:true,set:true},
    'decoration:shadow:enabled': {bool:false,set:true},
    'general:gaps_in': {css:'4 4 4 4',set:true},
    'input:accel_profile': {str:'[[EMPTY]]',set:false},
}
```

Append after the first read test:

```js
result = await dispatch({op:'read',ids:['appearance.shadows','appearance.gaps-in']})
assert.equal(result.values['appearance.shadows'].value,false)
assert.equal(result.values['appearance.gaps-in'].value,4)
console.log('ok: keyword reads use the typed value field, never `set`')
```

- [ ] **Step 2: Run it and watch it fail.** `node quickshell/settings-panel/test/backend.mjs` → `AssertionError` on `appearance.shadows` (actual `true`).

- [ ] **Step 3: Fix the read.** In `backend.js`, add above `snapshot`:

```js
// hyprctl getoption names the value field after the option's type. `set` only
// says whether the config assigns the option, so it is never a value.
function keywordValue(data) {
    for (const field of ["bool", "int", "float", "str", "css", "custom"]) {
        if (data[field] === undefined) continue
        return field === "str" && data[field] === "[[EMPTY]]" ? "" : data[field]
    }
    throw new Error("Hyprland did not return a value")
}
```

and replace the two lines

```js
                value = data.int ?? data.float ?? data.str ?? data.custom ?? data.set
                if (value === undefined) throw new Error("Hyprland did not return a value")
```

with

```js
                value = keywordValue(data)
```

- [ ] **Step 4: Delete the dead helpers.** In `hyprctl.js` delete `execSync`, `getOption`, `getOptionBool`, `getOptionInt`, `getOptionFloat`. They carry the same bug and have no callers: `rg -n getOption quickshell/ scripts/` shows only their definitions. Keep `luaValue`, `setKeyword`, `checkedHyprctl`, `reloadConfig`. Drop the `GLib` import if nothing else in the file uses it.

- [ ] **Step 5: Run tests, then check live.** Run the Verify commands.

- [ ] **Step 6: Commit.**

```bash
git add quickshell/settings-panel/backend.js quickshell/settings-panel/hyprctl.js quickshell/settings-panel/test/backend.mjs
git commit -m "fix(settings): read Hyprland option values by their typed field

Toggles showed whether an option was assigned (getoption's \`set\`), not its
value, so Shadows, Smart Split, Tearing and Natural Scroll read as on while
off. Gap sliders showed null because \`css\` values were never read."
```

---

### Task 2: Keyboard, pointer, window and accessibility rows

**Goal:** Add 15 Hyprland-option rows and an Accessibility category, with keyboard layout/variant/options validated against XKB so a typo can never break the keymap.

**Files:**
- Modify: `quickshell/settings-panel/catalog.json` (new category `accessibility`; rows below)
- Modify: `quickshell/settings-panel/backend.js` (`validate` becomes async; add `optional` and `check`)
- Modify: `quickshell/settings-panel/SettingControl.qml` (`formatted`: `zeroLabel`, `seconds`)
- Test: `quickshell/settings-panel/test/backend.mjs`, `quickshell/settings-panel/test/tst_Settings.qml`

**Acceptance Criteria:**
- [ ] New rows exist: Input `kb-layout`, `kb-variant`, `kb-options`, `repeat-rate`, `repeat-delay`, `accel-profile`, `left-handed`, `tap-to-click`, `dwt`, `hide-cursor`, `no-warps`; Windows `dim-inactive`, `dim-strength`, `focus-on-activate`; Accessibility `zoom`
- [ ] `{op:"set",id:"input.kb-layout",value:"zz"}` is rejected before any `hyprctl eval`
- [ ] Changing the layout is rejected when the current variant does not exist for the new layout
- [ ] `kb-variant` and `kb-options` accept `""`; other text rows still reject it
- [ ] A slider with `zeroLabel` shows that label at 0; `format: "seconds"` shows `N s`
- [ ] Live: every new row reads without `error`; setting then resetting Repeat Rate leaves `overrides.lua` without a `repeat_rate` line

**Verify:** `bash quickshell/settings-panel/test/run-tests.sh` → pass; `bash scripts/settings/panel-request.sh "$(jq -c '{op:"read",ids:[.rows[]|select(.category=="input" or .category=="windows" or .category=="accessibility")|.id]}' quickshell/settings-panel/catalog.json)" | jq '[.values[]|select(.error)]|length'` → `0`

**Steps:**

- [ ] **Step 1: Failing backend tests.** In `backend.mjs` extend the `execAsync` mock (before the final `return 'ok'`):

```js
        if (args[0] === 'localectl') return {
            'list-x11-keymap-layouts': 'us\nit\nde\n',
            'list-x11-keymap-options': 'caps:escape\ngrp:alt_shift_toggle\n',
            'list-x11-keymap-variants': args[2] === 'us' ? 'intl\ncolemak\n' : 'nodeadkeys\n',
        }[args[1]]
```

and add `'input:kb_layout': {str:'us',set:true}` and `'input:kb_variant': {str:'intl',set:true}` to `hyprOptions`. Then append:

```js
events=[]
await assert.rejects(dispatch({op:'set',id:'input.kb-layout',value:'zz'}),/Unknown keyboard layout zz/)
await assert.rejects(dispatch({op:'set',id:'input.kb-layout',value:'de'}),/de has no variant intl/)
await assert.rejects(dispatch({op:'set',id:'input.kb-options',value:'caps:nope'}),/Unknown keyboard option/)
await assert.rejects(dispatch({op:'set',id:'apps.browser',value:''}),/nonempty/)
assert.equal(events.some(e => e[1] === 'eval'),false)
await dispatch({op:'set',id:'input.kb-variant',value:''})
await dispatch({op:'set',id:'input.kb-options',value:'caps:escape,grp:alt_shift_toggle'})
await dispatch({op:'set',id:'input.kb-layout',value:'us,it'})
assert.match(files.get(base+'/hypr/config/overrides.lua'),/kb_variant = ""/)
assert.match(files.get(base+'/hypr/config/overrides.lua'),/kb_layout = "us,it"/)
console.log('ok: keyboard layout, variant and options are checked against XKB before applying')
```

Run `node quickshell/settings-panel/test/backend.mjs` → fails with `Unknown setting`.

- [ ] **Step 2: Add the rows to `catalog.json`.** Add the category after `input`:

```json
    {
      "id": "accessibility",
      "title": "Accessibility",
      "description": "Zoom and text size"
    },
```

Insert the Input rows after `input.scroll-factor`, the Windows rows after `win.xwayland`, and the Accessibility row after those:

```json
    { "category": "input", "id": "input.kb-layout", "title": "Keyboard Layout", "description": "XKB layout, e.g. us or us,it for two", "keywords": ["keymap", "language"], "source": "keyword", "key": "input:kb_layout", "kind": "text", "check": "xkb-layout" },
    { "category": "input", "id": "input.kb-variant", "title": "Layout Variant", "description": "Optional, one per layout, e.g. intl", "keywords": ["keymap"], "source": "keyword", "key": "input:kb_variant", "kind": "text", "optional": true, "check": "xkb-variant" },
    { "category": "input", "id": "input.kb-options", "title": "Keyboard Options", "description": "Optional XKB options, e.g. caps:escape", "keywords": ["caps", "compose", "keymap"], "source": "keyword", "key": "input:kb_options", "kind": "text", "optional": true, "check": "xkb-options" },
    { "category": "input", "id": "input.repeat-rate", "title": "Key Repeat Rate", "description": "Repeats per second while a key is held", "keywords": ["keyboard"], "source": "keyword", "key": "input:repeat_rate", "kind": "slider", "min": 10, "max": 100, "step": 1 },
    { "category": "input", "id": "input.repeat-delay", "title": "Key Repeat Delay", "description": "Milliseconds before a held key repeats", "keywords": ["keyboard"], "source": "keyword", "key": "input:repeat_delay", "kind": "slider", "min": 150, "max": 1000, "step": 25 },
    { "category": "input", "id": "input.accel-profile", "title": "Pointer Acceleration", "description": "Flat keeps pointer speed constant", "keywords": ["mouse"], "source": "keyword", "key": "input:accel_profile", "kind": "select", "items": [ { "label": "Default", "value": "" }, { "label": "Flat", "value": "flat" }, { "label": "Adaptive", "value": "adaptive" } ] },
    { "category": "input", "id": "input.left-handed", "title": "Left-Handed Mouse", "description": "Swap the primary and secondary buttons", "source": "keyword", "key": "input:left_handed", "kind": "toggle" },
    { "category": "input", "id": "input.tap-to-click", "title": "Tap to Click (Touchpad)", "description": "A tap counts as a click", "source": "keyword", "key": "input:touchpad:tap_to_click", "kind": "toggle" },
    { "category": "input", "id": "input.dwt", "title": "Disable Touchpad While Typing", "description": "Ignore the touchpad during typing", "source": "keyword", "key": "input:touchpad:disable_while_typing", "kind": "toggle" },
    { "category": "input", "id": "input.hide-cursor", "title": "Hide Idle Cursor", "description": "Seconds without movement before the cursor hides", "keywords": ["mouse", "pointer"], "source": "keyword", "key": "cursor:inactive_timeout", "kind": "slider", "min": 0, "max": 30, "step": 1, "format": "seconds", "zeroLabel": "Never" },
    { "category": "input", "id": "input.no-warps", "title": "Keep Cursor in Place", "description": "Keyboard focus changes do not move the cursor", "keywords": ["warp", "mouse"], "source": "keyword", "key": "cursor:no_warps", "kind": "toggle" },
    { "category": "windows", "id": "win.dim-inactive", "title": "Dim Inactive Windows", "description": "Darken every window except the focused one", "source": "keyword", "key": "decoration:dim_inactive", "kind": "toggle" },
    { "category": "windows", "id": "win.dim-strength", "title": "Dim Strength", "description": "How dark inactive windows become", "source": "keyword", "key": "decoration:dim_strength", "kind": "slider", "min": 0.05, "max": 0.8, "step": 0.05 },
    { "category": "windows", "id": "win.focus-on-activate", "title": "Focus on Activation", "description": "Switch to windows that ask for attention", "source": "keyword", "key": "misc:focus_on_activate", "kind": "toggle" },
    { "category": "accessibility", "id": "a11y.zoom", "title": "Screen Zoom", "description": "Magnify around the cursor", "keywords": ["magnifier"], "source": "keyword", "key": "cursor:zoom_factor", "kind": "slider", "min": 1, "max": 4, "step": 0.1 }
```

Reformat the file afterwards with `jq . catalog.json > tmp && mv tmp catalog.json` so it keeps the existing one-key-per-line style. Check that `git diff` shows only additions.

- [ ] **Step 3: Async validation with `optional` and `check`.** In `backend.js`, replace `function validate(row, value) { ... }` with:

```js
const xkbLists = new Map()
function xkbList(...args) {
    const key = args.join(" ")
    if (!xkbLists.has(key)) xkbLists.set(key, execAsync(["localectl", ...args]).then(text => text.split("\n").filter(Boolean)))
    return xkbLists.get(key)
}
async function currentKeyword(key) {
    return String(keywordValue(JSON.parse(await execAsync(["hyprctl", "getoption", key, "-j"]))))
}
async function checkVariants(value, layouts) {
    if (!value) return
    const variants = value.split(",")
    if (variants.length > layouts.length) throw new Error("There are more variants than layouts")
    for (const [index, variant] of variants.entries()) {
        if (variant && !(await xkbList("list-x11-keymap-variants", layouts[index])).includes(variant))
            throw new Error(`${layouts[index]} has no variant ${variant}`)
    }
}
// A rejected keymap leaves Hyprland on its old one with only a log line, so
// every XKB name is checked before it is applied.
const checks = {
    "xkb-layout": async value => {
        const known = await xkbList("list-x11-keymap-layouts")
        const layouts = value.split(",")
        for (const layout of layouts) if (!known.includes(layout)) throw new Error(`Unknown keyboard layout ${layout}`)
        await checkVariants(await currentKeyword("input:kb_variant"), layouts)
    },
    "xkb-variant": async value => checkVariants(value, (await currentKeyword("input:kb_layout")).split(",")),
    "xkb-options": async value => {
        if (!value) return
        const known = await xkbList("list-x11-keymap-options")
        for (const option of value.split(",")) if (!known.includes(option)) throw new Error(`Unknown keyboard option ${option}`)
    },
}
async function validate(row, value) {
    if (row.kind === "toggle" && typeof value !== "boolean") throw new Error("Expected an on/off value")
    if (row.kind === "slider" && (typeof value !== "number" || !Number.isFinite(value) || value < row.min || value > row.max)) throw new Error("Value is outside this setting's range")
    if (row.kind === "slider" && row.step >= 1 && !Number.isInteger(value)) throw new Error("Expected a whole number")
    if (row.kind === "select" && !row.items.some(item => item.value === value)) throw new Error("Unknown choice")
    if (row.kind === "text") {
        if (typeof value !== "string" || /[\n\r\0]/.test(value) || value.length > 512) throw new Error("Enter a single-line value")
        if (!value.trim() && !row.optional) throw new Error("Enter a nonempty single-line value")
        if (row.check) await checks[row.check](value.trim())
    }
}
```

In `change()`, replace `validate(row, value)` with `await validate(row, value)`. Keyword text values must reach Hyprland trimmed, so in the `case "keyword":` line use `persist.setPersistent(row.key, row.kind === "text" ? value.trim() : value)`.

- [ ] **Step 4: Slider labels.** In `SettingControl.qml` `formatted(value)`, add as the first two lines:

```qml
        if (row.zeroLabel && Number(value) === 0) return row.zeroLabel;
        if (row.format === "seconds") return Math.round(value) + " s";
```

In `tst_Settings.qml` add a row `{id:"idle",category:"input",title:"Idle",description:"Hide",kind:"slider",min:0,max:30,step:1,format:"seconds",zeroLabel:"Never"}` with value `idle:{value:0}` and a test:

```qml
        function test_zero_label() {
            controller.select("input"); wait(20);
            const slider = findChild(view,"slider-idle");
            verify(slider);
            compare(slider.parent.children[1].text,"Never");
        }
```

(If the value label is not `children[1]`, give it `objectName: "value-" + control.row.id` and find it by name instead.)

- [ ] **Step 5: Run the suite, then verify live.** Run both Verify commands. Then set and reset one row live:

```bash
bash scripts/settings/panel-request.sh '{"op":"set","id":"input.repeat-rate","value":30}'
hyprctl getoption input:repeat_rate -j | jq .int     # → 30
bash scripts/settings/panel-request.sh '{"op":"reset","id":"input.repeat-rate"}'
rg -c repeat_rate hypr/config/overrides.lua          # → no output
```

- [ ] **Step 6: Commit.**

```bash
git add quickshell/settings-panel/
git commit -m "feat(settings): keyboard, pointer, window and zoom settings

Keyboard layout, variant and options are checked against XKB before they
reach Hyprland, so a typo cannot silently keep the old keymap."
```

---

### Task 3: Dynamic choices and GTK appearance rows

**Goal:** Rows can offer a list of values the backend finds on the system, and Appearance gains GTK theme, icon theme, colour scheme and text scaling, written to gsettings **and** both tracked `settings.ini` files.

**Files:**
- Modify: `quickshell/settings-panel/backend.js` (`children`, `exists`, `themeNames`, `enumerators`, `choicesFor`, `gtk` source, `iniSet`, `writeGtkIni`)
- Modify: `quickshell/settings-panel/catalog.json`
- Modify: `quickshell/settings-panel/SettingControl.qml` (select uses `choices`, capped popup, fallback text)
- Test: `quickshell/settings-panel/test/backend.mjs`, `quickshell/settings-panel/test/tst_Settings.qml`

**Acceptance Criteria:**
- [ ] A read of a row with `choices` returns `{value, reset, choices:[{label,value}]}`
- [ ] Setting `appearance.gtk-theme` to a name not in the choices is rejected with no `gsettings` call
- [ ] Setting it to a listed theme runs `gsettings set org.gnome.desktop.interface gtk-theme '<name>'` and rewrites `gtk-theme-name=` in both `gtk-3.0/settings.ini` and `gtk-4.0/settings.ini`, leaving every other line unchanged
- [ ] `appearance.color-scheme` = `prefer-dark` also writes `gtk-application-prefer-dark-theme=true` (and `false` for the others)
- [ ] The dropdown popup never grows taller than 320 px, and a value missing from the list is still displayed
- [ ] Live: the four new rows read without error; the GTK theme row lists `Kripton`

**Verify:** `bash quickshell/settings-panel/test/run-tests.sh` → pass; `bash scripts/settings/panel-request.sh '{"op":"read","ids":["appearance.gtk-theme","appearance.icon-theme","appearance.color-scheme","a11y.text-scale"]}' | jq -c '.values|map_values({value,n:(.choices|length?)})'` → four values, no `error`, `Kripton` in the GTK list.

**Steps:**

- [ ] **Step 1: Extend the mocks and write failing tests.** In `backend.mjs`:
  - Add `FileQueryInfoFlags:{NONE:0}` to the `Gio` mock.
  - Add a `dirs` map and the fixtures:

```js
const dirs = new Map([
    ['/usr/share/themes', ['Kripton','Adwaita','NoGtk']],
    ['/usr/share/themes/Kripton/gtk-3.0', []],
    ['/usr/share/themes/Adwaita/gtk-3.0', []],
    ['/usr/share/icons', ['Papirus-Dark','Bibata-Modern-Classic']],
    ['/usr/share/icons/Bibata-Modern-Classic/cursors', []],
])
files.set('/usr/share/icons/Papirus-Dark/index.theme','[Icon Theme]\nDirectories=16x16/apps\n')
files.set('/usr/share/icons/Bibata-Modern-Classic/index.theme','[Icon Theme]\nName=Bibata\n')
files.set(base+'/gtk-3.0/settings.ini','[Settings]\ngtk-theme-name=Kripton\ngtk-font-name=Sans 11\n')
files.set(base+'/gtk-4.0/settings.ini','[Settings]\ngtk-theme-name=Kripton\n')
const gsettings = {'gtk-theme':"'Kripton'",'icon-theme':"'Papirus-Dark'",'color-scheme':"'prefer-dark'",'text-scaling-factor':'1.0','cursor-size':'24','cursor-theme':"'Bibata-Modern-Classic'"}
```

  - Inside `new_for_path: path => ({ ... })` add:

```js
            query_exists: () => files.has(path) || dirs.has(path),
            enumerate_children: () => {
                if (!dirs.has(path)) throw new Error('No such directory: '+path)
                const names = [...dirs.get(path)]
                return { next_file: () => names.length ? {get_name: (n => () => n)(names.shift())} : null, close: () => {} }
            },
```

  - In `execAsync`, before `return 'ok'`:

```js
        if (args[0] === 'gsettings' && args[1] === 'get') return gsettings[args[3]]
        if (args[0] === 'gsettings' && args[1] === 'set') { gsettings[args[3]] = args[4]; return '' }
```

  Append the tests:

```js
result = await dispatch({op:'read',ids:['appearance.gtk-theme','appearance.icon-theme']})
assert.deepEqual(result.values['appearance.gtk-theme'].choices.map(c=>c.value),['Adwaita','Kripton'])
assert.deepEqual(result.values['appearance.icon-theme'].choices.map(c=>c.value),['Papirus-Dark'])
assert.equal(result.values['appearance.gtk-theme'].value,'Kripton')
events=[]
await assert.rejects(dispatch({op:'set',id:'appearance.gtk-theme',value:'NoGtk'}),/Unknown choice/)
assert.equal(events.some(e=>e[0]==='gsettings'),false)
await dispatch({op:'set',id:'appearance.gtk-theme',value:'Adwaita'})
assert.equal(gsettings['gtk-theme'],"'Adwaita'")
assert.equal(files.get(base+'/gtk-3.0/settings.ini'),'[Settings]\ngtk-theme-name=Adwaita\ngtk-font-name=Sans 11\n')
assert.equal(files.get(base+'/gtk-4.0/settings.ini'),'[Settings]\ngtk-theme-name=Adwaita\n')
await dispatch({op:'set',id:'appearance.color-scheme',value:'prefer-light'})
assert.match(files.get(base+'/gtk-3.0/settings.ini'),/^gtk-application-prefer-dark-theme=false$/m)
console.log('ok: GTK appearance writes gsettings and both settings.ini files, only to listed themes')
```

  Run → fails with `Unknown setting`.

- [ ] **Step 2: Choice enumeration in `backend.js`.** Add after the `write` function:

```js
const exists = path => Gio.File.new_for_path(path).query_exists(null)
function children(path) {
    let enumerator
    try { enumerator = Gio.File.new_for_path(path).enumerate_children("standard::name", Gio.FileQueryInfoFlags.NONE, null) }
    catch (_) { return [] } // A missing search directory is normal.
    const names = []
    for (let info; (info = enumerator.next_file(null));) names.push(info.get_name())
    enumerator.close(null)
    return names
}
const home = GLib.get_home_dir()
const themeDirs = kind => [`${home}/.local/share/${kind}`, `${home}/.${kind}`, `/usr/share/${kind}`]
function themeNames(dirs, isTheme) {
    const names = new Set()
    for (const dir of dirs) for (const name of children(dir)) if (isTheme(`${dir}/${name}`)) names.add(name)
    return [...names].sort((a, b) => a.localeCompare(b)).map(name => ({ label: name, value: name }))
}
const hasIcons = dir => { try { return /^Directories=/m.test(read(`${dir}/index.theme`)) } catch (_) { return false } }
// Each enumerator returns what the system has now, so validation and the
// dropdown can never disagree and no list of names is kept in the repo.
const enumerators = {
    "gtk-themes": () => themeNames(themeDirs("themes"), dir => exists(`${dir}/gtk-3.0`)),
    "icon-themes": () => themeNames(themeDirs("icons"), hasIcons),
    "cursor-themes": () => themeNames(themeDirs("icons"), dir => exists(`${dir}/cursors`)),
}
async function choicesFor(row) {
    if (row.items) return row.items
    if (!Object.hasOwn(enumerators, row.choices)) throw new Error("This setting has no choices")
    return enumerators[row.choices](row)
}
```

In `validate`, change the select line to:

```js
    if (row.kind === "select" && !(await choicesFor(row)).some(item => item.value === value)) throw new Error("Unknown choice")
```

In `snapshot`, replace `values[id] = { value, reset }` with:

```js
            values[id] = row.choices ? { value, reset, choices: await choicesFor(row) } : { value, reset }
```

- [ ] **Step 3: The `gtk` source.** Add to `backend.js`:

```js
const gtkIniPaths = ["gtk-3.0", "gtk-4.0"].map(dir => `${configDir}/${dir}/settings.ini`)
const gsettingsArgs = key => ["org.gnome.desktop.interface", key]
function gvariantValue(text) {
    const quoted = text.trim().match(/^'(.*)'$/)
    return quoted ? quoted[1] : Number(text)
}
const gvariantLiteral = value => typeof value === "number" ? String(value) : `'${String(value).replace(/[\\']/g, "\\$&")}'`
function iniSet(path, text, key, value) {
    if (!/^\[Settings\]$/m.test(text)) throw new Error(`${path} has no [Settings] section`)
    const line = `${key}=${value}`
    const pattern = new RegExp(`^${key}=.*$`, "m")
    return pattern.test(text) ? text.replace(pattern, line) : text.replace(/^\[Settings\]\n/m, `[Settings]\n${line}\n`)
}
// GTK 3 on Wayland reads some keys from gsettings and others from settings.ini,
// so both are written; the ini files are tracked and keep every other line.
function writeGtkIni(entries) {
    for (const path of gtkIniPaths) {
        if (!exists(path)) continue
        let text = read(path)
        for (const [key, value] of entries) text = iniSet(path, text, key, value)
        write(path, text)
    }
}
async function setGtk(row, value) {
    const before = gvariantValue(await execAsync(["gsettings", "get", ...gsettingsArgs(row.key)]))
    const saved = gtkIniPaths.filter(exists).map(path => [path, read(path)])
    try {
        if (row.ini) writeGtkIni([[row.ini.key, row.ini.values ? row.ini.values[value] : String(value)]])
        await execAsync(["gsettings", "set", ...gsettingsArgs(row.key), gvariantLiteral(value)])
    } catch (error) {
        for (const [path, text] of saved) write(path, text)
        await execAsync(["gsettings", "set", ...gsettingsArgs(row.key), gvariantLiteral(before)])
        throw error
    }
}
```

In `snapshot` add `case "gtk": value = gvariantValue(await execAsync(["gsettings", "get", ...gsettingsArgs(row.key)])); break`. In `change` add `case "gtk": return setGtk(row, value)`. Also switch the existing `cursor` source reads and writes to `gsettingsArgs("cursor-size")` so the schema string exists once.

- [ ] **Step 4: Rows.** Add after `appearance.font-gtk`:

```json
    { "category": "appearance", "id": "appearance.color-scheme", "title": "Colour Scheme", "description": "Light or dark preference for GTK and portal apps", "keywords": ["dark mode", "light mode"], "source": "gtk", "key": "color-scheme", "kind": "select", "items": [ { "label": "Dark", "value": "prefer-dark" }, { "label": "Light", "value": "prefer-light" }, { "label": "Default", "value": "default" } ], "ini": { "key": "gtk-application-prefer-dark-theme", "values": { "prefer-dark": "true", "prefer-light": "false", "default": "false" } } },
    { "category": "appearance", "id": "appearance.gtk-theme", "title": "GTK Theme", "description": "Widget theme for GTK apps", "source": "gtk", "key": "gtk-theme", "kind": "select", "choices": "gtk-themes", "ini": { "key": "gtk-theme-name" } },
    { "category": "appearance", "id": "appearance.icon-theme", "title": "Icon Theme", "description": "Application and file icons", "source": "gtk", "key": "icon-theme", "kind": "select", "choices": "icon-themes", "ini": { "key": "gtk-icon-theme-name" } },
```

and in Accessibility:

```json
    { "category": "accessibility", "id": "a11y.text-scale", "title": "Text Size", "description": "Scale text in GTK apps", "keywords": ["font", "larger"], "source": "gtk", "key": "text-scaling-factor", "kind": "slider", "min": 0.75, "max": 2, "step": 0.05 }
```

- [ ] **Step 5: The dropdown.** In `SettingControl.qml` `selectComponent`, add `readonly property var choices: control.row.items || control.settingState.choices || []` to the `ComboBox` and replace every `control.row.items` inside it with `combo.choices`. Show values that are not in the list: `displayText: currentIndex < 0 ? String(control.settingState.value ?? "") : currentText`. Cap the popup: replace its `implicitHeight:` with `implicitHeight: Math.min(contentItem.implicitHeight + topPadding + bottomPadding, 320)`.

  In `tst_Settings.qml` add the row `{id:"theme",category:"appearance",title:"Theme",description:"GTK",kind:"select",choices:"gtk-themes"}` with value `theme:{value:"B",choices:[{label:"A",value:"A"},{label:"B",value:"B"}]}` and:

```qml
        function test_dynamic_choices() {
            const combo = findChild(view,"select-theme");
            compare(combo.currentIndex,1);
            combo.forceActiveFocus();
            mouseClick(combo);
            tryCompare(combo.popup,"visible",true);
            keyClick(Qt.Key_Up); keyClick(Qt.Key_Return);
            tryCompare(combo.popup,"visible",false);
            compare(controller.calls[0].value,"A");
        }
```

- [ ] **Step 6: Run the suite and check live.** Run the Verify commands. Then open the panel (Super+I), go to Appearance, open the GTK Theme dropdown and check it scrolls within 320 px. Pick `Kripton` (the current value) to confirm the round trip, then run `git diff gtk-3.0 gtk-4.0`. Expect no change.

- [ ] **Step 7: Commit.**

```bash
git add quickshell/settings-panel/
git commit -m "feat(settings): GTK theme, icons, colour scheme and text size

Rows can declare \`choices\`: the backend lists what is installed and
validates writes against the same list. GTK values go to gsettings and to
both tracked settings.ini files, which GTK 3 on Wayland reads separately."
```

---

### Task 4: Font and cursor consistency

**Goal:** Font rows reject fonts that are not installed, the GTK font reaches gsettings, and the cursor theme becomes a dropdown whose value is written everywhere GTK reads it.

**Background (verified):** `options/font-gtk` is FiraCode but gsettings `font-name` is `Adwaita Sans 11`. `options/cursortheme` and gsettings say `Bibata-Modern-Classic`, while `gtk-3.0/settings.ini` says `Bibata-Modern-Ice`.

**Files:**
- Modify: `quickshell/settings-panel/backend.js` (`checks.font`, `cursor()`)
- Modify: `quickshell/settings-panel/catalog.json` (`appearance.font`, `appearance.font-gtk`, `appearance.cursor-theme`)
- Modify: `scripts/fonts/apply-font.sh`
- Create: `scripts/fonts/test-apply-font.sh`
- Test: `quickshell/settings-panel/test/backend.mjs`

**Acceptance Criteria:**
- [ ] `{op:"set",id:"appearance.font",value:"No Such Font"}` is rejected before `apply-font.sh` runs
- [ ] `appearance.cursor-theme` is a select with `choices: "cursor-themes"`; setting it writes `gtk-cursor-theme-name` and `gtk-cursor-theme-size` in both ini files
- [ ] `apply-font.sh` runs `gsettings set org.gnome.desktop.interface font-name "<gtk font> <size><weight>"` when gsettings exists, and exits 1 if that call fails
- [ ] `scripts/fonts/test-apply-font.sh` passes and is discovered by `./test.sh --list`
- [ ] Live: after running `apply-font.sh`, `gsettings get org.gnome.desktop.interface font-name` names FiraCode; after re-picking the cursor theme, `rg cursor-theme-name gtk-3.0/settings.ini` matches `options/cursortheme`

**Verify:** `./test.sh` → all pass; the two live checks above.

**Steps:**

- [ ] **Step 1: Failing backend test.** Add to `execAsync` in `backend.mjs`: `if (args[0] === 'fc-list') return 'FiraCode Nerd Font,FiraCode Nerd Font Med\nAdwaita Sans\n'`. Append:

```js
events=[]
await assert.rejects(dispatch({op:'set',id:'appearance.font',value:'No Such Font'}),/No installed font/)
assert.equal(events.some(e=>e[0]==='bash'),false)
await dispatch({op:'set',id:'appearance.font',value:'FiraCode Nerd Font Med'})
await dispatch({op:'set',id:'appearance.cursor-theme',value:'Bibata-Modern-Classic'})
assert.match(files.get(base+'/gtk-3.0/settings.ini'),/^gtk-cursor-theme-name=Bibata-Modern-Classic$/m)
assert.match(files.get(base+'/gtk-4.0/settings.ini'),/^gtk-cursor-theme-size=24$/m)
console.log('ok: fonts must be installed and the cursor theme reaches settings.ini')
```

- [ ] **Step 2: Implement.** Add to `checks` in `backend.js`:

```js
    font: async value => {
        const families = (await execAsync(["fc-list", ":", "family"])).split("\n").flatMap(line => line.split(",")).map(name => name.trim())
        if (!families.includes(value)) throw new Error(`No installed font is named ${value}`)
    },
```

Replace `cursor()` with:

```js
async function cursor(theme, size) {
    await execAsync(["gsettings", "set", ...gsettingsArgs("cursor-theme"), theme])
    await execAsync(["gsettings", "set", ...gsettingsArgs("cursor-size"), String(size)])
    writeGtkIni([["gtk-cursor-theme-name", theme], ["gtk-cursor-theme-size", String(size)]])
    await checkedHyprctl(["setcursor", theme, String(size)])
}
```

In `catalog.json` add `"check": "font"` to `appearance.font` and `appearance.font-gtk`. Change `appearance.cursor-theme` to `"kind": "select", "choices": "cursor-themes"`. The option source already writes `options/cursortheme` and calls `cursor()`. Its `saveAndApply` rollback re-runs `cursor()` with the old theme, which restores the ini lines too.

- [ ] **Step 3: Failing shell test.** Read `scripts/lib/assert.sh` first and use its real helper names. Create `scripts/fonts/test-apply-font.sh` with this logic:

```bash
#!/bin/bash
# apply-font.sh writes the GTK font to gsettings as well as settings.ini.
set -euo pipefail
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/assert.sh"

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/apply-font.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.config/options" "$tmp/.config/rofi/options" "$tmp/.config/gtk-3.0" "$tmp/bin"
echo "Main Font" > "$tmp/.config/options/font"
echo "Gtk Font" > "$tmp/.config/options/font-gtk"
printf '[Settings]\ngtk-font-name=Old 12 @wght=600\n' > "$tmp/.config/gtk-3.0/settings.ini"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/gsettings.log"\n' "$tmp" > "$tmp/bin/gsettings"
chmod +x "$tmp/bin/gsettings"

HOME="$tmp" PATH="$tmp/bin:$PATH" bash "$script" >/dev/null
assert_eq "$(cat "$tmp/gsettings.log")" "set org.gnome.desktop.interface font-name Gtk Font 12 @wght=600" \
    "the GTK font, size and weight reach gsettings"

printf '#!/bin/sh\nexit 1\n' > "$tmp/bin/gsettings"
if HOME="$tmp" PATH="$tmp/bin:$PATH" bash "$script" >/dev/null 2>&1; then
    fail "a failed gsettings write must fail the script"
else
    pass "a failed gsettings write fails the script"
fi
test_summary
```

Run `bash scripts/fonts/test-apply-font.sh` → fails (no log file).

- [ ] **Step 4: Implement in `apply-font.sh`.** Move `size=11 weight=""` to just before the GTK loop, so the values survive it, and remove them from inside the loop. After the loop add:

```bash
# GTK 4, libadwaita and the settings portal read gsettings, not settings.ini.
if command -v gsettings >/dev/null; then
    gsettings set org.gnome.desktop.interface font-name "$gtk_font $size$weight" || failed=1
fi
```

Run the test → passes; `./test.sh --list | rg apply-font` → listed.

- [ ] **Step 5: Live check, then commit.** Run `bash scripts/fonts/apply-font.sh` (the panel's Save button is disabled for an unchanged value), then do the two live checks.

```bash
git add quickshell/settings-panel/ scripts/fonts/ gtk-3.0/settings.ini gtk-4.0/settings.ini
git commit -m "fix(settings): fonts must exist; GTK font and cursor reach every reader

The GTK font only reached settings.ini, so GTK 4 apps kept Adwaita Sans. The
cursor theme skipped settings.ini, which still named Bibata-Modern-Ice."
```

---

### Task 5: Qt (Kvantum) theme row

**Goal:** Pick the Kvantum theme Qt apps use.

**Files:**
- Modify: `quickshell/settings-panel/backend.js` (`kvantum` source and enumerator)
- Modify: `quickshell/settings-panel/catalog.json`
- Test: `quickshell/settings-panel/test/backend.mjs`

**Acceptance Criteria:**
- [ ] Choices are directories under `~/.config/Kvantum` and `/usr/share/Kvantum` that contain `<Name>/<Name>.kvconfig`
- [ ] Setting rewrites only `theme=` under `[General]` in `~/.config/Kvantum/kvantum.kvconfig`, creating the file when it is missing, and refuses a file without `[General]`
- [ ] Live: the row reads `Carl`

**Verify:** `node quickshell/settings-panel/test/backend.mjs` → pass; `bash scripts/settings/panel-request.sh '{"op":"read","ids":["appearance.kvantum"]}' | jq -c '.values[]|{value,choices:(.choices|map(.value))}'` → `value: "Carl"`

**Steps:**

- [ ] **Step 1: Failing test.** In `backend.mjs` add:

```js
dirs.set(base+'/Kvantum',['Carl','kvantum.kvconfig'])
dirs.set('/usr/share/Kvantum',['KvArc'])
files.set(base+'/Kvantum/Carl/Carl.kvconfig','')
files.set('/usr/share/Kvantum/KvArc/KvArc.kvconfig','')
files.set(base+'/Kvantum/kvantum.kvconfig','[General]\ntheme=Carl\n')
```

and append:

```js
result = await dispatch({op:'read',ids:['appearance.kvantum']})
assert.equal(result.values['appearance.kvantum'].value,'Carl')
assert.deepEqual(result.values['appearance.kvantum'].choices.map(c=>c.value),['Carl','KvArc'])
await dispatch({op:'set',id:'appearance.kvantum',value:'KvArc'})
assert.equal(files.get(base+'/Kvantum/kvantum.kvconfig'),'[General]\ntheme=KvArc\n')
console.log('ok: Kvantum theme is chosen from installed themes')
```

- [ ] **Step 2: Implement.** In `backend.js`:

```js
const kvantumPath = configDir + "/Kvantum/kvantum.kvconfig"
const kvantumDirs = [configDir + "/Kvantum", "/usr/share/Kvantum"]
```

Add the enumerator `"kvantum-themes": () => themeNames(kvantumDirs, dir => exists(`${dir}/${dir.split("/").pop()}.kvconfig`))`. Snapshot case:

```js
            case "kvantum": value = exists(kvantumPath) ? (read(kvantumPath).match(/^theme=(.*)$/m) || [, ""])[1] : ""; break
```

Change case (Qt apps read the file at start; there is nothing to reload):

```js
    case "kvantum": {
        const text = exists(kvantumPath) ? read(kvantumPath) : "[General]\n"
        if (!/^\[General\]$/m.test(text)) throw new Error("kvantum.kvconfig has no [General] section")
        return write(kvantumPath, /^theme=.*$/m.test(text)
            ? text.replace(/^theme=.*$/m, `theme=${value}`)
            : text.replace(/^\[General\]\n/m, `[General]\ntheme=${value}\n`))
    }
```

Row, after `appearance.icon-theme`:

```json
    { "category": "appearance", "id": "appearance.kvantum", "title": "Qt Theme (Kvantum)", "description": "Qt apps pick it up when they restart", "keywords": ["qt", "kde"], "source": "kvantum", "kind": "select", "choices": "kvantum-themes" }
```

- [ ] **Step 3: Run, verify live, commit.**

```bash
git add quickshell/settings-panel/
git commit -m "feat(settings): choose the Kvantum theme for Qt apps"
```

---

### Task 6: Default apps: file manager, installed-command check, update command

**Goal:** The file manager becomes a preference like the other apps, app rows reject commands that are not installed, and the update command is editable. Hyprland reload is driven by a catalog flag instead of a hardcoded key list.

**Files:**
- Create: `options/filemanager` (content `thunar`)
- Modify: `hypr/config/apptype.lua`, `hypr/config/software/keybinds.lua:7`
- Modify: `scripts/lib/hypr-vars.sh` (`hypr_var_origin` and the comment table)
- Modify: `test/test-docs.sh` (the `printf` list of option-backed names)
- Modify: `quickshell/settings-panel/backend.js`, `catalog.json`, `test/backend.mjs`
- Modify: `CLAUDE.md` (options list), `docs/keybindings.md` (regenerated)

**Acceptance Criteria:**
- [ ] Super+E runs `apps.filemanager`, read from `options/filemanager` (fallback `thunar`)
- [ ] The cheatsheet prints `File manager (thunar)`; `docs/keybindings.md` says `options/filemanager`
- [ ] App rows with `"check": "command"` reject a value whose first word is not on `PATH`, before writing
- [ ] `backend.js` has no hardcoded list of reload keys; rows with `"reload": true` reload Hyprland
- [ ] New row `apps.aurhelper` edits `options/aurhelper`
- [ ] `./doctor.sh` Binaries group is all-clear

**Verify:** `./test.sh` → pass; `./rofi/keybinds-cheatsheet.sh --print | rg "Super \+ E "` → `File manager (thunar)`; `./doctor.sh | rg -A1 Binaries` → `✓`

**Steps:**

- [ ] **Step 1: Failing backend test.** In `backend.mjs`, change the mock `find_program_in_path: name => name` to `find_program_in_path: name => name === 'missing-app' ? null : name`, and add `'filemanager','aurhelper'` to the options fixture list. Append:

```js
events=[]
await assert.rejects(dispatch({op:'set',id:'apps.filemanager',value:'missing-app --flag'}),/missing-app is not installed/)
assert.equal(events.length,0)
await dispatch({op:'set',id:'apps.filemanager',value:'nautilus'})
assert.equal(files.get(base+'/options/filemanager'),'nautilus\n')
assert.ok(events.some(e=>e[1]==='reload'))
console.log('ok: app rows must name an installed command and reload Hyprland')
```

- [ ] **Step 2: Implement the backend.** Add to `checks`:

```js
    command: value => {
        const program = value.split(/\s+/)[0]
        if (!GLib.find_program_in_path(program)) throw new Error(`${program} is not installed`)
    },
```

In the `option` case replace `if (["terminal", "browser", "editor", "codeeditor"].includes(row.key)) await persistReload()` with `if (row.reload) await persistReload()`, keeping the comment above it.

In `catalog.json` add `"check": "command", "reload": true` to `apps.browser`, `apps.terminal`, `apps.editor`, `apps.codeeditor`. Add after `apps.codeeditor`:

```json
    { "category": "apps", "id": "apps.filemanager", "title": "File Manager", "description": "Launched with Super+E", "source": "option", "key": "filemanager", "kind": "text", "check": "command", "reload": true },
    { "category": "apps", "id": "apps.aurhelper", "title": "Update Command", "description": "Run by Update system, e.g. paru -Syu", "keywords": ["paru", "yay", "pacman"], "source": "option", "key": "aurhelper", "kind": "text", "check": "command" },
```

- [ ] **Step 3: Hyprland side.**
  - `printf 'thunar\n' > options/filemanager`.
  - In `apptype.lua`, replace `fileManager = "thunar", -- GUI file manager (yazi for CLI)` with `filemanager = read_option("filemanager", "thunar"), -- GUI file manager (yazi for CLI)`.
  - In `keybinds.lua:7`, use `hl.dsp.exec_cmd(apps.filemanager)) -- File manager ($filemanager)`.
  - In `hypr-vars.sh`, make the case `terminal|browser|editor|codeeditor|filemanager) printf 'options' ;;` (realign the `*)` line), and add `filemanager` to the comment table.
  - In `test/test-docs.sh`, add `filemanager` to the `printf '%s\n' ...` list.
  - In `CLAUDE.md`, add `` `filemanager` `` after `` `codeeditor` `` in the options sentence.
  
  The doctor fixture in `scripts/doctor/test/test-binaries.sh` uses `fileManager` as an apptype example on purpose; leave it.

- [ ] **Step 4: Regenerate, reload, check.**

```bash
scripts/docs/generate-keybindings.sh
hyprctl reload && hyprctl configerrors -j      # → [""] or []
```

Then run the Verify commands.

- [ ] **Step 5: Commit.**

```bash
git add options/filemanager hypr/ scripts/lib/hypr-vars.sh test/test-docs.sh quickshell/settings-panel/ CLAUDE.md docs/keybindings.md
git commit -m "feat(apps): file manager preference; app rows must be installed

A typo in an app row used to save cleanly and leave its keybind dead. Rows
now declare \`reload\` instead of the backend listing which keys reload."
```

---

### Task 7: File Types (default applications per kind of file)

**Goal:** A File Types category sets which installed app opens folders, links, PDFs, images, video, audio, text, archives and email, through `xdg-mime` into the tracked `mimeapps.list`.

**Background (verified):** folders open with `kitty-open.desktop`, PDFs with Chromium, zips with Nautilus. `inode/directory` and `application/pdf` have no line in `mimeapps.list`. `xdg-mime default` edits only the lines it needs (tested on a copy). No `hyprland-mimeapps.list` exists to override it.

**Files:**
- Modify: `quickshell/settings-panel/backend.js` (`mime` source, `applications` enumerator)
- Modify: `quickshell/settings-panel/catalog.json` (category `filetypes`, 9 rows)
- Test: `quickshell/settings-panel/test/backend.mjs`

**Acceptance Criteria:**
- [ ] Each row's value is `xdg-mime query default <first mime>`; its choices are `Gio.AppInfo.get_all_for_type(<first mime>)` as `{label: name, value: id}`, plus the current value if missing
- [ ] Setting a row runs `xdg-mime default <id> <mime>` once per mime in the row, and only for an id in the choices
- [ ] If one call fails, the mimes already changed are set back to their previous defaults and the error propagates
- [ ] Live: after setting Folders to `thunar.desktop`, `xdg-mime query default inode/directory` → `thunar.desktop` and `git diff mimeapps.list` shows exactly one added line

**Verify:** `node quickshell/settings-panel/test/backend.mjs` → pass; the live check above.

**Steps:**

- [ ] **Step 1: Failing test.** In `backend.mjs` add to the Gio mock:

```js
        AppInfo: { get_all_for_type: type => (appsForType[type] || []).map(([id,name]) => ({get_id: () => id, get_name: () => name})) },
```

with, near the other fixtures:

```js
const appsForType = {'inode/directory': [['thunar.desktop','Thunar'],['org.gnome.Nautilus.desktop','Files']], 'image/png': [['mpv.desktop','mpv']]}
const mimeDefaults = {'inode/directory':'kitty-open.desktop'}
let failMime = ''
```

and to `execAsync`:

```js
        if (args[0] === 'xdg-mime' && args[1] === 'query') return (mimeDefaults[args[3]] || '') + '\n'
        if (args[0] === 'xdg-mime' && args[1] === 'default') {
            if (args[3] === failMime) throw new Error('xdg-mime failed')
            mimeDefaults[args[3]] = args[2]; return ''
        }
```

Append:

```js
result = await dispatch({op:'read',ids:['mime.folders']})
assert.equal(result.values['mime.folders'].value,'kitty-open.desktop')
assert.deepEqual(result.values['mime.folders'].choices.map(c=>c.value),['thunar.desktop','org.gnome.Nautilus.desktop','kitty-open.desktop'])
await assert.rejects(dispatch({op:'set',id:'mime.folders',value:'evil.desktop'}),/Unknown choice/)
await dispatch({op:'set',id:'mime.folders',value:'thunar.desktop'})
assert.equal(mimeDefaults['inode/directory'],'thunar.desktop')
mimeDefaults['image/png']='old.desktop'; mimeDefaults['image/jpeg']='old.desktop'
failMime='image/jpeg'
await assert.rejects(dispatch({op:'set',id:'mime.images',value:'mpv.desktop'}),/xdg-mime failed/)
assert.equal(mimeDefaults['image/png'],'old.desktop')
failMime=''
console.log('ok: file types use installed handlers and roll back partial changes')
```

- [ ] **Step 2: Implement.** In `backend.js`:

```js
const mimeDefault = async mime => (await execAsync(["xdg-mime", "query", "default", mime])).trim()
```

Enumerator (it needs the current value, so it is async):

```js
    applications: async row => {
        const apps = Gio.AppInfo.get_all_for_type(row.mimes[0]).map(app => ({ label: app.get_name(), value: app.get_id() }))
        const current = await mimeDefault(row.mimes[0])
        if (current && !apps.some(app => app.value === current)) apps.push({ label: current.replace(/\.desktop$/, ""), value: current })
        return apps
    },
```

Snapshot case: `case "mime": value = await mimeDefault(row.mimes[0]); break`. Change case:

```js
    case "mime": {
        const before = await Promise.all(row.mimes.map(mimeDefault))
        const done = []
        try {
            for (const mime of row.mimes) { await execAsync(["xdg-mime", "default", value, mime]); done.push(mime) }
        } catch (error) {
            // xdg-mime cannot unset a default, so only mimes that had one are restored.
            for (const mime of done) {
                const previous = before[row.mimes.indexOf(mime)]
                if (previous) await execAsync(["xdg-mime", "default", previous, mime])
            }
            throw error
        }
        return
    }
```

- [ ] **Step 3: Category and rows.** Add the category after `apps`:

```json
    { "id": "filetypes", "title": "File Types", "description": "Which app opens each kind of file or link" },
```

Rows (all `"source": "mime", "kind": "select", "choices": "applications"`):

| id | title | description | mimes |
|---|---|---|---|
| `mime.folders` | Folders | Opened from other apps and the desktop | `inode/directory` |
| `mime.web` | Web Links | Links opened from other apps (Super+B uses Browser) | `x-scheme-handler/http`, `x-scheme-handler/https`, `text/html`, `application/xhtml+xml` |
| `mime.pdf` | PDF Documents | Default app | `application/pdf` |
| `mime.images` | Images | Default app | `image/png`, `image/jpeg`, `image/gif`, `image/webp`, `image/bmp`, `image/tiff`, `image/svg+xml` |
| `mime.video` | Video | Default app | `video/mp4`, `video/x-matroska`, `video/webm`, `video/quicktime`, `video/x-msvideo` |
| `mime.audio` | Audio | Default app | `audio/mpeg`, `audio/flac`, `audio/ogg`, `audio/x-wav`, `audio/aac`, `audio/mp4`, `audio/x-opus+ogg` |
| `mime.text` | Text Files | Default app | `text/plain`, `text/markdown` |
| `mime.archives` | Archives | Default app | `application/zip`, `application/x-tar`, `application/x-7z-compressed`, `application/gzip`, `application/vnd.rar` |
| `mime.email` | Email Links | mailto: links | `x-scheme-handler/mailto` |

Write each in the same JSON shape as the other rows, e.g.:

```json
    { "category": "filetypes", "id": "mime.folders", "title": "Folders", "description": "Opened from other apps and the desktop", "source": "mime", "kind": "select", "choices": "applications", "mimes": ["inode/directory"] },
```

- [ ] **Step 4: Run, verify live, commit.** Run the Verify steps. Setting Folders to `thunar.desktop` is the intended change, not a test artifact; keep it.

```bash
git add quickshell/settings-panel/ mimeapps.list
git commit -m "feat(settings): File Types chooses default apps per kind of file

Folders opened in kitty-open and PDFs in Chromium because nothing set them.
Choices are the installed apps that declare the type."
```

---

### Task 8: Power profile and automatic suspend

**Goal:** Choose the power-profiles-daemon profile, and optionally suspend after N minutes idle (hypridle currently never suspends).

**Files:**
- Modify: `quickshell/settings-panel/backend.js` (`powerprofile` source, idle `suspend` key, `withSuspend`)
- Modify: `quickshell/settings-panel/catalog.json`
- Test: `quickshell/settings-panel/test/backend.mjs`

**Acceptance Criteria:**
- [ ] `power.profile` reads `powerprofilesctl get` and offers the profiles from `powerprofilesctl list`; setting runs `powerprofilesctl set <profile>`
- [ ] `power.suspend` reads 0 when `hypridle.conf` has no `systemctl suspend` listener
- [ ] Setting N>0 appends one marked listener; setting another N edits its timeout; setting 0 removes it, and the file is then byte-identical to before the first append
- [ ] A hand-written suspend listener (without the `# Suspend after inactivity` marker) is never deleted; setting 0 then fails with a message
- [ ] Every suspend change restarts hypridle, and a failed restart restores the file
- [ ] Live: set 1800, `rg -A3 "Suspend after" hypr/hypridle.conf` shows the block and `pgrep -x hypridle` succeeds; set 0, `git diff hypr/hypridle.conf` is empty

**Verify:** `node quickshell/settings-panel/test/backend.mjs` → pass; the live check.

**Steps:**

- [ ] **Step 1: Failing test.** Add to the `execAsync` mock:

```js
        if (args[0] === 'powerprofilesctl') return args[1] === 'get' ? 'performance\n'
            : args[1] === 'list' ? '* performance:\n    CpuDriver:\tintel_pstate\n\n  balanced:\n    CpuDriver:\tintel_pstate\n\n  power-saver:\n    CpuDriver:\tintel_pstate\n' : ''
```

Append:

```js
result = await dispatch({op:'read',ids:['power.profile','power.suspend']})
assert.equal(result.values['power.profile'].value,'performance')
assert.deepEqual(result.values['power.profile'].choices.map(c=>c.value),['performance','balanced','power-saver'])
assert.equal(result.values['power.suspend'].value,0)
await dispatch({op:'set',id:'power.profile',value:'balanced'})
assert.ok(events.some(e=>e[0]==='powerprofilesctl' && e[1]==='set' && e[2]==='balanced'))
const idleBefore = files.get(base+'/hypr/hypridle.conf')
await dispatch({op:'set',id:'power.suspend',value:1800})
assert.match(files.get(base+'/hypr/hypridle.conf'),/# Suspend after inactivity\nlistener \{\n    timeout = 1800\n    on-timeout = systemctl suspend\n\}\n$/)
await dispatch({op:'set',id:'power.suspend',value:3600})
assert.match(files.get(base+'/hypr/hypridle.conf'),/timeout = 3600\n    on-timeout = systemctl suspend/)
await dispatch({op:'set',id:'power.suspend',value:0})
assert.equal(files.get(base+'/hypr/hypridle.conf'),idleBefore)
files.set(base+'/hypr/hypridle.conf',idleBefore+'listener {\n timeout = 99\n on-timeout = systemctl suspend\n}\n')
await assert.rejects(dispatch({op:'set',id:'power.suspend',value:0}),/by hand/)
files.set(base+'/hypr/hypridle.conf',idleBefore)
console.log('ok: power profile and suspend listener round-trip without touching custom content')
```

- [ ] **Step 2: Implement.** Enumerator:

```js
    "power-profiles": async () => (await execAsync(["powerprofilesctl", "list"])).split("\n")
        .map(line => line.match(/^\*?\s*([\w-]+):$/)).filter(Boolean)
        .map(([, name]) => ({ label: name.replace(/(^|-)(\w)/g, (_, dash, c) => (dash ? " " : "") + c.toUpperCase()), value: name })),
```

Snapshot case `case "powerprofile": value = (await execAsync(["powerprofilesctl", "get"])).trim(); break`; change case `case "powerprofile": return execAsync(["powerprofilesctl", "set", value])`.

In `idleValues`, add inside the loop `if (/systemctl suspend/.test(block)) values.suspend = Number(timeout[1])`, and after the loop's existing lock/dpms check add `values.suspend ??= 0`. Add:

```js
// The panel owns only the listener it wrote, found by its marker comment.
const suspendBlock = /\n*# Suspend after inactivity\nlistener\s*\{[^}]*systemctl suspend[^}]*\}\n?/
function withSuspend(text, seconds) {
    const existing = (text.match(/listener\s*\{[^}]*\}/g) || []).find(block => block.includes("systemctl suspend"))
    if (existing && seconds) return text.replace(existing, existing.replace(/(\btimeout\s*=\s*)\d+/, `$1${seconds}`))
    if (existing) {
        if (!suspendBlock.test(text)) throw new Error("hypridle.conf has a custom suspend listener; remove it by hand")
        return text.replace(suspendBlock, "\n")
    }
    if (!seconds) return text
    return text.replace(/\n*$/, "\n") + `\n# Suspend after inactivity\nlistener {\n    timeout = ${seconds}\n    on-timeout = systemctl suspend\n}\n`
}
```

In the `idle` change case, handle `suspend` right after the existing `idleValues(before)` sanity check:

```js
        if (row.key === "suspend") return saveAndApply(idlePath, withSuspend(before, value), () => restart("hypridle"))
```

Rows, in Power after `power.dpms`:

```json
    { "category": "power", "id": "power.profile", "title": "Power Profile", "description": "Performance, balanced or power saving", "keywords": ["battery", "cpu"], "source": "powerprofile", "kind": "select", "choices": "power-profiles" },
    { "category": "power", "id": "power.suspend", "title": "Suspend After", "description": "Sleep after this long idle; the lock screen engages first", "keywords": ["sleep"], "source": "idle", "key": "suspend", "kind": "slider", "min": 0, "max": 7200, "step": 60, "format": "duration", "zeroLabel": "Never" },
```

- [ ] **Step 3: Run, verify live, commit.**

```bash
git add quickshell/settings-panel/
git commit -m "feat(settings): power profile and optional automatic suspend

hypridle never suspended the machine. The panel adds, retimes and removes
only the listener it marked, and never touches a hand-written one."
```

---

### Task 9: Clear clipboard history from Super+C

**Goal:** The clipboard picker gets a "Clear history" entry with a confirmation. This lives in the existing menu, not the panel.

**Files:**
- Create: `rofi/clipboard.sh`, `rofi/test-clipboard.sh`
- Modify: `hypr/config/software/keybinds.lua:34`

**Acceptance Criteria:**
- [ ] Choosing a history line copies it exactly as before (`cliphist decode | wl-copy`)
- [ ] Choosing Clear history and then Yes runs `cliphist wipe`; No, or Escape at either prompt, changes nothing
- [ ] Glyphs are written as escapes, not pasted
- [ ] `rofi/test-clipboard.sh` passes and is discovered by `./test.sh --list`; the keybind label and `docs/keybindings.md` are unchanged

**Verify:** `bash rofi/test-clipboard.sh` → pass; `./test.sh` → pass; `./doctor.sh | rg -A1 Binaries` → `✓`

**Steps:**

- [ ] **Step 1: Failing test.** Create `rofi/test-clipboard.sh`. It puts stub `rofi`, `cliphist` and `wl-copy` on `PATH`; each appends its arguments and stdin to `$tmp/log`, and `rofi` answers with the next line of `$tmp/answers`. Get the clear entry's exact text with `CLIPBOARD_PRINT_CLEAR=1 bash rofi/clipboard.sh`, so the test holds no copy of the glyph. Cases:
  1. Answer a history line `1<TAB>hello` → log shows `cliphist decode` receiving `1<TAB>hello` and a `wl-copy` call.
  2. Answers `<clear entry>` then the Yes entry → log shows `cliphist wipe`.
  3. Answers `<clear entry>` then the No entry → no `wipe`, no `wl-copy`.
  4. Empty answer → nothing but `cliphist list`.

  Use `scripts/lib/assert.sh`, as in Task 4. Run → fails (script missing).

- [ ] **Step 2: Implement `rofi/clipboard.sh`.**

```bash
#!/usr/bin/env bash
#
# Clipboard History
# Pick an entry to copy it again, or clear the whole history.
#
# cliphist lines always start with a numeric id and a tab, so the clear entry
# can never collide with one.
#

# Nerd Font glyphs, escaped so no editor can silently drop them.
clear=$''"  Clear history"
yes=$''" Yes" no=$''" No"

if [ -n "${CLIPBOARD_PRINT_CLEAR:-}" ]; then printf '%s\n%s\n%s\n' "$clear" "$yes" "$no"; exit 0; fi

chosen=$({ printf '%s\n' "$clear"; cliphist list; } | rofi -dmenu -p "Clipboard")
[ -n "$chosen" ] || exit 0

if [ "$chosen" = "$clear" ]; then
    answer=$(printf '%s\n' "$yes" "$no" | rofi -dmenu -p "Clear clipboard history?")
    [ "$answer" = "$yes" ] && cliphist wipe
    exit 0
fi

printf '%s\n' "$chosen" | cliphist decode | wl-copy
```

`chmod +x rofi/clipboard.sh`. In `keybinds.lua:34` use `hl.dsp.exec_cmd("$HOME/.config/rofi/clipboard.sh")) -- Clipboard history`.

- [ ] **Step 3: Check it live.** Run `hyprctl reload`, press Super+C and pick an older entry, then paste it. Press Super+C again, pick Clear history, then No, and confirm `cliphist list | wc -l` is unchanged. **Do not choose Yes** unless the user agrees to lose their history.

- [ ] **Step 4: Commit.**

```bash
git add rofi/clipboard.sh rofi/test-clipboard.sh hypr/config/software/keybinds.lua
git commit -m "feat(rofi): clear clipboard history from the Super+C picker"
```

---

### Task 10: Docs, smoke test, live pass and review

**Goal:** The docs match the new panel, the live smoke test survives catalog growth, every new row is checked in the running panel, and the whole round gets an independent review.

**Files:**
- Modify: `quickshell/settings-panel/test/live-smoke.sh` (the `.rows == 14` check)
- Modify: `docs/settings-panel.md`, `CLAUDE.md` (setting and category counts, new sources)

**Acceptance Criteria:**
- [ ] `live-smoke.sh` derives the expected Appearance row count from `catalog.json` and passes
- [ ] `CLAUDE.md` and `docs/settings-panel.md` state the counts from `jq '.rows|length, (.categories|length)' catalog.json`, and briefly describe `choices`, the `gtk`/`kvantum`/`mime`/`powerprofile` sources, the XKB/font/command checks, and that GTK values go to gsettings and both `settings.ini` files
- [ ] Screenshots of every category show no row errors and no dropdown taller than the panel
- [ ] A full read is still fast: record `time panel-request.sh` for all ids (it was 0.07 s before Task 1) and note it in `docs/settings-panel.md`
- [ ] `./test.sh` and `./doctor.sh` pass; `git status` is clean except intended files
- [ ] `delegate-review` has run on `git diff 792ec88..HEAD`, and verified findings are fixed or reported

**Verify:** `bash quickshell/settings-panel/test/live-smoke.sh` → `All N settings read successfully`; `./test.sh` → all pass; `./doctor.sh` → exit 0

**Steps:**

- [ ] **Step 1: Smoke test.** In `live-smoke.sh`, before the loop add:

```bash
appearance_rows=$(jq '[.rows[] | select(.category == "appearance")] | length' "$config_dir/quickshell/settings-panel/catalog.json")
```

and change the check to `jq -e --argjson rows "$appearance_rows" '.error == "" and (.rowErrors | length) == 0 and .rows == $rows' <<< "$status"`.

- [ ] **Step 2: Docs.** Update the counts and add the source descriptions listed in the Acceptance Criteria, matching the existing prose style: short paragraphs, gotchas stated as facts. Record in `docs/settings-panel.md` that the legacy `tap-to-click` name is rejected by the Lua provider, and that `getoption`'s `set` field is not a value.

- [ ] **Step 3: Live pass.** Close the panel, run `live-smoke.sh`, then open Super+I and screenshot each category with `grim /tmp/settings-<category>.png`. Read the screenshots. Check that no row shows an error, that dropdowns stay inside the panel, and that "Never" appears on Hide Idle Cursor and Suspend After.

- [ ] **Step 4: Review.** Invoke the `delegate-review` skill with the goal, this plan's acceptance criteria and `git diff 792ec88..HEAD`. Verify each finding yourself, fix the confirmed ones with a test, and re-run `./test.sh`.

- [ ] **Step 5: Commit.**

```bash
git add quickshell/settings-panel/test/live-smoke.sh docs/settings-panel.md CLAUDE.md
git commit -m "docs(settings): round 1 sources, counts and checks"
```
