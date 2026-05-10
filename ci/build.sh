#!/bin/bash

: "${MACOS_CERTIFICATE_BASE64:?MACOS_CERTIFICATE_BASE64 not set}"
: "${MACOS_CERTIFICATE_PWD:?MACOS_CERTIFICATE_PWD not set}"

# Local-only password for the ephemeral CI keychain.
# This keychain is created and deleted within this script and never leaves the runner,
# so the password does not need to be secret.
KEYCHAIN_PWD="cibuild"

# Decode the cert
echo "$MACOS_CERTIFICATE_BASE64" | base64 --decode > cert.p12

# Create a temporary keychain
security create-keychain -p "$KEYCHAIN_PWD" cibuild.keychain
security set-keychain-settings -t 3600 -u cibuild.keychain
security unlock-keychain -p "$KEYCHAIN_PWD" cibuild.keychain

security list-keychains -d user -s cibuild.keychain $(security list-keychains -d user | tr -d '"')

# Import the cert into it
security import cert.p12 -k cibuild.keychain -P "$MACOS_CERTIFICATE_PWD" -T /usr/bin/codesign

# Allow codesign to use the key without prompting
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PWD" cibuild.keychain

# Clean up
rm cert.p12


xcodebuild archive \
  -project dictate.xcodeproj \
  -scheme lalfred \
  -configuration Release \
  -archivePath build/LAlfred.xcarchive \
  -destination "generic/platform=macOS" \
  DEVELOPMENT_TEAM=5X9ZWT7KT3 \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application: Cyprien Ricque (5X9ZWT7KT3)"


security delete-keychain cibuild.keychain
