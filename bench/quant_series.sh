#!/usr/bin/env bash
# Quantization series (2026-10-19): LLM and mmproj variants, O2 setting, 256 image tokens.
set -euo pipefail
cd "$(dirname "$0")/.."
export GGML_CUDA_MMQ_MAX_BATCH=32
M=models
REF_MMPROJ=$M/mmproj-Ministral-3-3B-Instruct-2512-Q8_0.gguf
Q4KM=$M/Ministral-3-3B-Instruct-2512-Q4_K_M.gguf
for q in Q4_0 Q5_K_M Q8_0; do
  for m in text image; do
    MODE=$m MODEL=$M/Ministral-3-3B-Instruct-2512-$q.gguf MMPROJ=$REF_MMPROJ IMAGE_MAX_TOKENS=256 \
      LABEL=quant-llm-$q-$m ./scripts/bench_vqa.sh; sleep 90
  done
done
for q in F16 Q8_0 Q5_0 Q4_0; do
  MODE=image MODEL=$Q4KM MMPROJ=$M/mmproj-lumen-$q.gguf IMAGE_MAX_TOKENS=256 \
    LABEL=quant-mmproj-$q-image ./scripts/bench_vqa.sh; sleep 90
done
# quality: 3 questions per variant, no --ignore-eos
O=bench/quality/$(date +%Y%m%d-%H%M%S)-quant; mkdir -p "$O"
B=third_party/llama.cpp/build-cuda/bin/llama-mtmd-cli
qs=("Describe the scene in two sentences. List the main objects you can see." \
    "What kitchen appliances can you see, and where are they in the image?" \
    "Is there a person in the image? If so, what are they doing?")
variants=("llm-Q4_0|$M/Ministral-3-3B-Instruct-2512-Q4_0.gguf|$REF_MMPROJ" \
          "llm-Q4_K_M|$Q4KM|$REF_MMPROJ" \
          "llm-Q5_K_M|$M/Ministral-3-3B-Instruct-2512-Q5_K_M.gguf|$REF_MMPROJ" \
          "llm-Q8_0|$M/Ministral-3-3B-Instruct-2512-Q8_0.gguf|$REF_MMPROJ" \
          "mmproj-F16|$Q4KM|$M/mmproj-lumen-F16.gguf" \
          "mmproj-Q5_0|$Q4KM|$M/mmproj-lumen-Q5_0.gguf" \
          "mmproj-Q4_0|$Q4KM|$M/mmproj-lumen-Q4_0.gguf")
for v in "${variants[@]}"; do
  IFS="|" read -r name model mmproj <<< "$v"
  for i in 0 1 2; do
    timeout 600 "$B" -m "$model" --mmproj "$mmproj" --image bench/images/test-720p.jpg -ngl 99 -t 4 -c 4096 \
      -n 160 --temp 0 -s 42 --image-max-tokens 256 -p "${qs[$i]}" < /dev/null > "$O/$name-q$((i+1)).out" 2> "$O/$name-q$((i+1)).err" || true
  done
done
echo "quality: $O"
