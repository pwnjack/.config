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
# Left-click (mediatoggle.sh) switches scope between all players and
# options/mediaplayer. Transport controls are bound to middle-click and
# scroll in config.jsonc.
#

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

# An empty options file is not a missing one: `cat` succeeds and returns "",
# so a plain || fallback never fires. Both files are user-editable and are
# routinely left blank.
player=$(cat "$HOME/.config/options/player" 2>/dev/null)
[ -z "$player" ] && player="all"

user_icon=$(cat "$HOME/.config/options/mediaicon" 2>/dev/null)
[ -z "$user_icon" ] && user_icon="$DEFAULT_ICON"

if [ "$player" = "all" ]; then
    player_arg=()
    icon="$DEFAULT_ICON"
    absent=""
else
    player_arg=(--player="$player")
    icon="$user_icon"
    absent="Player '$player' isn't open"
fi

# One playerctl call, not four: tab-separated so any field may contain spaces.
IFS=$'\t' read -r status title artist album name < <(
    playerctl "${player_arg[@]}" metadata \
        --format $'{{status}}\t{{title}}\t{{artist}}\t{{album}}\t{{playerName}}' \
        2>/dev/null
)

if [ -z "$title" ]; then
    # Nothing playing. In "all" mode stay silent so waybar hides the module;
    # in single-player mode say which player is missing.
    [ -z "$absent" ] && exit 0
    if [ "$mode" = "plain" ]; then
        pango "$absent"
        echo
        exit 0
    fi
    jq -nc --arg t "$absent" '
        def pango: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
        {text: ($t | pango), tooltip: ($t | pango)}'
    exit 0
fi

# Truncate the title only. The old version measured icon+title together, so
# the glyph ate into the character budget.
short="$title"
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
