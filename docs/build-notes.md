# llama.cpp build notes (phase 1)

Board values cited here come from `docs/hardware.md`.

## Source

| Item | Value |
|---|---|
| Repository | `https://github.com/ggml-org/llama.cpp` (shallow clone, `--depth 1`) |
| Location | `third_party/llama.cpp` |
| Commit | `ba3c05f71da85cd0439e84ba42b0478b24d5db16` (2026-10-15) |
| Ministral 3 support | text arch `LLM_ARCH_MISTRAL3` (`src/models/mistral3.cpp`), vision projector `PROJECTOR_TYPE_PIXTRAL` (`tools/mtmd/models/pixtral.cpp`) |

## Build script

`scripts/build_llama.sh`, which runs on the board. Every board value is a parameter
or is discovered at build time: the CUDA arch is read from the GPU by a small CUDA
program, and the CUDA C++ standard is derived from the nvcc version. The script
applies the patches in `third_party/patches/llama.cpp/` (each one only once) and
logs RAM with tegrastats into the build directory.

Fixed configure options and why:

| Option | Reason |
|---|---|
| `CC/CXX = gcc-8/g++-8` | gcc 7.5 has incomplete C++17 support; llama.cpp requires C++17 for host code |
| `-DLLAMA_OPENSSL=OFF` | `libssl-dev` not installed; HTTPS model download is not needed (models are fetched separately) |
| `-DLLAMA_USE_PREBUILT_UI=OFF` | otherwise configure downloads the server web UI from Hugging Face; the build must not need the network |
| `-DLLAMA_BUILD_TESTS=OFF` | build time |
| `-DCMAKE_CXX_STANDARD_LIBRARIES=-lstdc++fs` (if g++ < 9) | GCC 8 ships `std::filesystem` in a separate library; without it, linking `libggml.so` fails with undefined `std::filesystem::*` |
| `-DCMAKE_CUDA_STANDARD=14` (if nvcc < 11) | llama.cpp's global `CMAKE_CXX_STANDARD 17` makes CMake require the "CUDA17" dialect for `ggml-cuda`, which nvcc 10.2 does not support (configure error) |
| `TARGETS` = `llama-mtmd-cli llama-completion llama-bench llama-quantize` | `llama-server`, and `llama-cli`, which is built on the server code, do not compile with GCC 8 (see below) |

## Patches (`third_party/patches/llama.cpp/`)

| Patch | Problem | Fix |
|---|---|---|
| `0001-gcc8-neon-x4-loads.patch` | GCC 8's `arm_neon.h` has no `vld1q_u8_x4` / `vld1q_s8_x4`; ggml-cpu uses them on aarch64 (`ggml-cpu-impl.h`, `arch/arm/quants.c`, `arch/arm/repack.cpp`) | define both from four `vld1q_*` loads, only for GCC < 9 on aarch64 |
| `0002-missing-iomanip-includes.patch` | `std::setw` used without `#include <iomanip>` (`tools/server/server-context.cpp`, `common/download.cpp`); newer libstdc++ includes it transitively | add the include |
| `0003-cuda-10.2-sm62-port.patch` | ggml-cuda needs CUDA ≥ 11 and C++17, and two kernels exceed sm_62's 32K registers per block | see "CUDA 10.2 / sm_62 port" below (10 files, +216/−37, 2 new headers) |
| `0004-cuda-runtime-mmq-max-batch.patch` | on sm_62 the MMQ kernels scale poorly with the batch size (prefill ~10 t/s above 32 tokens), see `bench/results.md` B/O1/O2 | optional runtime threshold `GGML_CUDA_MMQ_MAX_BATCH` in `ggml_cuda_should_use_mmq()`: dense matmuls with more tokens than the threshold use cuBLAS; unset keeps upstream behaviour. lumen uses 32 on the TX2 (an optimization, not a build fix) |

The patch set is checked against a pristine worktree of the same commit:
`0001`-`0004` apply cleanly (re-checked 2026-10-18 after adding `0004`), and pristine + patches is identical to the working tree
(`diff -r`, 0 differences, 2026-10-17).

## Results

| Backend | Status | Notes |
|---|---|---|
| CPU | **OK** (2026-10-15) | first full compile 10 min 33 s with `-j4`; build RAM peak 2711 MB (tegrastats) |
| CUDA | **OK** (2026-10-17) | after patch `0003`; the full build of the lumen targets on top of a built ggml-cuda took 11 min; ggml-cuda alone ≈ 25 min with `-j4`; build RAM peak 2367 MB during the first pass (tegrastats) |

`llama-bench --list-devices` with the CUDA build:
`CUDA0: NVIDIA Tegra X2 (7859 MiB, 6132 MiB free)`, compute capability 6.2, VMM: no.

