# WoW / Battle.net on this setup

Hard-won launch tuning that this repo **cannot** track directly. `.gitignore:284`
ignores `faugus-launcher/**`, and rightly so: Faugus rewrites `games.json` on
every session (`playtime` alone churns), and the directory also holds absolute
paths, banners, icons and the BattlEye/EAC blobs. So the recipe lives here as
prose instead. A fresh `./install.sh` restores the Hyprland half automatically
and needs this file to rebuild the rest by hand.

Verified 2026-07-26 against gamescope 3.16.24, faugus-launcher 2.0.2, umu
1.4.1-patch1, GE-Proton11-1, Hyprland 0.56.0.

## The launch chain

Four hops, which is why the window rules have to match two different clients:

```
Faugus Launcher -> env vars -> gamescope -> Battle.net.exe -> WoW
```

Faugus entry `Battle.net`, prefix `~/Games/battlenet`, runner `Proton-GE Latest`
(`~/.local/share/Steam/compatibilitytools.d/Proton-GE Latest`, currently
GE-Proton11-1). `launch_arguments`, verbatim:

```
WINE_SIMULATE_WRITECOPY=1 PROTON_ENABLE_WAYLAND=0 gamescope -w 2560 -h 1440 -W 2560 -H 1440 -r 144 --backend sdl --expose-wayland --force-grab-cursor --adaptive-sync --
```

Plus `envar.txt`: `DISABLE_GAMESCOPE_WSI=1`.

Why each piece is there:

- **`--force-grab-cursor`** — the one that took the longest to find. Without it,
  click-and-dragging to swing the camera lets the pointer cross out of the game
  viewport, which drops Hyprland focus and stops the camera mid-turn. It ruins
  combat. Paired with `ClipCursor "1"` in-game (see below); both halves are
  needed.
- **`--backend sdl`** — nested backend rather than DRM, so gamescope stays a
  normal Hyprland client instead of taking the display.
- **`--adaptive-sync`** — VRR on DP-1.
- **`-w 2560 -h 1440 -W 2560 -H 1440 -r 144`** — matches DP-1 exactly
  (`hypr/config/hardware/monitor.conf`). If the monitor ever changes, this
  string changes with it.
- **`--expose-wayland`** — lets the nested client see the Wayland socket.
- **`PROTON_ENABLE_WAYLAND=0` + `DISABLE_GAMESCOPE_WSI=1`** — keep the game on
  XWayland inside gamescope rather than native Wayland, and stop Proton's
  gamescope WSI layer from fighting the nested compositor.
- **`WINE_SIMULATE_WRITECOPY=1`** — Battle.net launcher stability.
- Faugus's own `gamemode=False` and `mangohud=False`, globally and per-game.
  Deliberate; see "Measured and rejected" below.

Known wart: `games.json` sets `addapp_bat` to
`.../Battle.net/faugus-battlenet.bat`, and that file does not exist. Harmless
leftover, but don't be surprised by it.

## The Hyprland half (tracked)

`hypr/config/software/rules.conf`, under `## GAME WINDOW RULES`. Every game rule
is written twice — once for `class ^(WowClassic.exe)$` and once for
`class ^(gamescope)$, title ^(World of Warcraft)$` — because with the gamescope
wrapper above it is *gamescope* that is the Hyprland client, not the game. Both
Classic clients report the same `WowClassic.exe`, so one pair covers both.

- **`immediate on`** — allows tearing for the game window. This was the stutter
  fix; without it frame pacing is visibly worse.
- **`no_blur`, `no_shadow`, `decorate off`** — stop the compositor spending
  anything on effects behind a fullscreen game.
- **`workspace 5` + `fullscreen on`** — the game gets its own workspace, so
  `$Mod+1..4` still flips to a browser without disturbing it.
- **`idle_inhibit fullscreen`** — added 2026-07-26. Nothing in the
  wine/gamescope chain sends an idle inhibit, so `hypridle` would fire
  `hyprlock` at its 305s timeout over a fullscreen game during a cutscene,
  flight path or queue. The mode is `fullscreen`, not `always`, so switching to
  a browser workspace restores the normal lock timer immediately.

The rule name is **`idle_inhibit`**, with an underscore. Hyprland 0.56 rejects
`idleinhibit` as `invalid field type`. It validates its mode
(`none|always|focus|fullscreen`) and errors on anything else — unlike the
neighbouring `content` rule, which accepts any string including `bogus`, so
`content game` cannot be assumed to do anything without measuring it.

## Deliberate in-game CVars

