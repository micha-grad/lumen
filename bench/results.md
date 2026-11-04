# Benchmark results

Protocol: `CLAUDE.md` ("Benchmark protocol"), implemented by `scripts/bench_vqa.sh`
(definitions of every metric are in its header). Each row = median of 5 runs after
1 discarded warm-up run. Raw logs: `bench/runs/<date>-<label>/`, not versioned, like
the image.

Common conditions unless stated otherwise: nvpmodel MAXN, `jetson_clocks` applied
(CPU 2035.2 MHz, GPU 1300.5 MHz, EMC 1600 MHz), desktop stopped (gdm3 stopped and X11
session terminated), llama.cpp `ba3c05f` + patches 0001-0003 (v2: 0001-0004), CUDA build, `-ngl 99`,
`-t 4` (A57 cores; Denver cores isolated), `-c 4096`, flash attention auto (on),
`--temp 0 -s 42`, 64 generated tokens with `--ignore-eos`.
Power: external meter at the DC input, read manually; not recorded yet (blank column).

## Current results (v2, wall-clock TTFT, 2026-10-18)

All three configs use the same binary (`build-cuda`, patches 0001-0004) and differ
only by `GGML_CUDA_MMQ_MAX_BATCH`. The O2 sweep below checked that unset and 0
reproduce B and O1 exactly. Text: 20 prompt tokens. Image: 720p test image,
`--image-max-tokens 256`, 263 image + 21 text tokens. Throttling: cooling states 0 in
every run.

| # | Config | Mode | TTFT (wall) | Image encode | Prefill | Decode | RAM peak (Δ) | Max temp GPU/CPU | Power | Logs (`bench/runs/`) |
|---|---|---|---|---|---|---|---|---|---|---|
| B-text | baseline (MMQ, upstream choice) | text | **0.89 s** | — | 22.5 t/s | 4.74 t/s | 4036 MB (+2663) | 42.0 / 36.5 °C | — | `20261018-123630-v2-B-text-q4km` |
| B-image | baseline | image | **37.5 s** | 4.35 s | 8.6 t/s (33.0 s) | 4.71 t/s | 4784 MB (+3414) | 45.0 / 38.5 °C | — | `20261018-124022-v2-B-image-q4km` |
| O1-text | `GGML_CUDA_MMQ_MAX_BATCH=0` (= `GGML_CUDA_FORCE_CUBLAS`) | text | 2.27 s | — | 8.9 t/s | 4.74 t/s | 4293 MB (+2923) | 43.5 / 38.0 °C | — | `20261018-124802-v2-O1-text-q4km` |
| O1-image | same | image | 8.48 s | 2.77 s | 50.4 t/s (5.64 s) | 4.71 t/s | 4773 MB (+3405) | 44.5 / 39.0 °C | — | `20261018-125203-v2-O1-image-q4km` |
| **O2-text** | **`GGML_CUDA_MMQ_MAX_BATCH=32`** | text | **0.89 s** (= B) | — | 22.6 t/s | 4.74 t/s | 4032 MB (+2664) | 44.0 / 38.0 °C | — | `20261018-125650-v2-O2-text-q4km` |
| **O2-image** | same | image | **7.80 s** (×4.8 vs B) | 2.78 s | 57.4 t/s (4.95 s) | 4.71 t/s | 4845 MB (+3479) | 45.0 / 39.5 °C | — | `20261018-130042-v2-O2-image-q4km` |

**Retained configuration: O2** (`GGML_CUDA_MMQ_MAX_BATCH=32` on the TX2).

### Correction of the v1 numbers (2026-10-18)

The v1 rows below (B1/B2, O1-*, O2-* dated 2026-10-17/18) computed TTFT as
`image encode + prompt eval time + one decode step`. That was wrong twice:
1. libllama's "prompt eval time" runs from the first prompt `llama_decode` to the
   next `synchronize()` (`src/llama-context.cpp`). In VQA mode the vision encoding runs
   inside that window (text chunk → encode → image chunk → text chunk), so the encode
   was counted twice.
2. The first token is sampled from the prefill logits, so no extra decode step comes
   before it.

