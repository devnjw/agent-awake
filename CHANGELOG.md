# Changelog

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