`Config.wtf` lives per client under
`~/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/<client>/WTF/`,
where `<client>` is `_classic_era_` or `_anniversary_`. WoW rewrites the whole
file on exit, so **edit it only while the game is closed**, and back it up first.

Most of the file is churn — `CACHE-*`, `engineSurvey*`, `gameTip`, quest counts,
`lastAddonVersion`. Ignore all of it. These are the settings that were chosen:

| CVar | Value | Why |
|---|---|---|
| `ClipCursor` | `1` | In-game half of the camera-drag fix; pairs with `--force-grab-cursor` |
| `GxCompatWorkSubmitOptimizations` | `0` | vkd3d/D3D12 work-submit stutter workaround |
| `GxApi` | `D3D12` | D3D12 via vkd3d-proton rather than D3D11 |
| `hwDetect` | `0` | Stops WoW's auto-detect from overwriting these choices on launch |
| `vsync` | `1` | Works with gamescope's `--adaptive-sync` rather than against it |
| `GxMaximize` | `1` | Fullscreen behaviour inside the gamescope surface |
| `graphicsQuality` | `6` | Quality preset, with the individual knobs below overriding it |
| `shadowMode` / `shadowTextureSize` / `shadowNumCascades` | `3` / `2048` / `3` | Shadow detail |
| `SSAO` | `3` | Ambient occlusion |
| `reflectionMode` | `0` | Reflections off — costly, little visual gain here |
| `worldBaseMip` | `0` | Full-resolution world textures |
| `maxFPSBk` | `60` | Background FPS cap (`_classic_era_` only) |

`RAID*` and `raidGraphics*` duplicates of these exist and are set to match, so
raid encounters don't silently drop to a different profile.

**Both clients must be kept in sync.** On 2026-07-26 `_classic_era_` was missing
`ClipCursor` and `GxCompatWorkSubmitOptimizations` — the two hardest-won fixes
were only ever applied to `_anniversary_`. Both were added to `_classic_era_`
(backup at `Config.wtf.bak-20260726`). When tuning one client, apply it to the
other.

## Measured and rejected

Recorded so this ground isn't re-covered. All measured on this machine
(i7-9700K, RTX 3080 Ti, desktop, no battery) on 2026-07-26.

**`gamemode` — not worth wiring up.** Running `gamemoderun sleep 8` and watching
what actually changed:

| Claimed effect | Reality here |
|---|---|
| CPU governor -> performance | No-op. Governor stays `powersave`; `intel_pstate` is in **active** mode, so gamemode won't touch HWP |
| Power profile / EPP | Already `performance` — `powerprofilesctl` is pinned there and EPP reads `performance` |
| ioprio | Not applied (`none: prio 0` during) |
| NVIDIA PowerMizer | Needs explicit `gpu_device`/coolbits config; the card already clocks up under load |
| renice | Applied: `nice -4` |

So the sole working effect is a scheduler priority boost, and niceness only
matters under CPU contention — with 8 cores and one heavy process there is no
contest to win. `gamemoded` is installed and running (D-Bus activated) but stays
inactive because nothing registers with it. Leave it that way.

**`power-profiles-daemon` toggle — pointless here.** Already pinned
`performance`, and `/sys/class/power_supply` is empty. On a desktop it would buy
thermals and fan noise, not battery life.

**Session-level "gaming mode" — not built, on purpose.** The idea was to hide
waybar, force swaync DND and inhibit idle whenever a game was running. It
dissolved on inspection:

- Waybar is `"layer": "bottom"` (`waybar/config.jsonc:8`) with an exclusive
  zone, so a fullscreen window already occludes it completely. Hiding it gains
  no screen space during play, and would remove the bar exactly during the
  workspace-switched moments when it's wanted.
- The real workflow is `$Mod+1..4` to a browser workspace and back, not
  alt-tabbing out of a fullscreen window. Anything scoped to "the game is
  *running*" is therefore wrong; it has to be scoped to "the game is
  *focused*". `gamemode`'s `start=`/`end=` hooks are process-lifetime only, so
  gamemode cannot express that distinction at all.
- Notification toasts over the game and mid-game `hyprlock` had never actually
  occurred in practice. The lock risk was closed by one window rule
  (`idle_inhibit fullscreen`) with no script, daemon or state file — and hence
  nothing to restore if the game crashes.

Deliberately **no `doctor.sh` check** for any of this. `games.json` is
git-ignored and machine-local, so a check would be a second source of truth and
would ERROR on any machine without Faugus installed.
