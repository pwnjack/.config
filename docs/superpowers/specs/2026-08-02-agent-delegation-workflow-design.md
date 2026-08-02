# Agent Delegation Workflow — Design

**Date:** 2026-08-02
**Status:** approved, pending implementation

## Problem

Claude orchestrates work and delegates it to Codex through a Herdr pane. The
mechanism works, but Codex is not a *subagent* in any meaningful sense — it is a
terminal that Claude reads with `herdr agent read --lines 200`.

Six defects follow directly from that:

1. **Lossy report-back.** Scraping a TUI loses content to reflow, truncation and
   ANSI noise, with no guarantee the final message is still on screen. Claude's
   native `Agent` tool returns a complete report; Codex returns whatever fits.
2. **No project context.** No `AGENTS.md` exists anywhere, so every constraint
   must be hand-carried in the prompt — which the skills themselves instruct,
   and which silently fails whenever the orchestrator forgets one.
3. **No operating contract.** Nothing tells Codex it is being orchestrated: not
   to commit, what to report, or when to stop.
4. **No brief template.** "Write it self-contained" with no structure.
5. **No acceptance round-trip.** Nothing requires Codex to report files touched,
   commands run, or — critically — what it could *not* do.
6. **Pane proliferation.** Every delegation splits a new pane at ratio 0.5 and
   never closes it. Three tasks leave four panes.

Four more are latent rather than observed:

7. **Unbounded delegation regress.** `~/.claude/CLAUDE.md` instructs Claude to
   delegate to Codex. A `claude-implement` pane is a real `claude` CLI process,
   so it loads that same file and delegates in turn. Nothing bounds it.
8. **Model rot.** Any skill naming `gpt-5.6-terra` is wrong the day a successor
   ships, and the orchestrator itself may be Fable or Opus depending on how the
   session was launched. Nothing may hardcode a model identity.
9. **Single-vendor fragility.** Every current skill hard-fails outside a Herdr
   session, and the workflow assumes a live Codex subscription. Either going
   away strands the user.
10. **Contaminated review.** Handing a reviewer the implementer's own summary
    anchors it on the implementer's framing, making "independent review"
    theatre.

## Verified facts

Every load-bearing claim was probed against the live binaries rather than read
from documentation, per this repo's standing habit.

| Claim | How verified | Result |
|---|---|---|
| Codex writes a report file to `/tmp` without an approval prompt | live delegation to a Herdr pane | valid JSON, exact schema honoured, correct answer |
| Codex honours a mandated final-step report instruction | same probe | honoured on first attempt |
| Panes can be named and targeted by name | `herdr agent rename` + name-targeted prompt | works |
| `herdr pane split --env K=V` reaches the pane's shell | `echo "$CLAUDE_AGENT_DEPTH"` in the split pane | `DEPTHVAL=[1]` |
| `herdr agent start ... -- <args>` passes argv to the agent | `herdr agent start --help` | `[-- [AGENT_ARG]...]` supported |
| `~/.codex/AGENTS.md` loads as a global in *any* repo | `codex exec` in a brand-new `git init` repo at `/tmp/freshrepo` | handshake token returned |
| A relative tracked `AGENTS.md` symlink is doctor-healthy | read `scripts/doctor/checks/symlinks.sh` | only *absolute* targets are flagged |
| Codex refuses to spawn sub-agents by default | binary strings | "do not spawn sub-agents unless the user or applicable AGENTS.md/skill instructions explicitly ask" |
| Codex availability is cheaply probeable | `codex login status` | "Logged in using ChatGPT", fast exit |

Two findings from `~/.codex/models_cache.json` shape the model strategy:

- **`priority` is a vendor-maintained recommendedness ranking**, not a raw
  capability score: `gpt-5.6-terra`=2, `gpt-5.6-luna`=3, `gpt-5.5`=7,
  `gpt-5.4-mini`=23, `codex-auto-review`=43 (`visibility: hide`). Useful
  precisely because the vendor maintains it — a future model inherits a low
  number and is picked up with no edit here.
