#!/bin/bash
#
# Media status for waybar, and for hyprlock with --plain.
#
# Emits JSON so the module can carry a tooltip. Built with jq because track
# titles are arbitrary text -- a quote or backslash in a song name would
# break hand-written JSON and blank the module.
#
# hyprlock labels take one line of plain text, not JSON, so it calls this with
# --plain: same icon and truncation, no tooltip, no <span> (the lock screen
# has its own font_size and does not share waybar's scale). Both modes still
# escape Pango entities -- hyprlock parses label markup exactly as waybar does.
#
# The glyph is wrapped in <span size='large'> to match the bar scale: every
# module sits at 13px and promotes its glyph by a fifth. See waybar/style.css.
# Because the markup counts toward waybar's max-length, that key is deliberately
# absent from the module config -- truncation happens here instead, on the
# title alone.
#
# Which player is shown is decided by medialib.sh, not by a stored preference.
# All the click and scroll bindings are transport controls (mediactl.sh).
#

# shellcheck source=./medialib.sh
. "$HOME/.config/scripts/hyprland/medialib.sh"

MAXLEN=38
DEFAULT_ICON=$'\U000f075a'

mode="json"
[ "$1" = "--plain" ] && mode="plain"

# & must be replaced first or it would re-escape the entities produced by the
# other two. The backslashes are required: since bash 5.2 a bare & in a ${//}
# replacement expands to the matched text, so "&lt;" would yield "<lt;".
pango() {
    local s=${1//&/\&amp;}
    s=${s//</\&lt;}
    printf '%s' "${s//>/\&gt;}"
}

# The glyph is not configurable. There used to be an options/mediaicon, but it
# was only ever consulted when the module was pinned to a single player, and
# the module was always in "all" mode -- so for its whole life it was read by
# nothing. Wiring it up during a rewrite silently swapped the bar's note glyph
# for whatever stale value the file held. One icon, in one place, is the honest
# arrangement.
icon="$DEFAULT_ICON"

# MEDIA_SEP, not a tab: see the comment on it in medialib.sh.
IFS="$MEDIA_SEP" read -r name status title artist album < <(media_snapshot)

# Nothing playing: stay silent so waybar hides the module.
[ -z "$title" ] && exit 0

# "Artist - Title" when the player gives an artist, which for music is the half
# that identifies the song -- Spotify titles like "Before Taxes (feat. The
# 1978ers)" say nothing about who made it. Browsers put the channel here, so a
# YouTube tab reads "Smoke - Inside Alcatraz", which is also what you want.
label="$title"
[ -n "$artist" ] && label="$artist - $title"

# Truncate the whole label, not the title alone: the artist is part of the
# width now, and the bar's budget is the same either way. Truncating before
# escaping is what keeps a cut from landing inside an &amp;.
short="$label"
[ "${#short}" -gt "$MAXLEN" ] && short="${short:0:$MAXLEN}…"

if [ "$mode" = "plain" ]; then
    printf '%s  %s\n' "$(pango "$icon")" "$(pango "$short")"
    exit 0
fi

jq -nc \
    --arg icon "$icon" \
    --arg short "$short" \
    --arg title "$title" \
    --arg artist "$artist" \
    --arg album "$album" \
    --arg status "$status" \
    --arg name "$name" '
    # Waybar parses every label as Pango markup, so an ampersand in a track
    # name -- "Simon & Garfunkel" -- is malformed markup and blanks the
    # module. Escape before embedding, same order as the shell pango() above.
    def pango: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
    {
        text: ("<span size=\"large\">" + ($icon | pango) + "</span>  "
               + ($short | pango)),
        tooltip: ([($title | pango),
                   (if $artist == "" then empty else ($artist | pango) end),
                   (if $album  == "" then empty else ($album  | pango) end)]
                  | join("\n")
                  + "\n\n" + ($status | pango) + " · " + ($name | pango)),
        class: ($status | ascii_downcase)
    }'
