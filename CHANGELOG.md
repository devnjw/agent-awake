# Changelog

## 0.3.1 — 2026-10-09

- Use awake time and sleep/wake notifications for monitor health checks,
  preventing a normal sleep interval from being treated as a response timeout.
- Reconnect a stopped or unresponsive monitor automatically, with bounded retries.
  Preserve the power mode and original session end time; a user stop cancels resume.
- Allow another attempt with the Keep awake switch after recovery fails.
- Ignore replies from retired monitors and restore sleep before replacing
  an abnormally terminated monitor.

## 0.3.0 — 2026-10-09

- Build and distribute Apple Silicon-only (arm64) apps, including the monitor.
  No Intel executable slice or Rosetta is required.
- Require native execution and verify every bundled executable is arm64-only.
- Update downloads, install instructions, and CI for Apple Silicon.
  Intel Macs can use the earlier v0.2.1 universal preview.

## 0.2.1 — 2026-10-08

- Open the options menu below its button in screen coordinates to prevent
  it collapsing into a one-row scrolling menu inside the compact popover.
- Keep monitor replies and heartbeats running during menu tracking, so an
  open menu cannot expire the monitor's lease.

## 0.2.0 — 2026-10-08

- Optional battery operation via Only when plugged in in the options menu.
  Charger-only remains the default; the choice is saved across launches.
- Changing the power mode reevaluates the session without restarting its timer.
- Turn off displays sleeps all connected screens; ordinary keyboard, mouse,
  and trackpad input wakes them using macOS's existing behavior.
- The primary panel stays a single Keep awake row.

## 0.1.0 — 2026-10-08

Initial public preview.

- A compact menu bar panel with one Keep awake switch.
- AC-only sleep and lid control for local agent work.
- Stop after 1, 2, 4, or 8 hours, or keep running until stopped.
- Launch at login, with Keep awake initially off.
- Pause on battery or serious thermal pressure and resume when conditions allow.
- A separate monitor that restores sleep on normal exit, pipe closure,
  missed heartbeats, and handled termination signals.
- Universal Apple Silicon / Intel ZIP and drag-to-install DMG.

The first binaries are Developer ID signed, but not Apple notarized.
Physical closed-lid behavior must be checked on each Mac; the lid API is private.
