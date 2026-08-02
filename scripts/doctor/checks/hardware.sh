#!/bin/bash
#
# Host hardware truth: no tracked config names a display output that this
# machine does not have.
#
# Nothing is enumerated here. The valid set comes from the kernel, the
# occurrences come from `git ls-files -z`. A config file added tomorrow is
# covered the moment it is committed.
#
# WHY /sys/class/drm RATHER THAN hyprctl. The doctor must be runnable from a
# TTY with no compositor — that is exactly when a broken monitor config is
# worth diagnosing — and sysfs answers there. hyprctl does not.
#
# SEVERITY IS WARN, NEVER ERROR. Naming a connector that happens to be
# unplugged right now is legitimate: a docked laptop, a monitor switched off at
# the wall. The finding says the config is stale, not that the session is
# broken, and doctor.sh must not exit 1 on a machine whose session came up fine.
#
# WHAT IS DELIBERATELY NOT SCANNED:
#
#   *.md — README.md and QUICKSTART.md carry connector names as deliberate
#   examples of what a value looks like. This is the same reasoning that
#   already excludes docs/ from references.sh's literal-path scan.
#
#   docs/ — the specs and plans quote real connector names when recording what
#   was measured on a given machine.
#
#   scripts/doctor/ — this file's own pattern below, and its fixtures, are made
#   of connector names.
#
# Accepted limitation: a connector name inside a comment reads the same as one
# in a live setting. Distinguishing them means knowing the comment syntax of
# every tracked file type, which is a worse trade than one occasional finding
# on a line that was already documenting the stale value.

# The DRM connector namespace, as the kernel spells it. This is upstream
# vocabulary — the same kind of constant as DOCTOR_WAYBAR_ACTIONS in waybar.sh,
# and stale only on a kernel release, never on a change to this repo. eDP is
# listed before DP so a leading `e` is consumed rather than left dangling.
DOCTOR_DRM_CONNECTOR_RE='(eDP|DP|HDMI-A|HDMI-B|DVI-D|DVI-I|DVI-A|LVDS|DSI|VGA|Virtual)-[0-9]+'

# Overridable so the test suite can point the probe at a fake DRM tree instead
# of the running machine. Same seam, for the same reason, as BATTERY_SYSFS in
# scripts/waybar/battery.sh.
DOCTOR_DRM_SYSFS="${DOCTOR_DRM_SYSFS:-/sys/class/drm}"

# _hw_connected_outputs — host probe, in its own function so tests can aim it.
#
# Node names are card<N>-<CONNECTOR>; the card prefix is stripped so what comes
# back is the name Hyprland, hyprlock and awww all use. The strip is a
# shortest-match prefix removal, so a multi-dash name survives whole.
_hw_connected_outputs() {
    local node base status
    for node in "$DOCTOR_DRM_SYSFS"/card*-*; do
        [ -r "$node/status" ] || continue
        read -r status < "$node/status" || continue
        [ "$status" = "connected" ] || continue
        base="${node##*/}"
        printf '%s\n' "${base#card*-}"
    done
}

check_hardware() {
    group "Hardware"

    local before_warnings="$DOCTOR_WARNINGS"
    local connected file token

    connected="$(_hw_connected_outputs)"

    if [ -z "$connected" ]; then
        note "no connected display output found under $DOCTOR_DRM_SYSFS — skipping the connector scan" \
             "run doctor.sh on the machine itself; a container has no DRM nodes to read"
        return 0
    fi

    # Process substitution, not a pipeline — see the contract note in lib.sh.
    # -z and -d '' because git C-quotes any path holding a non-ASCII or quote
    # character, and the quoted form names no file on disk.
    while IFS= read -r -d '' file; do
        case "$file" in
            *.md|docs/*|scripts/doctor/*) continue ;;
        esac
        [ -f "$DOCTOR_ROOT/$file" ] || continue

        while IFS= read -r token; do
            [ -n "$token" ] || continue
            printf '%s\n' "$connected" | grep -qxF -- "$token" && continue
            warn "$file names $token, which is not a connected output on this machine" \
                 "update $(doctor_q "$DOCTOR_ROOT/$file"), or leave the value empty to mean no preference"
        done < <(grep -ohIE "$DOCTOR_DRM_CONNECTOR_RE" "$DOCTOR_ROOT/$file" 2>/dev/null | sort -u)
    done < <(git -C "$DOCTOR_ROOT" ls-files -z)

    # ok is the all-clear and nothing else.
    if [ "$DOCTOR_WARNINGS" -eq "$before_warnings" ]; then
        ok "no tracked config names a disconnected output"
    fi
}
