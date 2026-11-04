# lumen

**On-device visual question answering on an older edge board.** Ask a question about
what a USB camera sees, and a local vision-language model answers. No cloud and no
network round trip.

The point of the project is **inference optimization**. A recent multimodal model,
[Ministral 3 3B Instruct (2512)](https://huggingface.co/mistralai/Ministral-3-3B-Instruct-2512)
from Mistral AI, runs on an **NVIDIA Jetson TX2 NX**. That module has a Pascal GPU,
8 GB of memory shared between CPU and GPU, CUDA 10.2 and passive cooling. Recent
inference stacks no longer support it.

## Results so far

Time to first token (TTFT, wall clock) for a question about a 720p camera frame
(256 image tokens), and for a short text prompt. Median of 5 runs, clocks pinned,
desktop stopped:

| Configuration | Image + question TTFT | Text TTFT | Generation |
|---|---|---|---|
| Baseline: llama.cpp ported to CUDA 10.2, Q4_K_M | 37.5 s | 0.89 s | 4.7 tok/s |
| + batch-size-aware kernel selection (MMQ ↔ cuBLAS FP16) | 7.8 s | 0.89 s | 4.7 tok/s |
| + IQ4_NL weights with an importance matrix | **7.5 s** | **0.66 s** | **5.8 tok/s** |

- **5× faster** on image questions than the first working build (37.5 s → 7.5 s). The kernel
  change only selects a different matmul path; the weight-format change is backed by the
  quality measurement below.
- Quality of each weight format is measured, not eyeballed. KL divergence against the
  original BF16 model on the full wikitext-2 test set: IQ4_NL + imatrix 0.030, the
  official Q4_K_M 0.026, plain Q4_0 0.062.
- With 128 image tokens instead of 256, an image question starts answering in about 5 s
  (measured with Q4_K_M: 5.2 s). Answer quality drops visibly below 128.

Full tables, conditions and the reasoning behind each step:
[`bench/results.md`](bench/results.md).

## What it took

1. **Porting llama.cpp's CUDA backend to CUDA 10.2 and compute capability 6.2.**
   Upstream requires CUDA ≥ 11 and C++17. The port adds a software bf16 type, rewrites
   C++17 constructs that nvcc 10.2 rejects (structured bindings, fold expressions,
   inline variables) in C++14, fills CUDA 10 API gaps, and adds launch bounds so two
   kernels fit the TX2's 32K registers per block. Every change is guarded, so newer
   toolkits keep upstream behaviour. GPU output is identical to the CPU build at
   temperature 0.
2. **Finding the real bottleneck.** Prefill ran at ~10 tok/s regardless of batch size.
   Per-op measurements showed the quantized matmul kernels (MMQ) reaching ~61 GFLOPS on
   this GPU, while dequantize + cuBLAS FP16 scales well but has a fixed cost per
   matmul. A small runtime switch picks the right path per batch size (crossover at
   ~30 tokens).
3. **Measuring correctly.** An early TTFT formula counted the vision encoding twice.
   It was caught, replaced by a wall-clock measurement, and every number was re-run.
   The correction is documented in `bench/results.md`.
4. **Choosing the weight format with data.** Nine quantizations were compared, with KL
   divergence computed on a workstation GPU against the BF16 reference and speed measured on
   the Jetson. On this GPU, dequantization cost matters more than file size, so simple
   block formats (Q4_0, IQ4_NL) beat K-quants on speed.

## Hardware

| | |
|---|---|
| Board | Jetson TX2 NX module (`p3636-0001`) on a third-party carrier |
| CPU / GPU | 4× Cortex-A57 + 2× NVIDIA Denver / 256 CUDA cores, compute capability 6.2 |
| Memory | 8 GB, shared CPU/GPU |
| Software | L4T R32.7.6 (Ubuntu 18.04), CUDA 10.2, gcc 8.4, CMake 3.31 (user-local) |
| Camera | USB UVC camera, 720p MJPEG, decoded by `nvv4l2decoder` |

Every value comes from a command run on the board: [`docs/hardware.md`](docs/hardware.md).

## Repository layout

```
docs/hardware.md        board inventory, each value with the command that produced it
docs/build-notes.md     llama.cpp build and the CUDA 10.2 port, step by step
docs/model-sources.md   where every model file comes from, and its SHA-256 to check it
scripts/build_llama.sh  portable build (CUDA arch and C++ standard detected, patches applied)
scripts/bench_vqa.sh    benchmark protocol: warm-up + N runs, medians, RAM, temperatures
scripts/ttft_wall.py    wall-clock time to first token
scripts/mmproj_requant.py  requantize the vision projector (runs on a dev machine, Python ≥ 3.10)
third_party/patches/    the four llama.cpp patches
bench/results.md        all measurements, with conditions and analysis
bench/*.sh              measurement series on the Jetson (speed)
bench/kl-divergence/    quality measurement vs the BF16 model (needs a recent GPU)
```

Not versioned: model files, camera images, raw run logs, the llama.cpp clone.

## Reproduce

On the Jetson, from the repository root:

```bash
git clone https://github.com/ggml-org/llama.cpp third_party/llama.cpp
git -C third_party/llama.cpp checkout ba3c05f71da85cd0439e84ba42b0478b24d5db16
BACKEND=cuda ./scripts/build_llama.sh          # applies third_party/patches/llama.cpp/*

# models: see docs/model-sources.md for the exact files and SHA-256
export GGML_CUDA_MMQ_MAX_BATCH=32              # TX2 setting from patch 0004
MODE=image MODEL=models/Ministral-3-3B-Instruct-2512-IQ4_NL-imatbf16.gguf \
  ./scripts/bench_vqa.sh
```

The same build script runs unchanged on a workstation with a recent NVIDIA GPU (CUDA 13),
and the
quality series there lives in `bench/kl-divergence/`.

## Status

- [x] Hardware and camera inventory
- [x] llama.cpp on the TX2 GPU (CUDA 10.2 port)
- [x] Baseline benchmarks and protocol
- [x] Kernel selection, weight format and image-token trade-offs
- [ ] Camera capture + question/answer application (`src/`)
- [ ] Vision encoder speed-up (GPU `IM2COL`, then possibly TensorRT)
- [ ] Port to a Jetson Orin (nothing board-specific is hardcoded)

## Credits

- [llama.cpp / ggml](https://github.com/ggml-org/llama.cpp) (MIT), on which all the
  patches are built
- Ministral 3 3B Instruct 2512 by Mistral AI (Apache 2.0)
- wikitext-2 (Salesforce), used for calibration and quality measurement

## License

MIT, see [`LICENSE`](LICENSE). The llama.cpp patches in `third_party/patches/` apply to
llama.cpp, which is itself MIT-licensed. Model weights are not part of this repository
and keep their own license (Apache 2.0 for Ministral 3).
