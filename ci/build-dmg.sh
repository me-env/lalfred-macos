#!/bin/sh
set -euo pipefail

: "${AC_API_KEY_BASE64:?AC_API_KEY_BASE64 not set}"

APP_PATH="build/export/L'Alfred.app"
VERSION="$(plutil -extract CFBundleShortVersionString raw "${APP_PATH}/Contents/Info.plist")"
BUILD="$(plutil -extract CFBundleVersion raw "${APP_PATH}/Contents/Info.plist")"
DMG_FINAL="build/LAlfred-${VERSION}.dmg"
VOLNAME="L'Alfred"
DEVELOPER_ID="Developer ID Application: Cyprien Ricque (5X9ZWT7KT3)"

echo "Version found : $VERSION"
echo "Build found : $BUILD"

AC_API_KEY_PATH="$(mktemp -t ac_api_key).p8"

trap 'rm -f "${AC_API_KEY_PATH}"' EXIT
echo "${AC_API_KEY_BASE64}" | base64 --decode > "${AC_API_KEY_PATH}"

# 1. Build DMG with dmgbuild
echo "==> Creating DMG"
mkdir -p "$(dirname "${DMG_FINAL}")"
rm -f "${DMG_FINAL}"
dmgbuild \
  -s ci/dmg-settings.py \
  -D app="${APP_PATH}" \
  "${VOLNAME}" \
  "${DMG_FINAL}"

# 2. Sign + notarize + staple (unchanged)
echo "==> Signing"
codesign --sign "${DEVELOPER_ID}" --timestamp "${DMG_FINAL}"

echo "==> Notarizing"
xcrun notarytool submit "${DMG_FINAL}" \
  --key "${AC_API_KEY_PATH}" \
  --key-id "75U623RH52" \
  --issuer "1d327459-1aa2-4c1c-9ef3-561cea662e40" \
  --wait

echo "==> Stapling"
xcrun stapler staple "${DMG_FINAL}"
xcrun stapler validate "${DMG_FINAL}"

echo "==> Done: ${DMG_FINAL}"
