#!/bin/bash
set -euo pipefail

# Installs the official Sparkle release tarball into build/.sparkle/<version>/
# and exposes it under build/.sparkle/current/ for downstream scripts.
#
# We deliberately do NOT use `brew install --cask sparkle`:
#   1. The cask is being disabled on 2026-09-01 because it fails Gatekeeper —
#      `spctl` rejects the bundled binaries, so launching `sign_update` pops
#      the "could not verify ... is free of malware" dialog.
#   2. Pinning the upstream tarball gives us a reproducible build (version +
#      SHA256) and avoids Homebrew formula churn.
#
# `curl` does not set com.apple.quarantine, so Gatekeeper won't gate the
# extracted tools locally or in CI. The defensive `xattr -dr` below is
# belt-and-braces in case a future macOS changes that.
#
# To upgrade:
#   VER=<new-version>
#   curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$VER/Sparkle-$VER.tar.xz" | shasum -a 256
# then bump SPARKLE_VERSION and SPARKLE_SHA256 below.

SPARKLE_VERSION="2.9.1"
SPARKLE_SHA256="c0dde519fd2a43ddfc6a1eb76aec284d7d888fe281414f9177de3164d98ba4c7"

DIST_DIR="build"
SPARKLE_ROOT="${DIST_DIR}/.sparkle"
SPARKLE_CACHE_DIR="${SPARKLE_ROOT}/${SPARKLE_VERSION}"
SPARKLE_CURRENT="${SPARKLE_ROOT}/current"
SPARKLE_TARBALL="${SPARKLE_CACHE_DIR}/Sparkle-${SPARKLE_VERSION}.tar.xz"
SIGN_UPDATE="${SPARKLE_CACHE_DIR}/bin/sign_update"

mkdir -p "${SPARKLE_CACHE_DIR}"

if [[ ! -x "${SIGN_UPDATE}" ]]; then
  echo "==> Downloading Sparkle ${SPARKLE_VERSION}"
  curl -fsSL \
    "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
    -o "${SPARKLE_TARBALL}"

  echo "==> Verifying checksum"
  ACTUAL_SHA256="$(shasum -a 256 "${SPARKLE_TARBALL}" | awk '{print $1}')"
  if [[ "${ACTUAL_SHA256}" != "${SPARKLE_SHA256}" ]]; then
    echo "ERROR: Sparkle tarball checksum mismatch" >&2
    echo "  expected: ${SPARKLE_SHA256}" >&2
    echo "  actual:   ${ACTUAL_SHA256}" >&2
    exit 1
  fi

  echo "==> Extracting Sparkle"
  tar -xJf "${SPARKLE_TARBALL}" -C "${SPARKLE_CACHE_DIR}"
  xattr -dr com.apple.quarantine "${SPARKLE_CACHE_DIR}" 2>/dev/null || true
fi

if [[ ! -x "${SIGN_UPDATE}" ]]; then
  echo "ERROR: sign_update not found at ${SIGN_UPDATE} after extraction" >&2
  exit 1
fi

# Stable path that downstream scripts can rely on without knowing the version.
ln -sfn "${SPARKLE_VERSION}" "${SPARKLE_CURRENT}"

echo "==> Sparkle ${SPARKLE_VERSION} ready at ${SPARKLE_CURRENT}/"
"${SPARKLE_CURRENT}/bin/sign_update" --help >/dev/null 2>&1 || true
echo "    sign_update: ${SPARKLE_CURRENT}/bin/sign_update"
