# AgentAwake

Keep local agents working with your MacBook's lid closed, on charger or battery.
A small native macOS menu bar app with one **Keep awake** switch.

[Download v0.2.0](https://github.com/devnjw/agent-awake/releases/tag/v0.2.0) ·
[한국어](README.ko.md) · [Development](docs/DEVELOPMENT.md) · [MIT license](LICENSE)

## Install

**macOS 14 or later · Apple Silicon and Intel · no administrator helper**

1. Download [AgentAwake-0.2.0-universal.dmg](https://github.com/devnjw/agent-awake/releases/download/v0.2.0/AgentAwake-0.2.0-universal.dmg).
2. Open the disk image and drag **AgentAwake.app** to **Applications**.
3. Launch it from Applications, eject the disk image, and connect your charger.
4. Click the lightning icon in the menu bar and turn on **Keep awake**.

A [ZIP](https://github.com/devnjw/agent-awake/releases/download/v0.2.0/AgentAwake-0.2.0-universal.zip)
is also available; unzip it and move the app to Applications.

Release binaries are **Developer ID signed, but not Apple notarized**. If macOS
blocks it, use the app-specific **Open Anyway** flow described in
[Apple's instructions](https://support.apple.com/102445). Managed Macs may prohibit
this. Only install a binary you trust; do not disable Gatekeeper globally.

This is an early preview: lid control uses a private macOS API. Test a short
closed-lid session on your Mac before relying on it for a long job. A successful
power request is not proof that the Mac stayed awake with its lid closed.

## Use

The **⋯** menu contains **Turn off displays**, **Only when plugged in**,
**Stop after** (until stopped, 1, 2, 4, or 8 hours), **Launch at login**, help,
and quit. Changing the timer during a session restarts
it from that moment. A running timer's remaining time appears in the same menu.

- **Only when plugged in** is checked by default. Unplugging pauses the request;
  reconnecting resumes an enabled session. Uncheck it to keep working on battery.
  This preference is saved. Changing it does not restart the session timer.
- **Turn off displays** immediately sleeps all connected screens, including external
  monitors. Keyboard, mouse, or trackpad input wakes them normally. Keep awake
  stays as you set it; turn it on to keep jobs running while the screens are off.
  Your existing macOS lock/password settings still apply.
- Serious thermal pressure pauses it until temperatures recover.
- Quitting or reaching the timer ends the request. Launching the app starts with
  Keep awake off, including at login.
- Charger-only mode checks the power source, even if charging is paused or full.
  Battery mode consumes battery and cannot prevent sleep or shutdown at exhaustion.

Works with Codex and other local tasks. Network failures, agent approval prompts,
and errors inside another app still need your attention. There is no server,
analytics, or access to your agent's content.

Use a hard, ventilated surface. Never put an awake MacBook in a bag. Avoid running
multiple lid/sleep utilities together.

## Verify your Mac

Connect the charger, enable Keep awake, and start a harmless local task that
records progress. Close the lid for 30 seconds, reopen it, and check that progress
continued. Then disable Keep awake and confirm ordinary sleep behavior. Behavior
can differ by hardware, display setup, and macOS version.

**Built for macOS 14+; development hardware: Apple Silicon / macOS 26.6.2.**
Intel binaries are included, with native builds tested in CI. Physical closed-lid
behavior, unplug/reconnect, and login after reboot need real-device testing.

## Troubleshooting and removal

**The switch is on, but work pauses:** check the power mode and any pause message.
Verify your Mac with the short lid test. If another app is waiting for approval
or has lost its network connection, AgentAwake cannot resolve that.

**The app reports a monitor error:** quit and reopen it. If both the UI and monitor
are forcibly killed and sleep behavior remains abnormal, restart the Mac.
AgentAwake does not write persistent `pmset` settings.

**Uninstall:** turn off Launch at login in **⋯**, quit AgentAwake, and move it
from Applications to the Trash. The app saves the power mode in its local preferences
and keeps a monitor lock at
`~/Library/Application Support/AgentAwake/session.lock`; its containing directory
may be removed after quitting. No privileged service is installed.

## Build from source

Requires Xcode or Command Line Tools with Swift 6+ on macOS.

```sh
git clone https://github.com/devnjw/agent-awake.git
cd agent-awake
make test
make build
open dist/AgentAwake.app
```

See [development and release instructions](docs/DEVELOPMENT.md) for universal
packaging, signing, notarization, hardware tests, and implementation limits.
Release assets include [SHA256 checksums](https://github.com/devnjw/agent-awake/releases/download/v0.2.0/SHA256SUMS.txt).

## References

- [Apple: idle sleep assertions and lid closure](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridlesystemsleep)
- [Apple: system sleep assertions](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventsystemsleep)
- [Apple XNU: root-domain user client](https://github.com/apple-oss-distributions/xnu/blob/main/iokit/Kernel/RootDomainUserClient.cpp)
- [Apple XNU: power and lid policy](https://github.com/apple-oss-distributions/xnu/blob/main/iokit/Kernel/IOPMrootDomain.cpp)
