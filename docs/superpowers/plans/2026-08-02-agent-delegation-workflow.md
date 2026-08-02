# Agent Delegation Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Codex a real subagent rather than a scraped terminal, with adversarial cross-family review, a structural recursion guard, no hardcoded model identities, and graceful degradation when Codex or Herdr is unavailable.

**Architecture:** Everything functional lives in home config, so a fresh repo needs no setup. Four skills collapse to two plus a router, sharing one handoff contract. Reviews pair against the opposite family and are blind to the implementer's report. Capability is probed, never assumed.

**Tech Stack:** Claude Code skills and hooks, Codex CLI 0.146.0 (`AGENTS.md`, `config.toml`), Herdr pane/agent API, bash, jq.

**Spec:** `docs/superpowers/specs/2026-08-02-agent-delegation-workflow-design.md`

---

## File Structure

| File | Action | Responsibility after this plan |
|------|--------|-------------------------------|
| `~/.codex/AGENTS.md` | Create | Global subagent contract, loaded in every repo |
| `~/.claude/skills/_shared/handoff.md` | Create | Brief template, report schema, capability probe — the single copy |
| `~/.claude/skills/delegate-implement/SKILL.md` | Create | The one implementation path, executor-parameterised |
| `~/.claude/skills/delegate-review/SKILL.md` | Create | The one review path; owns pairing and blindness |
| `~/.claude/skills/auto-subagent-routing/SKILL.md` | Rewrite | Roles, pairing, degradation ladder, superpowers translation |
| `~/.claude/skills/codex-implement/SKILL.md` | Rewrite | Thin alias -> `delegate-implement` (executor: codex) |
| `~/.claude/skills/codex-review/SKILL.md` | Rewrite | Thin alias -> `delegate-review` (executor: codex) |
| `~/.claude/skills/claude-implement/SKILL.md` | Rewrite | Thin alias -> `delegate-implement` (executor: claude) |
| `~/.claude/skills/claude-review/SKILL.md` | Rewrite | Thin alias -> `delegate-review` (executor: claude) |
| `~/.claude/CLAUDE.md` | Modify | Slim routing policy pointing at skills; adds the leaf-worker rule |
| `~/.claude/hooks/auto-subagent-reminder.sh` | Modify | Reminder text names the new skills |
| `~/.config/AGENTS.md` | Create | Tracked relative symlink -> `CLAUDE.md`; the only repo commit |

**Task order is deliberate.** The four existing skills keep working untouched until Task 6. Tasks 1–5 only *add* files, so at no point between commits is the delegation workflow broken. Task 6 is the cutover, and Task 10 verifies the whole thing end to end.

---

### Task 1: Global subagent contract

**Goal:** Give every Codex session, in every repo, the operating contract it currently lacks.

**Files:**
- Create: `~/.codex/AGENTS.md`

**Acceptance Criteria:**
- [x] Never instructs Codex to spawn sub-agents (its base instructions refuse by default; this file must not grant the exception)
- [x] States: never commit, never push, never `git add`
- [x] States the report-file protocol as a mandated final action, including on failure
- [x] Instructs reading repo-root `AGENTS.md`/`CLAUDE.md` when present
- [x] Contains no model identifier and no `ultra`

**Verify:** `cd $(mktemp -d) && git init -q && codex exec --sandbox read-only "Summarise your operating contract in 3 bullets."` → returns the contract in a repo that has no local `AGENTS.md`

**Steps:**

- [x] **Step 1: Write the contract**

Cover, in order: you may be driven by an orchestrating agent; you are a leaf worker and must not delegate; never commit/push/stage; read repo-root `AGENTS.md` or `CLAUDE.md` if present; when the prompt names a report path, writing it is your mandated final action even if you failed; `blockers` and `concerns` are required and an empty array asserts genuinely none.

- [x] **Step 2: Confirm the no-sub-agent constraint is not accidentally granted**

```bash
grep -inE 'sub-?agent|delegate|spawn' ~/.codex/AGENTS.md
```
Expected: only prohibitions, no grants.

- [x] **Step 3: Run the fresh-repo verify above**

---

### Task 2: Shared handoff contract

**Goal:** One copy of the brief template, report schema and capability probe, so the two delegate skills cannot drift apart.

**Files:**
- Create: `~/.claude/skills/_shared/handoff.md`