Check (O2, image): wall clock 7.81 / 7.76 s, against 10.73 / 10.68 s with the v1 formula
(`scripts/ttft_wall.py`, 2 runs). v1 TTFT values were therefore too high (by roughly
encode + one decode step), and v1 image prefill t/s too low. Decode, encode and RAM
figures were not affected. Since 2026-10-18, `bench_vqa.sh` measures TTFT on the wall
clock and computes image prefill as prompt eval − encode. The v1 tables are kept for
traceability only.

### v1 (superseded)

| # | Date | Config | Mode | TTFT | Image encode | Prefill | Decode | RAM peak (Δ) | Max temp GPU/CPU | Power | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| B1 | 2026-10-17 | baseline Q4_K_M | text (20 prompt tokens) | ~~1.10 s~~ | — | 22.5 t/s | 4.74 t/s | 4468 MB (+2835) | 43.0 / 37.5 °C | — | `bench/runs/20261017-175017-baseline-text-q4km` |
| B2 | 2026-10-17 | baseline Q4_K_M + mmproj Q8_0 | image 720p, `--image-max-tokens 256` (263 image + 21 text tokens) | ~~42.1 s~~ | 4.36 s | ~~7.56 t/s~~ | 4.71 t/s | 4874 MB (+3253) | 46.0 / 39.0 °C | — | `bench/runs/20261017-175440-baseline-image-q4km`; provisional (dark) test image, see below |

## Notes on the baseline

- **Test image is provisional.** `bench/images/test-720p.jpg`
  (sha256 `b1f81c29…`) was captured with the room unlit and is nearly black. Image
  encode and prefill cost depend on resolution and token count, not on content, so the
  B2 timings stand. Answer quality is not assessed until the image is recaptured with
  the room lit (same resolution, same `--image-max-tokens`).
- With `--ignore-eos` the model keeps generating after its answer (garbage after the
  real answer). This is intended: it gives a fixed decode length for timing. Quality
  checks must run without `--ignore-eos`.
- No throttling: `cpu-balanced` / `gpu-balanced` cooling states stayed at 0 in every
  run.
- The tegrastats RAM peak creeps up between runs of the same config (B1: 4421 → 4512
  MB over 5 runs, each run a new process). To watch over longer series.

## Finding: prefill is bound by the MMQ kernels on sm_62

`llama-bench` (same conditions, 3 reps): pp16 = 29.3 t/s, **pp64 = 9.8 t/s,
pp256 = 9.9 t/s** (flash attention on or off gives the same result), tg32 = 4.75 t/s.
Prefill gets slower above 16 tokens: batches above `MMVQ_MAX_BATCH_SIZE` (8) switch from
the MMVQ kernels to MMQ. On sm_62, `ggml_cuda_should_use_mmq()` returns true: no tensor
cores, dp4a available, and 48 KiB of shared memory per block meets the MMQ minimum.

`test-backend-ops perf -o MUL_MAT` (CUDA0), m=4096, k=14336:

| type | n=1 | n=8 | n=512 (MMQ) |
|---|---|---|---|
| q4_K | 53 GFLOPS | 112 GFLOPS | **61 GFLOPS** |
| q6_K | 32 GFLOPS | 115 GFLOPS | **64 GFLOPS** |

At ~61 GFLOPS and ~6.8 GFLOP per token (2 × 3.4 B parameters), prefill is capped at
~9 t/s. This matches pp256 = 9.9 t/s and the 8.6 t/s of B-image (v2; v1 showed 7.6), where image tokens also pay
the attention cost. The MMQ kernels have no register spill (`cuobjdump`: 0 bytes local
memory), so the cost comes from the kernel design for this GPU, not from the build.
Candidate optimization #1: route large batches to cuBLAS (dequantize to FP16 + GEMM;
the TX2 has 2× FP16 throughput), compile option `GGML_CUDA_FORCE_CUBLAS`.

## Optimizations

