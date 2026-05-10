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

# 1. Stage: a temp dir containing the .app and an Applications symlink
STAGING_DIR="$(mktemp -d -t lalfred-dmg)"
trap 'rm -rf "${STAGING_DIR}"' EXIT
echo "==> Staging DMG contents"
ditto "${APP_PATH}" "${STAGING_DIR}/$(basename "${APP_PATH}")"
ln -s /Applications "${STAGING_DIR}/Applications"

# 2. Create DMG from staging dir
DMG_TMP="$(mktemp -t lalfred-dmg).dmg"
rm -f "${DMG_TMP}"
echo "==> Creating DMG"
hdiutil create \
  -volname "${VOLNAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_TMP}"


mkdir -p "$(dirname "${DMG_FINAL}")"
mv "${DMG_TMP}" "${DMG_FINAL}"


# 3. Sign the DMG
echo "==> Signing DMG"
codesign --sign "${DEVELOPER_ID}" --timestamp "${DMG_FINAL}"

# 4. Notarize the DMG
echo "==> Notarizing DMG"
xcrun notarytool submit "${DMG_FINAL}" \
  --key "${AC_API_KEY_PATH}" \
  --key-id "75U623RH52" \
  --issuer "1d327459-1aa2-4c1c-9ef3-561cea662e40" \
  --wait


# 5. Staple
echo "==> Stapling DMG"
xcrun stapler staple "${DMG_FINAL}"
xcrun stapler validate "${DMG_FINAL}"

echo "==> Done: ${DMG_FINAL}"
