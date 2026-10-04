#!/bin/bash
#
# Tests for scripts/waybar/network.sh.
#
# The script is sourced -- it starts its loop only when executed -- and its
# functions run against a fixture sysfs and /proc/net, the NET_SYSFS/NET_PROC
# seam. One end-to-end run at the bottom executes it the way Waybar does.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck disable=SC1091 # Shared assertions are checked by their own suite.
# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"
# The user's own Bar page choice must not steer the baseline: an empty options
# directory means every mode is its default. Mode tests set NET_MODE.
export BAR_OPTIONS="$TMP/no-options"
# shellcheck disable=SC1091 # network.sh is linted on its own.
. "$TEST_DIR/network.sh"

# fixture — a fresh sysfs and proc root; NET_SYSFS/NET_PROC point at them
fixture() {
    NET_SYSFS=$(mktemp -d "$TMP/sys.XXXXXX")
    NET_PROC=$(mktemp -d "$TMP/proc.XXXXXX")
    : > "$NET_PROC/route"
    : > "$NET_PROC/ipv6_route"
    : > "$NET_PROC/dev"
}

# iface <name> <physical|virtual> [uevent-line] [operstate]
iface() {
    mkdir -p "$NET_SYSFS/$1"
    [ "$2" = physical ] && : > "$NET_SYSFS/$1/device"
    printf 'INTERFACE=%s\n%s\n' "$1" "${3:-}" > "$NET_SYSFS/$1/uevent"
    printf '%s\n' "${4:-up}" > "$NET_SYSFS/$1/operstate"
}

# route4 <iface> <dest> <mask> — one /proc/net/route row
route4() {
    printf '%s\t%s\t01B2A8C0\t0003\t0\t0\t100\t%s\t0\t0\t0\n' "$1" "$2" "$3" >> "$NET_PROC/route"
}

# route6_default <iface> — one ::/0 row in /proc/net/ipv6_route
route6_default() {
    printf '%s 00 %s 00 %s 0000005f 00000001 00000000 00000003 %8s\n' \
        00000000000000000000000000000000 00000000000000000000000000000000 \
        fdeb446c912d08da0000000000000001 "$1" >> "$NET_PROC/ipv6_route"
}

echo "interface choice"

fixture
iface eno1 physical
iface ipv6leakintrf0 virtual
iface proton0 virtual DEVTYPE=wireguard unknown
printf 'Iface\tDestination\tGateway\tFlags\tRefCnt\tUse\tMetric\tMask\tMTU\tWindow\tIRTT\n' > "$NET_PROC/route"
route4 eno1 00000000 00000000
route4 eno1 00B2A8C0 00FFFFFF
route6_default ipv6leakintrf0
net_iface
assert_eq "$REPLY" eno1 "Proton's leak dummy with a better IPv6 metric does not win over the NIC"

fixture
iface wlan0 physical
mkdir -p "$NET_SYSFS/wlan0/wireless"
route6_default wlan0
net_iface
assert_eq "$REPLY" wlan0 "an IPv6-only default route on a physical interface counts"

fixture
iface eno1 physical
iface proton0 virtual DEVTYPE=wireguard unknown
route4 proton0 00000000 00000000
route6_default proton0
net_iface
assert_eq "$REPLY" "" "default routes only through a tunnel read as offline"

fixture
iface eno1 physical
route4 eno1 00B2A8C0 00FFFFFF
net_iface
assert_eq "$REPLY" "" "a link without a default route reads as offline"

echo
echo "counters"

fixture
printf '%s\n' \
    'Inter-|   Receive                                                |  Transmit' \
    ' face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed' \
    '  eno1: 834145522  812967    0 11078    0     0          0      2725 407745073  630900    0    0    0     0       0          0' \
    'proton0:780604028  785045    0    0    0     0          0         0 378275136  623168    0    0    0     0       0          0' \
    > "$NET_PROC/dev"
net_counters eno1
assert_eq "$RX/$TX" 834145522/407745073 "a padded row splits on colon and space"
net_counters proton0
assert_eq "$RX/$TX" 780604028/378275136 "a row with no space after the colon still splits"
net_counters missing
assert_eq "$?" 1 "an unknown interface reports failure"

echo
echo "rate format"

for case in '0|0 KB/s' '102400|100 KB/s' '1023999|999 KB/s' '1024000|1.0 MB/s' '1048576|1.0 MB/s' \
            '13002343|12.4 MB/s' '104857599|99.9 MB/s' '104857600|100 MB/s' \
            '157286400|150 MB/s' '1048576000|1.0 GB/s' '1181116007|1.1 GB/s'; do
    net_human "${case%%|*}"
    assert_eq "$REPLY" "${case#*|}" "${case%%|*} B/s renders as '${case#*|}'"
done

echo
echo "visibility"

NET_SHOW=100 NET_LINGER=3 NET_QUIET=3
seen=''
for rate in 0 500 0 0 0 0; do
    if net_visible "$rate" 0; then seen+='1'; else seen+='0'; fi
done
assert_eq "$seen" 011100 "hidden while idle, shown on traffic, hidden after three quiet ticks"
NET_QUIET=3
net_visible 0 100
assert_eq "$?" 0 "upload alone reaching the threshold shows the module"
NET_QUIET=3
net_visible 60 60
assert_eq "$?" 0 "neither direction alone, but their sum reaching the threshold shows the module"
NET_QUIET=3
net_visible 40 40
assert_eq "$?" 1 "a combined rate below the threshold stays hidden"

