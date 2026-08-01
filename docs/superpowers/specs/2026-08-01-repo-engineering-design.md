# Repo Engineering — Design

**Date:** 2026-08-01
**Status:** Approved, ready for planning
**Backlog chunk:** D (repo engineering)

## Problem

Two gaps, both verified against the live tree on 2026-08-01.

**`scripts/waybar/test-battery.sh` is orphaned.** It is a real suite — 35
assertions, 0.2 s — but nothing discovers it. The pre-commit hook runs only the
doctor's suite, `CLAUDE.md` does not list it under Key Commands, and its own
header says *"Chunk D decides whether the two styles get one runner."* There is
no way to test the whole repo in one command.

**The doctor has no waybar check.** `waybar` appears nowhere in
`scripts/doctor/checks/` except incidentally inside `references.sh`. Nothing
verifies that a module placed on the bar has a config block, and nothing
verifies that the binaries waybar's click handlers invoke exist —
`binaries.sh` derives its targets from `keybinds.conf` and `autostart.conf`
only, so `nm-connection-editor`, `blueman-manager`, `pavucontrol`, `astal`,
`swaync-client` and `wpctl` are unchecked.

### What is already in place, and must not be rebuilt

An earlier note claimed there was no pre-commit wiring. That is wrong.
`scripts/hooks/pre-commit` exists, is tracked, and is active — `install.sh:290`
sets `core.hooksPath scripts/hooks`, and `git config core.hooksPath` confirms
it locally. It already runs `shellcheck -S warning` on staged shell files, the
doctor suite when `scripts/doctor/` changes, and `ags bundle` when `ags/`
changes. `shellcheck -S warning` across all 56 tracked scripts is currently
clean, and `bash -n` passes on all of them.

`references.sh` already scans every tracked file for literal `~/.config/...`
paths, which covers the `exec` values in `waybar/config.jsonc`. The waybar
check must not re-report them.

## Scope

In scope: one repo-wide test runner, its own tests, a doctor waybar check, its
own tests, hook wiring, and the doc updates each of those falsifies.

Out of scope, decided explicitly:

- Repo-wide `shellcheck` / `bash -n` in the runner. The runner owns test
  suites; lint stays in the hook.
- `./doctor.sh` in the runner or the hook. The doctor reports on the *live
  machine*, so a missing pywal cache would fail "the tests" or block an
  unrelated commit.
- A style.css coverage check (every placed module has a selector). Dropped as
  the most heuristic of the three candidate assertions — CSS selectors nest and
  group, so the derivation is unreliable.

## Component 1 — `test.sh`

A new top-level entry point beside `doctor.sh` and `install.sh`, matching the
repo's existing entry-point convention. Dependency-free: no `jq`, and it does
**not** source `scripts/doctor/lib.sh` — that library belongs to the doctor,
and depending on it would point the arrow the wrong way.

### Discovery

From `git ls-files -z`, read with `while IFS= read -r -d ''` per the repo rule.
A path is a suite entry point if:

- its basename is `run-tests.sh`, **or**
- it matches `test-*.sh` **and** its directory contains no `run-tests.sh`.

The second clause is load-bearing: it keeps the doctor's sourced fragments
out of the listing, since running one standalone would fail. The rule stays
correct when a third suite arrives in either style, so there is no list to
maintain.

Suites are invoked as `bash <path>`, which removes any dependency on the exec
bit or on shebang variance. The only contract with a suite is: it is
executable as a bash script, and it exits non-zero on failure. Both existing
suites already satisfy this with no change.

### Owning directory

A suite's owner is its directory with a trailing `test/` component stripped:

| Suite | Owner |
|---|---|
| `scripts/doctor/test/run-tests.sh` | `scripts/doctor/` |
| `scripts/waybar/test-battery.sh` | `scripts/waybar/` |

Derived, not listed. This is the only place the file-area-to-suite mapping
lives, which is why it belongs in the runner rather than in the hook.

### Interface

Mirrors `doctor.sh`'s conventions: a self-documenting `--help` produced by
`sed -n` over the script's own header comment, and exit 2 on an unknown option.

- `./test.sh` — run every suite
- `./test.sh --for PATH...` — run only suites whose owning directory is a
  path prefix of one of those paths; this is what the hook calls
