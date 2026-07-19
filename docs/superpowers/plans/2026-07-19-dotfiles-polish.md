# Dotfiles Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove superseded configs (wofi, wlogout, kitty, placeholder), make wallpaper switches stop dirtying git by moving generated state to `~/.cache`, shellcheck-clean the scripts, and track `.claude/` + `paneflow/`.

**Architecture:** The repo *is* `~/.config` on a live Hyprland desktop. Tracked files must never change at runtime: generated state moves to `~/.cache`, reached via tracked *relative* symlinks (the pattern `hypr/config/colors.conf` already uses). Every change is verified live (wallpaper switch, rofi menus, `install.sh --dry-run`).

**Tech Stack:** bash, git, pywal, Hyprland, waypaper (awww backend), mako, rofi, shellcheck.

**Spec:** `docs/superpowers/specs/2026-07-19-dotfiles-polish-design.md`

**Verified facts this plan relies on:**
- `scripts/settings/placeholder.sh` has no callers (grep confirmed).
- `TERMINAL` in `scripts/hyprland/startup.sh:8` is assigned but never used — dead, and it's the only kitty reference there.
- eww **is installed** (`/usr/bin/eww`) and the desktop-clock feature (`startup.sh`, `settings.sh` option 8) uses it → **all eww lines stay**, including `eww reload` in `wall.sh`.
- waypaper saves its config via plain truncating `open(self.config_file, "w")` (no atomic rename) → symlinked config should survive saves; verified live in Task 2.
- SDDM's `watch_wallpaper.sh` watches the awww cache, not `options/wallpaper` → unaffected by the churn fix.
- `.claude/settings.local.json` contains only paneflow-managed hooks and permission allowlists (no secrets); `paneflow/paneflow.json` is UI prefs.
- `mako/apply_wal_colors.sh` already regenerates the full mako config from a heredoc — the heredoc *is* the template, so no separate `mako/config.template` file is needed (DRY; deviation from the spec's table, same intent).

---

### Task 1: Remove superseded configs (wofi, wlogout, kitty, placeholder)

**Goal:** Delete unused tool configs and every reference to them; docs match reality.

**Files:**
- Delete: `wofi/config`, `wofi/style.css`, `wlogout/layout`, `wlogout/style.css`, `kitty/kitty.conf`, `scripts/settings/placeholder.sh`
- Modify: `install.sh:96,98,184-185`, `scripts/hyprland/startup.sh:7-8`, `scripts/fonts/apply-font.sh:59-69,85-93`, `scripts/settings/settings.sh:194`, `.gitignore:202,206,318,321,322`, `CLAUDE.md:31` + stack table, `QUICKSTART.md:65`, `README.md:189`

**Acceptance Criteria:**
- [ ] `grep -rniE "wofi|wlogout|kitty" --exclude-dir=.git --exclude-dir=docs --exclude=CHANGELOG.md .` returns nothing (CHANGELOG is historical record, docs/ contains this plan)
- [ ] `./install.sh --dry-run` completes without error
- [ ] `bash -n` passes on all four edited scripts

**Verify:** the grep above → empty; `./install.sh --dry-run` → "Installation Complete!" banner

**Steps:**

- [ ] **Step 1: Delete the files**

```bash
cd ~/.config
git rm -r wofi wlogout kitty
git rm scripts/settings/placeholder.sh
```

- [ ] **Step 2: install.sh — drop removed packages and backup entries**

Line 96: `"rofi" "rofi-emoji" "wofi" "wlogout"` → `"rofi" "rofi-emoji"`
Line 98: `"ghostty" "kitty" "fish" "starship" "neovim" "zed" "kwrite"` → `"ghostty" "fish" "starship" "neovim" "zed" "kwrite"`
Lines 184–185 (CONFIGS_TO_BACKUP):

```bash
        "hypr" "waybar" "swaync" "rofi" "mako"
        "fish" "ghostty" "nvim" "btop" "gtk-3.0" "gtk-4.0"
```

- [ ] **Step 3: startup.sh — remove dead TERMINAL assignment (lines 7–8)**

Delete:

```bash
# Use ghostty as preferred terminal (fallback to kitty if not available)
TERMINAL="${TERMINAL:-$(command -v ghostty || command -v kitty)}"
```

(`TERMINAL` is never used in the script.)

- [ ] **Step 4: apply-font.sh — remove kitty block (lines 59–69) and dead alacritty block (lines 85–93)**

Delete both `# Update Kitty font` and `# Update Alacritty font` sections (no alacritty config exists anywhere in the setup).

- [ ] **Step 5: settings.sh line 194 — fix example text**

```bash
echo "If you arent sure, its probably the same as the package name (e.g ghostty, alacritty, etc)."
```

- [ ] **Step 6: .gitignore — drop kitty/wofi/wlogout entries**

Line 202 comment → `# Waybar/rofi/hypr/ghostty/gtk/alacritty: keep config, exclude backups`
Delete line 206 `kitty/**/*.bak` and the whitelist lines `!kitty/`, `!wofi/`, `!wlogout/`.

- [ ] **Step 7: Docs**

`CLAUDE.md:31`: `echo "kitty" > ~/.config/options/terminal` → `echo "ghostty" > ~/.config/options/terminal`
`CLAUDE.md` Core Stack table: `| Terminal | Ghostty (primary), Kitty (fallback) |` → `| Terminal | Ghostty |`
`QUICKSTART.md:65`: same `echo "kitty"` → `echo "ghostty"` change
`README.md:189`: remove `wofi wlogout` and `kitty` from the package list line.

- [ ] **Step 8: Verify**

```bash
grep -rniE "wofi|wlogout|kitty" --exclude-dir=.git --exclude-dir=docs --exclude=CHANGELOG.md .
# Expected: no output
bash -n install.sh scripts/hyprland/startup.sh scripts/fonts/apply-font.sh scripts/settings/settings.sh
./install.sh --dry-run   # Expected: completes, "Installation Complete!"
```

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "remove superseded configs: wofi, wlogout, kitty, placeholder script"
```

---

### Task 2: Wallpaper-churn fix — generated state to ~/.cache via tracked symlinks

**Goal:** Wallpaper switches never dirty git; the four churning files become stable tracked symlinks into `~/.cache`.

**Files:**
- Modify: `scripts/hyprland/wall.sh:22-24`, `mako/apply_wal_colors.sh`, `install.sh:257-266`, `CLAUDE.md` (pywal flow + options descriptions)
- Create: `waypaper/config.ini.template`
- Convert to symlinks: `options/wallpaper` → `../../.cache/current_wallpaper`; `rofi/options/wallpaper.rasi` → `../../../.cache/wal/rofi-wallpaper.rasi`; `mako/config` → `../../.cache/wal/mako-config`; `waypaper/config.ini` → `../../.cache/waypaper-config.ini`

**Acceptance Criteria:**
- [ ] After a wallpaper switch (CLI and GUI): `git status --short` is empty
- [ ] All four paths are symlinks and resolve to existing files
- [ ] Colors propagate: ghostty, waybar, mako, swaync, rofi background all update
- [ ] `./install.sh --dry-run` still completes
- [ ] Plan B applied to waypaper only if its save replaces the symlink (untrack + `config.ini.example`)

**Verify:** `waypaper --wallpaper <path>` then `git status --short` → empty; `find options/wallpaper rofi/options/wallpaper.rasi mako/config waypaper/config.ini -type l | wc -l` → 4

**Steps:**

- [ ] **Step 1: wall.sh — write cache paths instead of repo paths (replace lines 22–24)**

```bash
# Record the current wallpaper and rofi background in the cache
mkdir -p "$HOME/.cache/wal"
ln -sfn "$wallpaper" "$HOME/.cache/current_wallpaper"
echo "* { wallpaper: url(\"$wallpaper\", width); }" > "$HOME/.cache/wal/rofi-wallpaper.rasi"
```

- [ ] **Step 2: mako/apply_wal_colors.sh — render to cache, read font from options**

After the `source` line add:

```bash
main_font="$(cat "$HOME/.config/options/font" 2>/dev/null || echo "FiraCode Nerd Font")"
```

Change the heredoc target: `cat > "$HOME/.cache/wal/mako-config" << EOF` (add `mkdir -p "$HOME/.cache/wal"` before it), and the font line inside the heredoc: `font=${main_font} 11`. Everything else (colors, makoctl reload) unchanged.

- [ ] **Step 3: Create waypaper/config.ini.template**

Copy of the current `waypaper/config.ini` with one change — the wallpaper line:

```ini
wallpaper = ~/Pictures/Wallpapers/wall1.jpg
```

(Full content: current `waypaper/config.ini` with only that line substituted. `post_command = ~/.config/scripts/hyprland/wall.sh` and all other keys stay.)

- [ ] **Step 4: One-time migration on this machine**

```bash
cd ~/.config
mkdir -p ~/.cache/wal
cur=$(readlink -f options/wallpaper)
ln -sfn "$cur" ~/.cache/current_wallpaper
ln -sfn ../../.cache/current_wallpaper options/wallpaper

cp rofi/options/wallpaper.rasi ~/.cache/wal/rofi-wallpaper.rasi
ln -sfn ../../../.cache/wal/rofi-wallpaper.rasi rofi/options/wallpaper.rasi

./mako/apply_wal_colors.sh          # renders ~/.cache/wal/mako-config
ln -sfn ../../.cache/wal/mako-config mako/config

cp waypaper/config.ini ~/.cache/waypaper-config.ini
ln -sfn ../../.cache/waypaper-config.ini waypaper/config.ini
```

- [ ] **Step 5: install.sh — replace the wallpaper deploy block (lines 257–266)**

```bash
# Current-wallpaper state + generated configs (cache-backed, symlinked from the repo)
if [ -n "$FIRST_WALLPAPER" ]; then
    execute ln -sfn "$FIRST_WALLPAPER" "$HOME/.cache/current_wallpaper"
    if [ "$DRY_RUN" = false ]; then
        echo "* { wallpaper: url(\"$FIRST_WALLPAPER\", width); }" > "$HOME/.cache/wal/rofi-wallpaper.rasi"
    else
        echo "[DRY RUN] write $HOME/.cache/wal/rofi-wallpaper.rasi"
    fi
    success "Wallpaper state initialized"
fi

# Render mako config from the pywal palette (wal ran above)
if [ -f "$HOME/.cache/wal/colors.sh" ]; then
    execute "$CONFIG_DIR/mako/apply_wal_colors.sh"
fi

# Seed waypaper config
if [ ! -f "$HOME/.cache/waypaper-config.ini" ]; then
    execute cp "$CONFIG_DIR/waypaper/config.ini.template" "$HOME/.cache/waypaper-config.ini"
fi
```

- [ ] **Step 6: Live verification — CLI switch**

```bash
bash -n scripts/hyprland/wall.sh mako/apply_wal_colors.sh install.sh
waypaper --wallpaper ~/Pictures/Wallpapers/earth-planet-space.jpg
sleep 3
git status --short         # Expected: empty (only staged plan-B state if triggered)
find options/wallpaper rofi/options/wallpaper.rasi mako/config waypaper/config.ini -type l | wc -l   # Expected: 4
readlink -f options/wallpaper    # Expected: the image path
./install.sh --dry-run           # Expected: completes
```

- [ ] **Step 7: Live verification — GUI switch (the waypaper symlink test)**

Open waypaper, pick a different wallpaper, close it. Then:

```bash
[ -L waypaper/config.ini ] && echo "symlink survived" || echo "PLAN B NEEDED"
git status --short   # Expected: empty
```

**Plan B (only if the symlink was replaced):** `git rm --cached waypaper/config.ini`, add `waypaper/config.ini` to `.gitignore`, rename `config.ini.template` → `config.ini.example`, and change the install.sh seed step to copy the example to `$CONFIG_DIR/waypaper/config.ini` instead of the cache path.

Also confirm visually: rofi launcher shows the new wallpaper background; a `notify-send test` notification uses the new mako colors.

- [ ] **Step 8: Docs — CLAUDE.md**

In "User Preferences": `wallpaper` described as "symlink → `~/.cache/current_wallpaper` (maintained by wall.sh)".
In "Pywal Color Flow": note that wall.sh writes generated state to `~/.cache` (`current_wallpaper`, `wal/rofi-wallpaper.rasi`, `wal/mako-config`, `waypaper-config.ini`) and the repo tracks only symlinks to it, so wallpaper switches never dirty git.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "move wallpaper-generated state to ~/.cache so switches never dirty the repo"
```

---

### Task 3: Shellcheck cleanup pass

**Goal:** All tracked scripts pass shellcheck at warning level (or carry a justified inline suppression); no behavior changes.

**Files:**
- Modify: any of the ~30 tracked `*.sh` files flagged by shellcheck

**Acceptance Criteria:**
- [ ] `shellcheck -S warning $(git ls-files '*.sh')` exits 0
- [ ] Any `# shellcheck disable=` carries a one-line justification comment
- [ ] eww lines untouched (eww installed, clock feature active); `sleep` timing in wall.sh untouched
- [ ] `bash -n` passes on every tracked script

**Verify:** `shellcheck -S warning $(git ls-files '*.sh'); echo $?` → 0

**Steps:**

- [ ] **Step 1: Ensure shellcheck is available**

```bash
command -v shellcheck || sudo pacman -S --needed shellcheck
```

- [ ] **Step 2: Run and fix**

```bash
cd ~/.config
shellcheck -S warning $(git ls-files '*.sh')
```

Fix real issues only — typical expected classes: unquoted `$(cat ...)` expansions (SC2086, e.g. `apply-font.sh:10-11`), `read` without `-r`, word-splitting arrays (`settings.sh:7` `MONITORS=( $(...) )` → `mapfile -t MONITORS < <(hyprctl monitors | grep -oP '(?<=Monitor )[^ ]+')`), useless `echo | sed` chains. Where a "fix" would change behavior (e.g. intentional word splitting), add `# shellcheck disable=SCXXXX` with a one-line reason instead. Do NOT restructure scripts, rename variables wholesale, or touch eww/sleep lines.

- [ ] **Step 3: Verify**

```bash
shellcheck -S warning $(git ls-files '*.sh'); echo "exit=$?"   # Expected: exit=0
for f in $(git ls-files '*.sh'); do bash -n "$f" || echo "SYNTAX FAIL: $f"; done   # Expected: no output
```

Spot-run the safe ones that were edited, e.g. `scripts/fonts/apply-font.sh` (idempotent) and `bash scripts/hyprland/restore-wallpaper.sh`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "shellcheck cleanup across scripts"
```

---

### Task 4: Track .claude/ and paneflow/

**Goal:** Claude Code project config and paneflow prefs are tracked; their runtime state is ignored.

**Files:**
- Modify: `.gitignore` (add lease-dir ignore)
- Track: `.claude/settings.local.json`, `paneflow/paneflow.json`

**Acceptance Criteria:**
- [ ] `git status --short` shows no `??` entries for `.claude/` or `paneflow/`
- [ ] `.claude/.paneflow-hook-leases/` is ignored
- [ ] No secrets in tracked files (verified: hooks + permission allowlists + UI prefs only)

**Verify:** `git status --short` → empty; `git check-ignore .claude/.paneflow-hook-leases/x` → path echoed

**Steps:**

- [ ] **Step 1: .gitignore — ignore paneflow lease state**

Add under the backup/temp section:

```gitignore
# Paneflow hook lease state (runtime)
.claude/.paneflow-hook-leases/
```

- [ ] **Step 2: Track the files**

```bash
git add .gitignore .claude/settings.local.json paneflow/paneflow.json
```

- [ ] **Step 3: Verify and commit**

```bash
git check-ignore .claude/.paneflow-hook-leases/test && echo ignored   # Expected: ignored
git status --short   # Expected: only staged entries, no ??
git commit -m "track claude code project settings and paneflow prefs"
```

---

## Execution notes

- Order: Task 1 → Task 2 → Task 3; Task 4 is independent and can run any time.
- This is a live desktop: after Task 2, the wallpaper pipeline must be exercised for real (both CLI and GUI switch) before the commit is considered done.
- The four uncommitted wallpaper-churn diffs currently in the working tree (`mako/config`, `options/wallpaper`, `rofi/options/wallpaper.rasi`, `waypaper/config.ini`) are consumed by Task 2's migration — do not commit or discard them beforehand.
