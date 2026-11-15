"""Gamepad calibration for Engine Builder.

Waits for each control, one at a time, and only moves on when that control is actually actuated. There is no timer:
squeeze the trigger as slowly as you like. Press S to skip a control, Q (or Ctrl+C) to quit.

Reads the pad through Windows XInput - no pip packages, no Godot.

The mapping the game uses (scripts/controls/gamepad.gd) is the standard XInput one:
    right trigger -> throttle (analog)
    left trigger  -> clutch (analog)
    A             -> brake
    RB            -> upshift
    LB            -> downshift
    Y             -> starter (hold)

Run it with run_gamepad_calibration.bat, or:  python gamepad_calibrate.py
"""
import ctypes
import os
import sys
import time

from ctypes import wintypes

try:
    import msvcrt  # Windows only: lets S / Q be read without waiting for a line of input
except ImportError:  # pragma: no cover
    msvcrt = None

MAX_CONTROLLERS = 4
TRIGGER_DONE = 200  # of 255: this counts as "squeezed to the bottom"
MISSES_BEFORE_WARNING = 60  # polls of ~8 ms: about half a second with no answer from the pad

BUTTONS = {
    "dpad_up": 0x0001,
    "dpad_down": 0x0002,
    "dpad_left": 0x0004,
    "dpad_right": 0x0008,
    "start": 0x0010,
    "back": 0x0020,
    "left_thumb": 0x0040,
    "right_thumb": 0x0080,
    "lb": 0x0100,
    "rb": 0x0200,
    "a": 0x1000,
    "b": 0x2000,
    "x": 0x4000,
    "y": 0x8000,
}


class XInputGamepad(ctypes.Structure):
    _fields_ = [
        ("wButtons", wintypes.WORD),
        ("bLeftTrigger", ctypes.c_ubyte),
        ("bRightTrigger", ctypes.c_ubyte),
        ("sThumbLX", ctypes.c_short),
        ("sThumbLY", ctypes.c_short),
        ("sThumbRX", ctypes.c_short),
        ("sThumbRY", ctypes.c_short),
    ]


class XInputState(ctypes.Structure):
    _fields_ = [("dwPacketNumber", wintypes.DWORD), ("Gamepad", XInputGamepad)]


def load_xinput():
    for name in ("xinput1_4.dll", "xinput1_3.dll", "xinput9_1_0.dll"):
        try:
            lib = ctypes.WinDLL(name)
        except OSError:
            continue
        lib.XInputGetState.argtypes = [wintypes.DWORD, ctypes.POINTER(XInputState)]
        lib.XInputGetState.restype = wintypes.DWORD
        return lib
    return None


def connected_slots(xinput):
    slots = []
    for slot in range(MAX_CONTROLLERS):
        state = XInputState()
        if xinput.XInputGetState(slot, ctypes.byref(state)) == 0:
            slots.append(slot)
    return slots


def poll(xinput, slot):
    state = XInputState()
    if xinput.XInputGetState(slot, ctypes.byref(state)) != 0:
        return None
    return state.Gamepad


def key_pressed():
    """'s', 'q' or None - read without blocking."""
    if msvcrt is None or not msvcrt.kbhit():
        return None
    ch = msvcrt.getwch()
    return ch.lower() if ch else None


# ---------------------------------------------------------------- the checks

