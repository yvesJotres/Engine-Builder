#!/usr/bin/env bash
# Device frame/CPU sampler for the phone over USB.
#
#   tools/diagnostics/device_perf.sh [seconds] [label]
#
# Prints one block for whatever the app was doing during that window: presented frames,
# dropped frames, average FPS, the app's own frame latency (post2acquire) and the CPU time of
# its busiest threads. Uses only SurfaceFlinger and top, so it works on the release APK:
# nothing has to be re-exported and the app does not need to be debuggable.
#
# Run it while you do ONE thing on the phone (hold the throttle, orbit the camera, sit idle),
# and compare the blocks.

set -u
SECONDS_TO_RUN="${1:-10}"
LABEL="${2:-window}"
PKG=com.enginebuilder.app
ADB="${ADB:-$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe}"
DEV="${DEV:--s RRGYC02GZQB}"

PID=$("$ADB" $DEV shell pidof "$PKG" | tr -d '\r')
if [ -z "$PID" ]; then
	echo "device_perf: $PKG is not running" >&2
	exit 1
fi

"$ADB" $DEV shell 'dumpsys SurfaceFlinger --timestats -clear' >/dev/null 2>&1
CPU_BEFORE=$("$ADB" $DEV shell "top -n 1 -b -H -p $PID -o TID,%CPU,TIME+" | tr -d '\r')
sleep "$SECONDS_TO_RUN"
STATS=$("$ADB" $DEV shell 'dumpsys SurfaceFlinger --timestats -dump' | tr -d '\r')
CPU_AFTER=$("$ADB" $DEV shell "top -n 1 -b -H -p $PID -o TID,%CPU,TIME+" | tr -d '\r')

# The per-layer block starts at its layerName line and runs to the next blank line.
LAYER=$(echo "$STATS" | awk -v pkg="$PKG" '
	/layerName = .*SurfaceView\[/ {inside = index($0, pkg) > 0}
	inside && /^$/ {inside = 0}
	inside
')
pick() { echo "$LAYER" | grep -m1 "^$1 = " | sed 's/.*= //'; }
FRAMES=$(pick totalFrames)
DROPPED=$(pick droppedFrames)
FPS=$(pick averageFPS)
JANK=$(pick jankyFrames)
P2A=$(echo "$LAYER" | awk '/post2acquire histogram/ {getline; print}' | grep -o '[0-9]*ms=[1-9][0-9]*' | tr '\n' ' ')
P2P=$(echo "$LAYER" | awk '/^present2present histogram/ {getline; print}' | grep -o '[0-9]*ms=[1-9][0-9]*' | tr '\n' ' ')

echo "== $LABEL (${SECONDS_TO_RUN}s on device) =="
echo "frames presented : ${FRAMES:-?}  -> ${FPS:-?} fps average"
echo "dropped / janky  : ${DROPPED:-?} dropped, ${JANK:-?} janky"
echo "app frame latency: ${P2A:-none outside the 0-1 ms bucket}"
echo "present interval : ${P2P:-none outside the 0-1 ms bucket}"
echo "busiest threads (after):"
echo "$CPU_AFTER" | grep -E '^[0-9]+ +[0-9]' | awk '$2 >= 5.0 {print "  tid " $1 "  " $2 "% cpu"}' | head -6
echo "cumulative cpu time (after minus before, by tid):"
join -j 1 \
	<(echo "$CPU_BEFORE" | grep -E '^[0-9]+ +[0-9]' | awk '{print $1, $3}') \
	<(echo "$CPU_AFTER" | grep -E '^[0-9]+ +[0-9]' | awk '{print $1, $3}') 2>/dev/null |
	awk '{split($2,a,":"); split($3,b,":"); d=(b[1]-a[1])*60+(b[2]-a[2]); if (d>0.20) printf "  tid %s  +%.2f s\n", $1, d}' |
	sort -k3 -nr | head -6
echo