- `./test.sh --list` — print each suite and its owning directory, run nothing;
  makes discovery testable without executing anything
- `./test.sh --help`

### Execution and output

Each suite runs as a subprocess with its output captured. Capturing rather than
streaming is a measurement, not a preference: the doctor suite emits 222 lines
in 1.6 s and the battery suite 38 lines in 0.2 s, and streaming 222 lines on
every commit is how a gate gets ignored.

On pass, one line per suite: `✓ scripts/waybar/test-battery.sh (0.2s)`. On
fail, the same line marked `✗` followed by that suite's full captured output,
so diagnosing a failure needs no second command. A roll-up line closes the run.

Exit 0 if every suite passed, 1 if any failed, 2 on a usage error.

### Edge cases

- `--for` matching no suite exits 0 and says "no suites cover the changed
  files". A commit touching only `rofi/` is not a failure.
- A non-git root is an error, exit 1. Discovery derives from git, so "no suites
  found" and "not a repository" must not look alike — the same reasoning that
  produced `doctor_require_repo`.
- A path passed to `--for` that no longer exists on disk still matches, because
  the owning-directory comparison is textual. The hook passes `ACM`-filtered
  paths regardless.

### Its own tests

`test/test-runner.sh`, which the discovery rule then picks up for free — the
runner is self-hosting. It needs a root override so it can point discovery at a
fixture repo instead of the live tree: `TEST_ROOT`, following the existing
`DOCTOR_ROOT` / `DOCTOR_CACHE` / `BATTERY_SYSFS` seam.

**Why the repo root and not `scripts/test/`.** The owning-directory rule maps a
top-level `test/` to the empty prefix — the whole repo — so these tests run
whenever `test.sh` itself is staged. Under `scripts/test/` the owner would be
`scripts/`, which does not contain the root-level `test.sh`, and a broken
discovery rule could land through the gate untested. The cost is that this one
suite runs on every commit; it drives fixtures rather than real suites, so it
is fast, and a runner that gates every commit is worth verifying on every
commit.

### Accepted limitations

- No per-suite timeout. Both suites run in under 2 s; a hung suite hangs the
  commit, and `git commit --no-verify` is the escape.
- Suites are trusted to clean up after themselves. Both already do, via
  `mktemp` with an `EXIT` trap.

## Component 2 — `scripts/doctor/checks/waybar.sh`

A fifth check module following the four existing ones exactly: one public
`check_waybar`, private helpers prefixed `_way_`, no reserved name redefined,
no pipeline-into-`while`, every path in a fix hint through `doctor_q`, and no
`<placeholder>` text in a hint.

If `waybar/config.jsonc` is absent the check returns quietly, as the other
modules do for their inputs.

### Derivations

Both by `grep`/`sed`. `jq` cannot parse `config.jsonc` — verified, it fails on
the comments and trailing commas — and stripping comments first would corrupt
any string containing `//`.

**Placed modules** — the names inside the `modules-left`, `modules-center` and
`modules-right` arrays. The extractor must handle both forms present in the
file: inline (`"modules-left": ["hyprland/window", "wlr/taskbar"]`) and
multi-line.

**Configured blocks** — top-level keys at exactly 2-space indent whose value
opens `{`. The `{` requirement excludes the scalar settings (`"layer":
"bottom"`) and the `modules-*` arrays themselves, which open `[`. The indent
requirement excludes nested keys such as `"actions"` and `"format"`.

### Finding 1 — placed but unconfigured

The severity splits, because the two cases are not equally broken:

- A `custom/*` module with no config block has no `exec` and no `format`. It is
  definitively dead: **ERROR**.
- A built-in with no config block is not broken — waybar renders `clock` or
  `cpu` on defaults. But it is also exactly what a typo looks like (`cpuu`),
  which waybar drops silently: **WARN**, worded as "renders on waybar defaults,
  or is a typo waybar will drop".

Zero findings today under either branch, so this adds no noise.

### Finding 2 — configured but unplaced

**INFO**. `doctor.sh`'s own header defines that severity as precisely this
case: "tidiness — orphaned config, package drift". The fix is a one-line
deletion or a placement.