(v1 TTFT and image prefill values in this table are superseded; see "Current results
(v2)" at the top.)

| # | Date | Change | vs | TTFT | Prefill | Decode | RAM peak | Verdict |
|---|---|---|---|---|---|---|---|---|
| O1-image | 2026-10-18 | `GGML_CUDA_FORCE_CUBLAS=ON` (all batched quantized matmuls through cuBLAS FP16 instead of MMQ); build `build-cuda-cublas` | B2 | **11.59 s** (−72%, ×3.6) | 33.28 t/s (×4.4) | 4.71 t/s (=) | 4756 MB (−118) | keep for VQA; image encode also drops 4.36 → 2.84 s; `bench/runs/20261018-073110-opt1-cublas-image-q4km` |
| O1-text | 2026-10-18 | same build | B1 | 2.46 s (+124%) | 8.89 t/s (×0.39) | 4.74 t/s (=) | 4214 MB (−254) | regression for short prompts; `bench/runs/20261018-072640-opt1-cublas-text-q4km` |
| O2-image | 2026-10-18 | patch `0004`: runtime `GGML_CUDA_MMQ_MAX_BATCH=32` (dense matmuls: MMVQ ≤ 8 tokens, MMQ 9-32, cuBLAS FP16 > 32); reference build `build-cuda` | B2 | **10.77 s** (−74%, ×3.9; −7% vs O1) | 36.58 t/s (×4.8) | 4.71 t/s (=) | 4749 MB (−125) | **keep**; image encode 2.79 s; `bench/runs/20261018-103651-opt2-mmq32-image-q4km` |
| O2-text | 2026-10-18 | same | B1 | **1.10 s** (= B1) | 22.61 t/s (=) | 4.73 t/s (=) | 4265 MB (−203) | **keep**: O1 regression gone; `bench/runs/20261018-103229-opt2-mmq32-text-q4km` |

### O1 analysis

`llama-bench` with the O1 build (same conditions, 3 reps, FA on): pp16 = 9.07 t/s,
pp64 = 37.6 t/s, pp256 = 81.6 t/s, pp512 = 90.3 t/s, tg32 = 4.76 t/s.
The reference (MMQ) gave pp16 = 29.3, pp64 = 9.8, pp256 = 9.9.

- cuBLAS behaves like a fixed cost of ~1.6 s per forward pass (each quantized weight
  matrix is dequantized to FP16 before the GEMM), plus ~8 ms per token. MMQ has no
  fixed cost but costs ~0.1 s per token above 16 tokens. Crossover: about 16-24 tokens
  per batch.
- In B2/O1-image, the prompt is processed in 3 chunks (text before the image, 263
  image tokens, text after). Each short text chunk pays the cuBLAS fixed cost, which is
  why O1-image prefill (33 t/s) is far below pp256 (82 t/s).
- Decode (1 token per step) still uses MMVQ and is unchanged.
- Candidate O2: choose per batch, MMQ for small batches and cuBLAS above a threshold
  (start at 32, sweep 16-64), as a runtime threshold in `ggml_cuda_should_use_mmq()`
  for GPUs without tensor cores. Expected: text TTFT back to ~1.1 s, and image TTFT
  below O1 because the two short text chunks avoid the fixed cost.

### O2 analysis

Threshold sweep, `llama-bench` on the O2 build (same conditions, 2 reps, FA on, t/s).
Each value is only an environment variable on the same binary:

| `GGML_CUDA_MMQ_MAX_BATCH` | pp12 | pp16 | pp24 | pp32 | pp48 | pp64 | pp256 |
|---|---|---|---|---|---|---|---|
| unset (= upstream = B) | 22.1 | 29.3 | 27.0 | 19.2 | 13.0 | 10.1 | 10.0 |
| 0 (= O1) | 7.0 | 9.1 | 15.1 | 19.9 | 28.9 | 37.8 | 81.7 |
| 16 | 22.3 | 29.4 | 15.1 | 19.9 | 28.8 | 37.7 | 81.8 |
| 24 | 22.2 | 29.3 | 27.0 | 19.8 | 28.9 | 37.4 | 81.9 |
| **32** | 22.3 | 29.5 | 27.2 | 19.7 | 28.8 | 37.7 | 81.8 |
| 48 | 22.2 | 29.3 | 27.1 | 19.7 | 13.0 | 37.7 | 82.1 |
| 64 | 22.2 | 29.3 | 27.2 | 19.1 | 12.8 | 10.1 | 81.8 |

- "unset" and "0" reproduce B and O1 exactly, so the patch only changes the kernel
  choice.
- MMQ and cuBLAS cross over at about 30 tokens (pp32: 19.2 vs 19.9 t/s). With 32, every
  size is within ~3% of the better path.
- The setting is per process. Any lumen command that runs inference must export
  `GGML_CUDA_MMQ_MAX_BATCH=32`. The value is GPU-specific: GPUs with tensor cores
  take a different upstream path, so the value must come from a parameter, not be
  hardcoded.

### O3: breakdown of the VQA prefill (2026-10-18), no code change

The "missing ~4 s" of O2-image prefill (v1: 7.76 s for 284 tokens, against ~3.1 s for
pp256) turned out to be mostly a measurement artifact: the encode inside libllama's
prompt-eval window (see the correction above). Breakdown of the O2-image TTFT, single
runs with `CUDA_LAUNCH_BLOCKING=1` so that per-chunk timings are synchronous:

| Part | Time | Share of 7.8 s |
|---|---|---|
| image chunk prefill (263 tokens, cuBLAS) | ~3.9 s | ~50% |
| vision encode (mmproj) | 2.8 s | ~36% |
| text chunks prefill (21 tokens in 2 chunks, MMVQ/MMQ) | ~1.0 s | ~13% |
| JPEG load, preprocessing, sampling | ~0.1 s | ~1% |

- The image chunk (3.9 s) is a bit slower than pp256 in `llama-bench` (3.1 s). It is the
  first cuBLAS use in the process, and the chunk is larger (263 tokens). Not
  investigated further.
- Flash attention on/off changes nothing measurable (prompt span 7.7 vs 8.2 s).
- Text after the image: 8 vs 21 tokens changes the text-chunk time by ~0.5 s, so ~40 ms
  per token, consistent with MMQ at that size.
- Next levers: the image token count (`--image-max-tokens`, input resolution) cuts both
  encode and image prefill. The `IM2COL` op in the vision encoder runs on the CPU
  (CUDA rejects it because its input is not contiguous; warm-up warning).

## O4: number of image tokens (2026-10-19)

New reference test image `bench/images/test-720p.jpg` (sha256 `7615ada2ef32…`,
captured 2026-10-19 with the room lit and the camera privacy control off, kept by the
user as the reference). The earlier dark image is kept as
`test-720p-dark-20261017.jpg`; it was most likely dark because the camera privacy
mode was on, not because the room was unlit (privacy read 1 on 2026-10-18). Same
conditions as v2, O2 setting (`GGML_CUDA_MMQ_MAX_BATCH=32`), only `--image-max-tokens`
varies.

| `--image-max-tokens` | Image tokens | TTFT (wall) | Image encode | Prefill (prompt tokens) | Decode | RAM peak | Logs (`bench/runs/`) |
|---|---|---|---|---|---|---|---|
| 64 | 65 | **4.56 s** | 1.34 s | 3.16 s (86) | 4.74 t/s | 4798 MB | `20261019-084029-o4-mmq32-img64-q4km` |
| 128 | 127 | **5.21 s** | 1.77 s | 3.38 s (148) | 4.74 t/s | 4803 MB | `20261019-084451-o4-mmq32-img128-q4km` |
| 256 | 263 | 7.79 s | 2.78 s | 4.94 s (284) | 4.71 t/s | 4823 MB | `20261019-084917-o4-mmq32-img256-q4km` |
| 512 | 495 | 11.58 s | 5.03 s | 6.49 s (516) | 4.67 t/s | 4843 MB | `20261019-085359-o4-mmq32-img512-q4km` |

- 256 with the new image gives 7.79 s against 7.80 s with the dark image (O2-image v2), so
  timing does not depend on image content.
- Prefill has a large fixed part: 3.16 s at 65 image tokens against 4.94 s at 263. The
  image chunk (> 32 tokens) takes cuBLAS, and its ~1.6 s dequantization cost does not
  shrink with fewer tokens. The ~1 s of text chunks stays as well. Below ~128 image
  tokens, cutting tokens buys little time.

Answer quality, one run per setting, 3 questions, no `--ignore-eos`, checked by
hand against the image (living room + kitchen: person with headset at a laptop,
armchair in the foreground, painting, lamp, fridge, built-in oven with drawers, green
fabric on the left). Answers in `bench/quality/20261019-083255-image-tokens/`.

| Tokens | Assessment | Main errors |
|---|---|---|
| 64 | poor | hallucinates a "face mask" (2 of 3 answers), "green tabletop", fridge "far right" |
| 128 | acceptable | headset correct; "microwave oven", fridge position wrong |
| 256 | good, most detail | green robe, lamp on the left, painting; still a "microwave" and a "dishwasher" |
| 512 | good | correct object list (armchair, artwork, fridge, cabinets + oven); "dishwasher" |

All settings get some kitchen layout details wrong (3B model limit). The clear quality
drop is below 128 tokens. Trade-off: 128 gives −33% TTFT vs 256, at some loss of
detail. Choice of the default left to the user.

## O5: weight quantization (2026-10-19)

Same conditions as v2, O2 setting (`GGML_CUDA_MMQ_MAX_BATCH=32`), image mode at
`--image-max-tokens 256` (263 image + 21 text tokens), reference image
`7615ada2ef32…`. Sources: `models/SOURCES.txt`. Q4_K_M, Q5_K_M and Q8_0 are official
`mistralai` files. Q4_0 was made with `llama-quantize … Q4_0` from the official BF16
(output and embedding tensors keep llama-quantize's default higher precision; 1939
MiB, 4.74 BPW). The mmproj variants were made by `scripts/mmproj_requant.py` from the
official BF16 mmproj, using the same tensor policy as ggml-org's Q8_0 (2-D matrices
quantized, norms / patch_embd / img_break in F32). A Q8_0→Q8_0 round trip through the
script is byte-identical.

