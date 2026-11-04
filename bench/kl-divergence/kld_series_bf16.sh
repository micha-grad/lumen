#!/usr/bin/env bash
# KL-divergence series vs the BF16 reference, full wikitext-2 test set (2026-10-23).
set -euo pipefail
cd "$(dirname "$0")/../.."   # repository root
B=third_party/llama.cpp/build-cuda/bin
M=models
D=bench/data
O=bench/quality/$(date +%Y%m%d-%H%M%S)-kld-bf16; mkdir -p "$O"
TEST=$D/wikitext-2-raw/wiki.test.raw
TRAIN=$D/wikitext-2-raw/wiki.train.raw
COMMON="-ngl 99 -c 512 -b 512"
BASE=$D/kld-base-bf16-c512-full.bin
echo "== reference logits (BF16, full test set)"
$B/llama-perplexity -m $M/Ministral-3-3B-Instruct-2512-BF16.gguf -f $TEST $COMMON --kl-divergence-base $BASE > $O/base-bf16.log 2>&1
echo "== imatrix (BF16, wiki.train, 200 chunks)"
$B/llama-imatrix -m $M/Ministral-3-3B-Instruct-2512-BF16.gguf -f $TRAIN $COMMON --chunks 200 -o $D/imatrix-bf16-wikitrain-c512-n200.gguf > $O/imatrix.log 2>&1
echo "== quantize Q4_0 with BF16 imatrix"
$B/llama-quantize --imatrix $D/imatrix-bf16-wikitrain-c512-n200.gguf $M/Ministral-3-3B-Instruct-2512-BF16.gguf $M/Ministral-3-3B-Instruct-2512-Q4_0-imatbf16.gguf Q4_0 > $O/quantize.log 2>&1
for q in Q8_0 Q5_K_M Q4_K_M Q4_0 Q4_0-imatbf16; do
  echo "== KLD $q"
  $B/llama-perplexity -m $M/Ministral-3-3B-Instruct-2512-$q.gguf $COMMON --kl-divergence-base $BASE --kl-divergence > $O/kld-$q.log 2>&1
done
echo "logs: $O"
