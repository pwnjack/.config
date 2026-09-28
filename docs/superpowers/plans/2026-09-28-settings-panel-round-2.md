# Settings Panel Round 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native Sound page (default output/input device, port, card profile, mic level) and make the Displays page editable with apply-and-revert. The Displays page replaces `scripts/settings/advanced/monitor.sh` and stops machine-specific lines landing in the tracked `monitor.lua`. The idle system gains no process or resource cost.

**Architecture:**
- **Sound** is six ordinary catalog rows on a new `pulse` source (`pulse.js`). They share one set of four parallel `pactl -f json` reads per request, through the snapshot's `once()` cache.
- **Live refresh** runs only while a live-tagged row or the Displays page is on screen. `shell.qml` runs `pactl subscribe` and listens to `Hyprland.rawEvent`, then does single-flight, debounced reads of just those rows.
- **Displays** are cards backed by pure helpers in `displays.mjs`, shared by GJS, QML and Node. Per-machine config lives in the untracked `~/.local/state/hypr/monitors.lua`, which the tracked `monitor.lua` loads if present.
- **Apply** arms a `systemd-run --user` timer that runs `hyprctl reload`, then `hyprctl eval`s the new rule. Keep writes the same line to the state file. Revert, timeout, closing the panel or a crash all end in a reload of the unchanged file.

**Tech Stack:** GJS (`gi://Gio`, `gi://GLib`), Quickshell/QML (Qt 6, `Quickshell.Io`, `Quickshell.Hyprland`), ES modules (`.mjs`, importable by GJS, QML and Node), bash, Node for backend unit tests (`node:assert`), `qmltestrunner` for UI tests, `pactl` (PipeWire's pulse server), `systemd-run`.

**Spec:** `docs/superpowers/specs/2026-09-28-settings-panel-round-2-design.md`. Read it first. It lists the verified facts every task relies on.

---

## Context the engineer needs

- **Branch first.** `main` is the default branch. Run `git switch -c settings-panel-round-2` before Task 1. Round 1 is merged at `b6ca971`, which is the review base in Task 8.
- **Run all tests:** `./test.sh` from `~/.config`. The panel suite is `quickshell/settings-panel/test/run-tests.sh`: QML tests (`tst_Settings.qml`), then `persist.mjs`, then `backend.mjs`, plus the new `displays.mjs` added in Task 4. `backend.mjs` runs the real `backend.js` against in-memory mocks of Gio, GLib and `execAsync`. **Every backend change gets a case in `backend.mjs`.**
- **Talk to the real backend without the UI:** `bash scripts/settings/panel-request.sh '<json>'`. Reads are side-effect free.
- **Drive the panel from a shell:** `qs -p ~/.config/quickshell/settings-panel/shell.qml ipc call settings status`. Task 3 adds `ipc call settings page <category>`.
- **The pre-commit hook** runs shellcheck plus the suites that own the staged paths. Never bypass it.
- **Nothing may become a second source of truth** (see `CLAUDE.md` → Conventions). The catalog is the only list of settings. Live refresh derives its ids from rows' `live` tag; display choices come from `hyprctl` and `displays.mjs`.
- **PipeWire trap (verified):** `pactl -f json list sinks` reports `"card": null` for every sink. A sink's card is `sink.properties["device.name"]`, which equals the card's `name`.
- **`pactl subscribe` is chatty (verified):** a `notify-send` alone emits `Event 'change' on client`. Only `sink`, `source`, `card` and `server` events matter, and `sink-input #3` must not match `sink`.
- **Hyprland Lua (verified):** `hl.monitor` keys are `output`, `mode`, `position`, `scale`, `transform` and `disabled`. `dofile`, `io.open`, `pcall` and `os.getenv` all work, and `XDG_STATE_HOME` is set in Hyprland's environment. `hyprctl eval` prints `ok`, or `error: …`, which `checkedHyprctl` already turns into an exception.
- **`.mjs` loads everywhere (verified):** `import { f } from "./m.mjs"` works under `gjs -m`, and `import "m.mjs" as M` works in QML.
- **Performance is the first priority.** Nothing new may run while the panel is closed, and nothing new runs while it is open unless a Sound row or the Displays page is on screen. Task 8 measures this.
- **Measured on this machine:** each `pactl -f json` call takes about 4 ms (all four in parallel, 6 ms); `hyprctl monitors all -j` takes 3 ms; a full panel read takes about 280 ms (re-measured in Task 1).
- **Before any live Apply or synthetic input**, check the session isn't locked: `pgrep -x hyprlock` must print nothing.
- **Glyphs in shell scripts** must be written as `$'\uXXXX'` escapes, never pasted.

## What is deliberately NOT in this plan

- Output volume, mute and per-app volume (the SwayNC sidebar and Waybar own them).
- Per-monitor VRR (the global `monitors.vrr` row stays), mirroring, bit depth, HDR/colour management.
- A doctor check for stale state-file outputs.
- **Recorded follow-up:** the File Types rows fork `xdg-mime` nine times per full read, which accounts for most of the ~280 ms open cost. It is not fixed here.

## File map

| File | Responsibility | Tasks |
|---|---|---|
| `docs/settings-panel.md` | Probe results, Sound/Displays sections, measurements | 1, 8 |
| new `quickshell/settings-panel/pulse.js` | PipeWire reads, choices and writes | 2 |
| `quickshell/settings-panel/backend.js` | `pulse` source; `onceCache`; display read/apply/keep/revert; `displays-file` action; `monitors` action removed | 2, 6, 7 |
| `quickshell/settings-panel/catalog.json` | `sound` category and six rows; `monitors` retitled Displays | 2, 7 |
| `quickshell/settings-panel/SettingControl.qml` | `percent` format; `interacting`; select becomes `PanelCombo` | 2, 3, 7 |
| `quickshell/settings-panel/shell.qml` | Live tags, `pactl subscribe`, `rawEvent`, live reads, `show` IPC, pending display, revert on close | 3, 7 |
| new `quickshell/settings-panel/displays.mjs` | Pure display helpers | 4 |
| new `quickshell/settings-panel/test/displays.mjs` | Tests for the helpers | 4 |
| `quickshell/settings-panel/test/run-tests.sh` | Runs `displays.mjs` | 4 |
| `hypr/config/hardware/monitor.lua` | Loads the per-machine state file | 5 |
| new `quickshell/settings-panel/PanelCombo.qml` | The shared themed dropdown | 7 |
| new `quickshell/settings-panel/DisplayCard.qml` | One output, staged edits | 7 |
| `quickshell/settings-panel/SettingsView.qml` | Cards, pending banner and countdown, Edit file | 7 |
| `quickshell/settings-panel/test/backend.mjs`, `test/tst_Settings.qml` | Tests | 2, 3, 6, 7 |
| delete `scripts/settings/advanced/monitor.sh`; `README.md`; `scripts/doctor/checks/references.sh` | Retire the wizard | 7 |
| `quickshell/settings-panel/test/live-smoke.sh`, `CLAUDE.md` | Smoke test, docs | 8 |

---

### Task 1: Probe live display behaviour and record the baseline

**Goal:** Confirm on the real display, before building anything, that `hyprctl eval` applies a per-output rule immediately, that `hyprctl reload` restores the file's rule, how Hyprland treats scales, and that a `systemd-run` guard reverts on its own. Also record the baseline full-read time.

**Background:** These are the only design assumptions that could not be checked without a visible display change. The screen will switch between 144 Hz and 120 Hz for a second at a time. Every probe is wrapped in a guard that reloads within 20 s, even if the shell running it dies.

**Files:**
- Modify: `docs/settings-panel.md` (new section `## Displays: verified behaviour`)

**Acceptance Criteria:**
- [ ] `hyprctl eval 'hl.monitor({ output = "DP-1", mode = "2560x1440@120.00", position = "auto", scale = 1, transform = 0 })'` prints `ok`, and within 1 s `hyprctl monitors -j | jq '.[0].refreshRate'` is about 120
- [ ] `hyprctl reload` then brings `refreshRate` back to about 144
- [ ] A guard armed with `--on-active=5` reverts an applied 120 Hz mode by itself, and afterwards `systemctl --user list-units 'settings-display-*' --all --no-legend` prints nothing
- [ ] The results of `scale = 1.25`, `scale = 1.3333333333333333` (160/120 as a full double) and `scale = 1.5` are recorded: accepted as-is, adjusted, or rejected, with the exact `hyprctl monitors` scale and any notification
- [ ] The median of five full reads is recorded as the round-2 baseline
- [ ] **If eval does not apply live, or reload does not restore 144 Hz: stop and report to the user.** The revert design depends on both.

**Verify:** The new section in `docs/settings-panel.md` states each result with the command that produced it, and `hyprctl monitors -j | jq -c '.[0]|{refreshRate,scale}'` → about `144` and `1` at the end.

**Steps:**

- [ ] **Step 1: Baseline.** Close the panel, then run:

```bash
req=$(jq -c '{op:"read",ids:[.rows[].id],monitors:true}' quickshell/settings-panel/catalog.json)
for i in 1 2 3 4 5; do s=$(date +%s%N); bash scripts/settings/panel-request.sh "$req" >/dev/null; echo $(( ($(date +%s%N)-s)/1000000 )) ms; done
```

Note the median.

- [ ] **Step 2: Eval and reload.** Arm a guard first. The probe has its own unit name, so it can never collide with the panel's.

```bash
hyprctl monitors -j | jq -c '.[0]|{name,refreshRate,scale}'          # expect DP-1, 144, 1
systemd-run --user --collect --unit=settings-display-probe --on-active=20 --timer-property=AccuracySec=100ms "$(command -v hyprctl)" reload
hyprctl eval 'hl.monitor({ output = "DP-1", mode = "2560x1440@120.00", position = "auto", scale = 1, transform = 0 })'
sleep 1; hyprctl monitors -j | jq '.[0].refreshRate'                  # expect ~120
hyprctl reload; sleep 1; hyprctl monitors -j | jq '.[0].refreshRate'  # expect ~144
systemctl --user stop settings-display-probe.timer
```

- [ ] **Step 3: The guard reverts by itself.**

```bash
systemd-run --user --collect --unit=settings-display-probe --on-active=5 --timer-property=AccuracySec=100ms "$(command -v hyprctl)" reload
hyprctl eval 'hl.monitor({ output = "DP-1", mode = "2560x1440@120.00", position = "auto", scale = 1, transform = 0 })'
sleep 7; hyprctl monitors -j | jq '.[0].refreshRate'                  # expect ~144
systemctl --user list-units 'settings-display-*' --all --no-legend    # expect nothing
```

- [ ] **Step 4: Scales.** For each of `1.25`, `1.3333333333333333` and `1.5`, arm the 20 s guard, eval `hl.monitor({ output = "DP-1", mode = "2560x1440@144.00", position = "auto", scale = <S>, transform = 0 })`, then record the eval reply, `hyprctl monitors -j | jq '.[0].scale'`, and whether a Hyprland notification appeared. Run `hyprctl reload` and `systemctl --user stop settings-display-probe.timer` after each.

  `displays.mjs` (Task 4) offers only `k/120` scales that give a whole logical size, and writes each as a full double. If Hyprland rejects or changes `1.3333333333333333`, record it here. Task 4's `scaleChoices` must then also require `k/120` to be exact in binary (the numerator's odd part must divide 15), and its test list must change to match.

