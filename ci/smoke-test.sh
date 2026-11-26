#!/bin/bash
set -euo pipefail

# Pre-release smoke test with the real microphone, which CI runners don't have.
#
# Usage: ./ci/smoke-test.sh [dictations]   (default 10)
#
# Builds the Debug app (exclusivity checks on), quits the installed L'Alfred,
# then starts and cancels real dictations through `lalfred://debug/start` and
# `lalfred://debug/cancel`. Cancelling never transcribes nor pastes anything.
# Fails if the app dies, a crash report appears, or a dictation didn't open
# the microphone. On success it writes build/smoke-passed-<commit>, which
# `release.sh` requires before tagging. The installed app is relaunched at the end.
#
# Switch the input device in between runs (built-in mic, Bluetooth headset,
# USB mic) to cover the readiness paths that differ per device.

DICTATIONS="${1:-10}"
BUNDLE_ID="fr.lalfred.dictate"
DERIVED_DATA="build/smoke-derived-data"
APP="$(pwd)/${DERIVED_DATA}/Build/Products/Debug/L'Alfred.app"
LOG="build/smoke-test.log"
CRASH_REPORTS="${HOME}/Library/Logs/DiagnosticReports"
COMMIT="$(git rev-parse HEAD)"

mkdir -p build
rm -f build/smoke-passed-*

echo "==> Building Debug app"
xcodebuild build -project dictate.xcodeproj -scheme lalfred -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "${DERIVED_DATA}" SDK_STAT_CACHE_ENABLE=NO > build/smoke-build.log 2>&1 \
  || { tail -20 build/smoke-build.log >&2; echo "ERROR: build failed." >&2; exit 1; }

INSTALLED_WAS_RUNNING=0
if pgrep -f "/Applications/L'Alfred.app/" > /dev/null; then
  INSTALLED_WAS_RUNNING=1
  echo "==> Quitting the installed L'Alfred (relaunched at the end)"
  osascript -e "tell application id \"${BUNDLE_ID}\" to quit"
  sleep 2
fi

relaunch_installed_app() {
  pkill -f "${APP}/Contents/MacOS/" 2>/dev/null || true
  if [ -n "${LOG_PID:-}" ]; then
    kill "${LOG_PID}" 2>/dev/null || true
  fi
  if [ "${INSTALLED_WAS_RUNNING}" -eq 1 ]; then
    open "/Applications/L'Alfred.app"
  fi
}
trap relaunch_installed_app EXIT

START_MARKER="build/smoke-started"
touch "${START_MARKER}"
log stream --level info --predicate "subsystem == \"${BUNDLE_ID}\"" > "${LOG}" 2>&1 &
LOG_PID=$!

echo "==> Launching ${APP}"
open -a "${APP}"
sleep 3

for i in $(seq 1 "${DICTATIONS}"); do
  echo "    dictation ${i}/${DICTATIONS}"
  open -g -a "${APP}" "lalfred://debug/start"
  sleep 2
  open -g -a "${APP}" "lalfred://debug/cancel"
  sleep 1
done
sleep 1

if ! pgrep -f "${APP}/Contents/MacOS/" > /dev/null; then
  echo "ERROR: the app died during the smoke test." >&2
  exit 1
fi

NEW_CRASHES="$(find "${CRASH_REPORTS}" -name "L'Alfred*.ips" -newer "${START_MARKER}" 2>/dev/null || true)"
if [ -n "${NEW_CRASHES}" ]; then
  echo "ERROR: crash report(s) written during the smoke test:" >&2
  echo "${NEW_CRASHES}" >&2
  exit 1
fi

CAPTURES="$(grep -c "Capturing from" "${LOG}" || true)"
if [ "${CAPTURES}" -lt "${DICTATIONS}" ]; then
  echo "ERROR: only ${CAPTURES} of ${DICTATIONS} dictations opened the microphone (log: ${LOG})." >&2
  exit 1
fi

touch "build/smoke-passed-${COMMIT}"
echo "==> Smoke test passed: ${DICTATIONS} dictations, microphone: $(grep -o "Capturing from [^(]*" "${LOG}" | sort -u | sed 's/Capturing from //' | paste -sd, -)"
