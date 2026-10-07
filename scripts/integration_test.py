#!/usr/bin/env python3
"""Real IOKit smoke tests. Run on AC with lid OPEN and no other sleep utility.
Temporarily acquires assertions; never writes pmset preferences or closes the lid.
"""
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("AGENTAWAKE_BINARY", str(ROOT / ".build/release/AgentAwake")))


def pmset(*args):
    return subprocess.check_output(["/usr/bin/pmset", *args]).decode("utf-8", errors="replace")


class Guard:
    def __init__(self):
        self.process = subprocess.Popen([str(BINARY), "--guard"], stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.buffer = b""

    def send(self, action, seconds=None, power_mode=None):
        self.process.stdin.write((json.dumps({"action": action, "seconds": seconds,
                                             "powerMode": power_mode}) + "\n").encode())
        self.process.stdin.flush()

    def until(self, reason, timeout=5):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            while b"\n" in self.buffer:
                line, self.buffer = self.buffer.split(b"\n", 1)
                status = json.loads(line)
                if status["reason"] == reason:
                    return status
                if status["reason"] == "error":
                    raise AssertionError(status)
            ready, _, _ = select.select([self.process.stdout], [], [], max(0, end - time.monotonic()))
            if ready:
                chunk = os.read(self.process.stdout.fileno(), 8192)
                if not chunk:
                    raise AssertionError(f"Guard exited: {self.process.stderr.read().decode()}")
                self.buffer += chunk
        raise AssertionError(f"Timeout waiting for {reason}")

    def close(self):
        if self.process.poll() is None:
            try:
                self.process.stdin.close()
            except (BrokenPipeError, ValueError):
                pass
            self.process.wait(timeout=5)
        assert self.process.returncode == 0, self.process.stderr.read().decode()


assert "AC Power" in pmset("-g", "batt"), "Connect AC before integration test"
assert "AgentAwake" not in pmset("-g", "assertions"), "Stop the app session before testing"
before = pmset("-g", "custom")
results = []
for scenario in ["stop", "deadline", "configure_deadline", "configure_idle", "parent_eof",
                 "heartbeat_timeout", "signal", "duplicate_guard"]:
    guard = Guard()
    try:
        ready = guard.until("disabled")
        assert ready.get("lidClosed") is False, "Keep the lid open during tests"
        if scenario == "configure_idle":
            guard.send("configure", power_mode="anyPower")
            idle = guard.until("disabled")
            assert not idle["assertionHeld"] and not idle["lidControlAccepted"]
        guard.send("start", 1.5 if scenario in ("deadline", "configure_deadline") else None)
        active = guard.until("active")
        assert active["assertionHeld"] and active["lidControlAccepted"], active
        assert "AgentAwake" in pmset("-g", "assertions")
        if scenario == "stop":
            guard.send("stop")
            status = guard.until("disabled")
            assert not status["assertionHeld"] and not status["lidControlAccepted"]
        elif scenario in ("deadline", "configure_deadline"):
            if scenario == "configure_deadline":
                guard.send("configure", power_mode="anyPower")
                assert guard.until("active")["assertionHeld"]
                guard.send("configure", power_mode="pluggedInOnly")
                assert guard.until("active")["assertionHeld"]
            status = guard.until("expired")
            assert not status["assertionHeld"] and not status["lidControlAccepted"]
        elif scenario == "heartbeat_timeout":
            status = guard.until("disconnected", 11)
            assert not status["assertionHeld"] and not status["lidControlAccepted"]
        elif scenario == "signal":
            guard.process.send_signal(signal.SIGTERM)
            guard.process.wait(timeout=5)
        elif scenario == "duplicate_guard":
            other = subprocess.run([str(BINARY), "--guard"], input=b"", capture_output=True, timeout=5)
            assert other.returncode == 2
            assert json.loads(other.stdout)["reason"] == "error"
            guard.send("heartbeat")
            assert guard.until("active")["assertionHeld"]
    finally:
        guard.close()
    time.sleep(0.15)
    assert "AgentAwake" not in pmset("-g", "assertions"), "Assertion leaked"
    assert pmset("-g", "custom") == before, "Persistent power preferences changed"
    results.append(scenario)
    print(f"PASS {scenario}", flush=True)
print(json.dumps({"passed": results, "persistent_preferences_unchanged": True,
                  "physical_lid_test": "manual; not performed"}, indent=2))
