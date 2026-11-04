#!/usr/bin/env bash
# KL-divergence series (2026-10-23): quality of LLM quantizations vs a Q8_0 reference.
set -euo pipefail
cd "$(dirname "$0")/.."
export GGML_CUDA_MMQ_MAX_BATCH=32
B=third_party/llama.cpp/build-cuda/bin
M=models
D=bench/data
O=bench/quality/$(date +%Y%m%d-%H%M%S)-kld; mkdir -p "$O"
TEST=$D/wikitext-2-raw/wiki.test.raw
TRAIN=$D/wikitext-2-raw/wiki.train.raw
COMMON="-ngl 99 -t 4 -c 512 -b 512"
CHUNKS=60
BASE=$D/kld-base-q8_0-c512-n$CHUNKS.bin
echo "== reference logits (Q8_0)"
$B/llama-perplexity -m $M/Ministral-3-3B-Instruct-2512-Q8_0.gguf -f $TEST $COMMON --chunks $CHUNKS \
  --kl-divergence-base $BASE > $O/base-q8_0.log 2>&1
echo "== imatrix (Q8_0, wiki.train)"
$B/llama-imatrix -m $M/Ministral-3-3B-Instruct-2512-Q8_0.gguf -f $TRAIN $COMMON --chunks 100 \
  -o $D/imatrix-q8_0-wikitrain-c512-n100.gguf > $O/imatrix.log 2>&1
echo "== quantize Q4_0 with imatrix"
$B/llama-quantize --imatrix $D/imatrix-q8_0-wikitrain-c512-n100.gguf \
  $M/Ministral-3-3B-Instruct-2512-BF16.gguf $M/Ministral-3-3B-Instruct-2512-Q4_0-imat.gguf Q4_0 4 > $O/quantize-q4_0-imat.log 2>&1
for q in Q4_0 Q4_0-imat Q4_K_M Q5_K_M; do
  echo "== KLD $q"
  $B/llama-perplexity -m $M/Ministral-3-3B-Instruct-2512-$q.gguf $COMMON --chunks $CHUNKS \
    --kl-divergence-base $BASE --kl-divergence > $O/kld-$q.log 2>&1
done
echo "logs: $O"