- [ ] **Step 5: Record.** Add to `docs/settings-panel.md`, before `## Measurements`:

```markdown
## Displays: verified behaviour

Probed on DP-1 (ROG PG279Q, 2560×1440) with Hyprland 0.56.2 on 2026-09-28.
Each probe ran under a `systemd-run --user` guard that reloaded after 20 s.

- `hyprctl eval 'hl.monitor({ output = "DP-1", ... })'` applies at once
  (144 → 120 Hz within 1 s); `hyprctl reload` restores the configured rule.
- A transient timer (`--on-active=5 --collect`) reverted by itself and left
  no unit behind.
- Scales: 1.25 → RESULT; 1.3333333333333333 → RESULT; 1.5 → RESULT.
- Full read of every row before round 2: MEDIAN ms (five runs).
```

Replace each `RESULT` and `MEDIAN` with the observed values before committing.

- [ ] **Step 6: Commit.**

```bash
git add docs/settings-panel.md
git commit -m "docs(settings): verify live monitor eval, reload revert and scale handling"
```

---

### Task 2: Sound rows on a `pulse` source

**Goal:** A Sound category with six rows (output device, output port, output profile, input device, input port, mic level). They read four `pactl -f json` calls once per request, offer only usable choices and follow the current default device.

**Files:**
- Create: `quickshell/settings-panel/pulse.js`
- Modify: `quickshell/settings-panel/backend.js` (`onceCache`, `choicesFor`/`validate` take `once`, `pulse` source cases)
- Modify: `quickshell/settings-panel/catalog.json` (category `sound`, six rows)
- Modify: `quickshell/settings-panel/SettingControl.qml` (`format: "percent"`)
- Test: `quickshell/settings-panel/test/backend.mjs`, `quickshell/settings-panel/test/tst_Settings.qml`

**Acceptance Criteria:**
- [ ] A read of all six sound rows makes exactly four `pactl` calls
- [ ] Output ports exclude `not available` ones, except the active one; profiles exclude `off` and unavailable ones, except the active one; inputs exclude sink monitors
- [ ] Setting an unavailable port, `off`, a monitor source or level 150 is rejected before any `pactl set-*`; `reset` on a sound row is rejected
- [ ] Writes run `set-card-profile <card of default sink>`, `set-source-volume <default source> N%` and `set-default-sink`
- [ ] After changing the default sink, the port and profile rows describe the new sink's port and card
- [ ] With no default source, the input rows each carry `error: "No input device"` while the output rows still read
- [ ] A slider with `format: "percent"` shows `62 %`
- [ ] Live: all six rows read without `error`; Output Port lists `Headphones` but not `Line Out`; Input Device does not list any `Monitor of …`

**Verify:** `bash quickshell/settings-panel/test/run-tests.sh` → all pass. Then `bash scripts/settings/panel-request.sh "$(jq -c '{op:"read",ids:[.rows[]|select(.category=="sound")|.id]}' quickshell/settings-panel/catalog.json)" | jq -c '.values|map_values({value,error,choices:((.choices // [])|map(.label))})'` → six values, no `error`.

**Steps:**

- [ ] **Step 1: Mocks and failing test.** In `backend.mjs`, next to the other fixtures, add these shapes, trimmed from this machine's `pactl -f json` output:

```js
// Trimmed from `pactl -f json` on PipeWire 1.6.9. Note `card` is null on the
// real sinks: the card is linked through properties["device.name"].
const pulse = {
    info: {default_sink_name:'alsa_output.analog', default_source_name:'alsa_input.analog'},
    sinks: [
        {name:'alsa_output.analog',description:'Built-in Audio Analog Stereo',card:null,active_port:'analog-output-headphones',properties:{'device.name':'alsa_card.analog'},
         ports:[{name:'analog-output-lineout',description:'Line Out',availability:'not available'},{name:'analog-output-headphones',description:'Headphones',availability:'available'}]},
        {name:'alsa_output.hdmi',description:'GA102 Digital Stereo (HDMI)',card:null,active_port:'hdmi-output-0',properties:{'device.name':'alsa_card.hdmi'},
         ports:[{name:'hdmi-output-0',description:'HDMI / DisplayPort',availability:'available'}]},
    ],
    sources: [
        {name:'alsa_output.analog.monitor',description:'Monitor of Built-in Audio Analog Stereo',monitor_source:'alsa_output.analog',active_port:'analog-output-headphones',ports:[],volume:{}},
        {name:'alsa_input.analog',description:'Built-in Audio Analog Stereo',monitor_source:'',active_port:'analog-input-front-mic',
         ports:[{name:'analog-input-front-mic',description:'Front Microphone',availability:'not available'},{name:'analog-input-rear-mic',description:'Rear Microphone',availability:'not available'}],
         volume:{'front-left':{value_percent:'60%'},'front-right':{value_percent:'64%'}}},
    ],
    cards: [
        {name:'alsa_card.analog',active_profile:'output:analog-stereo+input:analog-stereo',profiles:{
            off:{description:'Off',available:true},
            'output:analog-stereo+input:analog-stereo':{description:'Analog Stereo Duplex',available:true},
            'output:analog-surround-51':{description:'Analog Surround 5.1 Output',available:false},
            'output:iec958-stereo':{description:'Digital Stereo (IEC958) Output',available:true}}},
        {name:'alsa_card.hdmi',active_profile:'output:hdmi-stereo',profiles:{'output:hdmi-stereo':{description:'Digital Stereo (HDMI) Output',available:true}}},
    ],
}
```

In `execAsync`, before the final `return 'ok'`:

```js
        if (args[0] === 'pactl' && args[1] === '-f') return JSON.stringify(args[3] === 'info' ? pulse.info : pulse[args[4]])
        if (args[0] === 'pactl') {
            if (args[1] === 'set-default-sink') pulse.info.default_sink_name = args[2]
            return ''
        }
```

Append the test:

```js
events=[]
result = await dispatch({op:'read',ids:catalog.rows.filter(r=>r.source==='pulse').map(r=>r.id)})
assert.equal(events.filter(e=>e[0]==='pactl').length,4)
const sound = id => result.values['sound.'+id]
assert.equal(sound('output').value,'alsa_output.analog')
assert.deepEqual(sound('output').choices.map(c=>c.value),['alsa_output.analog','alsa_output.hdmi'])
assert.deepEqual(sound('output-port').choices.map(c=>c.label),['Headphones'])
assert.deepEqual(sound('output-profile').choices.map(c=>c.value),['output:analog-stereo+input:analog-stereo','output:iec958-stereo'])
assert.deepEqual(sound('input').choices.map(c=>c.value),['alsa_input.analog'])
assert.deepEqual(sound('input-port').choices.map(c=>c.value),['analog-input-front-mic'])
assert.equal(sound('mic-level').value,62)
events=[]
await assert.rejects(dispatch({op:'set',id:'sound.output-port',value:'analog-output-lineout'}),/Unknown choice/)
await assert.rejects(dispatch({op:'set',id:'sound.output-profile',value:'off'}),/Unknown choice/)
await assert.rejects(dispatch({op:'set',id:'sound.input',value:'alsa_output.analog.monitor'}),/Unknown choice/)
await assert.rejects(dispatch({op:'set',id:'sound.mic-level',value:150}),/outside/)
await assert.rejects(dispatch({op:'reset',id:'sound.output'}),/no reset/)
assert.equal(events.some(e=>e[0]==='pactl' && e[1].startsWith('set-')),false)
await dispatch({op:'set',id:'sound.output-profile',value:'output:iec958-stereo'})
await dispatch({op:'set',id:'sound.mic-level',value:40})
await dispatch({op:'set',id:'sound.output',value:'alsa_output.hdmi'})
assert.deepEqual(events.filter(e=>e[0]==='pactl' && e[1].startsWith('set-')).map(e=>e.slice(1)),[
    ['set-card-profile','alsa_card.analog','output:iec958-stereo'],
    ['set-source-volume','alsa_input.analog','40%'],
    ['set-default-sink','alsa_output.hdmi'],
])
result = await dispatch({op:'read',ids:['sound.output-port','sound.output-profile']})
assert.equal(result.values['sound.output-port'].value,'hdmi-output-0')
assert.equal(result.values['sound.output-profile'].value,'output:hdmi-stereo')
pulse.info.default_sink_name = 'alsa_output.analog'
const savedSource = pulse.info.default_source_name
pulse.info.default_source_name = ''
result = await dispatch({op:'read',ids:['sound.input','sound.mic-level','sound.output']})
assert.match(result.values['sound.input'].error,/No input device/)
assert.match(result.values['sound.mic-level'].error,/No input device/)
assert.equal(result.values['sound.output'].value,'alsa_output.analog')
pulse.info.default_source_name = savedSource
console.log('ok: sound rows share four pactl reads, offer only usable choices and follow the default device')
```