echo
echo "vpn"

fixture
iface eno1 physical
iface proton0 virtual DEVTYPE=wireguard unknown
net_vpn
assert_eq "$REPLY" proton0 "a WireGuard interface in state unknown is an active VPN"
fixture
iface tun0 virtual
: > "$NET_SYSFS/tun0/tun_flags"
net_vpn
assert_eq "$REPLY" tun0 "a tun interface is a VPN"
fixture
iface proton0 virtual DEVTYPE=wireguard down
net_vpn
assert_eq "$REPLY" "" "a VPN interface that is down is not reported"

echo
echo "render"

fixture
iface eno1 physical
# shellcheck disable=SC2034 # read by the sourced functions
NET_SHOW=102400 NET_LINGER=3 NET_QUIET=3
net_render "" 0 0 "" ""
assert_json_field "$OUT" .class offline "no interface renders the offline class"
assert_json_contains "$OUT" .text Offline "offline says so"
net_render eno1 0 0 192.168.178.23 ""
assert_json_field "$OUT" .text "" "idle renders empty text, which hides the module"
assert_json_lacks "$OUT" .tooltip "B/s" "no breakdown in the tooltip while the readout is hidden"
assert_json_contains "$OUT" .tooltip "eno1  192.168.178.23" "the idle tooltip still names the interface and address"
net_render eno1 13002343 839680 192.168.178.23 proton0
assert_json_contains "$OUT" .text "</span>13.2 MB/s" "the combined rate sits flush against its glyph span"
assert_json_contains "$OUT" .text "$NET_GLYPH_RATE" "the bar uses the single up/down glyph"
assert_json_lacks "$OUT" .text "12.4" "the bar shows no per-direction rate"
assert_json_field "$OUT" '.tooltip | split("\n")[0]' \
    "$NET_GLYPH_DOWN 12.4 MB/s   $NET_GLYPH_UP 820 KB/s" "the tooltip's first line is the breakdown"
assert_json_contains "$OUT" .tooltip "eno1  192.168.178.23" "the tooltip names the interface and address"
assert_json_contains "$OUT" .tooltip "VPN  proton0" "the tooltip names the VPN"
net_render 'we"ird<&' 0 0 "" ""
assert_json_contains "$OUT" .tooltip 'we"ird&lt;&amp;' "names are escaped for JSON and Pango"
net_render $'en\001x\bq' 0 0 "" ""
assert_json_contains "$OUT" .tooltip "enxq" "control characters are dropped, keeping the JSON valid"

echo
echo "modes"

fixture
iface eno1 physical
# shellcheck disable=SC2034 # read by the sourced functions
NET_QUIET=3
NET_MODE=always net_render eno1 0 0 "" ""
assert_json_contains "$OUT" .text "0 KB/s" "always shows the rate with no traffic"
# shellcheck disable=SC2034 # read by the sourced functions
NET_QUIET=3
NET_MODE=offline net_render eno1 13002343 0 "" ""
assert_json_field "$OUT" .text "" "offline-only never shows the rate"
NET_MODE=offline net_render "" 0 0 "" ""
assert_json_field "$OUT" .class offline "offline-only still reports Offline"

echo
echo "end to end"

fixture
iface eno1 physical
route4 eno1 00000000 00000000
printf '  eno1: 100 0 0 0 0 0 0 0 200 0 0 0 0 0 0 0\n' > "$NET_PROC/dev"
first=$(NET_SYSFS=$NET_SYSFS NET_PROC=$NET_PROC NET_INTERVAL=0.1 timeout 2 bash "$TEST_DIR/network.sh" | head -n 1)
assert_json_field "$first" .class active "the executed script emits a first line"
fixture
first=$(NET_SYSFS=$NET_SYSFS NET_PROC=$NET_PROC NET_INTERVAL=0.1 timeout 2 bash "$TEST_DIR/network.sh" | head -n 1)
assert_json_field "$first" .class offline "the executed script reports offline with no route"

# Offline is stable, so after the first line nothing is written and a closed
# stdout would go unnoticed: the parent's exit is what must stop the loop.
# The parent lingers so the child records it as $PPID before it disappears.
bash -c 'NET_INTERVAL=0.1 bash "$1" > /dev/null & echo $!; sleep 0.3' _ "$TEST_DIR/network.sh" > "$TMP/pid"
child=$(<"$TMP/pid")
alive=gone
for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$child" 2>/dev/null || break
    sleep 0.1
done
kill -0 "$child" 2>/dev/null && { alive=running; kill "$child"; }
assert_eq "$alive" gone "the loop exits once its parent is gone, even with nothing to write"

# The reader closes while this shell -- the parent -- lives on. Offline never
# changes, so only the periodic re-send can hit the closed pipe.
exec {reader}< <(NET_SYSFS=$NET_SYSFS NET_PROC=$NET_PROC NET_INTERVAL=0.05 NET_BEAT=4 bash "$TEST_DIR/network.sh")
child=$!
read -r -u "$reader" _
exec {reader}<&-
alive=gone
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    kill -0 "$child" 2>/dev/null || break
    sleep 0.1
done
kill -0 "$child" 2>/dev/null && { alive=running; kill "$child"; }
assert_eq "$alive" gone "the loop exits once its reader closes, even with an unchanged line"

test_summary test-network
