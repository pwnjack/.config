#!/bin/bash
#
# Re-theme running Neovim instances after a palette change.
#
# Nothing is rendered: pywal itself writes ~/.cache/wal/colors-wal.vim, and
# nvim/lua/plugins/colorscheme.lua loads it through pywal16.nvim at startup.
# Each instance listens on $XDG_RUNTIME_DIR/nvim.<pid>.0 by default; asking it
# to run `colorscheme pywal16` again re-reads the file. --remote-expr evaluates
# without typing into the instance, so a buffer in insert mode is untouched.
# An instance whose user switched to another scheme is left alone.
#
# A socket can outlive a crashed instance, and an instance can be busy, so
# each request is bounded and its failure ignored: a stale editor is not a
# theming failure.
#

set -uo pipefail

command -v nvim >/dev/null 2>&1 || exit 0
runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

shopt -s nullglob
for socket in "$runtime_dir"/nvim.*.0; do
    [ -S "$socket" ] || continue
    timeout 2 nvim --server "$socket" --remote-expr \
        'execute(get(g:, "colors_name", "") ==# "pywal16" ? "colorscheme pywal16" : "")' \
        >/dev/null 2>&1 || true
done

exit 0