Run `node quickshell/settings-panel/test/backend.mjs` → fails (the `sound.*` rows don't exist yet).

- [ ] **Step 2: `pulse.js`.**

```js
import { execAsync } from "./process.js"

// Four reads describe every sound row. The backend's once() cache shares one
// result per request; each read is ~4 ms and they run in parallel.
export async function pulseState() {
    const [info, sinks, sources, cards] = await Promise.all([["info"], ["list", "sinks"], ["list", "sources"], ["list", "cards"]]
        .map(async args => JSON.parse(await execAsync(["pactl", "-f", "json", ...args]))))
    return { info, sinks, sources, cards }
}
// Sink monitors are sources too; only real inputs have no monitor_source.
const inputs = state => state.sources.filter(source => !source.monitor_source)
function defaultOf(list, name, what) {
    const device = list.find(device => device.name === name)
    if (!device) throw new Error(`No ${what} device`)
    return device
}
const output = state => defaultOf(state.sinks, state.info.default_sink_name, "output")
const input = state => defaultOf(inputs(state), state.info.default_source_name, "input")
// PipeWire's pulse server reports `card: null`; the card is named in properties.
function cardOf(state, sink) {
    const card = state.cards.find(card => card.name === sink.properties?.["device.name"])
    if (!card) throw new Error("The output device has no card profiles")
    return card
}
const devices = list => list.map(device => ({ label: device.description, value: device.name }))
// A "not available" port has nothing plugged in. The active one is always kept.
function ports(device) {
    if (!device.ports.length) throw new Error("This device has no ports")
    return device.ports.filter(port => port.availability !== "not available" || port.name === device.active_port)
        .map(port => ({ label: port.description, value: port.name }))
}
// "off" would remove the very device these rows describe.
const profiles = card => Object.entries(card.profiles)
    .filter(([name, profile]) => name === card.active_profile || (profile.available && name !== "off"))
    .map(([name, profile]) => ({ label: profile.description, value: name }))

const shared = once => once("pulse", pulseState)
export const pulseEnumerators = {
    "audio-outputs": async (_row, _current, once) => devices((await shared(once)).sinks),
    "audio-inputs": async (_row, _current, once) => devices(inputs(await shared(once))),
    "output-ports": async (_row, _current, once) => ports(output(await shared(once))),
    "input-ports": async (_row, _current, once) => ports(input(await shared(once))),
    "output-profiles": async (_row, _current, once) => { const state = await shared(once); return profiles(cardOf(state, output(state))) },
}
export function pulseValue(key, state) {
    switch (key) {
    case "output": return output(state).name
    case "output-port": return output(state).active_port
    case "output-profile": return cardOf(state, output(state)).active_profile
    case "input": return input(state).name
    case "input-port": return input(state).active_port
    case "mic-level": {
        const channels = Object.values(input(state).volume)
        return Math.round(channels.reduce((sum, channel) => sum + parseFloat(channel.value_percent), 0) / channels.length)
    }
    }
    throw new Error("Unknown sound setting")
}
export async function setPulse(key, value, state) {
    const command = {
        output: () => ["set-default-sink", value],
        "output-port": () => ["set-sink-port", output(state).name, value],
        "output-profile": () => ["set-card-profile", cardOf(state, output(state)).name, value],
        input: () => ["set-default-source", value],
        "input-port": () => ["set-source-port", input(state).name, value],
        "mic-level": () => ["set-source-volume", input(state).name, `${value}%`],
    }[key]
    if (!command) throw new Error("Unknown sound setting")
    await execAsync(["pactl", ...command()])
}
```

- [ ] **Step 3: Wire it into `backend.js`.**
  - Import: `import { pulseState, pulseValue, pulseEnumerators, setPulse } from "./pulse.js"`.
  - Spread the enumerators into `enumerators`: add `...pulseEnumerators,` as its last entry.
  - Lift the snapshot's cache into a reusable factory above `snapshot`:

```js
// One cache per request: rows that share a source share its reads.
function onceCache() {
    const cached = new Map()
    return (key, fn) => {
        if (!cached.has(key)) cached.set(key, Promise.resolve().then(fn))
        return cached.get(key)
    }
}
```

  In `snapshot`, replace the inline `cached`/`once` definitions and their comment with `const once = onceCache()`.
  - `choicesFor` passes the cache on: `async function choicesFor(row, current, once = onceCache())`, calling `enumerators[row.choices](row, current, once)`. In `snapshot` use `choicesFor(row, value, once)`.
  - `async function validate(row, value, once = onceCache())`, and its select line uses `choicesFor(row, undefined, once)`.
  - In `change`: add `const once = onceCache()` just before `await validate(...)`, call `await validate(row, value, once)`, and add to the switch `case "pulse": return setPulse(row.key, value, await once("pulse", pulseState))`.
  - In `snapshot`'s switch: `case "pulse": value = pulseValue(row.key, await once("pulse", pulseState)); break`.

- [ ] **Step 4: Catalog.** Insert the category after `accessibility`:

```json
    { "id": "sound", "title": "Sound", "description": "Devices, ports and microphone level. Volume lives in the notification sidebar." },
```

and, after the last `accessibility` row:

```json
    { "category": "sound", "id": "sound.output", "title": "Output Device", "description": "Where sound plays", "keywords": ["speakers", "headphones", "audio"], "source": "pulse", "key": "output", "kind": "select", "choices": "audio-outputs", "live": "audio" },
    { "category": "sound", "id": "sound.output-port", "title": "Output Port", "description": "Connector on the output device, e.g. headphones or line out", "keywords": ["jack", "headphones", "speakers"], "source": "pulse", "key": "output-port", "kind": "select", "choices": "output-ports", "live": "audio" },
    { "category": "sound", "id": "sound.output-profile", "title": "Output Profile", "description": "Channel layout of the output device's card", "keywords": ["surround", "stereo", "hdmi"], "source": "pulse", "key": "output-profile", "kind": "select", "choices": "output-profiles", "live": "audio" },
    { "category": "sound", "id": "sound.input", "title": "Input Device", "description": "Microphone that apps record from", "keywords": ["microphone", "mic", "recording"], "source": "pulse", "key": "input", "kind": "select", "choices": "audio-inputs", "live": "audio" },
    { "category": "sound", "id": "sound.input-port", "title": "Input Port", "description": "Connector on the input device", "keywords": ["microphone", "mic", "jack"], "source": "pulse", "key": "input-port", "kind": "select", "choices": "input-ports", "live": "audio" },
    { "category": "sound", "id": "sound.mic-level", "title": "Microphone Level", "description": "Recording volume of the input device", "keywords": ["microphone", "mic", "gain"], "source": "pulse", "key": "mic-level", "kind": "slider", "min": 0, "max": 100, "step": 1, "format": "percent", "live": "audio" },
```

Reformat, keeping the existing style: `jq . quickshell/settings-panel/catalog.json > /tmp/claude-1000/catalog.json && mv /tmp/claude-1000/catalog.json quickshell/settings-panel/catalog.json`. Check that `git diff` shows only additions.

- [ ] **Step 5: Percent label.** In `SettingControl.qml` `formatted(value)`, add after the `seconds` line:

```qml
        if (row.format === "percent") return Math.round(value) + " %";
```

In `tst_Settings.qml`, add the row `{id:"mic",category:"input",title:"Mic",description:"Level",kind:"slider",min:0,max:100,step:1,format:"percent"}` and `mic:{value:62}` to **both** `values` literals (the property and `init()`), and add:

```qml
        function test_percent_format() {
            controller.select("input"); wait(20);
            const slider = findChild(view,"slider-mic");
            verify(slider);
            compare(slider.parent.children[1].text,"62 %");
        }
```

- [ ] **Step 6: Run and verify live.** Run both Verify commands. Then set the output port to the value it already has, which proves the write path without changing anything audible:

```bash
bash scripts/settings/panel-request.sh '{"op":"set","id":"sound.output-port","value":"analog-output-headphones"}'   # → {"ok":true}
```

- [ ] **Step 7: Commit.**

```bash
git add quickshell/settings-panel/
git commit -m "feat(settings): Sound page for devices, ports, card profile and mic level

Four parallel pactl reads serve every sound row. Choices hide unplugged
ports, the card's off profile and sink monitors, and PipeWire's null
sink.card is resolved through device.name."
```

---

### Task 3: Live refresh while a live page is on screen

**Goal:** Sound rows and Displays cards follow device changes while visible. `pactl subscribe` and the Hyprland event handler exist only while those rows are on screen. Reads are single-flight, debounced and limited to the tagged rows, and never move a control the user is holding.

**Files:**
- Modify: `quickshell/settings-panel/shell.qml`
- Modify: `quickshell/settings-panel/SettingControl.qml` (report `interacting`)
- Test: `quickshell/settings-panel/test/tst_Settings.qml`

**Acceptance Criteria:**
- [ ] `liveTags` is derived from `visibleRows[].live`, plus `displays` on the unsearched Displays page; no id list exists in QML
- [ ] Only lines matching ` on (sink|source|card|server)( #|$)` mark `audio` dirty; `sink-input`/`client` lines do not
- [ ] Events while `busy` or while a full read runs are dropped
- [ ] At most one live read runs; events during it cause exactly one follow-up
- [ ] A live merge skips `controller.interacting`; pressing a slider sets it to the row id and releasing clears it; an open dropdown popup sets it too
- [ ] `ipc call settings status` reports `liveTags` and `liveReads`; `ipc call settings page <category>` switches the page
- [ ] Live: `pgrep -fa "pactl subscribe"` finds a process only while the Sound page is shown, and none after close; audio playback plus notifications cause 0 live reads, and one real default-sink change causes 1

**Verify:** `bash quickshell/settings-panel/test/run-tests.sh` → pass. Then the live sequence in Step 5.

**Steps:**

- [ ] **Step 1: Failing UI test.** In `tst_Settings.qml`, add `property string interacting: ""` to the mock controller and `controller.interacting = "";` to `init()`. Add:

```qml
        function test_slider_and_popup_report_interaction() {
            const slider = findChild(view,"slider-size");
            mousePress(slider, slider.width / 2, slider.height / 2);
            compare(controller.interacting,"size");
            mouseRelease(slider, slider.width / 2, slider.height / 2);
            compare(controller.interacting,"");
            const combo = findChild(view,"select-theme");
            mouseClick(combo);
            tryCompare(combo.popup,"visible",true);
            compare(controller.interacting,"theme");
            keyClick(Qt.Key_Escape);
            tryCompare(controller,"interacting","");
        }
```

Run the suite → fails (`interacting` stays `""`).

- [ ] **Step 2: Report interaction in `SettingControl.qml`.** In the slider's `onPressedChanged` handler, add as the first statement (keep the existing submit-on-release code after it):

```qml
                    control.controller.interacting = pressed ? control.row.id : "";
```

In the `ComboBox`, add:

```qml
            Connections {
                target: combo.popup
                function onVisibleChanged() { control.controller.interacting = combo.popup.visible ? control.row.id : ""; }
            }
```

Run → passes.

- [ ] **Step 3: Live machinery in `shell.qml`.** Add these properties after `property var monitors: []`:

```qml
    property string interacting: ""
    property var liveDirty: ({})
    property string liveReply: ""
    property int liveReads: 0
    // Only what is on screen is watched: no page, no subscription.
    readonly property var liveTags: {
        const tags = new Set(visibleRows.map(row => row.live).filter(Boolean));
        if (category === "monitors" && !query.trim()) tags.add("displays");
        return [...tags];
    }
```

and these functions after `refresh()`:

```qml
    function markLive(tag) {
        // A write refreshes everything afterwards, so its own echoes are not news.
        if (busy || reader.running || !liveTags.includes(tag)) return;
        liveDirty = Object.assign({}, liveDirty, {[tag]: true});
        liveTimer.restart();
    }
    function readLive() {
        const tags = Object.keys(liveDirty).filter(tag => liveTags.includes(tag));
        if (!tags.length || busy || closing) { liveDirty = ({}); return; }
        if (reader.running || liveReader.running) { liveTimer.restart(); return; }
        liveDirty = ({});
        liveReads += 1;
        const ids = catalog.rows.filter(row => tags.includes(row.live)).map(row => row.id);
        liveReply = "";
        liveReader.command = ["bash", configDir + "/scripts/settings/panel-request.sh", JSON.stringify({op: "read", ids: ids, monitors: tags.includes("displays")})];
        liveReader.running = true;
    }
```

In `drain()`, change the first line to `if (writer.running || reader.running || liveReader.running) return;`.

In `IpcHandler`, add:

```qml
        function page(category: string): void { root.select(category); }
```

and add `liveTags: root.liveTags, liveReads: root.liveReads,` to the object that `status()` stringifies.

Add the watchers and the reader before `PanelWindow`:

```qml
    Timer { id: liveTimer; interval: 300; onTriggered: root.readLive() }
    Process {
        id: audioEvents
        running: root.opened && root.liveTags.includes("audio")
        command: ["pactl", "subscribe"]
        // `sink-input #3` must not count as `sink`; clients and streams are noise.
        stdout: SplitParser { onRead: line => { if (/ on (sink|source|card|server)( #|$)/.test(line)) root.markLive("audio"); } }
    }
    Connections {
        target: Hyprland
        enabled: root.opened && root.liveTags.includes("displays")
        function onRawEvent(event) {
            if (["monitoradded", "monitoraddedv2", "monitorremoved", "monitorremovedv2", "configreloaded"].includes(event.name)) root.markLive("displays");
        }
    }
    Process {
        id: liveReader
        stdout: StdioCollector { onStreamFinished: root.liveReply = text }
        onExited: code => {
            try {
                const result = JSON.parse(root.liveReply);
                if (!result.ok) throw new Error(result.error);
                const values = Object.assign({}, result.values);
                // Never move a control under the user's hand.
                delete values[root.interacting];
                root.values = Object.assign({}, root.values, values);
                if (result.monitors) { root.monitors = result.monitors; root.mainMonitor = result.mainMonitor; }
            } catch (error) { console.warn("Live refresh failed: " + error); }
            if (Object.keys(root.liveDirty).length) liveTimer.restart();
            if (root.busy || root.closing) root.drain();
        }
    }
```

`drain()` on an empty queue sets `busy = false`, then refreshes or quits. The `busy || closing` call is what lets a write that queued behind a live read finish.

- [ ] **Step 4: Lint and run.** `/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml quickshell/settings-panel/*.qml` → only the three known Quickshell warnings (see `docs/settings-panel.md`). Run the suite.

- [ ] **Step 5: Live check.** Run `pgrep -x hyprlock` first; it must print nothing.

```bash
qs=(qs -p ~/.config/quickshell/settings-panel/shell.qml ipc call settings)
bash scripts/hyprland/settings-panel.sh; sleep 1
pgrep -fa "pactl subscribe" || echo none                 # → none (Appearance page)
"${qs[@]}" page sound; sleep 0.5
pgrep -fa "pactl subscribe"                              # → one process
before=$("${qs[@]}" status | jq .liveReads)
paplay /usr/share/sounds/freedesktop/stereo/complete.oga; for i in 1 2 3; do notify-send -t 500 probe; done; sleep 2
echo $(( $("${qs[@]}" status | jq .liveReads) - before ))  # → 0
sink=$(pactl get-default-sink); pactl set-default-sink alsa_output.pci-0000_01_00.1.hdmi-stereo; sleep 1
echo $(( $("${qs[@]}" status | jq .liveReads) - before ))  # → 1
pactl set-default-sink "$sink"; sleep 1
"${qs[@]}" page appearance; sleep 0.5
pgrep -fa "pactl subscribe" || echo none                 # → none
"${qs[@]}" close; sleep 1
pgrep -fa "pactl subscribe" || echo none                 # → none
```

Watching the open Sound page, the Output Device row switches to HDMI and back without the panel reopening.

- [ ] **Step 6: Commit.**

```bash
git add quickshell/settings-panel/
git commit -m "feat(settings): live refresh for rows on screen only

pactl subscribe runs only while a live-tagged row is visible and ignores
stream and client events, so playing audio costs no reads. Reads are
single-flight and never move a control the user is holding."
```

---

### Task 4: `displays.mjs` pure helpers

**Goal:** One module computes mode, scale, position and rotation choices, builds and parses the exact `hl.monitor()` line format, and edits the state file. GJS, QML and Node all import it.

**Files:**
- Create: `quickshell/settings-panel/displays.mjs`
- Create: `quickshell/settings-panel/test/displays.mjs`
- Modify: `quickshell/settings-panel/test/run-tests.sh` (add `node "$test_dir/displays.mjs"` as the last line)

**Acceptance Criteria:**
- [ ] `scaleChoices(2560, 1440)` labels are `100 %, 107 %, 125 %, 133 %, 160 %, 167 %, 200 %, 213 %, 250 %, 267 %`, with no `1.5` (or, if Task 1 recorded that inexact doubles are rejected, the list Task 1 prescribes)
- [ ] `modeChoices` puts `Automatic` (`highres@highrr`) first, then modes without `Hz`, labelled `2560 × 1440 · 144 Hz`
- [ ] `monitorLine` produces exactly `hl.monitor({ output = "DP-1", mode = "…", position = "…", scale = …, transform = … })` or `hl.monitor({ output = "…", disabled = true })`, and rejects an output or mode containing quotes or spaces
- [ ] `parseStateFile` returns `outputs` for panel-format lines and `handEdited` for any other line (`"*"` when the line names no output)
- [ ] Adding then removing a line with `stateFileWith` returns the original text byte for byte

**Verify:** `node quickshell/settings-panel/test/displays.mjs` → four `ok:` lines, exit 0; `bash quickshell/settings-panel/test/run-tests.sh` → pass.

**Steps:**

- [ ] **Step 1: Failing test.** Create `quickshell/settings-panel/test/displays.mjs`:

```js
import assert from 'node:assert/strict'
import * as displays from '../displays.mjs'

const pg279q = {name:'DP-1',width:2560,height:1440,availableModes:['2560x1440@59.95Hz','2560x1440@144.00Hz','1024x768@60.00Hz']}
assert.deepEqual(displays.modeChoices(pg279q).map(c=>c.value),['highres@highrr','2560x1440@59.95','2560x1440@144.00','1024x768@60.00'])
assert.equal(displays.modeChoices(pg279q)[2].label,'2560 × 1440 · 144 Hz')
assert.deepEqual(displays.modeChoices({availableModes:[]}).map(c=>c.value),['highres@highrr'])
assert.deepEqual(displays.modeSize('highres@highrr',pg279q),[2560,1440])
assert.deepEqual(displays.modeSize('1024x768@60.00',pg279q),[1024,768])
console.log('ok: modes list Automatic first and drop the Hz suffix')

assert.deepEqual(displays.scaleChoices(2560,1440).map(c=>c.label),['100 %','107 %','125 %','133 %','160 %','167 %','200 %','213 %','250 %','267 %'])
assert.equal(displays.scaleChoices(2560,1440).some(c=>c.value===1.5),false)
assert.equal(displays.scaleChoices(2560,1440)[3].value,160/120)
for (const choice of displays.scaleChoices(1024,768)) {
    const step = Math.round(choice.value * 120)
    assert.equal((1024 * 120) % step,0); assert.equal((768 * 120) % step,0)
}
console.log('ok: scales are 1/120 steps with a whole logical size')

const line = displays.monitorLine('DP-1',{mode:'2560x1440@120.00',position:'auto-left',scale:1.25,transform:0})
assert.equal(line,'hl.monitor({ output = "DP-1", mode = "2560x1440@120.00", position = "auto-left", scale = 1.25, transform = 0 })')
const off = displays.monitorLine('HDMI-A-1',{disabled:true})
assert.equal(off,'hl.monitor({ output = "HDMI-A-1", disabled = true })')
assert.throws(()=>displays.monitorLine('DP-1", disabled = true }) os.execute("x',{disabled:true}),/Invalid display value/)
assert.throws(()=>displays.monitorLine('DP-1',{mode:'a b',position:'auto',scale:1,transform:0}),/Invalid display value/)
console.log('ok: monitor lines have one exact format and never carry injected Lua')

const both = displays.stateFileWith(displays.stateFileWith('','DP-1',line),'HDMI-A-1',off)
assert.ok(both.startsWith(displays.STATE_HEADER))
assert.deepEqual(displays.parseStateFile(both).outputs,{'DP-1':{mode:'2560x1440@120.00',position:'auto-left',scale:1.25,transform:0},'HDMI-A-1':{disabled:true}})
const third = displays.monitorLine('DP-3',{mode:'highres@highrr',position:'auto',scale:160/120,transform:1})
assert.equal(displays.parseStateFile(displays.stateFileWith(both,'DP-3',third)).outputs['DP-3'].scale,160/120)
assert.equal(displays.stateFileWith(displays.stateFileWith(both,'DP-3',third),'DP-3',null),both)
const replaced = displays.stateFileWith(both,'DP-1',displays.monitorLine('DP-1',displays.AUTOMATIC))
assert.equal(replaced.split('\n').filter(l=>l.includes('"DP-1"')).length,1)
assert.equal(displays.stateFileWith(both,'DP-9',null),both)
const hand = displays.STATE_HEADER+'hl.monitor({ output = "DP-1", mode = "preferred", position = "0x0", scale = 1, bitdepth = 10 })\n'
assert.deepEqual([...displays.parseStateFile(hand).handEdited],['DP-1'])
assert.deepEqual(displays.parseStateFile(hand).outputs,{})
assert.deepEqual([...displays.parseStateFile(displays.STATE_HEADER+'hl.monitor({ output = "", mode = "preferred" })\n').handEdited],['*'])
console.log('ok: the state file keeps one line per output, round-trips exactly and reports hand edits')
```

Run `node quickshell/settings-panel/test/displays.mjs` → fails (module missing).

- [ ] **Step 2: Implement `displays.mjs`.**

```js
// Display configuration shared by the backend (GJS), the Displays page (QML)
// and the tests (Node). Pure functions only: no I/O, no Hyprland calls.

// The tracked catch-all in hypr/config/hardware/monitor.lua, per output.
export const AUTOMATIC = { mode: "highres@highrr", position: "auto", scale: 1, transform: 0 }
export const STATE_HEADER = "-- Written by the Super+I settings panel (Displays): one hl.monitor() per output.\n" +
    "-- Loaded by hypr/config/hardware/monitor.lua after its host-neutral default.\n"
// Hyprland's auto-* keywords place a display relative to the whole layout, so
// no pixel offset is stored that would go stale when another mode changes.
export const positions = [
    { label: "Automatic", value: "auto" },
    { label: "Left of the others", value: "auto-left" },
    { label: "Right of the others", value: "auto-right" },
    { label: "Above the others", value: "auto-up" },
    { label: "Below the others", value: "auto-down" },
]
export const transforms = ["Normal", "90°", "180°", "270°", "Flipped", "Flipped 90°", "Flipped 180°", "Flipped 270°"]
    .map((label, value) => ({ label, value }))

const modePattern = /^(\d+)x(\d+)@(\d+(?:\.\d+)?)$/
export function modeChoices(monitor) {
    return [{ label: "Automatic", value: AUTOMATIC.mode }].concat((monitor.availableModes || []).map(mode => {
        const value = mode.replace(/Hz$/, "")
        const [, width, height, hertz] = value.match(modePattern)
        return { label: `${width} × ${height} · ${Math.round(Number(hertz))} Hz`, value }
    }))
}
// highres@highrr picks the largest mode, so Automatic scales against that one.
export function modeSize(mode, monitor) {
    const match = mode.match(modePattern)
    if (match) return [Number(match[1]), Number(match[2])]
    const sizes = (monitor.availableModes || []).map(entry => entry.match(/^(\d+)x(\d+)/)).filter(Boolean)
        .map(([, width, height]) => [Number(width), Number(height)])
    return sizes.length ? sizes.reduce((best, size) => size[0] * size[1] > best[0] * best[1] ? size : best) : [monitor.width, monitor.height]
}
// Fractional scaling is expressed in 1/120 steps, and Hyprland needs a whole
// logical size, so only scales that divide both dimensions are offered.
export function scaleChoices(width, height) {
    const scales = []
    for (let step = 120; step <= 360; step++)
        if ((width * 120) % step === 0 && (height * 120) % step === 0)
            scales.push({ label: `${Math.round(step / 1.2)} %`, value: step / 120 })
    return scales
}

const quoted = text => {
    if (typeof text !== "string" || !/^[\w.@:+-]+$/.test(text)) throw new Error("Invalid display value")
    return `"${text}"`
}
export function monitorLine(output, config) {
    if (config.disabled) return `hl.monitor({ output = ${quoted(output)}, disabled = true })`
    if (!Number.isFinite(config.scale) || !Number.isInteger(config.transform)) throw new Error("Invalid display value")
    return `hl.monitor({ output = ${quoted(output)}, mode = ${quoted(config.mode)}, position = ${quoted(config.position)}, scale = ${config.scale}, transform = ${config.transform} })`
}

const linePattern = /^hl\.monitor\(\{ output = "([\w.@:+-]+)", (?:disabled = true|mode = "([\w.@:+-]+)", position = "([\w-]+)", scale = ([\d.]+), transform = ([0-7])) \}\)$/
// Lines in any other shape were edited by hand; the panel leaves those outputs alone.
export function parseStateFile(text) {
    const outputs = {}
    const handEdited = new Set()
    for (const line of text.split("\n")) {
        if (!line.trim() || line.startsWith("--")) continue
        const match = line.match(linePattern)
        if (match) {
            outputs[match[1]] = match[2] === undefined ? { disabled: true }
                : { mode: match[2], position: match[3], scale: Number(match[4]), transform: Number(match[5]) }
            continue
        }
        const named = line.match(/output\s*=\s*"([^"]+)"/)
        handEdited.add(named ? named[1] : "*")
    }
    return { outputs, handEdited }
}
const escaped = text => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
// Replace, add or (line = null) remove one output's line, keeping every other byte.
export function stateFileWith(text, output, line) {
    const base = text || STATE_HEADER
    const own = new RegExp(`^hl\\.monitor\\(\\{ output = "${escaped(output)}", .*\\n?`, "m")
    if (own.test(base)) return base.replace(own, () => line ? line + "\n" : "")
    return line ? base + line + "\n" : base
}
```

`base + line` assumes the file ends in exactly one newline. That always holds, because the header and every line the panel writes end in one.

- [ ] **Step 3: Run, add it to the runner, commit.** Add `node "$test_dir/displays.mjs"` as the last line of `run-tests.sh`, then run the Verify commands.

```bash
git add quickshell/settings-panel/displays.mjs quickshell/settings-panel/test/displays.mjs quickshell/settings-panel/test/run-tests.sh
git commit -m "feat(settings): shared display helpers for modes, scales and monitors.lua lines"
```

---

### Task 5: `monitor.lua` loads the per-machine state file

**Goal:** The tracked `monitor.lua` keeps only its host-neutral default and then loads `${XDG_STATE_HOME:-~/.local/state}/hypr/monitors.lua` if it exists. A broken state file falls back to automatic with a notification, and never breaks the config.

**Files:**
- Modify: `hypr/config/hardware/monitor.lua`

**Acceptance Criteria:**
- [ ] With no state file, `hyprctl reload` gives `hyprctl configerrors -j` of `[""]` or `[]` and DP-1 at 144 Hz
- [ ] A state file containing `hl.monitor({ output = "DP-1", mode = "2560x1440@120.00", position = "auto", scale = 1, transform = 0 })` gives 120 Hz after reload
- [ ] A state file containing a Lua syntax error gives a critical notification, 144 Hz and no config errors
- [ ] `./doctor.sh` exits 0 (the Binaries group accepts the new `notify-send` call)

**Verify:** The three reload checks in Step 2, then `./doctor.sh; echo $?` → `0`.

**Steps:**

- [ ] **Step 1: Replace the comment block and add the loader.** The file becomes:

```lua
-- Deliberately host-neutral: no connector is named here, so a fresh checkout
-- is correct on any hardware.
--
-- `highres@highrr`, not `preferred` or bare `highrr`. On this machine's
-- 144 Hz panel, `preferred` selected 2560x1440@59.951 while this combined form
-- selected 2560x1440@143.998. Hyprland parses the two keywords around `@`.
hl.monitor({ output = "", mode = "highres@highrr", position = "auto", scale = 1 })

-- Per-machine displays live outside the repo, written by the Super+I Displays
-- page to ${XDG_STATE_HOME:-~/.local/state}/hypr/monitors.lua. A named output
-- beats the catch-all above regardless of order; no file means all automatic.
-- A broken file must not take the whole config down, so it is loaded under
-- pcall and the catch-all stands.
local state_home = os.getenv("XDG_STATE_HOME")
if not state_home or state_home == "" then state_home = (os.getenv("HOME") or "") .. "/.local/state" end
local machine = state_home .. "/hypr/monitors.lua"
local file = io.open(machine, "r")
if file then
    file:close()
    local ok, err = pcall(dofile, machine)
    if not ok then
        print("monitors.lua: " .. tostring(err))
        hl.exec_cmd("notify-send -u critical Displays 'monitors.lua failed to load; displays use automatic settings'")
    end
end
```

The notification text is fixed on purpose: the Lua error message comes from file content and must never reach a shell.

- [ ] **Step 2: Check the three cases.** Arm a 20 s probe guard first, because the second case changes the mode: `systemd-run --user --collect --unit=settings-display-probe --on-active=20 --timer-property=AccuracySec=100ms "$(command -v hyprctl)" reload`.

```bash
state=${XDG_STATE_HOME:-$HOME/.local/state}/hypr/monitors.lua
test ! -e "$state" && hyprctl reload && hyprctl configerrors -j && hyprctl monitors -j | jq '.[0].refreshRate'   # → [""] / ~144
mkdir -p "${state%/*}"
echo 'hl.monitor({ output = "DP-1", mode = "2560x1440@120.00", position = "auto", scale = 1, transform = 0 })' > "$state"
hyprctl reload; sleep 1; hyprctl monitors -j | jq '.[0].refreshRate'                                          # → ~120
echo 'hl.monitor({ output = ' > "$state"
hyprctl reload; sleep 1; hyprctl configerrors -j; hyprctl monitors -j | jq '.[0].refreshRate'                 # → [""] / ~144, plus a critical toast
rm "$state"; hyprctl reload; systemctl --user stop settings-display-probe.timer
```

Screenshot the toast (`grim /tmp/monitors-toast.png`) and read it. If the Lua provider turns the swallowed error into a config error anyway, record that and report it rather than working around it.

- [ ] **Step 3: Doctor and commit.**

```bash
./doctor.sh; echo $?          # → 0
git add hypr/config/hardware/monitor.lua
git commit -m "feat(hypr): load per-machine monitors from XDG state, never the repo

monitor.sh appended connector-specific lines to this tracked file. The
Displays page will write ~/.local/state/hypr/monitors.lua instead; a broken
file falls back to the host-neutral default with a notification."
```

---

### Task 6: Backend display read, Apply, Keep, Revert and Edit file

**Goal:** The backend reports each output with its saved config, whether it was hand-edited, and its choices. It applies a validated line under a systemd guard, keeps it by writing that exact line, reverts by reloading, and never writes the state file before Keep.

**Files:**
- Modify: `quickshell/settings-panel/backend.js`
- Test: `quickshell/settings-panel/test/backend.mjs`

**Acceptance Criteria:**
- [ ] `read` with `monitors: true` calls `hyprctl monitors all -j` and returns each monitor with `saved`, `handEdited` and `choices.{modes,positions,transforms}`, plus `displayPending` (only while the guard timer is active)
- [ ] `displayApply` rejects an unknown output, mode, position, rotation, a scale not in `scaleChoices`, disabling the last enabled output, a hand-edited output, and a second pending change, all before `systemd-run`, `eval` or any write
- [ ] A valid Apply runs `systemd-run --user --collect --unit=settings-display-revert --on-active=20 … <hyprctl> reload` **before** `hyprctl eval <line>`, writes only the pending file, and returns `{pending:{output,line,remove,deadline}}`
- [ ] Keep writes exactly the evaluated line (Automatic deletes the output's line), stops the timer and removes the pending file; Keep after the guard fired writes nothing and says "already reverted"
- [ ] Revert stops the timer (ignoring "not loaded"), removes the pending file and reloads; a failed eval does the same and propagates the error
- [ ] A stale pending file (guard gone) does not block the next Apply
- [ ] `{op:"action",id:"displays-file"}` creates the file with the header if missing and opens it with `options/terminal -e options/editor`

**Verify:** `node quickshell/settings-panel/test/backend.mjs` → all `ok:` lines. Then `bash scripts/settings/panel-request.sh '{"op":"read","ids":[],"monitors":true}' | jq -c '(.monitors[0]|{name,saved,handEdited,modes:(.choices.modes|length)}), .displayPending'` → `{"name":"DP-1","saved":null,"handEdited":false,"modes":10}` and `null`.

**Steps:**

- [ ] **Step 1: Mocks.** In `backend.mjs`:
  - Add to the `GLib` mock: `getenv: name => ({XDG_STATE_HOME:'/fixture/.local/state',HYPRLAND_INSTANCE_SIGNATURE:'sig'})[name] ?? null,` and `get_user_runtime_dir: () => '/run/user/1000',`.
  - After the `dispatch` import add `const displays = await import('../displays.mjs')`.
  - Next to the fixtures, add:

```js
// Shape from `hyprctl monitors all -j` on Hyprland 0.56 (trimmed).
const monitorsFixture = [{name:'DP-1',make:'Ancor Communications Inc',model:'ROG PG279Q',width:2560,height:1440,refreshRate:143.998,scale:1,transform:0,disabled:false,
    availableModes:['2560x1440@59.95Hz','2560x1440@144.00Hz','2560x1440@120.00Hz','2560x1440@99.95Hz','2560x1440@84.98Hz','2560x1440@23.97Hz','1024x768@60.00Hz','800x600@60.32Hz','640x480@59.94Hz']}]
let guardArmed = false, failEval = false
```

  - Replace `if (args[1] === 'monitors') return JSON.stringify([{name:'DP-1',width:2560,height:1440}])` with:

```js
        if (args[1] === 'monitors') return JSON.stringify(monitorsFixture)
        if (args[1] === 'eval' && failEval) return 'error: bad monitor'
        if (args[0] === 'systemd-run') {
            if (guardArmed) throw new Error('Unit settings-display-revert.timer was already loaded')
            guardArmed = true; return ''
        }
        if (args[0] === 'systemctl' && args.includes('is-active')) { if (!guardArmed) throw new Error('inactive'); return '' }
        if (args[0] === 'systemctl' && args.includes('stop')) { if (!guardArmed) throw new Error('Unit settings-display-revert.timer not loaded.'); guardArmed = false; return '' }
```

- [ ] **Step 2: Failing tests.** Append:

```js
const statePath = '/fixture/.local/state/hypr/monitors.lua'
const pendingPath = '/run/user/1000/settings-panel/display-pending.json'
events=[]
result = await dispatch({op:'read',ids:[],monitors:true})
assert.equal(result.monitors[0].saved,null)
assert.equal(result.monitors[0].handEdited,false)
assert.equal(result.monitors[0].choices.modes[0].value,'highres@highrr')
assert.equal(result.displayPending,null)
assert.ok(events.some(e=>e[0]==='hyprctl' && e[1]==='monitors' && e[2]==='all'))
events=[]
for (const [request, message] of [
    [{op:'displayApply',output:'DP-9',mode:'highres@highrr',position:'auto',scale:1,transform:0},/no longer connected/],
    [{op:'displayApply',output:'DP-1',mode:'9999x9999@1.00',position:'auto',scale:1,transform:0},/Unknown mode/],
    [{op:'displayApply',output:'DP-1',mode:'2560x1440@120.00',position:'0x0',scale:1,transform:0},/Unknown position/],
    [{op:'displayApply',output:'DP-1',mode:'2560x1440@120.00',position:'auto',scale:1,transform:9},/Unknown rotation/],
    [{op:'displayApply',output:'DP-1',mode:'2560x1440@120.00',position:'auto',scale:1.5,transform:0},/does not divide/],
    [{op:'displayApply',output:'DP-1',disabled:true},/must stay on/],
]) await assert.rejects(dispatch(request),message)
assert.equal(events.some(e=>e[0]==='systemd-run' || e[1]==='eval' || e[0]==='write'),false)
console.log('ok: display changes are validated before any guard, eval or write')

const apply = {op:'displayApply',output:'DP-1',mode:'2560x1440@120.00',position:'auto-left',scale:1.25,transform:0}
const line = 'hl.monitor({ output = "DP-1", mode = "2560x1440@120.00", position = "auto-left", scale = 1.25, transform = 0 })'
events=[]
const applied = await dispatch(apply)
const guard = events.find(e=>e[0]==='systemd-run')
for (const flag of ['--user','--collect','--unit=settings-display-revert','--on-active=20','--setenv=HYPRLAND_INSTANCE_SIGNATURE=sig']) assert.ok(guard.includes(flag),flag)
assert.deepEqual(guard.slice(-2),['hyprctl','reload'])
assert.ok(events.indexOf(guard) < events.findIndex(e=>e[1]==='eval'))
assert.deepEqual(events.find(e=>e[1]==='eval'),['hyprctl','eval',line])
assert.equal(applied.pending.output,'DP-1')
assert.equal(files.has(statePath),false)
await assert.rejects(dispatch(apply),/waiting for Keep or Revert/)
result = await dispatch({op:'read',ids:[],monitors:true})
assert.equal(result.displayPending.output,'DP-1')
assert.deepEqual(await dispatch({op:'displayKeep'}),{pending:null})
assert.equal(files.get(statePath),displays.STATE_HEADER+line+'\n')
assert.equal(files.has(pendingPath),false)
assert.equal(guardArmed,false)
result = await dispatch({op:'read',ids:[],monitors:true})
assert.deepEqual(result.monitors[0].saved,{mode:'2560x1440@120.00',position:'auto-left',scale:1.25,transform:0})
console.log('ok: Apply arms the guard before eval; Keep writes exactly the evaluated line')

await dispatch({op:'displayApply',output:'DP-1',automatic:true})
assert.deepEqual(events.filter(e=>e[1]==='eval').at(-1),['hyprctl','eval','hl.monitor({ output = "DP-1", mode = "highres@highrr", position = "auto", scale = 1, transform = 0 })'])
await dispatch({op:'displayKeep'})
assert.equal(files.get(statePath),displays.STATE_HEADER)
events=[]
await dispatch(apply)
await dispatch({op:'displayRevert'})
assert.ok(events.some(e=>e[1]==='reload'))
assert.equal(files.get(statePath),displays.STATE_HEADER)
assert.equal(files.has(pendingPath),false)
assert.equal(guardArmed,false)
console.log('ok: Automatic removes the line on Keep; Revert reloads and writes nothing')

await dispatch(apply)
guardArmed=false
await assert.rejects(dispatch({op:'displayKeep'}),/already reverted/)
assert.equal(files.get(statePath),displays.STATE_HEADER)
assert.equal(files.has(pendingPath),false)
await dispatch(apply); guardArmed=false
await dispatch(apply)
assert.equal(guardArmed,true)
await dispatch({op:'displayRevert'})
failEval=true
await assert.rejects(dispatch(apply),/error: bad monitor/)
failEval=false
assert.equal(guardArmed,false)
assert.equal(files.has(pendingPath),false)
console.log('ok: a fired guard wins over Keep, stale pending files expire, failed evals disarm')

monitorsFixture.push({name:'HDMI-A-1',disabled:false,width:1920,height:1080,availableModes:['1920x1080@60.00Hz']})
await dispatch({op:'displayApply',output:'HDMI-A-1',disabled:true})
assert.deepEqual(events.filter(e=>e[1]==='eval').at(-1),['hyprctl','eval','hl.monitor({ output = "HDMI-A-1", disabled = true })'])
await dispatch({op:'displayRevert'})
monitorsFixture.pop()
files.set(statePath,displays.STATE_HEADER+'hl.monitor({ output = "DP-1", mode = "preferred", position = "0x0", scale = 1, bitdepth = 10 })\n')
await assert.rejects(dispatch(apply),/edited by hand/)
result = await dispatch({op:'read',ids:[],monitors:true})
assert.equal(result.monitors[0].handEdited,true)
files.delete(statePath)
files.set(base+'/options/terminal','ghostty\n'); files.set(base+'/options/editor','nvim\n')
events=[]
await dispatch({op:'action',id:'displays-file'})
assert.equal(files.get(statePath),displays.STATE_HEADER)
assert.deepEqual(events.find(e=>e[0]==='spawn')[1],['ghostty','-e','nvim',statePath])
console.log('ok: a second display can be disabled, hand-edited outputs are refused, Edit file opens the state file')
```

Run → fails at the first display assertion.

- [ ] **Step 3: Implement.** In `backend.js`, add the import:

```js
import * as displays from "./displays.mjs"
```

add these near the other path constants:

```js
const stateHome = GLib.getenv("XDG_STATE_HOME") || `${GLib.get_home_dir()}/.local/state`
const displayStatePath = `${stateHome}/hypr/monitors.lua`
const pendingPath = `${GLib.get_user_runtime_dir()}/settings-panel/display-pending.json`
const guardUnit = "settings-display-revert"
```

add these helpers after `write`:

```js
function makeParent(path) {
    const dir = path.slice(0, path.lastIndexOf("/"))
    if (!exists(dir)) Gio.File.new_for_path(dir).make_directory_with_parents(null)
}
const remove = path => Gio.File.new_for_path(path).delete(null)
```

and add the display section before `dispatch`:

```js
const readMonitors = async () => JSON.parse(await execAsync(["hyprctl", "monitors", "all", "-j"]))
const displayState = () => displays.parseStateFile(exists(displayStatePath) ? read(displayStatePath) : "")
async function guardArmed() {
    try { await execAsync(["systemctl", "--user", "is-active", "--quiet", `${guardUnit}.timer`]); return true }
    catch (_) { return false }
}
async function displaysSnapshot() {
    const state = displayState()
    return (await readMonitors()).map(monitor => ({
        ...monitor,
        saved: state.outputs[monitor.name] ?? null,
        handEdited: state.handEdited.has(monitor.name) || state.handEdited.has("*"),
        choices: { modes: displays.modeChoices(monitor), positions: displays.positions, transforms: displays.transforms },
    }))
}
function displayConfig(request, monitors) {
    const monitor = monitors.find(m => m.name === request.output)
    if (!monitor) throw new Error("Display is no longer connected")
    if (request.automatic === true) return { ...displays.AUTOMATIC }
    if (request.disabled === true) {
        if (!monitors.some(m => m.name !== monitor.name && !m.disabled)) throw new Error("At least one display must stay on")
        return { disabled: true }
    }
    const config = { mode: request.mode, position: request.position, scale: request.scale, transform: request.transform }
    if (!displays.modeChoices(monitor).some(c => c.value === config.mode)) throw new Error("Unknown mode")
    if (!displays.positions.some(c => c.value === config.position)) throw new Error("Unknown position")
    if (!displays.transforms.some(c => c.value === config.transform)) throw new Error("Unknown rotation")
    if (!displays.scaleChoices(...displays.modeSize(config.mode, monitor)).some(c => c.value === config.scale))
        throw new Error("This scale does not divide the mode evenly")
    return config
}
// Nothing reaches monitors.lua before Keep, so reloading is always a correct revert.
async function displayRevert() {
    try { await execAsync(["systemctl", "--user", "stop", `${guardUnit}.timer`]) } catch (_) { /* Already fired, or never armed. */ }
    if (exists(pendingPath)) remove(pendingPath)
    await persistReload()
    return { pending: null }
}
async function displayApply(request) {
    if (exists(pendingPath)) {
        if (await guardArmed()) throw new Error("A display change is waiting for Keep or Revert")
        remove(pendingPath) // The guard fired while no panel was watching.
    }
    const state = displayState()
    if (state.handEdited.has(request.output) || state.handEdited.has("*"))
        throw new Error(`${displayStatePath} was edited by hand; change ${request.output} there`)
    const line = displays.monitorLine(request.output, displayConfig(request, await readMonitors()))
    // The guard reverts even if the panel dies or its screen goes dark.
    await execAsync(["systemd-run", "--user", "--collect", `--unit=${guardUnit}`, "--on-active=20", "--timer-property=AccuracySec=100ms",
        `--setenv=HYPRLAND_INSTANCE_SIGNATURE=${GLib.getenv("HYPRLAND_INSTANCE_SIGNATURE") || ""}`, GLib.find_program_in_path("hyprctl"), "reload"])
    const pending = { output: request.output, line, remove: request.automatic === true, deadline: Date.now() + 15000 }
    try {
        makeParent(pendingPath)
        write(pendingPath, JSON.stringify(pending) + "\n")
        await checkedHyprctl(["eval", line])
    } catch (error) {
        await displayRevert()
        throw error
    }
    return { pending }
}
async function displayKeep() {
    if (!exists(pendingPath)) throw new Error("No display change is waiting")
    const pending = JSON.parse(read(pendingPath))
    if (!(await guardArmed())) { remove(pendingPath); throw new Error("The change was already reverted") }
    await execAsync(["systemctl", "--user", "stop", `${guardUnit}.timer`])
    try {
        makeParent(displayStatePath)
        write(displayStatePath, displays.stateFileWith(exists(displayStatePath) ? read(displayStatePath) : "", pending.output, pending.remove ? null : pending.line))
    } catch (error) {
        await displayRevert()
        throw new Error(`${error.message}. The display was reverted.`)
    }
    remove(pendingPath)
    return { pending: null }
}
```

Wire it in:
  - In `snapshot`, replace the `includeMonitors` block with:

```js
    if (includeMonitors) {
        result.monitors = await displaysSnapshot()
        result.mainMonitor = readOption("mainmonitor")
        result.displayPending = exists(pendingPath) && await guardArmed() ? JSON.parse(read(pendingPath)) : null
    }
```

  - In `dispatch`, before the `action` block:

```js
    if (request.op === "displayApply") return displayApply(request)
    if (request.op === "displayKeep") return displayKeep()
    if (request.op === "displayRevert") return displayRevert()
```

  - In the `action` block, before `const scripts`:

```js
        if (request.id === "displays-file") {
            if (!exists(displayStatePath)) { makeParent(displayStatePath); write(displayStatePath, displays.STATE_HEADER) }
            detached([readOption("terminal") || "ghostty", "-e", ...(readOption("editor") || "nvim").split(/\s+/), displayStatePath])
            return {}
        }
```

- [ ] **Step 4: Run and check the read live.** Run the Verify commands. **Do not** run `displayApply` against the real backend yet. Task 7 does that with the banner on screen.

- [ ] **Step 5: Commit.**

```bash
git add quickshell/settings-panel/backend.js quickshell/settings-panel/test/backend.mjs
git commit -m "feat(settings): apply display changes under a systemd revert guard

Apply arms a transient timer that reloads Hyprland, then evaluates the new
hl.monitor() line. Keep writes that exact line to ~/.local/state; Revert,
timeout or a dead panel reload the unchanged file."
```

---

### Task 7: Displays page UI, and retiring `monitor.sh`

**Goal:** Each output gets an editable card with staged Mode/Scale/Position/Rotation/Enabled, one Apply and an Automatic button. A banner counts down 15 s with Keep and Revert. Closing the panel reverts a pending change, and `monitor.sh` is gone.

**Files:**
- Create: `quickshell/settings-panel/PanelCombo.qml` (the dropdown, extracted from `SettingControl.qml`)
- Create: `quickshell/settings-panel/DisplayCard.qml`
- Modify: `quickshell/settings-panel/SettingControl.qml` (select uses `PanelCombo`)
- Modify: `quickshell/settings-panel/SettingsView.qml` (cards, banner, countdown, Edit file)
- Modify: `quickshell/settings-panel/shell.qml` (`pendingDisplay`, `keepDisplay`, `revertDisplay`, revert on close)
- Modify: `quickshell/settings-panel/catalog.json` (`monitors` title "Displays")
- Modify: `quickshell/settings-panel/backend.js` (drop `monitors` from action scripts)
- Delete: `scripts/settings/advanced/monitor.sh`
- Modify: `README.md` (`### Monitors`), `scripts/doctor/checks/references.sh:79`
- Test: `quickshell/settings-panel/test/tst_Settings.qml`, `quickshell/settings-panel/test/backend.mjs`

**Acceptance Criteria:**
- [ ] All existing dropdown tests pass unchanged against `PanelCombo` (`select-<id>`, `choices-<id>`, capped popup, unknown value shown)
- [ ] Changing mode and scale on a card sends no request; Apply sends exactly one `{op:"displayApply",output,mode,position,scale,transform}`
- [ ] Scale choices follow the staged mode, and a scale invalid for the new mode resets to 1
- [ ] The banner shows `Reverting in N s`; Keep sends `displayKeep`; reaching the deadline sends exactly one `displayRevert`
- [ ] Closing with a change pending queues `displayRevert` before quitting
- [ ] A hand-edited output shows why it is locked, and its Apply is disabled
- [ ] `rg -n "advanced/monitor|monitor\.sh" --glob '!CHANGELOG.md' --glob '!docs/superpowers/**'` finds nothing; `{op:"action",id:"monitors"}` is rejected
- [ ] Live: apply 120 Hz and let it time out → 144 Hz and no state file; apply 120 Hz and Keep → the state file holds the line and 120 Hz survives `hyprctl reload`; Automatic and Keep → no DP-1 line; `kill -9` the panel while a change is pending → 144 Hz within 20 s

**Verify:** `bash quickshell/settings-panel/test/run-tests.sh` → pass; `./test.sh` → pass; `./doctor.sh` → exit 0; the live sequence in Step 8.

**Steps:**

- [ ] **Step 1: Extract `PanelCombo.qml`.** Move the whole `ComboBox { … }` from `SettingControl.qml`'s `selectComponent` into a new file, parameterised so it knows nothing about rows. Its header is:

```qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

// The panel's dropdown: themed, in-scene popup capped at 320 px, and a value
// missing from its choices is displayed instead of going blank.
ComboBox {
    id: combo
    required property var theme
    property var choices: []
    property var value
    property string key: ""
    readonly property bool open: popup.visible
    signal picked(var value)
    objectName: "select-" + key
    implicitHeight: 40
    model: combo.choices
    textRole: "label"
    currentIndex: combo.choices.findIndex(item => String(item.value) === String(combo.value))
    displayText: currentIndex < 0 ? String(combo.value ?? "") : currentText
    onActivated: index => combo.picked(combo.choices[index].value)
```

Below it, move the existing `palette.*` lines and the `contentItem`, `indicator`, `delegate`, `popup` and `background` blocks from `SettingControl.qml` unchanged. Make only two substitutions throughout: `control.theme` → `combo.theme`, and the popup's `objectName: "choices-" + control.row.id` → `objectName: "choices-" + combo.key`. Close the `ComboBox` brace. Then `selectComponent` becomes:

```qml
    Component {
        id: selectComponent
        PanelCombo {
            theme: control.theme
            key: control.row.id
            choices: control.row.items || control.settingState.choices || []
            value: control.settingState.value
            Accessible.name: control.row.title
            onPicked: value => control.controller.change(control.row.id, value)
            onOpenChanged: control.controller.interacting = open ? control.row.id : ""
        }
    }
```

This replaces the `Connections` added in Task 3. Run the suite. Every existing test must pass unchanged, and that is the proof the extraction is faithful.

- [ ] **Step 2: Failing UI tests.** In `tst_Settings.qml`:
  - Add `{id:"monitors",title:"Displays",description:"Screens"}` to the mock categories.
  - Add to the controller: `property var pendingDisplay: null`, `function keepDisplay() { calls = calls.concat([{op:"displayKeep"}]); }`, and `function revertDisplay() { pendingDisplay = null; calls = calls.concat([{op:"displayRevert"}]); }`.
  - Add `controller.pendingDisplay = null; controller.monitors = [];` to `init()`.
  - Add:

```qml
        function pg279q(extra) {
            return Object.assign({name:"DP-1",make:"Ancor",model:"PG279Q",width:2560,height:1440,refreshRate:144,scale:1,disabled:false,saved:null,handEdited:false,
                availableModes:["2560x1440@144.00Hz","2560x1440@120.00Hz"],
                choices:{modes:[{label:"Automatic",value:"highres@highrr"},{label:"2560 × 1440 · 144 Hz",value:"2560x1440@144.00"},{label:"2560 × 1440 · 120 Hz",value:"2560x1440@120.00"}],
                         positions:[{label:"Automatic",value:"auto"},{label:"Left of the others",value:"auto-left"}],
                         transforms:[{label:"Normal",value:0},{label:"90°",value:1}]}}, extra || {});
        }
        function pick(name, downs) {
            const combo = findChild(view,name);
            mouseClick(combo); tryCompare(combo.popup,"visible",true);
            for (let i = 0; i < downs; ++i) keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return); tryCompare(combo.popup,"visible",false);
        }
        function test_display_card_stages_one_apply() {
            controller.monitors = [pg279q()]; controller.select("monitors"); wait(20);
            const apply = findChild(view,"applyDisplay-DP-1");
            verify(!apply.enabled);
            pick("select-DP-1-mode", 2);   // Automatic → 120 Hz
            pick("select-DP-1-scale", 2);  // 100 % → 107 % → 125 %
            compare(controller.calls.length,0);
            verify(apply.enabled);
            mouseClick(apply);
            compare(controller.calls.length,1);
            compare(JSON.stringify(controller.calls[0]),JSON.stringify({op:"displayApply",output:"DP-1",mode:"2560x1440@120.00",position:"auto",scale:1.25,transform:0}));
        }
        function test_hand_edited_display_is_locked() {
            controller.monitors = [pg279q({handEdited:true})]; controller.select("monitors"); wait(20);
            verify(!findChild(view,"applyDisplay-DP-1").enabled);
            verify(findChild(view,"handEdited-DP-1").visible);
        }
        function test_pending_banner_keep_and_timeout() {
            controller.pendingDisplay = {output:"DP-1",deadline:Date.now() + 60000}; wait(20);
            verify(findChild(view,"displayPending").visible);
            verify(findChild(view,"displayCountdown").text.indexOf("Reverting in") >= 0);
            mouseClick(findChild(view,"keepDisplay"));
            compare(controller.calls[0].op,"displayKeep");
            controller.calls = [];
            controller.pendingDisplay = {output:"DP-1",deadline:Date.now() + 300};
            tryVerify(() => controller.calls.length === 1 && controller.calls[0].op === "displayRevert", 3000);
            wait(600);
            compare(controller.calls.length,1);
        }
```

Run → fails (no `DisplayCard`, no banner).

- [ ] **Step 3: `DisplayCard.qml`.**

```qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "displays.mjs" as Displays

// One output. Edits are staged here and applied together: one Apply, one countdown.
Rectangle {
    id: card
    required property var monitor
    required property var theme
    required property var controller
    readonly property var saved: monitor.saved || (monitor.disabled ? {disabled: true} : Displays.AUTOMATIC)
    readonly property string savedKey: JSON.stringify(saved)
    property var staged: ({})
    readonly property var config: Object.assign({}, saved.disabled ? Displays.AUTOMATIC : saved, {disabled: !!saved.disabled}, staged)
    readonly property var scales: Displays.scaleChoices(...Displays.modeSize(config.mode, monitor))
    readonly property bool changed: Object.keys(staged).some(key => staged[key] !== (key === "disabled" ? !!saved.disabled : saved[key]))
    readonly property bool locked: monitor.handEdited || !!controller.pendingDisplay || controller.busy
    onSavedKeyChanged: staged = ({})
    function stage(key, value) {
        const next = Object.assign({}, staged, {[key]: value});
        // Scale 1 divides every mode; a scale that no longer divides the new mode falls back to it.
        if (key === "mode" && !Displays.scaleChoices(...Displays.modeSize(value, monitor)).some(c => c.value === config.scale)) next.scale = 1;
        staged = next;
    }
    function apply() {
        const c = config;
        controller.submit(c.disabled ? {op: "displayApply", output: monitor.name, disabled: true}
            : {op: "displayApply", output: monitor.name, mode: c.mode, position: c.position, scale: c.scale, transform: c.transform});
    }
    implicitHeight: body.implicitHeight + 28
    radius: 12
    color: theme.plate
    ColumnLayout {
        id: body
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 14
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                Label { text: card.monitor.name + " · " + (card.monitor.model || "Display"); color: card.theme.foreground; font.bold: true }
                Label { text: card.monitor.disabled ? "Off" : card.monitor.width + " × " + card.monitor.height + " · " + Number(card.monitor.refreshRate).toFixed(1) + " Hz · scale " + Number(card.monitor.scale).toFixed(2); color: card.theme.foreground; opacity: 0.75; font.pixelSize: 12 }
            }
            PanelButton {
                theme: card.theme
                text: card.controller.mainMonitor === card.monitor.name ? "Main display" : "Set as main"
                enabled: !card.controller.busy && card.controller.mainMonitor !== card.monitor.name && !card.monitor.disabled
                onClicked: card.controller.submit({op: "mainMonitor", value: card.monitor.name})
            }
        }
        Label {
            objectName: "handEdited-" + card.monitor.name
            visible: !!card.monitor.handEdited
            text: "This display was edited by hand in monitors.lua. Use Edit file to change it."
            color: card.theme.foreground; wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 12
        }
        GridLayout {
            Layout.fillWidth: true
            columns: 4; columnSpacing: 10; rowSpacing: 8
            enabled: !card.locked && !card.config.disabled
            Label { text: "Mode"; color: card.theme.foreground; font.pixelSize: 12 }
            PanelCombo { Layout.fillWidth: true; theme: card.theme; key: card.monitor.name + "-mode"; choices: card.monitor.choices.modes; value: card.config.mode; onPicked: value => card.stage("mode", value) }
            Label { text: "Scale"; color: card.theme.foreground; font.pixelSize: 12 }
            PanelCombo { Layout.fillWidth: true; theme: card.theme; key: card.monitor.name + "-scale"; choices: card.scales; value: card.config.scale; onPicked: value => card.stage("scale", value) }
            Label { text: "Position"; color: card.theme.foreground; font.pixelSize: 12 }
            PanelCombo { Layout.fillWidth: true; theme: card.theme; key: card.monitor.name + "-position"; choices: card.monitor.choices.positions; value: card.config.position; onPicked: value => card.stage("position", value) }
            Label { text: "Rotation"; color: card.theme.foreground; font.pixelSize: 12 }
            PanelCombo { Layout.fillWidth: true; theme: card.theme; key: card.monitor.name + "-rotation"; choices: card.monitor.choices.transforms; value: card.config.transform; onPicked: value => card.stage("transform", value) }
        }
        RowLayout {
            Layout.fillWidth: true
            Switch {
                objectName: "enableDisplay-" + card.monitor.name
                text: "On"
                enabled: !card.locked
                checked: !card.config.disabled
                onToggled: card.stage("disabled", !checked)
                palette.windowText: card.theme.foreground
            }
            Item { Layout.fillWidth: true }
            PanelButton { objectName: "automaticDisplay-" + card.monitor.name; theme: card.theme; text: "Automatic"; enabled: !card.locked && card.monitor.saved !== null; onClicked: card.controller.submit({op: "displayApply", output: card.monitor.name, automatic: true}) }
            PanelButton { objectName: "applyDisplay-" + card.monitor.name; theme: card.theme; text: "Apply"; enabled: !card.locked && card.changed; onClicked: card.apply() }
        }
    }
}
```

- [ ] **Step 4: `SettingsView.qml`.** Replace the monitors `Repeater`'s `delegate: Rectangle { id: display … }` with:

```qml
                            delegate: DisplayCard {
                                required property var modelData
                                Layout.fillWidth: true
                                monitor: modelData
                                theme: view
                                controller: view.controller
                            }
```

In the `Flow` below it, replace the "Advanced display setup" button with `PanelButton { theme: view; text: "Edit file"; onClicked: view.controller.action("displays-file") }`. Keep "Automatic main display".

Add the banner right after the `problem` rectangle, outside the `ScrollView`, so it stays visible on every page:

```qml
                Rectangle {
                    id: pendingBanner
                    objectName: "displayPending"
                    visible: !!view.controller.pendingDisplay
                    readonly property int secondsLeft: view.controller.pendingDisplay ? Math.max(0, Math.ceil((view.controller.pendingDisplay.deadline - view.now) / 1000)) : 0
                    Layout.fillWidth: true
                    implicitHeight: pendingRow.implicitHeight + 24
                    radius: 10; color: view.plate; border.color: view.accent; border.width: 2
                    RowLayout {
                        id: pendingRow
                        anchors.fill: parent; anchors.margins: 12
                        Label { objectName: "displayCountdown"; text: "Keep this display layout? Reverting in " + pendingBanner.secondsLeft + " s"; color: view.foreground; Layout.fillWidth: true; wrapMode: Text.WordWrap; Accessible.role: Accessible.AlertMessage }
                        PanelButton { objectName: "keepDisplay"; theme: view; text: "Keep"; enabled: !view.controller.busy; onClicked: view.controller.keepDisplay() }
                        PanelButton { objectName: "revertDisplay"; theme: view; text: "Revert"; enabled: !view.controller.busy; onClicked: view.controller.revertDisplay() }
                    }
                }
```

and, near the other top-level properties:

```qml
    property double now: Date.now()
    // The visible countdown. systemd's guard reverts at 20 s even if this never fires.
    Timer {
        interval: 250; repeat: true
        running: !!view.controller.pendingDisplay
        onTriggered: {
            view.now = Date.now();
            if (view.now >= view.controller.pendingDisplay.deadline && !view.controller.busy) view.controller.revertDisplay();
        }
    }
```

- [ ] **Step 5: `shell.qml`.** Add `property var pendingDisplay: null`. Then:
  - In both `reader`'s and `liveReader`'s `if (result.monitors) { … }`, also set `root.pendingDisplay = result.displayPending;`.
  - In `writer`'s `onExited`, after the `throw` check inside `try`, add `if (result.pending !== undefined) root.pendingDisplay = result.pending;`.
  - Add these functions:

```qml
    function keepDisplay() { submit({op: "displayKeep"}); }
    function revertDisplay() {
        // Cleared first so the countdown cannot submit twice; the next read restores it if still pending.
        pendingDisplay = null;
        submit({op: "displayRevert"});
    }
```

  - Make `close()`:

```qml
    function close() {
        // A layout nobody confirmed is never left behind.
        if (pendingDisplay && !closing) revertDisplay();
        closing = true;
        opened = false;
        if (!writer.running && !queue.length) Qt.quit();
    }
```

- [ ] **Step 6: Catalog, backend and retirement.**
  - `catalog.json`: the `monitors` category gets `"title": "Displays"` and `"description": "Resolution, refresh rate, scale, arrangement and the main display"`.
  - `backend.js`: remove `monitors: "/scripts/settings/advanced/monitor.sh"` from `scripts`. In `backend.mjs`, add `{op:'action',id:'monitors'},` to the rejected-requests list.
  - `git rm scripts/settings/advanced/monitor.sh`, and `rmdir scripts/settings/advanced` if it is now empty.
  - `README.md`: rename `### Monitors` to `### Displays`, with the body: `Use the Displays page of the settings panel (Super+I). Per-machine rules are written to ~/.local/state/hypr/monitors.lua and loaded by ~/.config/hypr/config/hardware/monitor.lua, which stays host-neutral.`
  - `scripts/doctor/checks/references.sh:79`: change the example to `(hypr/hyprland.lua's require call and a script's literal $HOME/.config/hypr/... path)`.

- [ ] **Step 7: Run everything.** Run the Verify commands and `/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml quickshell/settings-panel/*.qml` (no new warnings), then the retirement check:

```bash
rg -n "advanced/monitor|monitor\.sh" --glob '!CHANGELOG.md' --glob '!docs/superpowers/**'   # → nothing
```

- [ ] **Step 8: Live sequence.** Before each Apply, check `pgrep -x hyprlock` prints nothing. Set `state=${XDG_STATE_HOME:-$HOME/.local/state}/hypr/monitors.lua`.
  1. Open Super+I → Displays. Mode 120 Hz → Apply. The banner counts down; touch nothing. At 0 the display returns to 144 Hz, `test -e "$state"` fails, and `systemctl --user list-units 'settings-display-*' --all --no-legend` is empty.
  2. Mode 120 Hz → Apply → **Keep**. `cat "$state"` shows the header plus exactly the DP-1 line; `hyprctl reload; sleep 1; hyprctl monitors -j | jq '.[0].refreshRate'` → ~120.
  3. **Automatic** → Keep. `rg -c '"DP-1"' "$state"` → no output; 144 Hz.
  4. Mode 120 Hz → Apply, then `pkill -9 -f 'quickshell/settings-panel/shell.qml'`. Within 20 s: 144 Hz; the state file has no DP-1 line; reopening the panel shows no banner.
  5. Mode 120 Hz → Apply, then press Escape. 144 Hz at once, and the panel exits.
  6. Screenshot the Displays page with a pending banner (`grim /tmp/settings-displays.png`) and read it: the cards and banner stay inside the panel, and the dropdowns are readable.

- [ ] **Step 9: Commit.**

```bash
git add -A quickshell/settings-panel/ scripts/settings/ README.md scripts/doctor/checks/references.sh
git commit -m "feat(settings): editable Displays page with apply, countdown and revert

Edits are staged per display and applied together; a 15 s banner offers
Keep or Revert, closing reverts, and the systemd guard covers a dead panel.
Replaces monitor.sh, which appended machine-specific lines to a tracked file."
```

---

### Task 8: Docs, smoke test, performance budget and review

**Goal:** The docs describe the Sound and Displays pages and their traps. The smoke test survives the new rows. The spec's performance budget is measured and met, and the round gets an independent review.

**Files:**
- Modify: `docs/settings-panel.md`, `CLAUDE.md`
- Modify: `quickshell/settings-panel/test/live-smoke.sh` (only if the new rows break it)

**Acceptance Criteria:**
- [ ] `docs/settings-panel.md` states the row and category counts from `jq '.rows|length, (.categories|length)' catalog.json`, and documents:
  - the `pulse` source and the `card: null` trap;
  - live tags and the event filter;
  - the state-file location and format, hand-edited handling and Edit file;
  - apply, guard, Keep and Revert;
  - the File Types follow-up.
- [ ] `CLAUDE.md`'s settings-panel paragraph mentions the Sound page, live refresh (on-screen only), and the Displays state file with its revert guard; the `options/` paragraph's `monitor.lua` sentence names the state file
- [ ] Performance budget, measured and recorded:
  - a full read is within the Task 1 baseline + 10 ms;
  - with the panel closed there is no `pactl subscribe` process and no `settings-display-*` unit;
  - the Task 3 audio/notification check gives 0 live reads.
- [ ] `live-smoke.sh` passes: all N settings read successfully, no instance remains
- [ ] `./test.sh` and `./doctor.sh` pass; `git status` shows only intended files
- [ ] `delegate-review` has run on `git diff b6ca971..HEAD`, and its verified findings are fixed (each with a test) or reported

**Verify:** `bash quickshell/settings-panel/test/live-smoke.sh` → `All N settings read successfully; no panel instance remains.`; `./test.sh` → all pass; `./doctor.sh` → exit 0.

**Steps:**

- [ ] **Step 1: Measure.** Repeat Task 1 Step 1's five-run loop and compare the median with the baseline. If it is more than 10 ms over, time the new calls on their own before changing anything, e.g. `bash -c 's=$(date +%s%N); pactl -f json list cards >/dev/null; echo $(( ($(date +%s%N)-s)/1000000 )) ms'` and the same for `hyprctl monitors all -j`. Then, with the panel closed:

```bash
pgrep -fa "pactl subscribe" || echo none                               # → none
systemctl --user list-units 'settings-display-*' --all --no-legend     # → nothing
```

Re-run Task 3 Step 5's live-read check (→ `0`, then `1`).

- [ ] **Step 2: Docs.** In `docs/settings-panel.md`:
  - update the row/category counts and the "things another surface owns" sentence (sound volume → SwayNC);
  - add `pulse` to the Sources bullet;
  - add a **Live refresh** bullet and a **Displays** bullet;
  - fold the Task 1 probe section into the Displays bullet;
  - add the new measurements (full read ms, live-read counts);
  - add `node quickshell/settings-panel/test/displays.mjs` under Verification.

  In `CLAUDE.md`, extend the settings-panel paragraph with one or two sentences in its existing style, and change the `monitor.lua` sentence in the `options/` paragraph to say per-machine rules live in `~/.local/state/hypr/monitors.lua`, written by the Displays page.

- [ ] **Step 3: Smoke test.** Close the panel and run `live-smoke.sh`. It derives counts from the catalog. If a sound row errors on this machine (for example because no input device is set), fix the backend, not the test.

- [ ] **Step 4: Review.** Invoke the `delegate-review` skill with the goal, this plan's acceptance criteria and `git diff b6ca971..HEAD`. Verify each finding yourself, fix the confirmed ones with a test, and re-run `./test.sh`.

- [ ] **Step 5: Commit.**

```bash
git add docs/settings-panel.md CLAUDE.md quickshell/settings-panel/test/live-smoke.sh
git commit -m "docs(settings): round 2 Sound and Displays, live refresh and measurements"
```
