SHELL = /bin/bash
.SHELLFLAGS = -eo pipefail -c

SCHEME = Scramble
PROJECT = Scramble/Scramble.xcodeproj
BUNDLE_ID = me.nore.ig.Scramble
CONFIG ?= Debug

SIMULATOR ?= iPhone 17 Pro
DEVICE_MODEL ?= iPhone 17 Pro

DERIVED_DATA = ./DerivedData

# Pretty-print xcodebuild output if xcbeautify is installed
XCBEAUTIFY := $(shell command -v xcbeautify 2>/dev/null)
ifdef XCBEAUTIFY
PIPE_PRETTY = | xcbeautify
else
PIPE_PRETTY =
endif

# The .SHELLFLAGS pipefail above is ignored by GNU make 3.81 (the macOS system
# default; .SHELLFLAGS landed in 3.82). Without pipefail, `xcodebuild | xcbeautify`
# returns xcbeautify's exit code (0) and SILENTLY MASKS test/build failures —
# `make test` would report success on a red suite. Prefix every piped recipe
# with this so pipefail is set in the recipe's own shell regardless of make
# version (harmless when xcbeautify is absent and there is no pipe).
PIPEFAIL := set -o pipefail;

SWIFTLINT := $(shell command -v swiftlint 2>/dev/null)
SWIFT_FORMAT := $(shell command -v swift-format 2>/dev/null)

# ---------------------------------------------------------------------------
# Help (default target)
# ---------------------------------------------------------------------------

.PHONY: help
help:
	@echo "Scramble — common targets"
	@echo ""
	@echo "Development:"
	@echo "  build           Build for iOS Simulator ($(SIMULATOR))"
	@echo "  clean           Remove DerivedData"
	@echo ""
	@echo "Testing:"
	@echo "  test-quick      Unit tests only (iOS Simulator) — inner-loop"
	@echo "  test            Full suite incl. UI tests (iOS Simulator) — pre-push"
	@echo "  test-ui         UI tests only (iOS Simulator)"
	@echo ""
	@echo "Device:"
	@echo "  install         Build + install on connected device (\$$DEVICE_MODEL)"
	@echo "  run             install + launch on connected device"
	@echo "  run-release     run with CONFIG=Release"
	@echo ""
	@echo "Code quality:"
	@echo "  lint            swiftlint --strict (if installed)"
	@echo "  format          swift-format in-place (if installed)"
	@echo ""
	@echo "Overrides:"
	@echo "  CONFIG=Debug|Release        (default: Debug)"
	@echo "  SIMULATOR='iPhone 17'       (default)"
	@echo "  DEVICE_MODEL='iPhone 17 Pro'(default)"

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

.PHONY: build
build:
	$(PIPEFAIL) xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR)' \
		-configuration $(CONFIG) \
		-derivedDataPath $(DERIVED_DATA) \
		$(PIPE_PRETTY)

.PHONY: clean
clean:
	rm -rf $(DERIVED_DATA)

# ---------------------------------------------------------------------------
# Test
# ---------------------------------------------------------------------------

# Inner loop: unit tests only. Skips the UI test bundle (which boots an
# extra XCTest UI runner and is the dominant cost of a full `test` run).
.PHONY: test-quick
test-quick:
	$(PIPEFAIL) xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR)' \
		-configuration Debug \
		-derivedDataPath $(DERIVED_DATA) \
		-only-testing:ScrambleTests \
		-parallel-testing-worker-count 1 \
		-maximum-concurrent-test-simulator-destinations 1 \
		$(PIPE_PRETTY)

# Pre-push: full suite. Serial simulator runs are deliberate — parallel
# simulator clones race on launch / status-bar overrides and produce flakes.
.PHONY: test
test:
	$(PIPEFAIL) xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR)' \
		-configuration Debug \
		-derivedDataPath $(DERIVED_DATA) \
		-parallel-testing-worker-count 1 \
		-maximum-concurrent-test-simulator-destinations 1 \
		$(PIPE_PRETTY)

.PHONY: test-ui
test-ui:
	$(PIPEFAIL) xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR)' \
		-configuration Debug \
		-derivedDataPath $(DERIVED_DATA) \
		-only-testing:ScrambleUITests \
		-parallel-testing-worker-count 1 \
		-maximum-concurrent-test-simulator-destinations 1 \
		$(PIPE_PRETTY)

# ---------------------------------------------------------------------------
# Device install / run
# ---------------------------------------------------------------------------

# Resolve a connected device's UDID from its marketing name. devicectl writes
# JSON to a file (no stdout mode), so we round-trip through a tempfile.
DEVICE_ID = $(shell tmp=$$(mktemp); \
	xcrun devicectl list devices --json-output "$$tmp" >/dev/null 2>&1; \
	jq -r '.result.devices[] | select(.hardwareProperties.marketingName == "$(DEVICE_MODEL)") | .connectionProperties.potentialHostnames[] | select(startswith("0000"))' "$$tmp" 2>/dev/null | sed 's/.coredevice.local//' | head -1; \
	rm -f "$$tmp")

.PHONY: install
install:
	@if [ -z "$(DEVICE_ID)" ]; then \
		echo "Error: No '$(DEVICE_MODEL)' device found. Connect one or override DEVICE_MODEL=..."; \
		exit 1; \
	fi
	$(PIPEFAIL) xcodebuild build \
		-project $(PROJECT) -scheme $(SCHEME) \
		-destination 'id=$(DEVICE_ID)' -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED_DATA) $(PIPE_PRETTY)
	xcrun devicectl device install app \
		--device $(DEVICE_ID) \
		$(DERIVED_DATA)/Build/Products/$(CONFIG)-iphoneos/$(SCHEME).app

.PHONY: run
run: install
	xcrun devicectl device process launch --device $(DEVICE_ID) $(BUNDLE_ID)

.PHONY: run-release
run-release:
	$(MAKE) run CONFIG=Release

# ---------------------------------------------------------------------------
# Code quality
# ---------------------------------------------------------------------------

.PHONY: lint
lint:
ifdef SWIFTLINT
	swiftlint --strict
else
	@echo "swiftlint not installed (brew install swiftlint). Skipping."
endif

.PHONY: format
format:
ifdef SWIFT_FORMAT
	swift-format format -i -r Scramble/Scramble Scramble/ScrambleTests Scramble/ScrambleUITests
else
	@echo "swift-format not installed (brew install swift-format). Skipping."
endif