**Acceptance Criteria:**
- [x] Brief template with the `[LEAF WORKER — DO NOT DELEGATE]` marker
- [x] Report JSON schema exactly as specced
- [x] Report path convention `/tmp/codex-handoff/<slug>-<timestamp>.json`
- [x] Missing-report failure mode: re-prompt once, then fall back to scrollback and say so
- [x] Capability probe one-liner for the degradation ladder
- [x] Explicit statement that the reviewer never receives implementer report fields
- [x] A directory without `SKILL.md` does not register as a broken skill

**Verify:** `ls ~/.claude/skills/` shows `_shared`, and starting a new Claude session produces no skill-loading error naming it

**Steps:**

- [x] **Step 1: Write the file** with sections: Brief template, Report schema, Report path, Missing-report handling, Capability probe, Blindness rule.

- [x] **Step 2: Confirm skill discovery ignores it**

```bash
claude --help >/dev/null 2>&1 && echo "cli ok"
```
Then start a fresh session and confirm `_shared` does not appear as a skill or raise a warning. If it does, rename to a dotted directory and update references.

---

### Task 3: `delegate-implement`

**Goal:** One implementation path that works for a Codex pane, a Claude pane, or the native `Agent` tool.

**Files:**
- Create: `~/.claude/skills/delegate-implement/SKILL.md`

**Acceptance Criteria:**
- [x] Reads the shared contract rather than restating it
- [x] Takes executor (codex | claude-pane | agent-tool) and capability tier as inputs
- [x] Codex start passes `-c model_reasoning_effort=<effort>` and **omits `-m`** by default
- [x] Claude pane start passes `--model <alias>` and `--append-system-prompt` with the leaf directive
- [x] Pane split sets `--env CLAUDE_AGENT_DEPTH=1`
- [x] Reuses a named delegate pane when idle, sending `/new` first; splits only when absent; never closes
- [x] Reads the **report file**, not scrollback, as the primary channel
- [x] Contains no model identifier and no `ultra`
- [x] Re-runs the verification commands itself rather than trusting `tests_run`

**Verify:** `grep -nE 'gpt-5|claude-(opus|sonnet|haiku)-[0-9]|ultra' ~/.claude/skills/delegate-implement/SKILL.md` → no output

**Steps:**

- [x] **Step 1: Write the skill** with Preconditions (capability probe), Step 1 pane discovery/reuse, Step 2 start with executor-specific argv, Step 3 brief handoff, Step 4 outcome handling (idle/blocked/timeout), Step 5 read report file, Step 6 independent verification, Step 7 report to user.

- [x] **Step 2: Record the exact start commands**

```bash
# Codex: default model from config.toml, effort is the dial
herdr agent start codex --kind codex --pane <p> -- -c model_reasoning_effort=<effort>

# Claude pane: alias only, plus the leaf directive at system level
herdr agent start claude --kind claude --pane <p> -- --model <alias> \
  --append-system-prompt 'You are a leaf worker. Do not delegate, spawn subagents, or start other agents. Implement the task yourself.'
```

- [x] **Step 3: Run the drift-proofing grep above**

---

### Task 4: `delegate-review`

**Goal:** One review path that pairs adversarially and is blind to the implementer's report.

**Files:**
- Create: `~/.claude/skills/delegate-review/SKILL.md`

**Acceptance Criteria:**
- [x] Pairing table: Claude-implemented -> Codex reviewer; Codex-implemented -> Claude `opus` reviewer
- [x] Review brief carries **only** diff, goal and acceptance criteria
- [x] Explicitly forbids passing `summary`, `tests_run`, `blockers` or `concerns` into the review brief
- [x] Codex reviews run at effort `high` (`xhigh` when subtle), in a fresh session
- [x] Enumerated dual-review triggers, with both reviews reconciled by the orchestrator
- [x] Findings verified against the actual code before being relayed
- [x] Contains no model identifier and no `ultra`

**Verify:** `grep -nE 'gpt-5|claude-(opus|sonnet|haiku)-[0-9]|ultra' ~/.claude/skills/delegate-review/SKILL.md` → no output

**Steps:**

- [x] **Step 1: Write the pairing and blindness rules** as the first section, before mechanics, since they are the invariants.

- [x] **Step 2: Write the dual-review trigger list** verbatim from the spec: auth/secrets/crypto/permissions, migrations/schema, destructive ops, public API or config contracts, the delegation workflow itself.

