# Capture bar: screenshots and screen recording

Super+Shift+S opens the capture strip on its Screenshot tab, Super+Shift+R on
its Record tab. Super+S (region to disk) and Super+Alt+S (region to swappy)
are unchanged. While a recording runs, a red timer sits at the left of
Waybar's right-hand modules; click it, or press Super+Shift+R, to stop and save.
During a start delay the pill is amber and a click cancels the countdown.

Design: `docs/superpowers/specs/2026-10-09-capture-bar-design.md` (local).

## Pieces

| Piece | Job |
|---|---|
| `quickshell/capture/` | The strip. `model.mjs` is the pure model; `Strip.qml` draws it; `shell.qml` owns the window, IPC and the option files. Exits on close. |
| `scripts/hyprland/capture-bar.sh` | Launcher: lock, IPC toggle, palette, daemonize. `record` while recording stops instead. |
| `scripts/capture/record.sh` | The only driver of gpu-screen-recorder. State in `$XDG_RUNTIME_DIR/capture/recording.json`, recorder log in `gsr.log` beside it. |
| `scripts/hyprland/screenshot.sh` | The only screenshot command (hyprshot): `screen`, `window`, `region`. |
| `scripts/hyprland/lock.sh` | The only lock path; locks first, saves a recording in a detached process. |
| Waybar `custom/recording` | Hidden when idle; `interval: once` plus signal 11; click stops (or cancels a countdown). |

## The strip

IPC target `capture`: `ping`, `toggle <mode>`, `open <mode>`, `close`,
`status`, and `run`, a seam for scripted checks that presses the action button
and acts only while the strip is open. Option writes are synchronous
(`blockWrites`), so the script the strip starts reads exactly what it shows.

The capture is started detached, stdio closed, after Hyprland reports the
`capture-bar` layer closed (400 ms fallback if no event arrives). The layer
rules are blur and `no_anim`, so the strip is gone from the screen before the
shot and never appears in it. The Annotate button is 60 px: the spec's rule
that no label is elided beat the mockup's 58 px with FiraCode Nerd Font.

## Options

One value per file in `options/`, written by the strip the moment a control
changes and read by the scripts, so the keybind and the strip never disagree:
`capture-shot-target`, `capture-rec-target` (`screen|window|region`),
`capture-delay` (decimal seconds, `0` = off, so `08` is 8 s), `capture-freeze`,
`capture-annotate`, `capture-audio`, `capture-mic` (`true|false`).

## Recording

`gpu-screen-recorder -w <monitor> | -w WxH+X+Y -c mp4 -k h264 -ac aac -f 60
-q very_high -cursor yes [-a default_output|default_input] -v no
-o ~/Videos/Recordings/Recording_YYYY-MM-DD_HH-MM-SS.mp4`. Region and window
recordings use `-w WxH+X+Y` because gpu-screen-recorder 6.1.3 deprecates
`-w region -region`. Capture is KMS through `gsr-kms-server`, which needs
`cap_sys_admin` (the package sets it; `doctor.sh` warns if it is lost). No
portal dialog.

- **Window** recording records the window's rectangle at the moment you click
  it. Moving the window afterwards is not followed.
- **Region coordinates** are passed exactly as slurp prints them. Untested on a
  scaled monitor (this machine is scale 1).
- **Very small regions fail.** NVENC rejected 64x64 and accepted 256x256 here;
  a tiny selection ends in a "Recording failed" toast.
- **Identity.** record.sh identifies the recorder by pid and its `/proc` start
  time (`since` in the state), so a recycled pid is never mistaken for it. Stops
  are serialised by a flock. A click that lands on the countdown boundary
  cancels and discards. If the recorder dies mid-recording, a "Recording
  stopped" toast says so and the bar clears. While the file is finalised the
  module reads "saving".
- **Stop** sends SIGINT and waits up to 10 s for the file; the toast offers
  Open and Show in folder. Nothing goes to the clipboard.
- **Waybar.** The module runs once and on signal 11; record.sh sends it on each
  change and once a second while recording, so an idle bar runs nothing. The
  glyph is in `<span size='large'>`, the module carries its own 15 px edges, red
  pill while recording, amber while counting down.

## Lock and suspend

The lock comes first, the save second. logind's `InhibitDelayMaxSec` is 5 s, so
on suspend nothing may stand in front of hyprlock: `lock.sh` starts hyprlock at
once and hands `record.sh stop` to a detached process (a failed or missing save
never prevents the lock). A clip may therefore end with about a second of the
lock screen.

The guard fails closed: `flock -w 1` serialises callers, and only a running
hyprlock of the same user skips locking (a stale one still counts as locked).
hypridle's `lock_cmd` is `lock.sh`, and `before_sleep_cmd` runs
`loginctl lock-session`, so idle locking and suspend save the recording too.
hypridle has `inhibit_sleep = 3` (sleep waits until the session is locked)
because its auto mode keys on the string "hyprlock" in `lock_cmd`, which
lock.sh's path lacks.

## NVIDIA note

The package ships `/usr/lib/modprobe.d/gsr-nvidia.conf` with
`NVreg_PreserveVideoMemoryAllocations=1`; before it, the driver ran with 2.
It takes effect after a reboot. Check with
`grep PreserveVideoMemoryAllocations /proc/driver/nvidia/params` and test one
suspend/resume after the reboot.

## Testing

- `scripts/capture/test-record.sh`: record.sh against fakes in `scripts/capture/fakes/`.
- `scripts/hyprland/test-lock.sh`, `test-screenshot.sh`, `test-capture-bar.sh`.
- `quickshell/capture/test/run-tests.sh`: node model tests and offscreen QML tests.
- Live: `record.sh start region 640x360+100+100`, wait, `record.sh stop`, then
  `ffprobe -v error -show_entries stream=codec_name:format=duration -of compact <file>`.
