#!/bin/bash
#
# SDDM Wallpaper Updater (user side)
# Delegates the privileged work to the root-owned installed helper via sudo.
# Run setup-sudo.sh once to allow this to happen without a password
# (required for automatic updates from watch_wallpaper.sh).
#

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
setup_script="$script_dir/setup-sudo.sh"
installed_helper=""
installed_helpers=()

if [[ -f "$setup_script" ]]; then
    mapfile -t installed_helpers < <(
        sed -n 's/^INSTALLED_HELPER="\([^"]*\)"$/\1/p' "$setup_script"
    )
fi

if [[ "${#installed_helpers[@]}" -ne 1 ]]; then
    echo "Error: cannot derive one installed SDDM helper from $setup_script; run it to repair the setup" >&2
    exit 1
fi
installed_helper="${installed_helpers[0]}"

helper_metadata=$(stat -c '%u %a' -- "$installed_helper" 2>/dev/null)
helper_owner=${helper_metadata%% *}
helper_mode=${helper_metadata#* }
if [[ -L "$installed_helper" || ! -f "$installed_helper" || ! -x "$installed_helper" ||
      "$helper_owner" != "0" || ! "$helper_mode" =~ ^[0-7]+$ ]] ||
   (( (8#$helper_mode & 8#022) != 0 )); then
    echo "Error: installed SDDM helper is missing or unsafe; run $setup_script" >&2
    exit 1
fi

# Passwordless sudo (configured by setup-sudo.sh)
if sudo -n "$installed_helper" "$USER" 2>/dev/null; then
    if [[ -t 0 ]]; then
        echo "The SDDM wallpaper has been updated to your current wallpaper"
    fi
    exit 0
fi

# Interactive fallback: prompt for the sudo password
if [[ -t 0 ]]; then
    echo "Updating SDDM wallpaper (sudo password may be required)..."
    echo "Tip: run $setup_script once to make this automatic."

    if sudo "$installed_helper" "$USER"; then
        echo "The SDDM wallpaper has been updated to your current wallpaper"
        exit 0
    fi
    echo "Error: failed to update the SDDM wallpaper" >&2
    exit 1
fi

# The watcher journals this diagnostic but cannot consume the background job's
# status; a direct non-interactive run must report the broken sync too.
echo "Error: automatic SDDM wallpaper update failed; run $setup_script to configure passwordless sudo" >&2
exit 1
