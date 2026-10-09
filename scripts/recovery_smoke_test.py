#!/usr/bin/env python3
"""Fault-injection checks for the installed app on AC, with Keep awake ON.
Keep the lid open. Briefly suspends this app and kills only its child monitor.
Never changes persistent power preferences or physically sleeps the Mac.
"""
import os
from pathlib import Path
import re
import signal
import subprocess
import time

BINARY = Path("/Applications/AgentAwake.app/Contents/MacOS/AgentAwake")
PREFIX = "^" + re.escape(str(BINARY))


def text_command(*args):
    return subprocess.check_output(args).decode("utf-8", errors="replace")


def pid(suffix):
    result = subprocess.run(["pgrep", "-f", PREFIX + suffix], capture_output=True, text=True)
    matches = result.stdout.split()
    assert len(matches) <= 1, "Multiple matching processes; do not run this test"
    return int(matches[0]) if matches else None


def assertions_held(monitor):
    lines = text_command("pmset", "-g", "assertions").splitlines()
    return sum(f"pid {monitor}(AgentAwake)" in line for line in lines) == 2


def await_recovery(old_monitor, gui):
    end = time.monotonic() + 10
    while time.monotonic() < end:
        monitor = pid(" --guard$")
        if monitor and monitor != old_monitor and assertions_held(monitor):
            assert pid("$") == gui, "The UI must recover without restarting"
            return monitor
        time.sleep(0.2)
    raise AssertionError("Session did not recover")


assert "AC Power" in text_command("pmset", "-g", "batt"), "Connect AC before testing"
assert "lid=false" in text_command(str(BINARY), "--diagnose"), "Keep the lid open"
gui, monitor = pid("$"), pid(" --guard$")
assert gui and monitor and assertions_held(monitor), "Launch the installed app and enable Keep awake"
before = text_command("pmset", "-g", "custom")

os.kill(gui, signal.SIGSTOP)
try:
    time.sleep(10)
finally:
    os.kill(gui, signal.SIGCONT)
monitor = await_recovery(monitor, gui)
print("PASS UI suspension: same app, new monitor, awake assertions restored", flush=True)

os.kill(monitor, signal.SIGKILL)
monitor = await_recovery(monitor, gui)
print("PASS killed monitor: same app, new monitor, awake assertions restored", flush=True)

assert text_command("pmset", "-g", "custom") == before
print("PASS persistent power preferences unchanged")