### Language model (mmproj: ggml-org Q8_0)

| LLM | File | Text TTFT | Text decode | Image TTFT | Image encode | Image prefill | RAM peak (image) | Logs (`bench/runs/`) |
|---|---|---|---|---|---|---|---|---|
| **Q4_0** | 1.94 GiB | **0.66 s** | **6.19 t/s** | 7.30 s | 2.69 s | 4.50 s | **4668 MB** | `…100607-quant-llm-Q4_0-text`, `…100940-quant-llm-Q4_0-image` |
| Q4_K_M (O2) | 2.00 GiB | 0.89 s | 4.74 t/s | 7.79 s | 2.78 s | 4.94 s | 4823 MB | `…125650-v2-O2-text-q4km`, `…084917-o4-mmq32-img256-q4km` |
| Q5_K_M | 2.30 GiB | 0.73 s | 4.69 t/s | 7.50 s | 2.91 s | 4.52 s | 5070 MB | `…101402-quant-llm-Q5_K_M-text`, `…101802-quant-llm-Q5_K_M-image` |
| Q8_0 | 3.40 GiB | 0.64 s | 4.41 t/s | **7.07 s** | 2.77 s | 4.22 s | **6274 MB** | `…102250-quant-llm-Q8_0-text`, `…102718-quant-llm-Q8_0-image` |

