#!/bin/bash
set -euo pipefail

: "${SPARKLE_PRIVATE_KEY:?SPARKLE_PRIVATE_KEY not set}"

APP_PATH="build/export/L'Alfred.app"
VERSION="$(plutil -extract CFBundleShortVersionString raw "${APP_PATH}/Contents/Info.plist")"
BUILD="$(plutil -extract CFBundleVersion raw "${APP_PATH}/Contents/Info.plist")"
DIST_DIR="build"
ZIP_PATH="${DIST_DIR}/LAlfred-${VERSION}.zip"
APPCAST_PATH="${DIST_DIR}/appcast.xml"

# Public URLs go through the FastAPI release endpoints so we can swap
# hosting providers later without invalidating the URLs Sparkle already
# cached on user machines. The API routes are thin redirects to the bucket.
DOWNLOAD_BASE="https://api.dictate.lalfred.ai/releases/files"
DOWNLOAD_URL="${DOWNLOAD_BASE}/LAlfred-${VERSION}.zip"

mkdir -p "${DIST_DIR}"

# --- Write Sparkle private key to a temp file ---
# Key/Info.plist consistency is enforced by `verify-sparkle-key.sh`,
# run earlier in the pipeline — by the time we get here we know the
# secret matches the binary we're about to sign for.
# `sign_update -f` trims trailing whitespace, so a trailing newline from
# `echo` is harmless.
SPARKLE_KEY_PATH="$(mktemp -t sparkle_key)"
trap 'rm -f "${SPARKLE_KEY_PATH}"' EXIT
echo "${SPARKLE_PRIVATE_KEY}" > "${SPARKLE_KEY_PATH}"

# --- Locate Sparkle tools ---
# `ci/install-sparkle.sh` (run earlier) fetches a pinned, checksum-verified
# Sparkle release and exposes it under build/.sparkle/current/. We do not
# install Sparkle here so the install step can be cached independently and
# this script stays focused on signing/appcast generation.
SIGN_UPDATE="${DIST_DIR}/.sparkle/current/bin/sign_update"
if [[ ! -x "${SIGN_UPDATE}" ]]; then
  echo "ERROR: ${SIGN_UPDATE} not found. Run ci/install-sparkle.sh first." >&2
  exit 1
fi

# --- Zip the stapled .app ---
echo "==> Zipping app for Sparkle"
ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"

# --- Sign the zip ---
echo "==> Signing zip with EdDSA"
SIGN_OUTPUT="$("${SIGN_UPDATE}" -f "${SPARKLE_KEY_PATH}" "${ZIP_PATH}")"
echo "${SIGN_OUTPUT}"
# Output looks like: sparkle:edSignature="abc..." length="12345"
ED_SIGNATURE="$(echo "${SIGN_OUTPUT}" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
LENGTH="$(echo "${SIGN_OUTPUT}" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"

if [[ -z "${ED_SIGNATURE}" || -z "${LENGTH}" ]]; then
  echo "ERROR: failed to parse sign_update output" >&2
  exit 1
fi

# --- Generate appcast.xml ---
echo "==> Generating appcast.xml"
PUB_DATE="$(LC_TIME=en_US.UTF-8 date -u +"%a, %d %b %Y %H:%M:%S +0000")"

cat > "${APPCAST_PATH}" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>L'Alfred</title>
        <link>https://api.dictate.lalfred.ai/releases/appcast.xml</link>
        <description>L'Alfred updates</description>
        <language>en</language>
        <item>
            <title>Version ${VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${BUILD}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion>
            <enclosure
                url="${DOWNLOAD_URL}"
                length="${LENGTH}"
                type="application/octet-stream"
                sparkle:edSignature="${ED_SIGNATURE}" />
        </item>
    </channel>
</rss>
EOF

echo "==> Done"
echo "  Zip:     ${ZIP_PATH}"
echo "  Appcast: ${APPCAST_PATH}"
