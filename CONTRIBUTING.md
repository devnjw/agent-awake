# Contributing

Issues and small, focused pull requests are welcome. Include your Mac model,
macOS version, app version, power source, and external-display setup when
reporting a behavior difference. Do not post agent content or credentials.

Run `make test` and `make build` on macOS before opening a pull request. Keep
the menu bar panel small; put secondary controls in the options menu. Preserve
the AC-only and thermal rules, the independent monitor, and cleanup behavior.
Do not add persistent system power changes or administrator helpers casually.

CI exercises pure policy tests and native arm64 app builds on Apple Silicon.
Power-control changes also need the real-device tests described in
[DEVELOPMENT.md](docs/DEVELOPMENT.md). A build succeeding in CI does not
confirm physical lid behavior. Describe exactly what you tested.

Contributions are licensed under the project's [MIT license](LICENSE).
