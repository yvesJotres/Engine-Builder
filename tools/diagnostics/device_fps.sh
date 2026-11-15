#!/usr/bin/env bash
# Launch Engine Builder on the phone, press PLAY, and read the FPS strip off the screen.
#
#   tools/diagnostics/device_fps.sh [label]
#
# Prints the line the game's own "Show FPS" overlay draws (frame rate, frame time, GPU
# time, RAM, VRAM). Needs Pillow on the PC (`py -m pip install pillow`) and the debug APK,
# because the settings file is written through `run-as`.
#
# The overlay is turned on before the app starts, so the numbers are live from the first frame.

set -u
LABEL="${1:-run}"
PKG=com.enginebuilder.app
ADB="${ADB:-$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe}"
DEV="${DEV:--s RRGYC02GZQB}"
PY="${PY:-$LOCALAPPDATA/Programs/Python/Python312/python.exe}"
SHOT="$LOCALAPPDATA/hermes/cache/scratch/eb_shot.png"
TMPCFG="$LOCALAPPDATA/hermes/cache/scratch/eb_settings.cfg"
mkdir -p "$(dirname "$SHOT")"

"$ADB" $DEV shell am force-stop "$PKG" >/dev/null 2>&1
printf '[options]\n\nfps=true\naccuracy=0\n' > "$TMPCFG"
"$ADB" $DEV push "$TMPCFG" /data/local/tmp/eb_settings.cfg >/dev/null 2>&1
"$ADB" $DEV shell run-as "$PKG" cp /data/local/tmp/eb_settings.cfg /data/data/$PKG/files/settings.cfg
"$ADB" $DEV shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 10
# PLAY sits at the bottom of the launcher card; the card is centred on the 2340x1080 surface.
"$ADB" $DEV shell input tap 1170 700
sleep 8
"$ADB" $DEV exec-out screencap -p > "$SHOT"

"$PY" - "$SHOT" "$LABEL" <<'PYEOF'
import sys
from PIL import Image
path, label = sys.argv[1], sys.argv[2]
im = Image.open(path).convert("L")
if im.size[0] < im.size[1]:
    im = im.transpose(Image.ROTATE_90)
# The strip is black with white text at x 372.., y 124..160 in the 1920x1080 layout (device px = layout px).
crop = im.crop((370, 120, min(2330, im.size[0]), 165))
px = crop.load()
w, h = crop.size
cols = [sum(1 for y in range(4, min(45, h)) if px[x, y] > 170) for x in range(w)]
# split into glyph groups separated by >=6 blank columns
groups, x = [], 0
while x < w:
    if cols[x]:
        x2 = x
        while x2 < w and (cols[x2] or sum(cols[x2:x2 + 6])):
            x2 += 1
        groups.append((x, x2))
        x = x2
    else:
        x += 1
if not groups:
    print(f"{label}: no overlay text found - is Show FPS on?")
    sys.exit(1)
print(f"{label}: overlay text from x {groups[0][0] + 370} to {groups[-1][1] + 370}, {len(groups)} glyph groups")
crop.resize((crop.width * 2, crop.height * 2), Image.LANCZOS).save(path.replace(".png", "_strip.png"))
print(f"strip saved to {path.replace('.png', '_strip.png')}")
PYEOF