- [x] **Step 3: Write the mechanics** reusing the shared contract, with the review report using the same schema and findings in `concerns`.

- [x] **Step 4: Run the drift-proofing grep above**

---

### Task 5: Rewrite `auto-subagent-routing`

**Goal:** One place that decides executor, tier, review pairing and degradation, and translates superpowers vocabulary.

**Files:**
- Rewrite: `~/.claude/skills/auto-subagent-routing/SKILL.md`

**Acceptance Criteria:**
- [x] Role table: orchestrator, complex, workhorse (Sonnet), well-specified (Codex), bulk, review
- [x] Adversarial pairing rule stated as an invariant
- [x] Degradation ladder tiers A/B/C with the probe command, cached per session, degrading on auth/quota failure with a single announcement
- [x] Superpowers translation table
- [x] Model resolution: aliases for Claude, config default for Codex, `priority` resolution only when a non-default is genuinely wanted
- [x] `ultra` forbidden
- [x] Applies outside Herdr via tier C, rather than hard-failing

**Verify:** `grep -nE 'gpt-5|claude-(opus|sonnet|haiku)-[0-9]' ~/.claude/skills/auto-subagent-routing/SKILL.md` → no output; `grep -c 'ultra' …` → only the prohibition

**Steps:**

- [x] **Step 1: Write the invariants section** (adversarial, blind, degrade, no hardcoded identity).

- [x] **Step 2: Write the role and pairing tables.**

- [x] **Step 3: Write the degradation ladder**, including:

```bash
command -v codex >/dev/null 2>&1 && codex login status >/dev/null 2>&1
```

- [x] **Step 4: Write the superpowers translation table**, noting that its instructions describe a role, not a mechanism, and that its own priority order authorises this.

---

### Task 6: Cut the four old skills over to aliases

**Goal:** Keep `/codex-implement`, `/codex-review`, `/claude-implement`, `/claude-review` working while the logic lives in one place.

**Files:**
- Rewrite: `~/.claude/skills/codex-implement/SKILL.md`
- Rewrite: `~/.claude/skills/codex-review/SKILL.md`
- Rewrite: `~/.claude/skills/claude-implement/SKILL.md`
- Rewrite: `~/.claude/skills/claude-review/SKILL.md`

**Acceptance Criteria:**
- [x] Each is a thin alias naming its executor and deferring to the delegate skill
- [x] Each keeps a `description` that still triggers on the same user phrasings
- [x] None restates the brief template, report schema or pane mechanics
- [x] `claude-review` notes that pairing may override an explicit executor request, and says so to the user rather than silently

**Verify:** `wc -l ~/.claude/skills/{codex,claude}-{implement,review}/SKILL.md` → each well under 40 lines

**Steps:**

- [x] **Step 1: Rewrite all four** as aliases.

- [x] **Step 2: Confirm no duplicated contract text survives**

```bash
grep -l 'files_changed' ~/.claude/skills/*/SKILL.md
```
Expected: only `delegate-implement` and `delegate-review`, if at all — ideally only `_shared/handoff.md`.

---

### Task 7: Slim `~/.claude/CLAUDE.md`

**Goal:** Make the global instructions a pointer to the skills plus the one rule that must live outside them.

**Files:**
- Modify: `~/.claude/CLAUDE.md`

**Acceptance Criteria:**
- [x] Routing detail is replaced by a pointer to `auto-subagent-routing`
- [x] Retains the superpowers-priority framing that authorises the override
- [x] **Adds the leaf-worker rule:** if `CLAUDE_AGENT_DEPTH` is set and >= 1, never delegate or spawn — do the work directly
- [x] Retains the note that the hook does not fire on the Codex path
- [x] No model identifier

**Verify:** `grep -n 'CLAUDE_AGENT_DEPTH' ~/.claude/CLAUDE.md` → present

**Steps:**

- [x] **Step 1: Rewrite the subagent-routing section** as a pointer plus the leaf rule.

- [x] **Step 2: Confirm the leaf rule is unconditional** and does not depend on `$HERDR_ENV`, since tier C runs outside Herdr.

---

### Task 8: Update the reminder hook

**Goal:** The decision-point reminder names skills that exist.

**Files:**
- Modify: `~/.claude/hooks/auto-subagent-reminder.sh`

**Acceptance Criteria:**
- [x] References `auto-subagent-routing` and the delegate skills, not the old four
- [x] Mentions the adversarial-review rule
- [x] Stays advisory, non-blocking
- [x] Keeps the existing comment explaining why it is `PreToolUse` on `Agent` and why it does not fire on the Codex path

