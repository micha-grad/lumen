#!/usr/bin/env bash
# More 4-bit candidates with the BF16 imatrix, KLD vs BF16 (2026-10-23).
set -euo pipefail
cd "$(dirname "$0")/../.."   # repository root
B=third_party/llama.cpp/build-cuda/bin
M=models
D=bench/data
O=bench/quality/$(date +%Y%m%d-%H%M%S)-kld-candidates; mkdir -p "$O"
IMAT=$D/imatrix-bf16-wikitrain-c512-n200.gguf
BASE=$D/kld-base-bf16-c512-full.bin
for q in IQ4_NL Q4_1 Q4_K_S Q4_K_M; do
  out=$M/Ministral-3-3B-Instruct-2512-$q-imatbf16.gguf
  echo "== quantize $q"
  $B/llama-quantize --imatrix $IMAT $M/Ministral-3-3B-Instruct-2512-BF16.gguf $out $q > $O/quantize-$q.log 2>&1
  echo "== KLD $q-imatbf16"
  $B/llama-perplexity -m $out -ngl 99 -c 512 -b 512 --kl-divergence-base $BASE --kl-divergence > $O/kld-$q-imatbf16.log 2>&1
done
echo "logs: $O"