## CUDA 10.2 / sm_62 port (patch 0003)

Every change is guarded so that builds with CUDA ≥ 11 (and HIP/MUSA) keep upstream
behaviour: `CUDART_VERSION` checks for API gaps, `__cplusplus` checks for C++17.

| Problem (as reported by nvcc/ptxas/runtime) | Change |
|---|---|
| `cuda_bf16.h: No such file or directory` | new `vendors/cuda_bf16_compat.h`, included instead when `CUDART_VERSION < 11000`: `__nv_bfloat16`/`__nv_bfloat162` with the same 16-bit storage, round-to-nearest-even conversion (NaN preserved), implicit float conversion, and the conversion intrinsics ggml-cuda uses. sm_62 has no bf16 hardware; CUDA 11 also emulates it through float there |
| `CUDA_R_16BF` not in cuBLAS 10.2; `static inline const` members (inline variables) in `batched_mul_mat_traits` | traits: enum members → `static constexpr`, alpha/beta moved into `get_alpha()`/`get_beta()`; BF16 traits compiled only for CUDA ≥ 11; on CUDA < 11 a BF16 cuBLAS request runs as F32 (the existing path for GPUs without fast BF16) |
| `std::is_same_v` undeclared (66 uses) | new `vendors/cuda_cxx17_compat.h`: `std::is_same_v` as a C++14 variable template when `__cplusplus < 201703L` |
| fold expression + inline variables in `is_any` / `ggml_cuda_dependent_false_v` (`common.cuh`) | C++14 recursive trait under `#if __cplusplus < 201703L` |
| structured bindings (8 loops in `common.cuh`, `ggml-cuda.cu`; 1 in `allreduce.cu`) | `.first` / `.second` (all bound objects are `std::pair` or a two-field struct) |
| fold expressions in `softmax.cu` (`||`) and `binbcast.cu` (comma, ×2) | pack expansion into an `int[]` initializer list: left-to-right order, and the `||` version keeps short-circuit |
| `if (init; cond)` in `ggml-cuda.cu` | declaration moved before the `if` |
| `cooperative_groups/reduce.h` missing | include only for CUDA ≥ 11 (only `this_grid()` / `sync()` are used) |
| `cudaStreamWaitEvent(stream, event)`: too few arguments | 2-argument overload for CUDA < 11 (flags = 0) |
| `__builtin_assume` undefined | no-op macro for CUDA < 11.2 (optimization hint only) |
| ptxas: `Unresolved extern function 'cudaCGGetIntrinsicHandle'` (grid sync without `-rdc` before CUDA 11) | `GGML_CUDA_NO_COOPERATIVE_SOFTMAX` on CUDA < 11: the optional cooperative softmax kernel (rows > 8192 columns without mask/sinks) is compiled out; such rows take the existing non-cooperative fallback |
| runtime: `too many resources requested for launch` | `__launch_bounds__(block_size)` on `rms_norm_f32` and `rms_norm_mul_rope_f32`; see below |

**Registers per block on sm_62.** The TX2 has 32768 registers per block (`deviceQuery`,
`cudaDevAttrMaxRegistersPerBlock`), half of desktop Pascal. The fused
`rms_norm_f32<1024, true, ...>` variants used 38-39 registers and
`rms_norm_mul_rope_f32<1024, true, ...>` 37-38 (from `cuobjdump --dump-resource-usage`).
At 1024 threads that is ~39-40K registers, so the launch fails. A probe kernel showed
that ptxas does know the sm_62 per-block limit: with `__launch_bounds__(1024)` it
caps at 32 registers, and the launch succeeds. Without it, the same kernel had 47
registers and `maxThreadsPerBlock` 640. After the fix, the 1024-thread variants use
31-32 registers with 0 bytes of local memory (no spill).
Audit: every kernel family above 32 registers was checked. The heavy kernels
(`flash_attn_tile`, `flash_attn_ext_vec`, `mul_mat_q`, `mul_mat_vec_q`) already declare
launch bounds. All other 1024-thread launches (norm, group/l2 norm, softmax, argsort,
cumsum) are at or below 32 registers. 512-thread launches (sum_rows, mean) are at or
below 29. These kernels were checked by launch site and found to launch with 256
threads or fewer at 74 registers or fewer: `get_rows`, `im2col`, `cpy`, `pad`,
`upscale`, `conv2d`, `conv2d_dw`, `mul_mat_vec_f`. **Not audited:** kernels that only
serve other model families (`rwkv_wkv*`, `gated_linear_attn`, `gated_delta_net`,
`ssm_*`, `conv3d*`, `lightning_indexer*`, `dsv4_*`, up to 189 registers). Ministral 3
does not use them, but other models could hit the same launch failure on sm_62.

## Known blockers

