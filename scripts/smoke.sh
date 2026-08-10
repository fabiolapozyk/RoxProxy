#!/bin/bash
# RoxProxy smoke test.
# Launches the real built app, waits for the proxy to come up, verifies the
# /health and /stats endpoints over HTTP, then quits the app cleanly and
# checks the CrashGuard sentinel + os_log output for errors.
#
# It temporarily overrides the user settings file with a test-safe config
# (autoStartProxy on, system proxy disabled) and restores it afterwards.
#
# Usage:
#   ./scripts/smoke.sh            # build release + full smoke test
#   ./scripts/smoke.sh --skip-build   # reuse the existing release build
#
# Exit code 0 = app launched, proxy healthy, clean shutdown.

set -euo pipefail

cd "$(dirname "$0")/.."

SKIP_BUILD=0
if [[ "${1:-}" == "--skip-build" ]]; then
    SKIP_BUILD=1
fi

APP_NAME="Rox Proxy"
APP_BIN="build/macos/Build/Products/Release/${APP_NAME}.app/Contents/MacOS/${APP_NAME}"
SETTINGS_DIR="$HOME/Library/Application Support/RoxProxy"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
SENTINEL_FILE="$SETTINGS_DIR/.proxy-active"
PORT=19090
LOG_FILTER='subsystem == "com.roxproxy"'

# ---------------------------------------------------------------- build
if [[ "$SKIP_BUILD" -eq 0 ]]; then
    echo "==> Building release app..."
    flutter build macos --release
else
    echo "==> Skipping build (--skip-build)"
fi

if [[ ! -x "$APP_BIN" ]]; then
    echo "❌ App binary not found: $APP_BIN"
    exit 1
fi

# ------------------------------------------------------- pre-flight
if pgrep -f "$APP_BIN" >/dev/null 2>&1; then
    echo "❌ RoxProxy is already running. Quit it before running the smoke test."
    exit 1
fi

# ---------------------------------------------------- test settings
echo "==> Backing up settings and writing test config..."
mkdir -p "$SETTINGS_DIR"
SETTINGS_BACKUP="$(mktemp)"
if [[ -f "$SETTINGS_FILE" ]]; then
    cp "$SETTINGS_FILE" "$SETTINGS_BACKUP"
fi
cat > "$SETTINGS_FILE" <<EOF
{
  "port": $PORT,
  "domainRules": [],
  "isRecording": true,
  "maxExchanges": 2000,
  "autoStartProxy": true,
  "connectionTimeoutSeconds": 10,
  "setSystemProxy": false,
  "httpsInterceptionEnabled": false
}
EOF

APP_PID=""
restore_settings() {
    if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
        kill "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
    fi
    if [[ -f "$SETTINGS_BACKUP" ]] && [[ -s "$SETTINGS_BACKUP" ]]; then
        cp "$SETTINGS_BACKUP" "$SETTINGS_FILE"
    else
        rm -f "$SETTINGS_FILE"
    fi
    rm -f "$SETTINGS_BACKUP"
}
trap restore_settings EXIT

# ------------------------------------------------------------ launch
echo "==> Launching app..."
"$APP_BIN" >/dev/null 2>&1 &
APP_PID=$!

# --------------------------------------------------- wait for /health
echo "==> Waiting for proxy on 127.0.0.1:$PORT..."
HEALTH=""
for i in $(seq 1 30); do
    if ! kill -0 "$APP_PID" 2>/dev/null; then
        echo "❌ App exited during startup (check CrashGuard and os_log below)."
        exit 1
    fi
    if HEALTH="$(curl -s --max-time 2 "http://127.0.0.1:$PORT/health" || true)"; then
        if echo "$HEALTH" | grep -q '"running"'; then
            break
        fi
    fi
    sleep 1
done

if ! echo "$HEALTH" | grep -q '"running"'; then
    echo "❌ /health never reported running. Last response: $HEALTH"
    exit 1
fi
echo "✅ Proxy healthy: $HEALTH"

# ------------------------------------------------------- /stats check
STATS="$(curl -s --max-time 3 "http://127.0.0.1:$PORT/stats" || true)"
if ! echo "$STATS" | grep -q '"status"'; then
    echo "❌ /stats returned unexpected data: $STATS"
    exit 1
fi
echo "✅ Stats: $STATS"

# -------------------------------------------------------- HTTP proxy
echo "==> Verifying proxied HTTP request through the proxy..."
HTTP_RESULT="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
    -x "http://127.0.0.1:$PORT" "http://example.com" || true)"
if [[ "$HTTP_RESULT" == "200" ]]; then
    echo "✅ Proxied request OK (200)"
else
    echo "⚠️  Proxied request returned $HTTP_RESULT (network-dependent, not fatal)"
fi

# ------------------------------------------------------- clean quit
echo "==> Quitting app gracefully (SIGTERM)..."
kill -TERM "$APP_PID"
for i in $(seq 1 10); do
    if ! kill -0 "$APP_PID" 2>/dev/null; then
        break
    fi
    sleep 0.5
done
if kill -0 "$APP_PID" 2>/dev/null; then
    echo "❌ App did not exit after SIGTERM. Killing it."
    kill -9 "$APP_PID"
    exit 1
fi
APP_PID=""

# --------------------------------------------------- sentinel check
if [[ -f "$SENTINEL_FILE" ]]; then
    echo "❌ CrashGuard sentinel still present after clean exit — shutdown path broken."
    exit 1
fi
echo "✅ CrashGuard sentinel cleared (clean shutdown)"

# --------------------------------------------------- os_log check
echo "==> Scanning os_log for errors/faults..."
ERRORS="$(log show --last 2m --predicate 'subsystem == "com.roxproxy" AND (messageType == 16 OR messageType == 17)' 2>/dev/null | grep -v "^Timestamp" | grep -v " — " | grep -v "^$" || true)"
if [[ -n "$ERRORS" ]]; then
    echo "⚠️  os_log contains error/fault messages:"
    echo "$ERRORS" | head -n 20
else
    echo "✅ No error/fault messages in os_log"
fi

echo ""
echo "✅ Smoke test passed."
