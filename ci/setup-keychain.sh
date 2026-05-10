#!/bin/bash
set -euo pipefail

# Sets up an ephemeral signing keychain containing the Developer ID cert.
# Lives for the duration of the whole publish pipeline because every signing
# operation needs it:
#   - archive.sh         : `xcodebuild archive` signs the .app
#   - export.sh          : `xcodebuild -exportArchive` re-signs on export
#                          (yes, really — see ExportOptions.plist + the
#                           DistributionSummary.plist that exportArchive
#                           writes next to the exported binary)
#   - build-dmg.sh       : `codesign --sign` signs the DMG
#
# `teardown-keychain.sh` is wired to the workflow's `if: always()` step so
# the keychain is removed whether the pipeline succeeds, fails, or is
# re-run locally. Within this script, the trap covers the failure window
# where we've partly created the keychain — on success we explicitly
# disarm the trap so downstream scripts can use the cert.

: "${MACOS_CERTIFICATE_BASE64:?MACOS_CERTIFICATE_BASE64 not set}"
: "${MACOS_CERTIFICATE_PWD:?MACOS_CERTIFICATE_PWD not set}"

KEYCHAIN_NAME="cibuild.keychain"
# Local-only password for the ephemeral keychain. It never leaves the
# machine, so secrecy is irrelevant.
KEYCHAIN_PWD="cibuild"

CERT_FILE="$(mktemp -t cibuild-cert).p12"

KEYCHAIN_KEEP=0
cleanup() {
  rm -f "${CERT_FILE}"
  if [ "${KEYCHAIN_KEEP}" -ne 1 ]; then
    security delete-keychain "${KEYCHAIN_NAME}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Idempotent for local re-runs: on a fresh CI runner this is a no-op.
security delete-keychain "${KEYCHAIN_NAME}" 2>/dev/null || true

echo "${MACOS_CERTIFICATE_BASE64}" | base64 --decode > "${CERT_FILE}"

security create-keychain -p "${KEYCHAIN_PWD}" "${KEYCHAIN_NAME}"
security set-keychain-settings -t 3600 -u "${KEYCHAIN_NAME}"
security unlock-keychain -p "${KEYCHAIN_PWD}" "${KEYCHAIN_NAME}"

# Add our keychain to the user search list (keep the existing entries).
# `tr -d '"'` strips the quote marks `list-keychains` prints around each
# path; unquoted paths would break on a runner whose home has a space,
# but the standard GitHub runner paths don't.
security list-keychains -d user -s "${KEYCHAIN_NAME}" $(security list-keychains -d user | tr -d '"')

# Import the cert into the keychain
security import "${CERT_FILE}" -k "${KEYCHAIN_NAME}" -P "${MACOS_CERTIFICATE_PWD}" -T /usr/bin/codesign

# Allow codesign to use the imported key without prompting.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "${KEYCHAIN_PWD}" "${KEYCHAIN_NAME}"

# Past the last failure point — let the trap leave the keychain alive.
KEYCHAIN_KEEP=1
echo "==> Keychain ${KEYCHAIN_NAME} ready"
