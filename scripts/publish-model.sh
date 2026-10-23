#!/usr/bin/env bash
# Publishes a Phonon Core ML bundle to a Hugging Face model repo you own, so the app can download
# it on first run (it is never bundled in the app).
#
# Why this step exists: the upstream Hugging Face repos only hold GGUF/safetensors weights. The
# iOS runtime (PhononTTS) loads Core ML bundles served from a static folder with a bundle.json.
#
# Models (PHONON_MODEL, default 31m):
#   31m  Re-hosts Gradium's official prebuilt bundle (GitHub release phonon-31m-en-coreml.zip,
#        with the full English voice catalog). Apache 2.0.
#   40m  Exports gradium/phonon-40m-en with the xn-ptts `export_coreml` example, plus the
#        English voice catalog. CC BY-NC 4.0 (non-commercial, attribution required). The upstream
#        repo is gated: accept its terms at https://huggingface.co/gradium/phonon-40m-en first.
#
# Requirements:
#   - curl, unzip (31m) or cargo, git, python3 (40m)
#   - Hugging Face CLI (`hf`), logged in with a WRITE token: `hf auth login`
#
# Usage:
#   HF_REPO=yourname/phonon-31m-en-coreml ./scripts/publish-model.sh
#   PHONON_MODEL=40m HF_REPO=yourname/phonon-40m-en-coreml ./scripts/publish-model.sh
#
# Afterwards set the printed URL as PHONON_MODEL_BASE_URL in the Xcode project build settings.
set -euo pipefail

MODEL="${PHONON_MODEL:-31m}"
VERSION="${PHONON_RELEASE:-v0.4.0}"
: "${HF_REPO:?Set HF_REPO, for example yourname/phonon-${MODEL}-en-coreml}"

case "$MODEL" in
  31m)
    UPSTREAM_MODEL="gradium/phonon-31m-en"
    LICENSE_ID="apache-2.0"
    LICENSE_NAME="Apache 2.0"
    NEEDED_TOOLS=(curl unzip hf)
    ;;
  40m)
    UPSTREAM_MODEL="gradium/phonon-40m-en"
    LICENSE_ID="cc-by-nc-4.0"
    LICENSE_NAME="CC BY-NC 4.0: attribution required, non-commercial use only"
    NEEDED_TOOLS=(cargo git curl python3 hf)
    ;;
  *)
    echo "PHONON_MODEL must be 31m or 40m (got '${MODEL}')" >&2
    exit 1
    ;;
esac

for tool in "${NEEDED_TOOLS[@]}"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: ${tool}. See the requirements at the top of this script." >&2
    exit 1
  fi
done

if ! hf auth whoami >/dev/null 2>&1; then
  echo "Not logged in to Hugging Face. Run: hf auth login" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
BUNDLE="${WORK}/phonon-${MODEL}-en-coreml"

build_31m() {
  local zip_url="https://github.com/gradium-ai/xn-ptts/releases/download/${VERSION}/phonon-31m-en-coreml.zip"
  echo "Downloading ${zip_url}"
  curl -fL --progress-bar -o "${WORK}/model.zip" "${zip_url}"
  unzip -q "${WORK}/model.zip" -d "${WORK}"
}

build_40m() {
  # The exporter reads the token from HF_TOKEN or the CLI login.
  if [ -z "${HF_TOKEN:-}" ]; then
    HF_TOKEN="$(hf auth token 2>/dev/null || true)"
    export HF_TOKEN
  fi

  echo "Fetching the exporter (xn-ptts ${VERSION})"
  git clone --quiet --depth 1 --branch "${VERSION}" https://github.com/gradium-ai/xn-ptts "${WORK}/xn-ptts"

  echo "Fetching English voices from gradium/phonon-voices"
  local voices_base="https://huggingface.co/gradium/phonon-voices/resolve/main"
  mkdir -p "${WORK}/voices"
  curl -fsSL "${voices_base}/voices.jsonl" -o "${WORK}/voices.jsonl"
  python3 - "${WORK}" "${voices_base}" <<'PY'
import json, re, subprocess, sys
work, base = sys.argv[1], sys.argv[2]
seen = set()
for line in open(f"{work}/voices.jsonl", encoding="utf-8"):
    if not line.strip():
        continue
    voice = json.loads(line)
    if voice.get("language") != "en":
        continue
    name = re.sub(r"[^A-Za-z0-9_-]+", "-", voice["name"]).strip("-")
    if not name or name in seen:
        name = f"{name or 'voice'}-{voice['voice_id']}"
    seen.add(name)
    subprocess.run(
        ["curl", "-fsSL", f"{base}/{voice['filename']}", "-o", f"{work}/voices/{name}.safetensors"],
        check=True,
    )
print(f"{len(seen)} voices")
PY

  echo "Exporting ${UPSTREAM_MODEL} as Core ML (this compiles the exporter, so it takes a while)"
  (
    cd "${WORK}/xn-ptts"
    cargo run --release -p ptts --example export_coreml --features hub -- \
      "${BUNDLE}" --model "hf://${UPSTREAM_MODEL}" --voices "${WORK}/voices"
  )
}

"build_${MODEL}"

if [ ! -f "${BUNDLE}/bundle.json" ]; then
  echo "bundle.json not found in ${BUNDLE}" >&2
  exit 1
fi

cat > "${BUNDLE}/README.md" <<EOF
---
license: ${LICENSE_ID}
base_model: ${UPSTREAM_MODEL}
---
# Phonon ${MODEL} English, Core ML

Core ML bundle of [${UPSTREAM_MODEL}](https://huggingface.co/${UPSTREAM_MODEL}) by Gradium for the
PhononTTS Swift package (xn-ptts ${VERSION}). Voices are from
[gradium/phonon-voices](https://huggingface.co/gradium/phonon-voices).

License: ${LICENSE_NAME}.
EOF

echo "Uploading to ${HF_REPO}"
hf repo create "${HF_REPO}" --repo-type model --exist-ok
hf upload "${HF_REPO}" "${BUNDLE}" . --repo-type model \
  --commit-message "Phonon ${MODEL} English Core ML bundle (xn-ptts ${VERSION})"

echo
echo "Done. Set PHONON_MODEL_BASE_URL to:"
echo "  https://huggingface.co/${HF_REPO}/resolve/main"
