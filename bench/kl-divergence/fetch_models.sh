#!/usr/bin/env bash
# Download the official GGUF models and wikitext-2, checking SHA-256 against Hugging Face.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"   # repository root
mkdir -p "$ROOT/models" "$ROOT/bench/data"
cd "$ROOT/models"
get(){ repo=$1; file=$2
  sha=$(curl -fsSL "https://huggingface.co/api/models/$repo?blobs=true" | python3 -c "
import json,sys; d=json.load(sys.stdin)
print([s[\"lfs\"][\"sha256\"] for s in d[\"siblings\"] if s[\"rfilename\"]==\"$file\"][0])")
  [ -f "$file" ] && echo "$sha  $file" | sha256sum -c --quiet - 2>/dev/null && { echo "already ok: $file"; return; }
  curl -fsSL -C - "https://huggingface.co/$repo/resolve/main/$file" -o "$file"
  echo "$sha  $file" | sha256sum -c -
  echo "$repo $file $sha" >> SOURCES.txt
}
R=mistralai/Ministral-3-3B-Instruct-2512-GGUF
for f in BF16 Q8_0 Q4_K_M Q5_K_M; do get $R Ministral-3-3B-Instruct-2512-$f.gguf; done
cd "$ROOT/bench/data"
curl -fsSL https://huggingface.co/datasets/ggml-org/ci/resolve/main/wikitext-2-raw-v1.zip -o wikitext-2-raw-v1.zip
echo "ef7edb566e3e2b2d31b29c1fdb0c89a4cc683597484c3dc2517919c615435a11  wikitext-2-raw-v1.zip" | sha256sum -c -
python3 -c "import zipfile; zipfile.ZipFile(\"wikitext-2-raw-v1.zip\").extractall(\".\")"
ls -l "$ROOT/models" "$ROOT/bench/data/wikitext-2-raw"
