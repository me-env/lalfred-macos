#!/bin/bash
set -euo pipefail

# Removes the ephemeral signing keychain created by `setup-keychain.sh`.
# Idempotent (safe to run when the keychain isn't there) so it can be
# wired to the workflow's `if: always()` step — guarantees we never
# leak a signing keychain regardless of which earlier step failed.
# Matters more for local re-runs than CI (the runner is destroyed
# anyway), but consistency wins.

KEYCHAIN_NAME="cibuild.keychain"

security delete-keychain "${KEYCHAIN_NAME}" 2>/dev/null || true
echo "==> Keychain ${KEYCHAIN_NAME} torn down (no-op if it didn't exist)"