**This changes the current report.** `waybar/config.jsonc:275` defines a
`"user"` block that appears in no `modules-*` list, so adopting this check adds
one notice to a `./doctor.sh` run that is clean today. The check is right and
the config is what is stale, but the change in output is intended and recorded
here rather than discovered later. `./doctor.sh` still exits 0.

### Finding 3 — unresolved binaries

Take the first whitespace-delimited token of every `exec`, `on-click`,
`on-click-right`, `on-click-middle`, `on-scroll-up` and `on-scroll-down` value,
then apply three skips:

1. Tokens beginning `~/.config` or `$HOME/.config`. `references.sh` owns those;
   checking them here would report the same fact twice against the same file.
2. Absolute paths, which are tested with `-x` rather than against `PATH`.
3. Waybar's action vocabulary.

**WARN**, matching `references.sh`'s reasoning that a broken single interaction
is degradation rather than a broken session — and keeping `./doctor.sh` from
exiting 1 on a healthy machine.

#### The action vocabulary, and why it is a list

The skip set is `activate close minimize minimize-raise fullscreen mode
shift_up shift_down shift_reset`.

It is needed because enum-valued handlers are not separable by module.
`hyprland/workspaces` carries `"on-click": "activate"` (an enum) and
`"on-scroll-up": "hyprctl dispatch workspace r-1"` (a shell command) in the
same block. Probing every token in the live config confirms the shape of the
problem: `resources`, `nm-connection-editor`, `blueman-manager`, `pavucontrol`,
`astal`, `swaync-client`, `wpctl` and `hyprctl` all resolve, and the only
non-resolving tokens are the five action enums in use. Without the skip set the
check emits five false warnings on a healthy machine.

Failure modes, stated plainly rather than waved away: if waybar adds a keyword
and the config uses it, this produces a **false** WARN; if a binary is
genuinely named like a keyword, it misses a **real** finding. Both are bounded
and visible.

This does not violate the repo's "derive, don't list" rule. That rule forbids a
second source of truth for *this repo's* paths, binaries and packages, which
drift as the repo changes. This set is upstream waybar vocabulary; it drifts
with waybar releases, and nothing in this repo can make it stale.

The clock's nested `"actions"` block needs no special-casing — its three values
(`mode`, `shift_up`, `shift_down`) are already in the set.

### Host probe

The `PATH` lookup lives in its own one-line `_way_have_cmd`, so the tests can
stub it, following the existing convention for `pgrep`, `pacman` and `busctl`.

### Registration

`waybar` appended to `doctor.sh:51`'s module loop, and `check_waybar` appended
after `check_services` at `doctor.sh:70` — last, so the existing four groups
keep their output positions.

That loop is a hand-written list, and it stays one. It is the module registry
and it fixes report order, not a derived target list; converting it to a glob
would silently reorder the existing report into alphabetical order.

### Its own tests

`scripts/doctor/test/test-waybar.sh`, in the sourced-fragment style of its four
siblings, with fixture `config.jsonc` files covering each finding, both the
inline and multi-line array forms, the nested-key exclusion, and a stubbed
`_way_have_cmd`.

## Component 3 — hook wiring

`scripts/hooks/pre-commit` loses its hardcoded `grep -q '^scripts/doctor/'`
stanza. It builds a `STAGED_ALL` array, guards on that array being non-empty,
and calls `./test.sh --for "${STAGED_ALL[@]}"`. All file-area-to-suite
knowledge then lives in the runner's owning-directory rule, in one place.

