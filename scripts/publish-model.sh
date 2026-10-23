#!/usr/bin/env bash
# Publishes the Phonon 31m Core ML bundle to your own Hugging Face model repo so the app can
# download it on first run (it is never bundled in the app).
#
# Requirements: curl, unzip, and the Hugging Face CLI logged in with a write token
#   (https://huggingface.co/docs/huggingface_hub/guides/cli  ->  `hf auth login`).
#
# Usage:  HF_REPO=yourname/phonon-31m-en-coreml ./scripts/publish-model.sh
#
# Afterwards set the printed URL as the PHONON_MODEL_BASE_URL build setting (or paste it into
# Settings > Voice Model > Model host URL in the app).
set -euo pipefail

: "${HF_REPO:?Set HF_REPO, for example yourname/phonon-31m-en-coreml}"
VERSION="${PHONON_RELEASE:-v0.4.0}"
ZIP_URL="https://github.com/gradium-ai/xn-ptts/releases/download/${VERSION}/phonon-31m-en-coreml.zip"

if ! command -v hf >/dev/null 2>&1; then
  echo "The Hugging Face CLI ('hf') is not installed. See the link at the top of this script." >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Downloading ${ZIP_URL}"
curl -fL --progress-bar -o "${WORK}/model.zip" "${ZIP_URL}"
unzip -q "${WORK}/model.zip" -d "${WORK}"

BUNDLE="${WORK}/phonon-31m-en-coreml"
if [ ! -f "${BUNDLE}/bundle.json" ]; then
  echo "bundle.json not found in the release archive" >&2
  exit 1
fi

echo "Uploading to ${HF_REPO}"
hf repo create "${HF_REPO}" --repo-type model --exist-ok
hf upload "${HF_REPO}" "${BUNDLE}" . --repo-type model --commit-message "Phonon 31m English Core ML bundle (${VERSION})"

echo
echo "Done. Model host URL:"
echo "  https://huggingface.co/${HF_REPO}/resolve/main"
