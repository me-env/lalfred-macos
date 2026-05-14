#!/bin/bash
set -euo pipefail

# Generates a single-sentence release note for the given tag by asking Mistral
# (mistral-large-latest) to summarize the commits since the previous tag.
#
# Usage: ./ci/generate-release-notes.sh <tag>
# Prints the sentence to stdout. Fails fast on any error (missing key, network,
# bad response) — the workflow gates this step on the secret being present so
# we never reach this script unless we expect it to succeed.
#
# Requires: MISTRAL_API_KEY in env, plus `curl` and `jq` (preinstalled on
# GitHub-hosted macOS runners).

: "${MISTRAL_API_KEY:?MISTRAL_API_KEY not set}"

TAG="${1:-}"
if [ -z "${TAG}" ]; then
  echo "Usage: $0 <tag>" >&2
  exit 1
fi

# --- Collect commits ---
# Previous tag = highest semver `v*` tag that isn't the current one. If none
# exists (first release ever), we summarize the last 20 commits leading up
# to the tag.
PREV_TAG="$(git tag -l 'v*' --sort=-v:refname | grep -vFx "${TAG}" | head -1 || true)"

if [ -n "${PREV_TAG}" ]; then
  echo "==> Summarizing ${PREV_TAG}..${TAG}" >&2
  COMMITS="$(git log --pretty=format:'- %s' "${PREV_TAG}..${TAG}")"
else
  echo "==> No previous tag; summarizing last 20 commits before ${TAG}" >&2
  COMMITS="$(git log --pretty=format:'- %s' -n 20 "${TAG}")"
fi

if [ -z "${COMMITS}" ]; then
  echo "ERROR: no commits found for ${TAG} — refusing to call the model." >&2
  exit 1
fi

echo "${COMMITS}" >&2

# --- Build prompt + payload ---
# Commit messages follow a `Feature: / Fix: / Chore: / Docs: ...` convention;
# we ask the model to focus on user-visible changes and ignore chore/docs.
PROMPT="Summarize these git commits into a single, polished, user-facing sentence (max 25 words) for a macOS app release note. The commits follow a 'Feature:/Fix:/Chore:/Docs:' convention — focus on Feature and Fix items, ignore Chore and Docs. Output only the sentence, no quotes, no prefix like 'This release'.

Commits:
${COMMITS}"

PAYLOAD="$(jq -n --arg model "mistral-large-latest" --arg prompt "${PROMPT}" '{
  model: $model,
  messages: [{ role: "user", content: $prompt }],
  temperature: 0.1
}')"

# --- Call Mistral ---
# Mistral's chat-completions endpoint is OpenAI-compatible, so the request
# and response shapes match — only the host and auth header differ.
HTTP_CODE_FILE="$(mktemp -t mistral_code)"
RESPONSE_FILE="$(mktemp -t mistral_resp)"
trap 'rm -f "${HTTP_CODE_FILE}" "${RESPONSE_FILE}"' EXIT

HTTP_CODE="$(curl -sS -o "${RESPONSE_FILE}" -w '%{http_code}' \
  https://api.mistral.ai/v1/chat/completions \
  -H "Authorization: Bearer ${MISTRAL_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}")"

if [ "${HTTP_CODE}" != "200" ]; then
  echo "ERROR: Mistral API returned HTTP ${HTTP_CODE}" >&2
  cat "${RESPONSE_FILE}" >&2
  exit 1
fi

NOTE="$(jq -r '.choices[0].message.content // empty' < "${RESPONSE_FILE}")"

if [ -z "${NOTE}" ]; then
  echo "ERROR: Mistral response had no content." >&2
  cat "${RESPONSE_FILE}" >&2
  exit 1
fi

# Trim trailing whitespace / surrounding quotes the model sometimes adds
NOTE="$(echo "${NOTE}" | sed -e 's/^[[:space:]"'"'"']*//' -e 's/[[:space:]"'"'"']*$//')"

printf '%s\n' "${NOTE}"