- **Reasoning effort `ultra` is documented as "Maximum reasoning with automatic
  task delegation".** That is a nested-delegation vector hidden in the effort
  dial. It is forbidden outright.

## Core principles

Four invariants the rest of the design serves. Where a later section conflicts
with one of these, the invariant wins.

1. **Adversarial review.** Whenever both families are available, the reviewer is
   never from the same family as the implementer. With only one family left the
   guarantee degrades openly rather than pretending to hold.
2. **Blind review.** The reviewer never sees the implementer's report.
3. **Graceful degradation.** Losing Codex, or Herdr, or both, weakens the
   workflow and never breaks it.
4. **No hardcoded model identity.** Skills name roles and efforts. *Pinned*
   identifiers are banned; *aliases* are required, because an alias is a moving
   pointer and is what keeps a file correct across generations.

## Architecture

### Layering: global is the entire workflow

The workflow is functional with **zero per-repo files**:

| File | Role |
|---|---|
| `~/.claude/CLAUDE.md` | Slim routing policy; delegates detail to the skills |
| `~/.claude/skills/auto-subagent-routing/` | Picks executor, tier and review pairing |
| `~/.claude/skills/delegate-implement/` | One implementation path |
| `~/.claude/skills/delegate-review/` | One review path |
| `~/.claude/skills/_shared/handoff.md` | Brief template + report contract, single copy |
| `~/.codex/AGENTS.md` | Global subagent contract — applies in every repo |
| `~/.claude/hooks/auto-subagent-reminder.sh` | Decision-point reminder |

A repo may *add* context but never needs to. The brief instructs the subagent to
read repo-root `AGENTS.md` or `CLAUDE.md` **if present**, so a repo with
conventions gets them and a fresh repo still works. The
`AGENTS.md -> CLAUDE.md` symlink is an optional convenience for repos we own,
not a dependency.

### Adversarial review

**Whenever both families are available, the reviewer is never from the same
family as the implementer.** The conditional is load-bearing: with only one
family left the guarantee cannot hold, and the degraded form must be reported as
degraded rather than described as if it were the full rule.

| Implementer | Reviewer |
|---|---|
| Claude, any tier | **Codex**, effort `high` |
| **Codex** | **Claude `opus`**, fresh context |
| Orchestrator itself | **Codex**, effort `high` |

This makes same-family self-review structurally impossible rather than
mitigated. Codex still performs most reviews in practice, because Claude
`sonnet` is the default implementer — that outcome now *emerges* from the rule
instead of being hardcoded, which is what lets it survive degradation.

**Both families keep implementing, deliberately.** If Codex never implemented,
the Claude-as-reviewer path would never run, and would sit dormant until the day
the Codex subscription lapses — at which point tier B below would activate
machinery that had never once executed. Keeping both directions in continuous
use is what makes degradation a shift in mix rather than a switch to untried
code. The cost math agrees independently: implementation is token-heavy,
review reads a finished diff, so offloading the heavy half to Codex remains
favourable even paying for an `opus` review.

### Blind review

The reviewer receives exactly three things:

1. the raw diff
2. the original goal
3. the acceptance criteria from the original brief

It never receives the implementer's `summary`, `tests_run`, `blockers` or
`concerns`. Those go **only** to the orchestrator, for reconciliation.

Rationale: a reviewer told "the implementer was worried about X" will find X and
stop looking. Disagreement between an uncontaminated review and the
implementer's self-report is the highest-signal output of the workflow, and it
only exists if the two were genuinely blind to each other.

### Dual review triggers

Single adversarial review by default. **Both** families review when the diff
touches any of:

- authentication, secrets, crypto, or permissions
- database migrations or schema changes
- destructive operations (`rm -rf`, `DROP`, force-push, bulk delete)
- public API or config contracts other things depend on
- the delegation workflow itself

