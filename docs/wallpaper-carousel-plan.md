# Fullscreen wallpaper carousel: implementation plan

Prepared on 2026-09-18 for the next working session in `~/.config`.

**Implemented 2026-09-19.** See [the completed feature documentation](wallpaper-carousel.md)
for controls, actual integration choices, measured performance, verification,
and remaining hardware limitations. The proposal below is retained as planning
history; its future-tense statements describe the state before implementation.

## Purpose and current status

Replace the Waypaper picker opened by **Super+Ctrl+W** with a polished,
fullscreen wallpaper carousel inspired by
[motor-dev/wallpaperCarousel](https://github.com/motor-dev/wallpaperCarousel).
The desired experience is a horizontal row of large, skewed image cards with
smooth movement, a prominent selected wallpaper, and keyboard and mouse input.

This document records the original investigation and proposed implementation.
At the time of planning, no carousel code or dependencies had been installed and
no desktop configuration had been changed for this project. The user requested
a written plan so the next session can resume with the context intact.

The recommended direction is a small standalone Quickshell/QML application
connected to the existing wallpaper pipeline. Keep pywal for the initial
implementation. Matugen remains a possible follow-up after a visual comparison.
The detailed behavior below is a proposed default, not a claim that every design
choice has already been approved or tested.

## What exists today

The current flow is:

```text
Super+Ctrl+W
    → Waypaper picker
    → awww applies the wallpaper
    → Waypaper invokes scripts/hyprland/wall.sh
    → pywal generates the palette
    → component scripts render and reload the desktop theme
```

The following facts were checked against local files during the planning session:

| Area | Current behavior and source |
| --- | --- |
| Picker shortcut | `hypr/config/software/keybinds.lua` invokes `waypaper` for Super+Ctrl+W. |
| Random wallpaper | The same file invokes `waypaper --random` for Super+Shift+W. |
| Wallpaper directory | The live `waypaper/config.ini` specifies `~/Pictures/Wallpapers`, sorted by name, without subfolder scanning. Read this configuration at runtime instead of adding a second folder setting. |
| Application scope | Waypaper currently targets `All` monitors and uses the `awww` backend with `fill`. |
| Transition | Waypaper holds the transition settings, currently type `any`, duration 1 second, and 60 FPS. |
| Theme hook | Waypaper's `post_command` is `~/.config/scripts/hyprland/wall.sh`. |
| Persistent configuration | `waypaper/config.ini` is a tracked symlink to `~/.cache/waypaper-config.ini`; the tracked seed is `waypaper/config.ini.template`. |
| Current image | `options/wallpaper` is a tracked symlink through `~/.cache/current_wallpaper`. The latter is updated after successful palette generation. |
| Login restoration | `scripts/hyprland/restore-wallpaper.sh` prefers Waypaper's saved selection, then the awww cache, then the current-wallpaper symlink. It also supports random wallpaper at startup. |
| Startup | `hypr/config/setup/autostart.lua` starts awww, restoration, and the SDDM wallpaper watcher. |
| Settings UI | `ags/app.ts` runs a separate AGS/GTK4 settings panel. |

`wall.sh` takes a cache-backed lock, queries awww after acquiring it, selects the
palette source using `options/mainmonitor` or the first reported monitor, runs
`wal -n -i`, publishes current-wallpaper state, and invokes
`scripts/theming/apply-wal.sh`. The driver discovers component renderers by glob.
The script also refreshes Waybar and restarts the AGS settings panel. Its failure
notifications distinguish generation failures from partial component failures.

SDDM already follows awww changes through its watcher. The carousel should feed
that existing mechanism; no changes to privileged SDDM helpers are expected.

## Why Quickshell

The linked project is packaged for DankMaterialShell and Noctalia. Its README
requires the host shell to manage wallpapers, so installing that plugin as-is
would not integrate with this awww/pywal setup.

However, its `Carousel.qml` exposes a separate integration interface, including
the wallpaper folder, current image, focused-screen lookup, configuration, and a
`wallpaperPicked(fullPath, screenName)` signal. It already contains navigation,
search, image caching, skew transforms, and a Wayland overlay. This makes an
adaptation technically plausible without adopting an entire desktop shell.

Quickshell is the recommended fit for the requested animation and card geometry.
The existing AGS/GTK4 stack could also host a picker, but recreating this specific
visual treatment there would be a different implementation. Quickshell can run
alongside the existing panel and bar.

During inspection, neither `qs` nor `quickshell` was on PATH. `qt6-base` and
`qt6-declarative` were installed. Resolve the current Quickshell package and its
actual runtime dependencies at implementation time; this session did not install
or launch it. Do not infer missing Qt functionality solely from a package name.

Before copying upstream code, check the license and attribution requirements at
the exact revision selected. License compatibility was not established in this
session. If reuse is not permitted or practical, implement the visual design
independently. Record the upstream revision for any code that is reused.

## Proposed user experience

- Super+Ctrl+W toggles one overlay on the focused monitor. Repeated presses must
  not create multiple application instances.
- The overlay fills that monitor above the desktop and bar, dims the backdrop,
  and takes keyboard focus only while open. Blur is an optional visual refinement.
- Cards slide horizontally, with the selected image larger and more prominent.
  Preserve image proportions when cropping the previews.
- Opening highlights the current wallpaper when it exists in the folder.
- Left/Right navigate; mouse wheel navigation and clicking are supported.
  Enter applies, Escape cancels, and Ctrl+F opens filename search.
- Browsing changes only the overlay preview. Wallpaper application and palette
  generation happen once the user confirms.
- Closing releases keyboard focus and returns interaction to the previous app.
- Use the current desktop palette for accents and readable text. A palette engine
  change is not necessary for the carousel.
- Provide an understandable empty-folder state and handle unreadable or removed
  images without crashing. Search with no results must remain dismissible.

Opening on the focused monitor and applying to all monitors are separate choices.
Preserve the current **apply-to-all** behavior initially. Upstream provides a
screen name with a selection, but passing that directly into a per-monitor apply
operation would silently change this desktop's behavior.

Use a bounded preview cache and asynchronous image loading. Do not preload every
full-resolution wallpaper. Prefer a single resident process for quick subsequent
opens; measure first-open latency and memory use before choosing cache limits.

## Connecting selection to the existing pipeline

Keep one application boundary between the QML UI and wallpaper handling. The UI
passes the selected local path as a process argument to a small Bash helper. It
must not construct shell source by interpolating filenames.

The simplest candidate for the helper is Waypaper's existing command-line path:

```bash
waypaper --wallpaper "$selected_path"
```

Inspection of the installed Waypaper source confirmed that this route applies
without opening the picker, saves the selection in its configuration, and runs
the configured post-command. Retaining it also retains login restoration,
transition preferences, and the existing random-wallpaper shortcut.

There are two important limits to verify before relying on it:

1. Waypaper launches `post_command` asynchronously with `subprocess.Popen`.
   Waypaper exiting does **not** establish that pywal and every theme consumer
   finished successfully.
2. Its wallpaper application code catches exceptions and prints errors. Treating
   process exit status alone as proof of successful application is insufficient
   without further checks.

For the first prototype, the overlay can submit the selection and let the
existing pipeline own success/failure notifications. It must not display its own
premature “theme applied” message. Prevent repeated confirmation while a request
is being submitted.

If the final UI needs reliable completion feedback, add an explicit, tested
completion contract. One candidate is suppressing Waypaper's post-command and
having the helper verify the applied image before running `wall.sh` synchronously.
That needs checking against backend timing, concurrent requests, and persistence
behavior; it is not an already-proven solution. Avoid invoking the normal
post-command and then calling `wall.sh` a second time.

Do not assume that `wall.sh /path/to/image` applies a wallpaper. The current script
reads the image from awww and generates the theme; it is not a path-taking setter.
Its existing lock serializes theme work, not every operation performed inside
Waypaper or awww.

Keep thumbnail work and overlay navigation outside the theme lock. Preserve the
current lock, fallback rendering, cache-only generated outputs, and component
failure reporting if the apply integration requires changes.

## Implementation sequence

### 1. Re-establish the live baseline

Read root `AGENTS.md`/`CLAUDE.md` and any instructions beneath directories being
edited. Inspect the working tree before changing files. Recheck the relevant
configuration and package versions; this document records a point in time.

Read the current upstream source and determine reuse permissions. Install only
the runtime dependencies needed for the standalone carousel through the normal
permission flow. Do not install DMS or Noctalia for this feature.

### 2. Build a standalone visual prototype

Create the QML entry point and carousel in a dedicated configuration directory,
for example `quickshell/wallpaper-carousel/`. The exact path is a proposal.
Implement the overlay, focused-monitor selection, keyboard dismissal, folder
discovery, image previews, and navigation. Start with the existing palette and
inspect the result on the real display.

Keep the existing shortcut working until the standalone prototype opens and
closes reliably. Confirm the Quickshell CLI/IPC syntax for the installed version
instead of copying commands intended for a DMS or Noctalia instance.

### 3. Integrate wallpaper application

Add the Bash apply helper, use argument arrays from QML, and connect confirmation
to the existing backend. Read the current folder and selection from established
sources. Verify selection persistence, errors, and cancellation.

Account for external changes: using Super+Shift+W or opening Waypaper manually
must not leave the carousel permanently showing an obsolete selection. Re-read
state on open or watch the relevant state source. Remember that the current-image
symlink represents successful palette generation and may temporarily differ from
what awww displays.

### 4. Integrate lifecycle and polish

Add a reliable singleton launch/toggle mechanism and, if measurements support it,
start the hidden instance at login. Ensure restarting the AGS panel during a
wallpaper change does not control the carousel's lifecycle.

Finish card spacing, transitions, search, hover and selection states, readable
labels, and an unobtrusive keyboard hint. Respect an existing reduced-animation
preference if available. Tune thumbnail sizes for monitor scale and constrain
memory consumption.

Change Super+Ctrl+W to the carousel toggle, preserve Super+Shift+W, and keep
Waypaper available as a manual fallback. Add installer dependencies and
regenerate keybinding documentation.

### 5. Verify and document the completed feature

Run the relevant checks below, fix problems within scope, and record actual
outcomes and any remaining limitations. Update this document or the appropriate
usage documentation to distinguish implemented behavior from future ideas.

## Expected file changes

| Path | Expected responsibility |
| --- | --- |
| `quickshell/wallpaper-carousel/` (proposed) | QML UI, theme reader, application entry point. |
| `scripts/hyprland/` | Small launch/toggle and apply helpers, plus meaningful integration tests. |
| `hypr/config/software/keybinds.lua` | Replace only the picker command and adjust its human label if necessary. |
| `hypr/config/setup/autostart.lua` | Start the hidden carousel if a resident instance is chosen. |
| `install.sh` | Declare required runtime packages and any necessary setup. |
| `docs/keybindings.md` | Regenerate with `scripts/docs/generate-keybindings.sh`; never edit by hand. |
| Relevant usage documentation | Explain controls, dependencies, and fallback access. |

Changes to `wall.sh` should be driven by a demonstrated integration requirement.
Changes to SDDM privileged helpers, game rules, or unrelated desktop components
are outside this project. Inspect `.gitignore` so new source files are visible;
keep generated previews and runtime state in the cache.

## Verification and acceptance criteria

The initial feature is complete when:

- The shortcut reliably toggles one fullscreen overlay with no duplicate process
  accumulation or orphaned keyboard grab.
- Keyboard, mouse, search, and Escape behave correctly; canceling makes no
  wallpaper or palette change.
- Confirming applies the selected image, preserves the saved choice for login,
  and triggers the existing theme pipeline exactly once.
- Failed application or generation produces a truthful error, without a false
  success message from the overlay.
- The random-wallpaper shortcut, settings panel, current-wallpaper state, and
  SDDM propagation retain their existing behavior.
- The overlay handles an empty folder, unreadable images, removed files, and
  filenames containing spaces, quotes, non-ASCII characters, or shell metacharacters.
- Focused-monitor placement, fractional scaling, and apply-to-all behavior are
  correct on available hardware. Report hardware scenarios that could not be tested.
- First and subsequent opening latency, rapid navigation, and memory use are
  measured on the actual wallpaper collection. No performance numbers were
  established during planning.
- Runtime changes produce cache files rather than modifying tracked config files.

Use stubbed integration tests for process arguments, cancellation, duplicate
requests, and application failure behavior. Preserve or extend
`scripts/hyprland/test-wallpaper.sh` if the existing pipeline changes. UI animation
and focus behavior need live verification; shell tests alone cannot establish
them. Use the installed QML tooling for relevant syntax/runtime checks.

Useful repository commands, to run as appropriate during implementation:

```bash
bash scripts/hyprland/test-wallpaper.sh
scripts/docs/generate-keybindings.sh
bash test/test-docs.sh
./test.sh --list
./test.sh
./doctor.sh
hyprctl configerrors -j
```

Run shell syntax checks and shellcheck on changed Bash files. The test runner
discovers **tracked** suites, so newly created, unstaged test files must also be
run explicitly. Do not stage files just to make discovery see them. A healthy
`hyprctl configerrors -j` may return `[""]`.

No implementation tests or live carousel tests have been run yet. The planning
session's `waypaper --help` printed useful CLI help but also attempted a backend
probe that encountered sandbox-denied Wayland access. It is not evidence of a
successful live apply. Semantic `mgrep` searching also failed with `fetch failed`;
inspection continued using exact `rg` searches and file reads.

## Matugen: deferred evaluation

The user also asked whether replacing pywal with Matugen would be worthwhile.
The recommendation is to evaluate it for its visual results after the carousel
works, rather than make migration a prerequisite for this feature.

Matugen supports Material You and base16 palette generation, templates, and
controls for contrast, lightness, and scheme variants. Its appeal here is the
ability to design coordinated backgrounds, text, and accent roles. “Better
colors” remains a preference to establish with the user's own wallpapers.

The existing system makes a gradual migration possible:

- `scripts/theming/palette.sh` supplies a shared 16-color array to many renderers.
- `ags/lib/colors.ts` reads pywal's `colors.json` directly.
- Ghostty consumes a generated pywal file, while Waybar/SwayNC depend on its CSS.
- Other consumers use numbered palette entries for backgrounds, text, accents,
  and gradients; these mappings need review to benefit from semantic roles.

A future trial could render compatible outputs into an isolated preview location
and compare representative dark, bright, muted, and multicolored wallpapers.
Only after choosing the visual result should it replace live generation. Existing
reload scripts and cache symlinks could be retained with compatibility templates
first, then improved component by component.

Check terminal ANSI distinctions and text/background contrast as part of that
comparison. Merely substituting arbitrary Material colors into numbered slots
does not establish readability or correct terminal semantics.

No speed claim has been measured locally. Generation is only one stage; component
rendering and Waybar/AGS restarts also contribute to elapsed time. Rust alone is
not sufficient evidence for an end-to-end improvement. Keeping the carousel's
apply boundary independent of the generator avoids coupling it to either engine.

## Sources and next-session starting point

External references inspected during planning:

- [Wallpaper Carousel README](https://github.com/motor-dev/wallpaperCarousel)
- [Carousel.qml integration and UI](https://github.com/motor-dev/wallpaperCarousel/blob/main/Carousel.qml)
- [Noctalia-specific shell.qml wrapper](https://github.com/motor-dev/wallpaperCarousel/blob/main/shell.qml)
- [Quickshell Wayland layer-shell documentation](https://quickshell.org/docs/v0.2.0/types/Quickshell.Wayland/WlrLayershell/)
- [Matugen features](https://github.com/InioX/matugen)
- [Matugen application templates](https://github.com/InioX/matugen-themes)

The Quickshell documentation URL is versioned; consult documentation matching the
runtime actually installed. Upstream repositories can change between sessions.

Suggested next-session instruction:

> Read `AGENTS.md` and `docs/wallpaper-carousel-plan.md`, then implement the
> standalone fullscreen wallpaper carousel for Super+Ctrl+W. Keep the current
> awww/Waypaper/pywal pipeline and defer Matugen. Recheck the live configuration,
> upstream reuse permissions, and runtime dependencies first. Work through the
> prototype, integration, and verification steps, leaving changes unstaged.

The repository contract requires working as a leaf agent, preserving unrelated
changes, and leaving all edits in the working tree. Do not delegate, stage,
commit, create branches/worktrees, or otherwise change Git state. If a future
task explicitly supplies a report path, follow the repository's JSON report
protocol; no separate report was requested for this planning document.
