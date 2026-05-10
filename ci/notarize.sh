#!/bin/bash
set -euo pipefail

: "${AC_API_KEY_BASE64:?AC_API_KEY_BASE64 not set}"

APP_PATH="build/export/L'Alfred.app"
ZIP_NOTARIZE="build/lalfred-notarize.zip"

AC_API_KEY_PATH="$(mktemp -t ac_api_key).p8"
trap 'rm -f "${AC_API_KEY_PATH}"' EXIT
echo "${AC_API_KEY_BASE64}" | base64 --decode > "${AC_API_KEY_PATH}"


echo "==> Zipping app for notarization submission"
ditto -c -k --keepParent "${APP_PATH}" "${ZIP_NOTARIZE}"


echo "==> Submitting to Apple notary service"
xcrun notarytool submit "${ZIP_NOTARIZE}" \
  --key "${AC_API_KEY_PATH}" \
  --key-id "75U623RH52" \
  --issuer "1d327459-1aa2-4c1c-9ef3-561cea662e40" \
  --wait


echo "==> Stapling ticket"
xcrun stapler staple "${APP_PATH}"
xcrun stapler validate "${APP_PATH}"