The list is enumerated rather than described as "high-risk" on purpose: a
judgement call is something the orchestrator can rationalise away, whereas a
matching path in the diff is checkable. The orchestrator reconciles both reviews
into one report.

**When only one family is available**, dual review cannot be satisfied as
written. It must not silently collapse to a single review: run two passes that
are independent in every way still open — separate fresh sessions, different
capability tiers — and tell the user the requirement was met in degraded form
and which axis was missing. A trigger on this list is exactly when the user
needs to know the guarantee was weaker than usual.

### Graceful degradation

Capability is probed, never assumed. Crucially this is **two independent axes,
not one ladder** — an earlier draft conflated them, which left the both-failed
case undefined and never probed Herdr at all:

```bash
# Axis 1 — mechanism: can a pane actually be driven?
[ "${HERDR_ENV:-}" = "1" ] && command -v herdr >/dev/null 2>&1 && herdr agent list >/dev/null 2>&1

# Axis 2 — reviewer: is Codex usable?
command -v codex >/dev/null 2>&1 && codex login status >/dev/null 2>&1
```

| Axis 1 — mechanism | Use |
|---|---|
| pass | Herdr panes |
| fail | native `Agent` tool |

| Axis 2 — Codex | Review pairing |
|---|---|
| pass | Cross-**family** — the full guarantee |
| fail | **Degraded:** cross-**model** + fresh context |

The axes fail separately and every combination is legal, including both at once.

`$HERDR_ENV` alone is not a mechanism probe: the variable can be set while the
binary or session is gone, which selects panes and then fails on the first
command. Probe the command.

Probed lazily on first delegation and cached. A delegation failing on auth or
quota flips axis 2 for the session and announces it **once**. Degraded review
must never be reported as though the full guarantee held — cross-model review is
still same-family review.

Axis 1 also removes the Herdr dependency that currently makes every one of these
skills hard-fail outside a Herdr session.

### Model selection: roles and efforts, never names

**Hard rule: no skill file contains a model identifier.**

| Side | Mechanism | Why it cannot rot |
|---|---|---|
| Claude | aliases `fable` / `opus` / `sonnet` / `haiku` | Aliases always resolve to the current generation |
| Codex — default | **omit `-m`**, inherit `~/.codex/config.toml` | User-owned; one place to bump, zero skill edits |
| Codex — downshift or escalate | resolve by `priority` from `models_cache.json` | Vendor-maintained ordering |
| Both — capability | reasoning `effort` | `low\|medium\|high\|xhigh\|max` are stable across generations |

```bash
# Most-recommended currently-listed model
jq -r '[.models[] | select(.visibility=="list")] | sort_by(.priority) | .[0].slug' \
  ~/.codex/models_cache.json

# Least-promoted listed model, for bulk work
jq -r '[.models[] | select(.visibility=="list")] | sort_by(-.priority) | .[0].slug' \
  ~/.codex/models_cache.json
```

**`effort: ultra` is forbidden everywhere** — it enables automatic task
delegation and would breach the recursion guard from inside.

The **orchestrator is whatever the session was launched with** (Fable or Opus).
It is never selected and needs no detection.

### Roles

| Role | Executor | Selection |
|---|---|---|
| Orchestrator | The running session (Fable or Opus) | Given |
| Complex / architectural | Orchestrator directly, or Claude `opus`/`fable` subagent when context isolation is wanted | alias |
| **Workhorse implementation** | **Claude `sonnet`** | alias |
| Well-specified, self-contained implementation | Codex | config default, effort `medium` |
| Bulk mechanical | Claude `haiku`, or Codex at effort `low` | alias / config default |
| Review | Opposite family from the implementer | see Adversarial review |

### Superpowers integration

