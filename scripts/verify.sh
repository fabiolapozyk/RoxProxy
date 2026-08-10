#!/bin/bash
# RoxProxy verification script.
# Runs the full local test pipeline. Intended to be run by developers
# (and by the coding assistant) after every change, before committing.
#
# Usage:
#   ./scripts/verify.sh          # full: format + analyze + tests + build
#   ./scripts/verify.sh --fast   # skip the slow debug build
#
# Exit code 0 = everything passed.

set -euo pipefail

cd "$(dirname "$0")/.."

FAST=0
if [[ "${1:-}" == "--fast" ]]; then
    FAST=1
fi

STEP=0
run_step() {
    STEP=$((STEP + 1))
    echo ""
    echo "==> [$STEP] $1"
}

fail() {
    echo ""
    echo "❌ FAILED: $1"
    exit 1
}

# ---------------------------------------------------------------- format
run_step "Format check (dart format)"
if ! dart format --output=none --set-exit-if-changed lib test integration_test 2>/dev/null; then
    fail "dart format: run 'dart format lib test integration_test'"
fi

# ---------------------------------------------------------------- analyze
run_step "flutter analyze"
flutter analyze || fail "flutter analyze"

# ------------------------------------------------- unit tests (Dart)
run_step "Dart unit tests (flutter test test/)"
flutter test test/ || fail "flutter test test/"

# ------------------------------------------------------------ Swift core
run_step "Swift core tests (CoreTests package)"
(
    cd packages/rox_proxy_native/macos/CoreTests
    swift test 2>&1 | tail -n 5
) || fail "swift test (CoreTests)"

# ---------------------------------------------------- debug build (slow)
if [[ "$FAST" -eq 0 ]]; then
    run_step "Debug build (flutter build macos --debug)"
    flutter build macos --debug || fail "flutter build macos --debug"
else
    echo "  (skipped: --fast)"
fi

echo ""
echo "✅ All checks passed."
