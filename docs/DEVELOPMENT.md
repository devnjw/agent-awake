# Development and releases

Requires macOS 14+, Xcode or Command Line Tools with Swift 6+, and Python 3
for the optional hardware tests. The app has no external package dependencies.

```sh
git clone https://github.com/devnjw/agent-awake.git
cd agent-awake
make test
make build
open dist/AgentAwake.app
```

`Package.swift` can also be opened in Xcode. Launch the bundled app to test
login registration; running the raw Swift executable is not an app installation.
Builds are ad hoc signed by default. `--output-dir` keeps staged builds separate
from an installed or running app.

## Architecture

- `Sources/AgentAwakeCore/Policy.swift`: pure power, thermal, deadline, and
  heartbeat rules, with unit tests.
- `AppModel.swift`: UI state and line-delimited JSON communication with the monitor.
  Saves the power mode in UserDefaults; `configure` updates an active monitor
  without changing its deadline. Display sleep runs `/usr/bin/pmset displaysleepnow`
  asynchronously, after dismissing the menu. It does not change power preferences,
  enable Keep awake, or install an input monitor.
- `SessionGuard.swift`: a separate `--guard` process owns the power assertions.
- `PowerController.swift`: IOKit calls and restoration.
- `DashboardView.swift`: the panel and help window.
- `OptionsButton.swift`: a borderless native menu button opens an NSMenu below
  the button in screen coordinates. Menu contents are captured when opened and
  are not rebuilt while tracking. Monitor replies use the main run loop's common
  modes, and its common-mode timer sends heartbeats directly. Main-queue Tasks
  can be deferred during the menu's nested tracking loop.

The monitor acquires the public `PreventUserIdleSystemSleep` and supplementary
legacy `PreventSystemSleep` assertions and calls root-domain selector
`kPMSetClamshellSleepState` (12). The selector is private and can change with macOS
updates. It is isolated in `PowerController.swift`.

Charger-only is the default; battery operation is an explicit saved choice.
Unknown power sources always pause. UI pipe closure, an 8-second heartbeat expiry,
SIGTERM, a disallowed power source, excessive
thermal pressure, and the session deadline release the request. A surviving UI
attempts recovery if the monitor dies. Killing both processes prevents cleanup.
The selector is shared with powerd and other sleep utilities; ownership cannot
be fully isolated. An existing external-display mode is preserved where possible.
No persistent `pmset` preferences are written.

## Validation

`make test` runs pure policy tests, and CI builds on Apple Silicon and Intel.
Hosted VMs do not exercise physical lid control.

For a real MacBook hardware smoke test, fully quit AgentAwake and other sleep
utilities, connect AC power, keep the lid open, then run:

```sh
make integration-test
```

This briefly acquires real IOKit requests and checks stop, deadline, pipe EOF,
power-mode changes without restarting a deadline, idle configuration, heartbeat
expiry, SIGTERM, duplicate-monitor rejection, and unchanged persistent
power preferences. It does not physically close the lid.

Before a release, manually test a short closed-lid session in both power modes,
charger removal, reconnection, display sleep/input wake, login startup, timer expiry,
and quitting. Never manufacture thermal
pressure to test a pause.

Validated during development on macOS 26.6.2 / Apple Silicon: policy tests,
six real IOKit scenarios, UI on/off, help, timer selection, app signing, and
restoration after UI termination. Physical lid closure, charger removal,
actual thermal pressure, and login after reboot remain manual checks.

For v0.1.0, the universal hardened-runtime Developer ID build also passed all
six hardware scenarios. Both slices target macOS 14.0; Apple Silicon execution
and Intel read-only diagnostics through Rosetta succeeded locally. Native Intel
CI complements this; physical lid behavior on Intel is still a manual check.

For v0.2.0, all six policy/protocol tests and eight real IOKit scenarios passed.
The native menu's power-mode changes, saved preference, and login registration
were checked. The display action produced display-off/display-on events in the
macOS power log while the same session's assertions remained held. Physical
closed-lid battery use and each external monitor/input setup still need testing.

## Package a release

Update `CFBundleShortVersionString` / `CFBundleVersion` in `Resources/Info.plist`
and `CHANGELOG.md`, then run:

```sh
make test
CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
  bash scripts/package.sh
```

The script builds both architectures, combines them with `lipo`, signs the app
with hardened runtime, and creates a ZIP, a signed DMG with an Applications
shortcut, and `SHA256SUMS.txt` in `dist/releases/vVERSION/`.

Without `CODESIGN_IDENTITY`, packages are ad hoc signed local previews. Do not
describe them as Developer ID signed. Signing certificates, private keys, and
notarization credentials are never committed or copied into a release.

To notarize, first configure your own named `notarytool` keychain profile using
[Apple's notarization instructions](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
Then run:

```sh
CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
  bash scripts/package.sh --notarize-profile your-profile-name
```

This submits and staples the app and DMG. Update the install instructions and
release notes to state the actual notarization status before publishing.

Inspect the ZIP and DMG, verify `codesign --verify --strict`, check both slices
with `lipo -archs`, and run the app's read-only `--diagnose` command. Publish
the version tag and all three files through GitHub Releases. Keep the source
tag and packaged source identical; do not overwrite an existing release's files
with a different build under the same version.

`bash scripts/verify_release.sh` checks the packaged checksums, extracts the
ZIP, verifies its signature and both architectures, checks the version and
included license, runs read-only diagnostics, and mounts the DMG read-only to
verify its Applications shortcut and identical app contents.

## References

- [Apple: idle sleep assertions and lid closure](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridlesystemsleep)
- [Apple: system sleep assertions](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventsystemsleep)
- [Apple XNU: root-domain user client](https://github.com/apple-oss-distributions/xnu/blob/main/iokit/Kernel/RootDomainUserClient.cpp)
- [Apple XNU: power and lid policy](https://github.com/apple-oss-distributions/xnu/blob/main/iokit/Kernel/IOPMrootDomain.cpp)
- [Apple: positioning an independent NSMenu](https://developer.apple.com/documentation/appkit/nsmenu/popup(positioning:at:in:))
