#!/bin/sh
set -euo pipefail

# Pre-publish guard: fails the build if CFBundleVersion (used as
# `sparkle:version` in the appcast) has NOT been incremented compared to the
# currently published release.
#
# Without this check, shipping the same build number twice causes Sparkle to
# silently consider the "new" release as not-an-update — clients stay on the
# old version with no error surfaced anywhere.
#
# Source of truth: `latest.json` in the public bucket, written by
# `upload-release.sh` at the end of every successful publish.
#
# Designed to run as early as possible in the publish pipeline (right after
# the .app is produced, before notarization) so a missed bump fails fast.
#
# Pass-through cases (exit 0 with a warning):
#   - Manifest 404 → first publish ever, nothing to compare against.
#   - Manifest has no `build` field → legacy publish predates this check.

APP_PATH="build/export/L'Alfred.app"
MANIFEST_URL="https://lalfred-prod-public.s3.fr-par.scw.cloud/latest.json"

LOCAL_BUILD="$(plutil -extract CFBundleVersion raw "${APP_PATH}/Contents/Info.plist")"
LOCAL_VERSION="$(plutil -extract CFBundleShortVersionString raw "${APP_PATH}/Contents/Info.plist")"

echo "Local:  version=${LOCAL_VERSION} build=${LOCAL_BUILD}"

# Cache-bust the bucket's 5-minute Cache-Control window so we always read the
# freshest manifest (matters when re-running CI shortly after a publish).
TMP="$(mktemp -t latest_json)"
trap 'rm -f "${TMP}"' EXIT
HTTP_CODE="$(curl -fsS -o "${TMP}" -w '%{http_code}' \
  "${MANIFEST_URL}?ts=$(date +%s)" || echo "000")"

if [ "${HTTP_CODE}" = "404" ]; then
  echo "==> No published manifest yet (404) — first release, skipping check."
  exit 0
fi
if [ "${HTTP_CODE}" != "200" ]; then
  echo "ERROR: failed to fetch ${MANIFEST_URL} (HTTP ${HTTP_CODE})" >&2
  exit 1
fi

REMOTE_BUILD="$(python3 -c "import json,sys; print(json.load(sys.stdin).get('build') or '')" < "${TMP}")"
REMOTE_VERSION="$(python3 -c "import json,sys; print(json.load(sys.stdin).get('version') or '')" < "${TMP}")"

echo "Remote: version=${REMOTE_VERSION} build=${REMOTE_BUILD:-<missing>}"

if [ -z "${REMOTE_BUILD}" ]; then
  echo "==> Remote manifest has no 'build' field (legacy) — skipping check."
  exit 0
fi

# `sort -V` accepts both plain integers and dotted versions, so this works
# whether CFBundleVersion is `42` or `1.2.3.42`.
HIGHEST="$(printf '%s\n%s\n' "${REMOTE_BUILD}" "${LOCAL_BUILD}" | sort -V | tail -1)"
if [ "${LOCAL_BUILD}" = "${REMOTE_BUILD}" ] || [ "${HIGHEST}" != "${LOCAL_BUILD}" ]; then
  echo "ERROR: local build (${LOCAL_BUILD}) must be greater than published (${REMOTE_BUILD})." >&2
  echo "       Bump CFBundleVersion in the Xcode project before releasing." >&2
  exit 1
fi

echo "==> OK: build ${LOCAL_BUILD} > published ${REMOTE_BUILD}"
