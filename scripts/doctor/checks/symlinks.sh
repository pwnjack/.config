#!/bin/bash
#
# Symlink integrity. The list of symlinks is derived from git itself:
# `git ls-files -s` reports mode 120000 for every tracked symlink, so no path
# is ever enumerated here and a newly committed symlink is covered the moment
# it lands. The index — not the working tree — is the source of truth for what
# *should* be a symlink, which is what lets this catch a link that some tool
# has overwritten with a regular file.
#
# The listing is read NUL-delimited (-z). Without it git renders a path holding
# a quote or a non-ASCII byte as a C-quoted string ("\303\274..."), which no
# longer names a file on disk and would be misreported as dangling.
#
# In this repo every symlink points into ~/.cache, so an absolute target is
# always a portability bug: it bakes one machine's home path into a tracked
# file. Any absolute target is therefore flagged, not just /home/*.
#

check_symlinks() {
    group "Symlinks"

    local total=0 healthy=0
    local record mode path full target relative

    # Process substitution, not a pipeline — see the contract note in lib.sh.
    while IFS= read -r -d '' record; do
        mode="${record%% *}"
        [ "$mode" = "120000" ] || continue
        # Everything past the first tab is the path, verbatim.
        path="${record#*$'\t'}"
        total=$((total + 1))
        full="$DOCTOR_ROOT/$path"

        if [ ! -L "$full" ]; then
            if [ -e "$full" ]; then
                err "$path is a regular file, but git tracks it as a symlink" \
                    "restore the link, then re-run whatever wrote through it"
            else
                err "$path is tracked as a symlink but missing from the working tree" \
                    "git -C $DOCTOR_ROOT checkout -- $path"
            fi
            continue
        fi

        target="$(readlink "$full")"

        if [ ! -e "$full" ]; then
            err "$path → $target (dangling)" \
                "recreate the target, or repoint it: ln -sfn <correct-target> $full"
        elif [[ "$target" == /* ]]; then
            # Suggest the equivalent relative target so the fix is copy-pasteable.
            relative="$(realpath -ms --relative-to="${full%/*}" "$target" 2>/dev/null)"
            warn "$path → $target (absolute target is not portable)" \
                 "ln -sfn ${relative:-<relative-target>} $full"
        else
            healthy=$((healthy + 1))
        fi
    done < <(git -C "$DOCTOR_ROOT" ls-files -sz 2>/dev/null)

    if [ "$total" -eq 0 ]; then
        warn "no tracked symlinks found — is $DOCTOR_ROOT a git repository?"
    else
        ok "$healthy of $total tracked symlinks are healthy and portable"
    fi
}