**Verify:** `sh ~/.claude/hooks/auto-subagent-reminder.sh | jq .` with `HERDR_ENV=1` → valid JSON; with `HERDR_ENV` unset → no output

**Steps:**

- [x] **Step 1: Update the payload text.**

- [x] **Step 2: Run both verify cases**

```bash
HERDR_ENV=1 sh ~/.claude/hooks/auto-subagent-reminder.sh | jq .
env -u HERDR_ENV sh ~/.claude/hooks/auto-subagent-reminder.sh; echo "rc=$?"
```

---

### Task 9: Repo `AGENTS.md` symlink

**Goal:** Let Codex pick up this repo's conventions automatically. The only tracked change in the plan.

**Files:**
- Create: `~/.config/AGENTS.md` (relative symlink -> `CLAUDE.md`)

**Acceptance Criteria:**
- [x] Relative target, not absolute (absolute is a doctor warning)
- [x] Tracked by git as mode 120000
- [x] `./doctor.sh` reports no new finding
- [x] `./test.sh` passes
- [x] The workflow still functions with this file deleted — it is an optional layer

**Verify:** `git ls-files -s AGENTS.md` → mode `120000`; `./doctor.sh; echo "rc=$?"` → rc 0

**Steps:**

- [x] **Step 1: Create the link**

```bash
ln -s CLAUDE.md ~/.config/AGENTS.md
git -C ~/.config add AGENTS.md
git -C ~/.config ls-files -s AGENTS.md
```
Expected: `120000 … AGENTS.md`

- [x] **Step 2: Confirm the doctor stays clean**

```bash
cd ~/.config && ./doctor.sh; echo "rc=$?"
```

- [x] **Step 3: Confirm the reference scan is not confused** by the same content appearing under two tracked paths. If `check_references` double-reports, note it and decide whether to exclude `AGENTS.md` or dedupe by realpath.

- [x] **Step 4: Run the suites**

```bash
cd ~/.config && ./test.sh
```

---

### Task 10: End-to-end verification

**Goal:** Prove each invariant holds against the live system, not on paper.

**Files:** none — verification only

**Acceptance Criteria:**
- [x] Fresh-repo delegation produces a report file
- [x] Recursion guard holds
- [x] Adversarial pairing routes both directions correctly
- [x] Review brief is blind
- [x] Failed task still reports `status: "failed"` with populated `blockers`
- [x] Degradation to tier B works with `codex` off `PATH`
- [x] No model identifiers, no `ultra`, anywhere in the skills

**Verify:** every command below produces its expected result

**Steps:**

- [x] **Step 1: Fresh repo**

```bash
d=$(mktemp -d) && git -C "$d" init -q
# delegate a trivial task into $d, then:
ls /tmp/codex-handoff/
```

- [x] **Step 2: Recursion guard** — delegate a task phrased so a naive agent would sub-delegate ("implement X, using a subagent for the tests"); confirm the worker does it directly.

- [x] **Step 3: Pairing, both directions** — one Codex-implemented change (expect a Claude `opus` review) and one Sonnet-implemented change (expect a Codex review).

- [x] **Step 4: Blindness** — inspect the review brief actually sent:

```bash
grep -iE 'summary|tests_run|blockers|concerns' <the review brief text>
```
Expected: no match.

- [x] **Step 5: Failure path** — delegate an impossible task; confirm the report exists with `status: "failed"` and a non-empty `blockers`.

- [x] **Step 6: Degradation**

```bash
PATH=/usr/bin:/bin command -v codex   # confirm how it resolves
# then run routing with codex masked and confirm tier B is chosen and announced once
```

- [x] **Step 7: Static invariants**

```bash
grep -rnE 'gpt-5|claude-(opus|sonnet|haiku)-[0-9]' ~/.claude/skills/ ; echo "rc=$?"
grep -rn 'ultra' ~/.claude/skills/ ~/.codex/AGENTS.md
```
Expected: first returns nothing; second returns only prohibitions.

---

## Rollback

Tasks 1–8 touch untracked home config only. Back up first:

```bash
cp -a ~/.claude/skills ~/.claude/skills.bak.$(date +%F)
cp -a ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.bak
```

Task 9 is the only tracked change and reverts with `git rm AGENTS.md`.
