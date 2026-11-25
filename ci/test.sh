#!/bin/bash
set -euo pipefail

# Runs the unit tests (dictateTests). CI runs it on every push and before
# publishing a tag; `release.sh` runs it before tagging.
#
# The test host is signed ad hoc, so tests need no certificate. They never
# touch the microphone: the dictation lifecycle runs against fake services.

DERIVED_DATA="${DERIVED_DATA:-build/test-derived-data}"

xcodebuild test \
  -project dictate.xcodeproj \
  -scheme lalfred \
  -destination 'platform=macOS' \
  -only-testing:dictateTests \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  PROVISIONING_PROFILE_SPECIFIER=
