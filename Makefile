.PHONY: build test package integration-test

build:
	bash scripts/build.sh

test:
	swift test

package:
	bash scripts/package.sh

# Requires a real MacBook, AC power, an open lid, and AgentAwake fully quit.
integration-test:
	swift build -c release
	python3 scripts/integration_test.py
