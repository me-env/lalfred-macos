#!/bin/bash
set -euo pipefail

# Local helper to cut a new release.
#
# Usage: ./ci/release.sh <version> [--yes|-y]
#   e.g. ./ci/release.sh 1.16.6
#        ./ci/release.sh 1.16.6 --yes
#
# What it does:
#   1. Sanity-checks the working tree (on main, clean, in sync with origin).
#   2. Reads MARKETING_VERSION (CFBundleShortVersionString) from the Xcode
#      project and refuses to tag if it doesn't match the argument.
#   3. Reads CURRENT_PROJECT_VERSION (CFBundleVersion) and refuses to tag if
#      it wasn't bumped past the currently published build (same check that
#      `ci/check-build-bump.sh` does in CI, but earlier — before the tag is
#      pushed and CI is spent).
#   4. Prints a summary of what's about to happen and asks for confirmation
#      (skip with --yes / -y).
#   5. Creates an annotated tag `v<version>` and pushes it.
#
# CI takes over from there: builds, signs, notarizes, uploads to Scaleway,
# then creates the GitHub Release with an AI-generated one-line summary
# and the DMG/ZIP/appcast attached.

VERSION=""
ASSUME_YES=0
for arg in "$@"; do
  case "${arg}" in
    -y|--yes)
      ASSUME_YES=1
      ;;
    -h|--help)
      sed -n '4,22p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "ERROR: unknown flag '${arg}'." >&2
      echo "Usage: $0 <version> [--yes|-y]" >&2
      exit 1
      ;;
    *)
      if [ -n "${VERSION}" ]; then
        echo "ERROR: version already set to '${VERSION}', got extra arg '${arg}'." >&2
        exit 1
      fi
      VERSION="${arg}"
      ;;
  esac
done

if [ -z "${VERSION}" ]; then
  echo "Usage: $0 <version> [--yes|-y]   e.g. $0 1.16.6" >&2
  exit 1
fi

TAG="v${VERSION}"
PBXPROJ="dictate.xcodeproj/project.pbxproj"
MANIFEST_URL="https://lalfred-prod-public.s3.fr-par.scw.cloud/latest.json"

if [ ! -f "${PBXPROJ}" ]; then
  echo "ERROR: run this from the repo root (cannot find ${PBXPROJ})." >&2
  exit 1
fi

# --- Working tree must be clean ---
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ERROR: working tree has uncommitted changes." >&2
  exit 1
fi

# --- Must be on main, in sync with origin ---
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "${BRANCH}" != "main" ]; then
  echo "ERROR: must release from main (currently on '${BRANCH}')." >&2
  exit 1
fi

git fetch --quiet origin main
LOCAL_SHA="$(git rev-parse @)"
REMOTE_SHA="$(git rev-parse @{u})"
if [ "${LOCAL_SHA}" != "${REMOTE_SHA}" ]; then
  echo "ERROR: local main is not in sync with origin/main — pull/push first." >&2
  exit 1
fi

# --- Tag must not already exist ---
if git rev-parse "${TAG}" >/dev/null 2>&1; then
  echo "ERROR: tag ${TAG} already exists locally." >&2
  exit 1
fi
git fetch --quiet --tags origin
if git rev-parse "refs/tags/${TAG}" >/dev/null 2>&1; then
  echo "ERROR: tag ${TAG} already exists on origin." >&2
  exit 1
fi

# --- Version in Xcode project must match argument ---
# We read the first MARKETING_VERSION in the pbxproj (the app target's Release
# config — tests targets come later in the file and use a different value).
PROJECT_VERSION="$(awk -F' = |;' '/MARKETING_VERSION/ { gsub(/^[[:space:]]+/, "", $2); print $2; exit }' "${PBXPROJ}")"
if [ "${PROJECT_VERSION}" != "${VERSION}" ]; then
  echo "ERROR: MARKETING_VERSION in ${PBXPROJ} is '${PROJECT_VERSION}', you passed '${VERSION}'." >&2
  echo "       Bump it in Xcode first." >&2
  exit 1