The normal working mode is superpowers, whose execution skills hardcode
Claude-shaped dispatch. Those instructions describe a **role, not a mechanism**.
Superpowers' own stated priority order — user instructions outrank skills — is
what authorises this translation.

| Superpowers says | This workflow does |
|---|---|
| "dispatch an implementer subagent" | `delegate-implement`, routed per the role table (Sonnet default) |
| "dispatch a reviewer subagent" | `delegate-review`, paired adversarially against the implementer |
| `requesting-code-review` | `delegate-review`, same pairing rule |
| `dispatching-parallel-agents` (2+ independent tasks) | Multiple `delegate-implement`; a Codex pane and Claude subagents may run concurrently |
| `executing-plans` / `subagent-driven-development` per-task execution | Route each task through `auto-subagent-routing` first |
| `verification-before-completion` | The report's `tests_run` is evidence *submitted*, never evidence *accepted* — the orchestrator re-runs verification itself |

Superpowers' prompt templates still apply: a Codex pane needs the same
self-contained brief a Claude subagent does, and more, since it shares none of
the conversation's context.

### Recursion guard: three independent structural layers

Prose alone is insufficient — the guard must survive an agent that rationalises.

1. **`CLAUDE_AGENT_DEPTH` env var.** Every spawn sets depth+1 via
   `herdr pane split --env`. Global rule: *set and >= 1 means you are a leaf
   worker — never delegate, never spawn, do the work yourself.* Covers panes.
2. **`--append-system-prompt`** on Claude panes, injecting the leaf directive at
   system level where `CLAUDE.md` guidance can be reasoned away.
3. **Brief marker** `[LEAF WORKER — DO NOT DELEGATE]` at the head of every
   brief. This is the only layer reaching in-process `Agent`-tool subagents,
   which inherit session env and so would not see layer 1.

Plus the effort constraint: **never `ultra`**.

**Coverage is uneven, and pretending otherwise was a defect in an earlier
draft.** No single mechanism carries all three layers:

| Mechanism | Env var | System prompt | Brief marker | Standing contract |
|---|---|---|---|---|
| Claude pane | yes | yes | yes | `CLAUDE.md` leaf rule |
| Codex pane | set, but **Codex never reads it** | n/a | yes | `~/.codex/AGENTS.md`, unconditional |
| native `Agent` | no — inherits session env | n/a | **yes, the only one** | `CLAUDE.md`, keyed on the marker |

Consequences stated plainly rather than papered over:

- The env var is a **Claude-pane guard only**. Codex has no instruction to read
  it and is covered by its always-leaf `AGENTS.md` instead.
- The native `Agent` path rests on the brief marker, and its `CLAUDE.md`
  backstop keys off that same marker — so the two are *not* independent.
- A reused pane is never re-split or re-started, so it never receives
  launch-time flags again. Only panes this workflow named may be reused; the
  brief marker is what still applies unconditionally.

Codex needs no guard of its own — its base instructions already refuse to spawn
sub-agents unless an `AGENTS.md` asks. The contract file must therefore never
ask, and that is a standing constraint on `~/.codex/AGENTS.md`.

### Handoff contract

- **Path:** `/tmp/codex-handoff/<slug>-<timestamp>.json` — writable without an
  approval prompt, and repo-independent so it works on a fresh checkout.
- **Schema:**

  ```json
  {
    "status": "complete | partial | failed",
    "summary": "string",
    "files_changed": [],
    "commands_run": [],
    "tests_run": [],
    "blockers": [],
    "concerns": []
  }
  ```

- `blockers` and `concerns` are **required**. An empty array asserts genuinely
  none. This is what makes a subagent surface what it could not do.
- Writing the report is the mandated final action **even when the task failed**.
- **Missing file is a defined failure mode:** re-prompt once for the report; if
  still absent, fall back to scrollback and say so explicitly to the user.
- Scrollback demotes to a diagnostic channel.
- The **review** report uses the same schema, with findings in `concerns`.

### Brief template

