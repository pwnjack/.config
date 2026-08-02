#!/bin/bash
#
# Region screenshot -> swappy, for marking up before saving.
#
# Deliberately additive: $Mod,S still writes straight to disk and the rofi
# menu's first three entries are untouched. Annotation is opt-in, because
# putting an editor in front of every capture taxes the quick grab that is
# most of what screenshots are for.
#
# --raw streams the PNG to stdout instead of writing a file; where the result
# finally lands is swappy's decision, from swappy/config.
#
# USE THE LONG FORM, and do not add -s. Both rules come from reading
# /usr/bin/hyprshot rather than its --help:
#
#   * -s is a no-op here. save_geometry() (line 112) does
#     `if [ $RAW -eq 1 ]; then grim -g "$geometry" -; return 0; fi`, returning
#     before send_notification() on line 129. In raw mode there is no
#     notification to silence.
#   * `-r -s` only works by accident. hyprshot's short spec is `hf:o:m:dszr:t:`
#     -- `r:` declares a REQUIRED argument, though the long `raw` declares
#     none. Verified: getopt binds -s as -r's argument, returning
#     `-m 'region' -r '-s' --`, and it survives only because hyprshot's -r arm
#     shifts by one and re-parses. Reverse the two flags and getopt fails with
#     `option requires an argument -- 'r'`; hyprshot never checks getopt's exit
#     status, so it would carry on with RAW=0, WRITE A FILE, and pipe nothing
#     to swappy. `--raw` takes no argument and cannot be reordered into a trap.
#
# Both surfaces that offer annotation -- the $Mod ALT+S keybind and the fourth
# entry in rofi/screenshot.sh -- call this script rather than repeating the
# pipeline, so they cannot drift apart.
#

command -v hyprshot >/dev/null 2>&1 || exit 0
command -v swappy   >/dev/null 2>&1 || exit 0

hyprshot -m region --raw | swappy -f -