def wait_for_trigger(xinput, slot, which):
    """Waits until the trigger is squeezed to the bottom. Returns (peak, skipped).

    Prints a live bar every poll, so an unresponsive window is never mistaken for a hung script.
    """
    peak = 0
    misses = 0
    last_draw = 0.0
    print("    waiting for the trigger - take as long as you like  (S skips, Q quits)")
    while True:
        pad = poll(xinput, slot)
        if pad is None:
            misses += 1
            if misses == MISSES_BEFORE_WARNING:
                print("\n    ! the controller stopped answering. Still waiting; wake it or plug it back in.")
            time.sleep(0.008)
            continue
        if misses >= MISSES_BEFORE_WARNING:
            print("    controller is answering again")
        misses = 0
        value = pad.bRightTrigger if which == "right" else pad.bLeftTrigger
        peak = max(peak, value)
        if peak >= TRIGGER_DONE:
            sys.stdout.write("\r    [%s] %3d%%  done\n" % ("#" * 20, round(peak * 100 / 255)))
            sys.stdout.flush()
            return peak, False
        bar = "#" * int(round(value / 255 * 20))
        now = time.monotonic()
        if now - last_draw >= 0.06:
            last_draw = now
            sys.stdout.write("\r    [%-20s] %3d%%  " % (bar, round(value * 100 / 255)))
            sys.stdout.flush()
        key = key_pressed()
        if key == "s":
            sys.stdout.write("\n")
            return peak, True
        if key == "q":
            raise KeyboardInterrupt
        time.sleep(0.008)


def wait_for_button(xinput, slot, name):
    """Waits until the named button is held. Returns (pressed, skipped)."""
    mask = BUTTONS[name]
    misses = 0
    print("    waiting for it - take as long as you like  (S skips, Q quits)")
    while True:
        pad = poll(xinput, slot)
        if pad is None:
            misses += 1
            if misses == MISSES_BEFORE_WARNING:
                print("    ! the controller stopped answering. Still waiting; wake it or plug it back in.")
            time.sleep(0.008)
            continue
        misses = 0
        if pad.wButtons & mask:
            return True, False
        key = key_pressed()
        if key == "s":
            return False, True
        if key == "q":
            raise KeyboardInterrupt
        time.sleep(0.008)


def run_ladder(argv):
    """Records the distinct raw values XInput reports for each trigger while it is squeezed, and prints them.

    This is the question that decides whether analog throttle is possible at all: a Hall-effect trigger reports dozens
    of intermediate values, a switch reports only 0 and the top. Godot seeing only 0 and 1 is not proof by itself,
    because Windows, SDL and the game each read the pad their own way.
    """
    lines = []

    def say(text=""):
        print(text)
        lines.append(text)

    xinput = load_xinput()
    if xinput is None:
        say("No XInput library found.")
        write_report(lines)
        return 2
    slots = connected_slots(xinput)
    if not slots:
        say("No gamepad reported by XInput.")
        write_report(lines)
        return 2
    slot = slots[0]
    say("Engine Builder - trigger value ladder (XInput, slot %d)" % slot)
    say("=" * 52)
    say("")

    for label, attr in (("RIGHT TRIGGER (throttle)", "bRightTrigger"), ("LEFT TRIGGER (clutch)", "bLeftTrigger")):
        values = {}
        say("%s" % label)
        say("    squeeze it slowly all the way in, hold a beat, then let it back out")
        say("    (S skips, Q quits)")
        started = time.monotonic()
        saw_press = False
        released_after = False
        while True:
            pad = poll(xinput, slot)
            if pad is not None:
                v = getattr(pad, attr)
                values[v] = True
                if v > 200:
                    saw_press = True
                if saw_press and v == 0:
                    released_after = True
                    break
                # a live readout so it is obvious the tool is awake
                if time.monotonic() - started > 0.1:
                    bar = "#" * int(round(v / 255 * 24))
                    sys.stdout.write("\r    [%-24s] %3d  " % (bar, v))
                    sys.stdout.flush()
                    started = time.monotonic()
            key = key_pressed()
            if key == "s":
                break
            if key == "q":
                raise KeyboardInterrupt
            time.sleep(0.004)
        sys.stdout.write("\n")
        seen = sorted(values.keys())
        # the interesting number: how many distinct values arrived, and which ones in the middle
        middle = [v for v in seen if 0 < v < 255]
        say("    %d distinct value(s), %d of them between 0 and 255" % (len(seen), len(middle)))
        if len(middle) <= 14:
            say("    values: %s" % (", ".join(str(v) for v in seen) if seen else "none"))
        else:
            say("    sample: %s ... %s" % (", ".join(str(v) for v in middle[:7]), ", ".join(str(v) for v in middle[-3:])))
        if len(middle) >= 20:
            say("    VERDICT: analog - this trigger reports real travel")
        elif len(seen) <= 2 and saw_press:
            say("    VERDICT: digital switch - XInput itself only ever says 0 or full")
        else:
            say("    VERDICT: inconclusive - too few values seen; try squeezing slower")
        if not released_after and saw_press:
            say("    (never saw it return to 0; released detection skipped)")
        say("")

    write_report(lines)
    return 0