- **Decode is not bandwidth-bound for the K-quants on sm_62.** Q4_0 decodes 31% faster
  than Q4_K_M at almost the same size (6.19 vs 4.74 t/s), and Q8_0, with 1.7× the bytes,
  is only 7% slower than Q4_K_M. The more complex K-quant dequantization costs compute
  in MMVQ on this GPU.
- Short-batch prefill (text, 20 tokens, MMQ) is also slower for the K-quants: 0.89 s
  for Q4_K_M against 0.64-0.66 s for Q8_0 / Q4_0.
- Q8_0 has the best image TTFT (cheaper dequantization before the cuBLAS GEMM), but
  peaks at 6.27 GB of the 7.86 GB shared memory and decodes slowest.

### Vision encoder (LLM: Q4_K_M)

| mmproj | File | Image TTFT | Image encode | RAM peak | Logs (`bench/runs/`) |
|---|---|---|---|---|---|
| ggml-org Q8_0 (reference) | 428 MiB | 7.79 s | 2.78 s | 4823 MB | `…084917-o4-mmq32-img256-q4km` |
| F16 | 803 MiB | 7.85 s | 2.79 s | 5074 MB | `…103236-quant-mmproj-F16-image` |
| Q8_0 (lumen, from BF16) | 428 MiB | 7.79 s | 2.79 s | 4780 MB | `…103735-quant-mmproj-Q8_0-image` |
| Q5_0 | 278 MiB | 7.86 s | 2.87 s | 4754 MB | `…104220-quant-mmproj-Q5_0-image` |
| Q4_0 | 228 MiB | 7.82 s | 2.83 s | 4773 MB | `…104701-quant-mmproj-Q4_0-image` |

