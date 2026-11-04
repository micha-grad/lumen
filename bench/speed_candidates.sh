#!/usr/bin/env bash
# Speed of the imatrix 4-bit candidates on the Jetson (O2 setting, 256 image tokens). Waits for the KLD series.
set -euo pipefail
cd "$(dirname "$0")/.."
until [ -f bench/kld.done ]; do sleep 30; done
sleep 120
export GGML_CUDA_MMQ_MAX_BATCH=32
for q in IQ4_NL Q4_1 Q4_0 Q4_K_M; do
  for m in text image; do
    MODE=$m MODEL=models/Ministral-3-3B-Instruct-2512-$q-imatbf16.gguf IMAGE_MAX_TOKENS=256 \
      LABEL=speed-$q-imatbf16-$m ./scripts/bench_vqa.sh; sleep 90
  done
done