def main(argv):
    if "--ladder" in argv:
        return run_ladder(argv)
    self_test = "--selftest" in argv
    lines = []

    def say(text=""):
        print(text)
        lines.append(text)

    say("Engine Builder - gamepad calibration")
    say("=" * 40)
    xinput = load_xinput()
    if xinput is None:
        say("No XInput library found (xinput1_4.dll / xinput1_3.dll).")
        write_report(lines)
        return 2

    slots = connected_slots(xinput)
    if not slots:
        say("No gamepad reported by XInput. Plug it in, wake it, and make sure it is in Xbox mode.")
        write_report(lines)
        return 2
    slot = slots[0]
    say("controller on XInput slot %d" % slot)
    if self_test:
        say("self-test: pad detected, waits skipped")
    else:
        say("")
        say("Squeeze or press each control when asked. There is NO timer: take as long as you like.")
        say("S = skip this control,  Q = quit.")
    say("")

    results = []
    failures = 0

    for label, which in (("RIGHT TRIGGER", "right"), ("LEFT TRIGGER", "left")):
        say(">>> %s: squeeze it all the way in" % label)
        if self_test:
            say("    skipped (self-test)")
            results.append((label, None, "self-test"))
            say("")
            continue
        peak, skipped = wait_for_trigger(xinput, slot, which)
        if skipped:
            say("    skipped")
            results.append((label, None, "skipped"))
        elif peak >= TRIGGER_DONE:
            say("    reached %d/255 (%d%%) - OK, analog works" % (peak, round(peak * 100 / 255)))
            results.append((label, True, "%d/255" % peak))
        else:
            say("    only %d/255 - FAIL" % peak)
            results.append((label, False, "%d/255" % peak))
            failures += 1
        say("")

    for label, name in (
        ("A (brake)", "a"),
        ("RIGHT SHOULDER / RB (upshift)", "rb"),
        ("LEFT SHOULDER / LB (downshift)", "lb"),
        ("Y (starter)", "y"),
    ):
        say(">>> %s: press and hold" % label)
        if self_test:
            say("    skipped (self-test)")
            results.append((label, None, "self-test"))
            say("")
            continue
        pressed, skipped = wait_for_button(xinput, slot, name)
        if skipped:
            say("    skipped")
            results.append((label, None, "skipped"))
        elif pressed:
            say("    responded - OK")
            results.append((label, True, "ok"))
        else:
            say("    no response - FAIL")
            results.append((label, False, "none"))
            failures += 1
        say("")

    say("=" * 40)
    say("%-22s %-8s %s" % ("control", "result", "detail"))
    for label, ok, detail in results:
        verdict = "OK" if ok else ("SKIP" if ok is None else "FAIL")
        say("%-22s %-8s %s" % (label, verdict, detail))
    say("")
    if self_test:
        say("RESULT: self-test only - no controls were exercised.")
    elif failures == 0:
        say("RESULT: every control works. scripts/controls/gamepad.gd matches this pad.")
    else:
        say("RESULT: %d control(s) failed. RT is the analog throttle; if RT or LT failed, the game has no gradual input."
            % failures)
    write_report(lines)
    return 0 if (self_test or failures == 0) else 1


def write_report(lines):
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gamepad_calibration_result.txt")
    try:
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        print("\nwritten: %s" % path)
    except OSError as exc:
        print("could not write the report: %s" % exc)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        print("\ncancelled")
        sys.exit(130)