**`llama-server` / `llama-cli` with GCC 8.** `tools/server/server-schema.cpp` fails with
"class template argument deduction failed" (`field_num()`). Not needed for phases 2-3,
since `llama-mtmd-cli` covers image + question. To revisit only if phase 4 needs the
server.

## Background: what nvcc 10.2 accepts

What nvcc 10.2 accepts in `-std=c++14` mode (probe on the board, 2026-10-15):

| C++17 construct | nvcc 10.2 `-std=c++14` |
|---|---|
| `if constexpr` (host and device) | accepted, with warning "constexpr if statements are a C++17 feature" |
| `[[maybe_unused]]` | accepted |
| `std::is_same_v` and other `_v` traits | **error** (not declared) |
| `inline` variables | **error** |
| fold expressions | **error** |
| structured bindings | **error** |
| `constexpr` lambdas | **error** |
| nested namespaces `a::b` | **error** (not used in ggml-cuda) |
| `template<auto>` | **error** (not used in ggml-cuda) |

Initial estimate of the port before starting (grep over `ggml/src/ggml-cuda`, 281
`.cu`/`.cuh` files). The compiler later showed that only part of this needed changes,
see the patch 0003 table:

| Construct | Lines | Files |
|---|---|---|
| `if constexpr` | 316 | 32 (OK as is) |
| `std::*_v<` traits | 58 | 8 |
| inline variables | 17 | 2 |
| structured bindings | 9 | 3 |
| fold expressions | 1 | 1 |
| bf16 (`nv_bfloat16`, `__nv_bfloat16`, ...) | 114 | 21 |


## CPU validation of the model (2026-10-16)

This is not a benchmark: single runs, `jetson_clocks` not applied, desktop running.
It only shows that the CPU build runs the model end to end. The benchmark protocol
(5 runs, median) applies from phase 2 on.

Models (`models/SOURCES.txt`, SHA-256 checked against the Hugging Face API):
`mistralai/Ministral-3-3B-Instruct-2512-GGUF` → `Ministral-3-3B-Instruct-2512-Q4_K_M.gguf`
(2.15 GB), `ggml-org/Ministral-3-3B-Instruct-2512-GGUF` →
`mmproj-Ministral-3-3B-Instruct-2512-Q8_0.gguf` (0.45 GB).

| Test | Command (abridged) | Result |
|---|---|---|
| Text only | `llama-completion -t 4 -c 2048 -n 64 --temp 0 -no-cnv -p "[INST]...[/INST]"` | correct answer; load 2.1 s; prefill 16 tokens at 2.92 t/s; decode 40 tokens at 1.79 t/s |
| Image + question | `llama-mtmd-cli -t 4 -c 4096 -n 96 --temp 0 --image-max-tokens 256 --image <720p camera JPEG>` | coherent scene description; image encoding 48.7 s; wall time 182.8 s in total |

- RAM (tegrastats) peaked at 1618 MB for text only and 2383 MB with the image,
  against about 1378 MB before the run.
- **Caveat:** the weights are mmaped, so tegrastats RAM undercounts the models
  memory. Benchmarks need `--no-mmap` or process RSS to get a real peak-RAM figure.
- CPU temperature (BCPU) peaked at 33.0 °C.
- The 720p camera frame was grabbed with
  `v4l2src num-buffers=30 ! image/jpeg,width=1280,height=720 ! multifilesink max-files=1`
  into `/tmp` and deleted afterwards.

## GPU validation of the model (2026-10-17)

Same conditions as the CPU validation (single runs, `jetson_clocks` not applied,
desktop running, same prompts, `--temp 0`), with `-ngl 99` (all layers on the GPU,
mmproj offloaded by default).

| Test | CPU build | CUDA build |
|---|---|---|
| Text: output | (reference) | **identical, character for character** |
| Text: prefill (16 tokens) | 2.92 t/s | 29.04 t/s |
| Text: decode (40 tokens) | 1.79 t/s | 4.67 t/s |
| Text: load time | 2.1 s | 4.1 s |
| Image (720p, `--image-max-tokens 256`): encoding | 48.7 s | 4.67 s |
| Image: wall time incl. load | 182.8 s | 70.9 s |
| RAM peak, tegrastats (text / image) | 1618 / 2383 MB | 4474 / 5440 MB |
| GPU load (GR3D) peak | — | 99% |
| GPU temperature peak | — | 39.5 °C (text), 41.5 °C (image) |

- The image runs used different camera frames, so their answers are not comparable
  word for word. Both were coherent scene descriptions.
- With CUDA, the model, KV cache and compute buffers are allocated from the shared
  7859 MB. The tegrastats peak (5440 MB with the image) is the figure to watch against
  the memory budget in `docs/hardware.md`.
