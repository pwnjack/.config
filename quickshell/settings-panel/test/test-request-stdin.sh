#!/bin/bash
# The panel sends writes on stdin so a Wi-Fi password never sits in argv.
set -euo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$test_dir/../../.." && pwd)
request_sh="$repo_root/scripts/settings/panel-request.sh"
request_js="$repo_root/quickshell/settings-panel/request.js"
shell_qml="$repo_root/quickshell/settings-panel/shell.qml"

grep -Eq '^[[:space:]]*writer\.command = \[[^]]*,[[:space:]]*"-"\];[[:space:]]*$' "$shell_qml" || {
    echo 'writer.command must end with the stdin marker "-"' >&2
    exit 1
}
if grep -Eq 'command[[:space:]]*=.*(JSON\.stringify\(request\)|writeRequest)' "$shell_qml"; then
    echo 'writer.command must not put request JSON in argv' >&2
    exit 1
fi
echo 'ok: panel writer command uses stdin'

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export XDG_CACHE_HOME="$tmp/cache"

req='{"op":"read","ids":["startup.autologin"]}'
by_argv=$(bash "$request_sh" "$req")
by_stdin=$(printf '%s\n' "$req" | bash "$request_sh" -)
[[ $by_argv == "$by_stdin" ]] || { echo "stdin reply differs: $by_stdin" >&2; exit 1; }
by_unterminated_stdin=$(printf '%s' "$req" | bash "$request_sh" -)
[[ $by_argv == "$by_unterminated_stdin" ]] || { echo "unterminated stdin reply differs: $by_unterminated_stdin" >&2; exit 1; }
echo 'ok: stdin request equals argv request'

# A marker that only exists inside the request. grep reads it from a file, so
# grep's own argv never contains it.
marker="stdin-marker-$$-$RANDOM"
printf '%s\n' "$marker" > "$tmp/pattern"
real_gjs=$(command -v gjs)
mkdir "$tmp/bin"
cat > "$tmp/bin/gjs" <<'EOF'
#!/bin/bash
printf '%s\0' "$@" > "$GJS_ARGV_FILE"
sleep 0.15
exec "$REAL_GJS" "$@"
EOF
chmod +x "$tmp/bin/gjs"

{ sleep 0.2; printf '{"op":"read","ids":["startup.autologin"],"note":"%s"}\n' "$marker"; } |
    PATH="$tmp/bin:$PATH" REAL_GJS="$real_gjs" GJS_ARGV_FILE="$tmp/gjs-argv" bash "$request_sh" - >/dev/null &
job=$!

# The request helper is blocked in read here. Its sole request argument must be
# the stdin marker, never the JSON that will arrive through the pipe.
for _ in $(seq 1 1000); do
    [[ -s /proc/$job/cmdline ]] && break
done
mapfile -d '' -t panel_argv < "/proc/$job/cmdline"
[[ ${panel_argv[-1]} == - && ${#panel_argv[@]} == 3 ]] || {
    printf 'unexpected panel-request argv:' >&2
    printf ' <%s>' "${panel_argv[@]}" >&2
    printf '\n' >&2
    exit 1
}

# Sample continuously for the full request lifetime; a 20 ms interval can miss
# a short-lived process that accidentally receives the request in argv.
: > "$tmp/found"
while [[ -s /proc/$job/cmdline ]]; do
    grep -l -a -F -f "$tmp/pattern" /proc/[0-9]*/cmdline >> "$tmp/found" 2>/dev/null || true
done
wait "$job"
if [[ -s $tmp/found ]]; then echo "request text visible in argv: $(sort -u "$tmp/found")" >&2; exit 1; fi
mapfile -d '' -t gjs_argv < "$tmp/gjs-argv"
[[ ${#gjs_argv[@]} == 3 && ${gjs_argv[0]} == -m && ${gjs_argv[1]} == "$request_js" && ${gjs_argv[2]} == - ]] || {
    printf 'unexpected gjs argv:' >&2
    printf ' <%s>' "${gjs_argv[@]}" >&2
    printf '\n' >&2
    exit 1
}
echo 'ok: request text never in argv'

set +e
reply=$(bash "$request_sh" - < /dev/null)
status=$?
set -e
[[ $status == 1 ]] || { echo "empty stdin exit status: $status" >&2; exit 1; }
[[ $reply == '{"ok":false,"error":"Expected one JSON request on stdin"}' ]] || { echo "empty stdin: $reply" >&2; exit 1; }
echo 'ok: empty stdin is rejected'