- **The encode time does not depend on the weight type** (2.78-2.87 s from F16 to Q4_0).
  The vision encoder is not bound by weight bandwidth or weight dequantization at this
  size. Its cost is elsewhere: attention over ~1000 patches, the `IM2COL` CPU
  fallback, launch overheads. To profile in the next step.

### Quality (3 questions, one run each, `bench/quality/20261019-105141-quant/`)

- LLM variants: answers are near-identical in content. All four find the person with
  headphones at a laptop, the armchair, the fridge and the artwork. The kitchen
  appliance answer has errors at every level (a "dishwasher" for the built-in oven;
  Q4_K_M / Q5_K_M / Q8_0 also invent a "microwave"; Q4_0 does not in this sample). No
  quality loss from Q4_0 is visible on this small sample. 3 questions are not enough
  to rank the variants; a larger question set is needed for a real comparison.
- mmproj: F16 and Q8_0 give the same answers. Q5_0 mistakes the painting for a
  "clock"; Q4_0 misses the oven entirely. Small degradation and no speed gain, so Q8_0
  is the sensible choice.

**Recommendation:** LLM **Q4_0** (fastest decode and short prefill, lowest RAM, no
visible quality loss) with mmproj **Q8_0**.

## O6: quantization quality, measured (KL divergence vs BF16, 2026-10-23)

The O5 quality check (3 VQA questions) was far too small to rank quantizations.
This is the proper measurement: `llama-perplexity --kl-divergence` against the official
**BF16** model, on the **full wikitext-2 test set** (`wiki.test.raw`, context 512),
computed on a workstation with a recent NVIDIA GPU (CUDA 13.0). Same llama.cpp commit `ba3c05f`
+ patches 0001-0004, built there by the unchanged `scripts/build_llama.sh`, which
detected the GPU architecture and gcc 13 on its own. Quality depends on the GGUF file, not on the
board; speed stays measured on the Jetson. Identical files: SHA-256 checked on both
machines. Logs stay on the workstation (not versioned).
imatrix: `llama-imatrix` on the BF16 model, `wiki.train.raw` (no overlap with the test
set), 200 chunks × 512 tokens.

BF16 perplexity: **8.699 ± 0.056**.

| Model | Mean KLD ↓ | Median KLD | 99% KLD | PPL vs BF16 | Same top token | RMS Δp |
|---|---|---|---|---|---|---|
| Q8_0 | 0.00075 | 0.00041 | 0.0061 | −0.04% | 98.6% | 0.73% |
| Q5_K_M | 0.0089 | 0.0051 | 0.071 | +0.52% | 95.2% | 2.48% |
| **Q4_K_M** (official) | **0.0260** | 0.0150 | 0.207 | **+1.82%** | **92.1%** | 4.25% |
| **Q4_0** (plain rounding) | **0.0620** | 0.0352 | 0.520 | **+5.47%** | **88.3%** | 6.68% |
| **Q4_0 + imatrix (BF16)** | **0.0395** | 0.0229 | 0.319 | **+3.19%** | **90.3%** | 5.33% |