fi

# --- Build number must be bumped past what's currently published ---
# Same source of truth as the CI check (latest.json) so we fail fast locally.
LOCAL_BUILD="$(awk -F' = |;' '/CURRENT_PROJECT_VERSION/ { gsub(/^[[:space:]]+/, "", $2); print $2; exit }' "${PBXPROJ}")"
REMOTE_JSON="$(curl -fsS "${MANIFEST_URL}?ts=$(date +%s)" 2>/dev/null || echo "")"
if [ -n "${REMOTE_JSON}" ]; then
  REMOTE_BUILD="$(echo "${REMOTE_JSON}" | python3 -c "import json,sys; print(json.load(sys.stdin).get('build') or '')")"
  if [ -n "${REMOTE_BUILD}" ]; then
    HIGHEST="$(printf '%s\n%s\n' "${REMOTE_BUILD}" "${LOCAL_BUILD}" | sort -V | tail -1)"
    if [ "${LOCAL_BUILD}" = "${REMOTE_BUILD}" ] || [ "${HIGHEST}" != "${LOCAL_BUILD}" ]; then
      echo "ERROR: CURRENT_PROJECT_VERSION (${LOCAL_BUILD}) must be greater than published (${REMOTE_BUILD})." >&2
      echo "       Bump it in Xcode before releasing." >&2
      exit 1
    fi
    echo "==> Build ${LOCAL_BUILD} > published ${REMOTE_BUILD}"
  fi
fi


# --- Confirmation ---
# Show what's about to happen, including the commits that will become the
# release-note source, so the user has one last chance to bail.
HEAD_SHORT="$(git rev-parse --short HEAD)"
HEAD_SUBJECT="$(git log -1 --pretty='%s')"
PREV_TAG="$(git tag -l 'v*' --sort=-v:refname | head -1 || true)"

echo
echo "About to release:"
echo "  Tag           : ${TAG}"
echo "  Commit        : ${HEAD_SHORT}  ${HEAD_SUBJECT}"
echo "  Version       : ${VERSION}"
echo "  Build         : ${LOCAL_BUILD}"
if [ -n "${PREV_TAG}" ]; then
  COMMIT_COUNT="$(git rev-list --count "${PREV_TAG}..HEAD" 2>/dev/null || echo "?")"
  echo "  Since ${PREV_TAG} : ${COMMIT_COUNT} commit(s)"
  echo
  git log --pretty='  - %s' "${PREV_TAG}..HEAD" 2>/dev/null || true
else
  echo "  Previous tag  : (none — first release)"
fi
echo

if [ "${ASSUME_YES}" -ne 1 ]; then
  # Read from /dev/tty so a piped invocation (e.g. `yes | ./release.sh ...`)
  # doesn't silently auto-confirm — confirmation should be a deliberate act.
  if [ ! -t 0 ] && [ ! -r /dev/tty ]; then
    echo "ERROR: not running in a terminal and no --yes flag — refusing to tag." >&2
    exit 1
  fi
  printf "Proceed? [y/N] "
  if [ -t 0 ]; then
    read -r ANSWER
  else
    read -r ANSWER < /dev/tty
  fi
  case "${ANSWER}" in
    y|Y|yes|YES) ;;
    *)
      echo "Aborted."
      exit 1
      ;;
  esac
fi

echo "==> Tagging ${TAG} at ${HEAD_SHORT} (version=${VERSION}, build=${LOCAL_BUILD})"
git tag -a "${TAG}" -m "Release ${TAG}"
git push origin "refs/tags/${TAG}"

echo
echo "==> Pushed. CI is now building the release."
echo "    Watch progress in the GitHub Actions tab; the Release will appear"
echo "    on the Releases page once the build completes."
