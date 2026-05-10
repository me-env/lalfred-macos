#!/bin/sh
set -euo pipefail

# Publishes a release to Scaleway Object Storage.
#
# Layout in the bucket (`lalfred-prod-public`):
#   /appcast.xml                              ← Sparkle update feed (Sparkle's
#                                                signed payload guarantees
#                                                integrity, so it's safe to
#                                                serve over HTTPS from any host)
#   /latest.json                              ← single source of truth for
#                                                "what's the latest release",
#                                                consumed by the landing page's
#                                                /download/latest redirect
#   /lalfred-releases/LAlfred-${V}.dmg        ← user-facing download
#   /lalfred-releases/LAlfred-${V}.zip        ← Sparkle delta target
#
# `appcast.xml` and `latest.json` are rewritten on every release; the DMG/ZIP
# names are versioned so old releases stay reachable for users on older clients.
# `latest.json` MUST be uploaded last so it never points at a not-yet-uploaded
# artifact during the publish window.

: "${SCW_ACCESS_KEY:?SCW_ACCESS_KEY not set}"
: "${SCW_SECRET_KEY:?SCW_SECRET_KEY not set}"

APP_PATH="build/export/L'Alfred.app"
VERSION="$(plutil -extract CFBundleShortVersionString raw "${APP_PATH}/Contents/Info.plist")"
BUILD="$(plutil -extract CFBundleVersion raw "${APP_PATH}/Contents/Info.plist")"

DMG_PATH="build/LAlfred-${VERSION}.dmg"
ZIP_PATH="build/LAlfred-${VERSION}.zip"
APPCAST_PATH="build/appcast.xml"

BUCKET="lalfred-prod-public"
ENDPOINT="https://s3.fr-par.scw.cloud"
REGION="fr-par"
RELEASES_PREFIX="lalfred-releases"

# Match the existing bucket objects (see `LAlfred-1.12.dmg`) so binaries stay on
# the cheap tier — they're write-once, read-many and hosted from a single PoP.
STORAGE_CLASS="ONEZONE_IA"

export AWS_ACCESS_KEY_ID="${SCW_ACCESS_KEY}"
export AWS_SECRET_ACCESS_KEY="${SCW_SECRET_KEY}"
export AWS_DEFAULT_REGION="${REGION}"

s3() {
  aws --endpoint-url "${ENDPOINT}" "$@"
}

for f in "${DMG_PATH}" "${ZIP_PATH}" "${APPCAST_PATH}"; do
  if [ ! -f "${f}" ]; then
    echo "Missing artifact: ${f}" >&2
    exit 1
  fi
done

echo "==> Uploading DMG (${DMG_PATH})"
s3 s3 cp "${DMG_PATH}" "s3://${BUCKET}/${RELEASES_PREFIX}/$(basename "${DMG_PATH}")" \
  --acl public-read \
  --storage-class "${STORAGE_CLASS}" \
  --content-type "application/x-apple-diskimage" \
  --cache-control "public, max-age=31536000, immutable"

echo "==> Uploading ZIP (${ZIP_PATH})"
s3 s3 cp "${ZIP_PATH}" "s3://${BUCKET}/${RELEASES_PREFIX}/$(basename "${ZIP_PATH}")" \
  --acl public-read \
  --storage-class "${STORAGE_CLASS}" \
  --content-type "application/zip" \
  --cache-control "public, max-age=31536000, immutable"

# AppCast is mutable (rewritten on every release) so a short max-age is enough.
# The landing site's /appcast.xml proxy adds another caching layer in front.
echo "==> Uploading appcast.xml"
s3 s3 cp "${APPCAST_PATH}" "s3://${BUCKET}/appcast.xml" \
  --acl public-read \
  --content-type "application/xml; charset=utf-8" \
  --cache-control "public, max-age=300"

# Build the manifest into a temp file (kept out of build/ so it doesn't end up
# in the GitHub Actions artifact upload).
LATEST_JSON_PATH="$(mktemp -t latest_json)"
trap 'rm -f "${LATEST_JSON_PATH}"' EXIT
PUBLISHED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
cat > "${LATEST_JSON_PATH}" <<EOF
{
  "version": "${VERSION}",
  "build": "${BUILD}",
  "dmg": "${RELEASES_PREFIX}/$(basename "${DMG_PATH}")",
  "zip": "${RELEASES_PREFIX}/$(basename "${ZIP_PATH}")",
  "publishedAt": "${PUBLISHED_AT}"
}
EOF

# Uploaded LAST: once `latest.json` flips, the landing page starts pointing
# users at this version, so the DMG/ZIP/appcast must already be in place.
echo "==> Uploading latest.json"
s3 s3 cp "${LATEST_JSON_PATH}" "s3://${BUCKET}/latest.json" \
  --acl public-read \
  --content-type "application/json; charset=utf-8" \
  --cache-control "public, max-age=300"

echo "==> Done: version ${VERSION} published"
echo "    DMG       https://${BUCKET}.s3.fr-par.scw.cloud/${RELEASES_PREFIX}/$(basename "${DMG_PATH}")"
echo "    ZIP       https://${BUCKET}.s3.fr-par.scw.cloud/${RELEASES_PREFIX}/$(basename "${ZIP_PATH}")"
echo "    AppCast   https://${BUCKET}.s3.fr-par.scw.cloud/appcast.xml"
echo "    Manifest  https://${BUCKET}.s3.fr-par.scw.cloud/latest.json"
