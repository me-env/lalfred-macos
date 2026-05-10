#!/bin/bash
set -euo pipefail

# Builds the Xcode archive (.xcarchive) containing the signed .app.
# Assumes `setup-keychain.sh` has already populated the user keychain
# search list with the Developer ID cert.

xcodebuild archive \
  -project dictate.xcodeproj \
  -scheme lalfred \
  -configuration Release \
  -archivePath build/LAlfred.xcarchive \
  -destination "generic/platform=macOS" \
  DEVELOPMENT_TEAM=5X9ZWT7KT3 \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application: Cyprien Ricque (5X9ZWT7KT3)"
