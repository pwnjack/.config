#!/bin/bash
# The panel sends writes on stdin so a Wi-Fi password never sits in argv.
set -euo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$test_dir/../../.." && pwd)
request_sh="$repo_root/scripts/settings/panel-request.sh"
request_js="$repo_root/quickshell/settings-panel/request.js"
shell_qml="$repo_root/quickshell/settings-panel/shell.qml"

# Structural guards: the dynamic checks below never run shell.qml, so the QML
# side is pinned by allowlists rather than by patterns a rewrite could dodge.
guard_fail() { echo "shell.qml: $1" >&2; exit 1; }
# The request lives in writeRequest, which may only be declared, filled in
# drain(), written in the writer's onStarted, and cleared.
mapfile -t request_uses < <(grep -n 'writeRequest' "$shell_qml" | sed 's/^[0-9]*://; s/^[[:space:]]*//')
allowed_uses=(
    'property string writeRequest: ""'
    'writeRequest = JSON.stringify(request);'
    'onStarted: { writer.write(root.writeRequest + "\n"); root.writeRequest = ""; }'
    'root.writeRequest = "";'
)
for use in "${request_uses[@]}"; do
    known=false
    for allowed in "${allowed_uses[@]}"; do [[ $use == "$allowed" ]] && known=true; done
    [[ $known == true ]] || guard_fail "unexpected use of writeRequest: $use"
done
(( ${#request_uses[@]} == 4 )) || guard_fail "expected exactly 4 writeRequest lines, found ${#request_uses[@]}"
[[ $(grep -c 'JSON\.stringify(request)' "$shell_qml") == 1 ]] || guard_fail 'the request may only be serialised into writeRequest'
[[ $(grep -c 'writer\.command' "$shell_qml") == 1 ]] || guard_fail 'writer.command may only be set once'
grep -Eq '^[[:space:]]*writer\.command = \[[^]]*,[[:space:]]*"-"\];[[:space:]]*$' "$shell_qml" || guard_fail 'writer.command must end with the stdin marker "-"'
# No process in the panel needs a custom environment; any would be a place to leak into.
! grep -q 'environment' "$shell_qml" || guard_fail 'no Process may set an environment'
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
panel_ready=false
for _ in $(seq 1 300); do
    panel_argv=()
    if [[ -r /proc/$job/cmdline ]]; then
        mapfile -d '' -t panel_argv < "/proc/$job/cmdline"
        for arg in "${panel_argv[@]}"; do
            if [[ $arg == "$request_sh" ]]; then
                panel_ready=true
                break 2
            fi
        done
    fi
    sleep 0.01
done
if [[ $panel_ready != true ]]; then
    echo 'timed out waiting for panel-request.sh to exec' >&2
    exit 1
fi
[[ ${panel_argv[-1]} == - && ${#panel_argv[@]} == 3 ]] || {
    printf 'unexpected panel-request argv:' >&2
    printf ' <%s>' "${panel_argv[@]}" >&2
    printf '\n' >&2
    exit 1
}

# Sample continuously for the full request lifetime. The fake gjs delay keeps
# the job alive long enough that a zero-iteration sampler is itself a failure.
# This is best effort: a child living a millisecond or so falls between
# samples. The deterministic guards are the static shell.qml checks above and
# the gjs argv capture below; secrets past request.js stay in-process (libnm).
: > "$tmp/found-argv"
: > "$tmp/found-environ"
sample_count=0
deadline=$((SECONDS + 20))
while kill -0 "$job" 2>/dev/null; do
    (( SECONDS < deadline )) || { pkill -P "$job" 2>/dev/null; kill "$job" 2>/dev/null; echo 'request never finished' >&2; exit 1; }
    sample_count=$((sample_count + 1))
    grep -l -a -F -f "$tmp/pattern" /proc/[0-9]*/cmdline >> "$tmp/found-argv" 2>/dev/null || true
    grep -l -a -F -f "$tmp/pattern" /proc/[0-9]*/environ >> "$tmp/found-environ" 2>/dev/null || true
done
wait "$job"
(( sample_count > 0 )) || { echo 'process sampler ran zero times' >&2; exit 1; }
if [[ -s $tmp/found-argv ]]; then echo "request text visible in argv: $(sort -u "$tmp/found-argv")" >&2; exit 1; fi
if [[ -s $tmp/found-environ ]]; then echo "request text visible in environment: $(sort -u "$tmp/found-environ")" >&2; exit 1; fi
mapfile -d '' -t gjs_argv < "$tmp/gjs-argv"
[[ ${#gjs_argv[@]} == 3 && ${gjs_argv[0]} == -m && ${gjs_argv[1]} == "$request_js" && ${gjs_argv[2]} == - ]] || {
    printf 'unexpected gjs argv:' >&2
    printf ' <%s>' "${gjs_argv[@]}" >&2
    printf '\n' >&2
    exit 1
}
echo 'ok: request text never in argv or environment'

set +e
reply=$(bash "$request_sh" - < /dev/null)
status=$?
set -e
[[ $status == 1 ]] || { echo "empty stdin exit status: $status" >&2; exit 1; }
[[ $reply == '{"ok":false,"error":"Expected one JSON request on stdin"}' ]] || { echo "empty stdin: $reply" >&2; exit 1; }
echo 'ok: empty stdin is rejected'

# A caller that keeps stdin open without sending a line must fail, not hang.
# The writer end stays open for 30 s; without the read timeout this would hang
# until `timeout` kills it (status 124).
exec 3< <(sleep 30)
silent_writer=$!
set +e
reply=$(SETTINGS_STDIN_TIMEOUT=1 timeout 10 bash "$request_sh" - <&3)
status=$?
set -e
exec 3<&-
kill "$silent_writer" 2>/dev/null || true
[[ $status == 1 && $reply == '{"ok":false,"error":"Expected one JSON request on stdin"}' ]] || { echo "silent stdin: status=$status reply=$reply" >&2; exit 1; }
echo 'ok: silent stdin times out'
