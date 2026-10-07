# Help & troubleshooting

[Back to README](../README.md) · [한국어](GUIDE.ko.md)

## Power and sessions

**Only when plugged in** is checked by default. Unplugging pauses an enabled
session; reconnecting resumes it. Uncheck it to allow battery use. This preference
is saved, and changing it does not restart the session timer.

Charger-only mode checks the power source, even if the battery is full or charging
is paused. Battery mode consumes battery and cannot prevent sleep or shutdown
when the battery is exhausted.

Serious thermal pressure pauses the session until temperatures recover. Quitting
or reaching the timer ends it. The app always starts with Keep awake off,
including at login. Changing **Stop after** during a session restarts the selected
interval from that moment; remaining time appears in the same menu.

## Displays

**Turn off displays** sleeps all connected screens, including external monitors.
Keyboard, mouse, or trackpad input wakes them normally. The action leaves Keep awake
as you set it; enable it to keep jobs running while screens are off. Existing
macOS lock/password settings still apply.

## First launch

Release binaries are Developer ID signed, but not Apple notarized. If macOS blocks
the app, follow [Apple’s app-specific Open Anyway instructions](https://support.apple.com/102445).
Managed Macs may prohibit this. Do not disable Gatekeeper globally.

A ZIP and SHA256 checksums are also available on the
[release page](https://github.com/devnjw/agent-awake/releases/tag/v0.2.0).

## Check your Mac

Lid control uses a private macOS API. Hardware, display setup, and macOS updates
can affect behavior. Connect the charger, enable Keep awake, and start a harmless
local task that records progress. Close the lid for 30 seconds, reopen it, and
check that progress continued. Then turn Keep awake off and confirm ordinary sleep.
Repeat with your intended power mode and display setup before a long job.

Use a hard, ventilated surface. Never put an awake MacBook in a bag. Avoid running
other lid/sleep utilities at the same time. Network failures, agent approval
prompts, and errors in another app still need your attention.

## Problems

- **The switch is on, but work pauses:** check the power mode and pause message,
  then try the short lid test above.
- **Monitor error:** quit and reopen AgentAwake. If both the UI and monitor were
  forcibly killed and sleep stays abnormal, restart your Mac.

The app does not write persistent pmset settings. It has no server, analytics,
agent-content access, privileged service, or input monitor.

## Remove the app

Turn off **Launch at login**, quit AgentAwake, and move it from Applications to
the Trash. After quitting, you may remove the monitor lock directory at
~/Library/Application Support/AgentAwake. The power mode is stored in local app
preferences.

[Development, validation, and implementation details](DEVELOPMENT.md)
