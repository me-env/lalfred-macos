#!/bin/bash
set -euo pipefail

APP_PATH="build/export/L'Alfred.app"

echo "==> Verifying: '$APP_PATH'"

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: App not found at '$APP_PATH'"
    exit 1
fi

# 1. Codesign verification — must pass
echo ""
echo "==> Step 1: codesign --verify"
if codesign --verify --deep --strict --verbose=2 "$APP_PATH"; then
    echo "✓ Codesign verification passed"
else
    echo "✗ Codesign verification FAILED"
    exit 1
fi

# 2. Check signing identity is Developer ID (not adhoc, not Development)
echo ""
echo "==> Step 2: checking signing identity"
SIGN_INFO=$(codesign --display --verbose=2 "$APP_PATH" 2>&1)
echo "$SIGN_INFO"

if echo "$SIGN_INFO" | grep -q "Authority=Developer ID Application"; then
    echo "✓ Signed with Developer ID Application"
else
    echo "✗ Not signed with Developer ID Application"
    exit 1
fi

# 3. Check hardened runtime is enabled (required for notarization)
echo ""
echo "==> Step 3: checking hardened runtime"
if echo "$SIGN_INFO" | grep -q "flags=0x10000(runtime)"; then
    echo "✓ Hardened runtime enabled"
else
    echo "✗ Hardened runtime NOT enabled — notarization will fail"
    exit 1
fi

# 4. Check secure timestamp is present (required for notarization)
echo ""
echo "==> Step 4: checking secure timestamp"
if echo "$SIGN_INFO" | grep -q "Timestamp="; then
    echo "✓ Secure timestamp present"
else
    echo "✗ Secure timestamp missing — notarization will fail"
    exit 1
fi

# 5. Gatekeeper assessment — expected to FAIL pre-notarization
echo ""
echo "==> Step 5: Gatekeeper assessment (informational only, pre-notarization)"
if spctl --assess --type execute --verbose "$APP_PATH" 2>&1; then
    echo "ℹ Already passes Gatekeeper (already notarized?)"
else
    echo "ℹ Gatekeeper rejects (expected — not yet notarized)"
fi

echo ""
echo "==> All pre-notarization checks passed ✓"
exit 0
