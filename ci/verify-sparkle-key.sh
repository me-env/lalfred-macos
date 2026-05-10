#!/bin/bash
set -euo pipefail

# Pre-flight check: confirm `SPARKLE_PRIVATE_KEY` matches the
# `SUPublicEDKey` baked into the shipped .app's Info.plist.
#
# Without this check, a drift between the secret and the public key in
# the binary (e.g. one was rotated and the other wasn't) produces signed
# updates that every client silently rejects — CI sees nothing, no error
# is logged server-side, and users just stop receiving updates.
#
# Runs before zip+sign in the publish pipeline so a mismatch fails fast,
# *before* we've spent time uploading anything.
#
# Requires: python3 with the `cryptography` package (installed in the
# `Install Python deps` workflow step).

: "${SPARKLE_PRIVATE_KEY:?SPARKLE_PRIVATE_KEY not set}"

APP_PATH="build/export/L'Alfred.app"
INFO_PLIST="${APP_PATH}/Contents/Info.plist"

if [ ! -f "${INFO_PLIST}" ]; then
  echo "ERROR: ${INFO_PLIST} not found — run export.sh first." >&2
  exit 1
fi

EMBEDDED_PUBKEY="$(plutil -extract SUPublicEDKey raw "${INFO_PLIST}")"

DERIVED_PUBKEY="$(SPARKLE_PRIVATE_KEY="${SPARKLE_PRIVATE_KEY}" python3 - <<'PY'
import base64, os
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization

priv_b64 = os.environ["SPARKLE_PRIVATE_KEY"].strip()
# Sparkle exports the 32-byte ed25519 seed; some tools emit 64 bytes
# (seed + pubkey concatenated) — take the first 32 either way.
priv_seed = base64.b64decode(priv_b64)[:32]
priv = Ed25519PrivateKey.from_private_bytes(priv_seed)
pub_raw = priv.public_key().public_bytes(
    encoding=serialization.Encoding.Raw,
    format=serialization.PublicFormat.Raw,
)
print(base64.b64encode(pub_raw).decode())
PY
)"

if [ "${DERIVED_PUBKEY}" != "${EMBEDDED_PUBKEY}" ]; then
  echo "ERROR: SPARKLE_PRIVATE_KEY does not match SUPublicEDKey in Info.plist" >&2
  echo "  Info.plist: ${EMBEDDED_PUBKEY}" >&2
  echo "  Derived:    ${DERIVED_PUBKEY}" >&2
  exit 1
fi

echo "==> Sparkle key pair OK (pubkey ${EMBEDDED_PUBKEY})"