```
[LEAF WORKER — DO NOT DELEGATE]

## Goal
## Context          (repo path, relevant files, read AGENTS.md/CLAUDE.md if present)
## Out of scope     (what not to touch)
## Acceptance criteria
## Verification     (exact commands to run)
## Report           (mandated path + schema)
```

The review brief is the same shape, but its Context carries **only** diff, goal
and acceptance criteria — never the implementer's report.

### Pane lifecycle

Discover via `herdr agent list` (clean JSON: `agent`, `agent_status`, `cwd`,
`pane_id`, `name`). Match on agent kind, delegate name and `cwd`. Reuse when
idle, sending `/new` to clear context between tasks. Split and name only when
absent. Never close: the user may want the scrollback.

## File manifest

| Path | Change |
|---|---|
| `~/.codex/AGENTS.md` | **new** — global subagent contract |
| `~/.claude/skills/_shared/handoff.md` | **new** — brief template + report schema |
| `~/.claude/skills/delegate-implement/SKILL.md` | **new** — unified implement path |
| `~/.claude/skills/delegate-review/SKILL.md` | **new** — unified review path |
| `~/.claude/skills/auto-subagent-routing/SKILL.md` | rewrite — roles, pairing, degradation, superpowers translation |
| `~/.claude/skills/codex-implement/` | thin alias -> `delegate-implement` |
| `~/.claude/skills/codex-review/` | thin alias -> `delegate-review` |
| `~/.claude/skills/claude-implement/` | thin alias -> `delegate-implement` |
| `~/.claude/skills/claude-review/` | thin alias -> `delegate-review` |
| `~/.claude/CLAUDE.md` | slim to routing policy pointing at skills; add leaf rule |
| `~/.claude/hooks/auto-subagent-reminder.sh` | update text for new skill names |
| `~/.config/AGENTS.md` | **new** tracked relative symlink -> `CLAUDE.md` (optional layer) |

Only the last is a repo commit. Everything else is untracked home config.

## Non-goals

- Automatic staging, committing or pushing by any subagent. That stays an
  explicit, separate, human-initiated step.
- Replacing the native `Agent` tool for in-process read-only work.
- Making the `~/.config` repo a dependency of the workflow. It is one consumer.
- Detecting which model the orchestrator is running.
- Reading Claude quota to drive routing. No reliable signal exists; the mix is
  set by task shape, not by live quota.

## Verification

- **Global contract in a fresh repo:** `git init` a temp dir, delegate a trivial
  task, confirm the report file appears.
- **Recursion guard:** delegate a task whose brief would normally trigger
  further delegation; confirm the subagent implements it directly.
- **No `ultra`:** `grep -r 'ultra' ~/.claude/skills ~/.codex/AGENTS.md` returns
  no effort setting.
- **Model drift-proofing:** `grep -rE 'gpt-5|claude-(opus|sonnet|haiku)-[0-9]'`
  over the skills returns nothing.
- **Report contract:** a deliberately-failing task still writes a report with
  `status: "failed"` and a populated `blockers` array.
- **Adversarial pairing:** confirm Codex-implemented code routes to a Claude
  reviewer, and Claude-implemented code routes to Codex.
- **Blind review:** inspect a review brief and confirm it contains no field from
  the implementer's report.
- **Degradation, axis 2:** with a broken `codex` shadowing the real one on
  `PATH`, confirm the probe fails and routing still produces a cross-model
  review, announced as degraded.
- **Degradation, axis 1:** confirm the mechanism probe tests the `herdr`
  command, not merely `$HERDR_ENV`, so a set variable with a missing binary
  selects the `Agent` tool rather than failing on the first pane command.
- **`/new` really clears context:** tell a reused pane a token, `/new`, then ask
  for it back. It must not know it.
- `./doctor.sh` stays clean, in particular `check_symlinks` on the new
  `AGENTS.md`, and `./test.sh` passes.
