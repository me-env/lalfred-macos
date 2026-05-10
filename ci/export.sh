#!/bin/bash
set -euo pipefail

# Exports the .app from the .xcarchive into build/export/.
# `xcodebuild -exportArchive` with method=developer-id + signingStyle=manual
# RE-SIGNS the exported binary using the certificate from
# ExportOptions.plist (you can confirm this by inspecting the
# DistributionSummary.plist it writes next to the output), so the keychain
# set up by `setup-keychain.sh` must still be in the user search list.

xcodebuild -exportArchive \
  -archivePath build/LAlfred.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist
