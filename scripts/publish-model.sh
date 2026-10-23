#!/usr/bin/env bash
# Exports Phonon 40m English (gradium/phonon-40m-en) as a Core ML bundle and publishes it to a
# Hugging Face model repo you own, so the app can download it on first run (it is never bundled).
#
# Why this step exists: the upstream repo only holds GGUF/safetensors weights and is gated. The
# iOS runtime (PhononTTS) loads Core ML bundles, so the model has to be exported once.
#
# Requirements:
#   - Rust (cargo), git, curl, python3
#   - Hugging Face CLI (`hf`), logged in with a WRITE token: `hf auth login`
#   - You accepted the terms on https://huggingface.co/gradium/phonon-40m-en (the repo is gated)
#
# Usage:  HF_REPO=yourname/phonon-40m-en-coreml ./scripts/publish-model.sh
#
# License: the upstream weights are CC BY-NC 4.0 (non-commercial, attribution required). The
# published repo is a derivative; keep the attribution in its README (this script writes one).
#
# Afterwards set the printed URL as PHONON_MODEL_BASE_URL in the Xcode project build settings.
set -euo pipefail

: "${HF_REPO:?Set HF_REPO, for example yourname/phonon-40m-en-coreml}"
VERSION="${PHONON_RELEASE:-v0.4.0}"
UPSTREAM_MODEL="gradium/phonon-40m-en"
VOICES_BASE="https://huggingface.co/gradium/phonon-voices/resolve/main"

for tool in cargo git curl python3 hf; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: ${tool}. See the requirements at the top of this script." >&2
    exit 1
  fi
done

if ! hf auth whoami >/dev/null 2>&1; then
  echo "Not logged in to Hugging Face. Run: hf auth login" >&2
  exit 1
fi
# The exporter reads the token from HF_TOKEN or the CLI login.
if [ -z "${HF_TOKEN:-}" ]; then
  HF_TOKEN="$(hf auth token 2>/dev/null || true)"
  export HF_TOKEN
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Fetching the exporter (xn-ptts ${VERSION})"
git clone --quiet --depth 1 --branch "${VERSION}" https://github.com/gradium-ai/xn-ptts "${WORK}/xn-ptts"

echo "Fetching English voices from gradium/phonon-voices"
mkdir -p "${WORK}/voices"
curl -fsSL "${VOICES_BASE}/voices.jsonl" -o "${WORK}/voices.jsonl"
python3 - "${WORK}" "${VOICES_BASE}" <<'PY'
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

BUNDLE="${WORK}/phonon-40m-en-coreml"
echo "Exporting ${UPSTREAM_MODEL} as Core ML (this compiles the exporter, so it takes a while)"
(
  cd "${WORK}/xn-ptts"
  cargo run --release -p ptts --example export_coreml --features hub -- \
    "${BUNDLE}" --model "hf://${UPSTREAM_MODEL}" --voices "${WORK}/voices"
)

if [ ! -f "${BUNDLE}/bundle.json" ]; then
  echo "bundle.json was not produced by the export" >&2
  exit 1
fi

cat > "${BUNDLE}/README.md" <<EOF
---
license: cc-by-nc-4.0
base_model: ${UPSTREAM_MODEL}
---
# Phonon 40m English, Core ML

Core ML export of [${UPSTREAM_MODEL}](https://huggingface.co/${UPSTREAM_MODEL}) by Gradium,
built with the xn-ptts \`export_coreml\` example (${VERSION}) for the PhononTTS Swift package.
Voices are from [gradium/phonon-voices](https://huggingface.co/gradium/phonon-voices).

Licensed under CC BY-NC 4.0: attribution required, non-commercial use only.
EOF

echo "Uploading to ${HF_REPO}"
hf repo create "${HF_REPO}" --repo-type model --exist-ok
hf upload "${HF_REPO}" "${BUNDLE}" . --repo-type model \
  --commit-message "Phonon 40m English Core ML bundle (xn-ptts ${VERSION})"

echo
echo "Done. Set PHONON_MODEL_BASE_URL to:"
echo "  https://huggingface.co/${HF_REPO}/resolve/main"