- **Correction of O5:** Q4_0 does lose quality. Its mean KLD is 2.4× that of Q4_K_M, and it
  agrees with BF16 on the top token 88.3% of the time against 92.1%. The 3-question check
  could not show this.
- The imatrix cuts the Q4_0 KLD by 36% (0.062 → 0.039), for the same format and size
  (1944 MiB, 4.76 BPW), so presumably the same speed. It still does not reach Q4_K_M.
- None of the official files carries `quantize.imatrix.*` metadata, so they appear to be
  plain-rounding quantizations as well.
- Next: other fast 4-bit formats with imatrix (IQ4_NL, Q4_1), and Q4_K_M with imatrix.
  KLD on the workstation, then speed on the Jetson for the best candidates.

### O6 continued: imatrix 4-bit candidates (2026-10-23)

All quantized on the workstation from the official BF16 with the BF16 imatrix
(`llama-quantize --imatrix imatrix-bf16-wikitrain-c512-n200.gguf … <type>`), copied to
the Jetson (SHA-256 checked, `models/SOURCES.txt`). KLD on the workstation (vs BF16, full
wikitext-2 test). Speed on the Jetson (O2 setting, 256 image tokens, median of 5).
Workstation logs are not versioned. Jetson logs:
`bench/runs/*-speed-<type>-imatbf16-{text,image}`.

| Model | Size | Mean KLD ↓ | Same top token | PPL vs BF16 | Decode | Text TTFT | Image TTFT | RAM peak (image) |
|---|---|---|---|---|---|---|---|---|
| Q4_0 (no imatrix) | 1939 MiB | 0.0620 | 88.3% | +5.47% | 6.19 t/s | 0.66 s | 7.30 s | 4668 MB |
| Q4_0 + imatrix | 1944 MiB | 0.0395 | 90.3% | +3.19% | **6.19 t/s** | 0.66 s | 7.28 s | 4670 MB |
| **IQ4_NL + imatrix** | 1949 MiB | **0.0295** | 91.7% | +2.24% | **5.75 t/s** | **0.66 s** | 7.46 s | 4670 MB |
| Q4_1 + imatrix | 2119 MiB | 0.0287 | 91.8% | +2.14% | 5.49 t/s | 0.67 s | 7.27 s | 4843 MB |
| Q4_K_S + imatrix | 1951 MiB | 0.0287 | 91.7% | +2.53% | not measured (K-quant, expected ≈ Q4_K_M speed) | | | |
| Q4_K_M (official, no imatrix) | 2048 MiB | 0.0260 | 92.1% | +1.82% | 4.74 t/s | 0.89 s | 7.79 s | 4823 MB |
| Q4_K_M + imatrix | 2040 MiB | **0.0239** | **92.3%** | +2.09% | 4.73 t/s | 0.90 s | 7.78 s | 4771 MB |

Cross-check on the Jetson (reference Q8_0 instead of BF16, first 60 chunks, run with
the CUDA 10.2 port and `GGML_CUDA_MMQ_MAX_BATCH=32`, logs
`bench/quality/20261023-063852-kld/`): Q4_0 0.066, Q4_0 + imatrix (from Q8_0) 0.044,
Q4_K_M 0.030, Q5_K_M 0.0128. Same ordering and magnitude as on the workstation. Values are
slightly higher, as expected with a Q8_0 reference and a smaller sample. A numerical bug
in the port would show up as much larger divergences. This is not a formal proof but a
useful consistency check.

- Speed follows the format, not the imatrix: Q4_0 with and without imatrix decode at
  the same 6.19 t/s, and Q4_K_M with and without at 4.73-4.74 t/s.
- **Recommended default: IQ4_NL + imatrix.** 25% lower KLD than Q4_0 + imatrix for 7% less
  decode speed. Near Q4_K_M quality (KLD 0.0295 vs 0.0260), with 21% faster decode and
  0.23 s lower text TTFT.
- Highest quality at 4 bits: Q4_K_M + imatrix (KLD 0.0239), at Q4_K_M speed.
