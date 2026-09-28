#!/bin/bash
# The panel sends writes on stdin so a Wi-Fi password never sits in argv.
set -euo pipefail
request_sh="$HOME/.config/scripts/settings/panel-request.sh"
req='{"op":"read","ids":["startup.autologin"]}'
by_argv=$(bash "$request_sh" "$req")
by_stdin=$(printf '%s\n' "$req" | bash "$request_sh" -)
[[ $by_argv == "$by_stdin" ]] || { echo "stdin reply differs: $by_stdin" >&2; exit 1; }
echo 'ok: stdin request equals argv request'

# A marker that only exists inside the request. grep reads it from a file, so
# grep's own argv never contains it.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
marker="stdin-marker-$$-$RANDOM"
printf '%s\n' "$marker" > "$tmp/pattern"
{ sleep 0.3; printf '{"op":"read","ids":["startup.autologin"],"note":"%s"}\n' "$marker"; } | bash "$request_sh" - >/dev/null &
job=$!
for _ in $(seq 1 40); do
    grep -l -a -F -f "$tmp/pattern" /proc/[0-9]*/cmdline >> "$tmp/found" 2>/dev/null || true
    sleep 0.02
done
wait "$job"
if [[ -s $tmp/found ]]; then echo "request text visible in argv: $(sort -u "$tmp/found")" >&2; exit 1; fi
echo 'ok: request text never in argv'

reply=$(bash "$request_sh" - < /dev/null || true)
[[ $reply == '{"ok":false,"error":"Expected one JSON request on stdin"}' ]] || { echo "empty stdin: $reply" >&2; exit 1; }
echo 'ok: empty stdin is rejected'