`STAGED_ALL` comes from its **own** listing, not from the existing `staged()`
helper, and the difference is load-bearing. `staged()` filters
`--diff-filter=ACM` because a deleted file cannot be linted — but a deletion is
precisely when a suite most needs to run, since removing a covered script is
one of the likeliest ways to break its tests. Reusing that filtered listing
made the gate a silent no-op for deletion-only and rename-only commits, which
also contradicted the contract `_test_covers` already documents ("the hook
passes staged paths that may no longer exist on disk").

The suite listing therefore uses `--no-renames` and no `ACM` filter.
`--no-renames` rather than `--diff-filter=ACMRD`: the latter catches a rename
only at its destination, while `--no-renames` splits an `R` record into `D`+`A`
and yields both paths — which is what a rename *out of* an owned directory
needs in order to still run that directory's suite.

The cost is a second `git` invocation and a second loop. Correctness over the
single pass.

Deleting a script together with its suite stays green rather than failing
loudly, and that is correct: discovery reads `git ls-files`, so the suite drops
out of the index and there is nothing left to run.

The `>/dev/null` redirect and the "run X to see why" hint both go away:
`test.sh` prints a failing suite's full output inline, so there is no second
command to suggest.

The `shellcheck` and `ags bundle` stanzas keep their own logic — a bundle is a
build, not a test suite — but both gain `--no-renames` behaviour, because they
share the `staged()` helper and it needed the flag for its own reason: git
reports a rename as a single `R` record, which `--diff-filter=ACM` drops
entirely, so `git mv a.sh b.sh` slipped past shellcheck without being linted at
all. Splitting the record yields the destination as an `A`, which is linted,
and the source as a `D`, which `ACM` still excludes. For the `ags` stanza this
is a strict improvement: the old filter returned an empty listing for every
rename direction, so the stanza can now only fire more often, never less.

One gap is knowingly left: the `ags` stanza still reads `staged()`, so deleting
an `ags/` file — or moving one out of `ags/` — runs no bundle check, which are
the two cases most able to break a build. Pointing it at the suite listing
would close this; it is out of scope here because a bundle is not a test suite
and the change belongs with whoever owns the panel.

### Deliberate non-goal

Editing `waybar/config.jsonc` triggers **no** suite. The waybar check's tests
are owned by `scripts/doctor/` and run against fixtures, so a config edit
cannot break them. What a config edit can do is introduce a doctor *finding*,
and surfacing that is `./doctor.sh`'s job. Pulling `doctor.sh` into the commit
gate would let an unrelated missing pywal cache block a commit — the mixing
this design's scope section already rejects.

## Documentation

Each of these currently states something this change makes false:

| Location | Change |
|---|---|
| `install.sh:291` | Success message "(shellcheck + doctor tests + ags bundle)" |
| `README.md:136-140` | The same claim in prose, plus the standalone test command |
| `CLAUDE.md:21` | Key Commands gains `./test.sh`; suites stay runnable standalone |
| `CLAUDE.md:165` | Doctor architecture tree gains `waybar.sh` and `test-waybar.sh` |
| `CLAUDE.md` | New note stating the discovery convention |
| `scripts/waybar/test-battery.sh:8` | Header says "Chunk D decides whether the two styles get one runner" — record the answer |

The discovery convention is the one thing a future contributor must know: name
a suite `test-*.sh`, or `run-tests.sh` if it owns sibling fragments, and the
runner picks it up.

## Verification

Each with its expected result:

- `./test.sh --list` names exactly three suites, with owners `scripts/doctor/`,
  `scripts/waybar/` and the repo root.
- `./test.sh` exits 0; every suite runs — 213 + 35 assertions plus the
  runner's own, roughly 2 s.
- A deliberately broken assertion makes `./test.sh` exit 1 and print that
  suite's output; then it is reverted.
- `./test.sh --for rofi/powermenu.sh` exits 0 and runs only the repo-root
  suite. The "no suites cover the changed files" path is exercised in a
  fixture that has no repo-root suite.
- Staging a `scripts/waybar/` change and committing runs the battery suite and
  the repo-root suite, and neither runs the doctor's.
- `./doctor.sh` gains a "Waybar" group reporting exactly one notice — the
  orphaned `"user"` block — and still exits 0.
- `shellcheck -S warning` stays clean across all tracked scripts, now including
  the four new ones — `test.sh`, `test/test-runner.sh`,
  `scripts/doctor/checks/waybar.sh` and `scripts/doctor/test/test-waybar.sh`.
  The hook enforces this on the commit itself.

## Build order

1. `test.sh` plus `test/test-runner.sh` — independently useful, and adopts the
   orphaned battery suite immediately.
2. `scripts/doctor/checks/waybar.sh` plus
   `scripts/doctor/test/test-waybar.sh` — picked up by the existing doctor
   harness regardless of step 1.
3. Hook wiring.
4. Documentation.
