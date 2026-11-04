# Model files: where they come from and how to check them

The model files are too large for the repository (2 to 7 GB each), so they are not
versioned. This page lists every model file used in [`bench/results.md`](../bench/results.md):

- **where it comes from**: an official download, or a command run in this project;
- **its SHA-256 fingerprint**: a 64-character code computed from the file's content. If
  a single byte changes, the code changes completely. To check a file you have, run
  `sha256sum <file>` and compare the output with the table at the end of this page.

All files belong to the same model, Ministral 3 3B Instruct 2512 by Mistral AI
(Apache 2.0). They differ only in how the numbers are stored (see the format names
below), and the `mmproj` files hold the model's vision part (image encoder + projector).

## 1. Downloaded

Each file was downloaded from Hugging Face, and its SHA-256 was checked against the
value published by Hugging Face for that file.

| File | Size | Source | Role in the project |
|---|---|---|---|
| `Ministral-3-3B-Instruct-2512-BF16.gguf` | 6.4 GiB | [mistralai/Ministral-3-3B-Instruct-2512-GGUF](https://huggingface.co/mistralai/Ministral-3-3B-Instruct-2512-GGUF) | Original weights, 16 bits per weight. Quality reference, and the starting point of every quantization made here. Too large to run on the Jetson GPU. |
| `Ministral-3-3B-Instruct-2512-BF16-mmproj.gguf` | 803 MiB | same | Original vision part. Starting point of the `mmproj-lumen-*` variants. |
| `Ministral-3-3B-Instruct-2512-Q8_0.gguf` | 3.4 GiB | same | 8-bit version, near-lossless. Reference for the KL-divergence cross-check on the Jetson. |
| `Ministral-3-3B-Instruct-2512-Q5_K_M.gguf` | 2.3 GiB | same | 5-bit K-quant, tested for speed and quality. |
| `Ministral-3-3B-Instruct-2512-Q4_K_M.gguf` | 2.0 GiB | same | Official 4-bit version. Baseline of the speed measurements. |
| `mmproj-Ministral-3-3B-Instruct-2512-Q8_0.gguf` | 428 MiB | [ggml-org/Ministral-3-3B-Instruct-2512-GGUF](https://huggingface.co/ggml-org/Ministral-3-3B-Instruct-2512-GGUF) | Vision part in 8 bits, made by the llama.cpp team. **Used in every measurement.** |

The text used for calibration and quality measurement, wikitext-2 (Wikipedia articles,
Salesforce), comes from `https://huggingface.co/datasets/ggml-org/ci/resolve/main/wikitext-2-raw-v1.zip`
(SHA-256 `ef7edb566e3e2b2d31b29c1fdb0c89a4cc683597484c3dc2517919c615435a11`).

## 2. Made in this project

All commands use llama.cpp at commit `ba3c05f` with the patches in
`third_party/patches/llama.cpp/`.

### Calibration data (importance matrices)

An importance matrix (imatrix) records which weights matter most, measured by running
text through the model. `llama-quantize --imatrix` uses it to round more carefully where
it counts.

| File | Size | Made from | Command | Machine | Used for |
|---|---|---|---|---|---|
| `imatrix-bf16-wikitrain-c512-n200.gguf` | 5.7 MiB | BF16 model + wikitext-2 train split | `llama-imatrix -c 512 --chunks 200` | Workstation GPU | All `*-imatbf16` files below |
| `imatrix-q8_0-wikitrain-c512-n100.gguf` | 5.7 MiB | Q8_0 model + wikitext-2 train split | `llama-imatrix -c 512 --chunks 100` | Jetson | Cross-check only (`Q4_0-imat`) |

### Language model, re-quantized from the official BF16

| File | Size | Command | Machine | Status |
|---|---|---|---|---|
| `Ministral-3-3B-Instruct-2512-IQ4_NL-imatbf16.gguf` | 1.9 GiB | `llama-quantize --imatrix <BF16 imatrix> … IQ4_NL` | Workstation GPU | **Recommended default** |
| `Ministral-3-3B-Instruct-2512-Q4_0.gguf` | 1.9 GiB | `llama-quantize … Q4_0` (no calibration) | Jetson | Compared |
| `Ministral-3-3B-Instruct-2512-Q4_0-imatbf16.gguf` | 1.9 GiB | `llama-quantize --imatrix <BF16 imatrix> … Q4_0` | Workstation GPU | Compared |
| `Ministral-3-3B-Instruct-2512-Q4_1-imatbf16.gguf` | 2.1 GiB | `llama-quantize --imatrix <BF16 imatrix> … Q4_1` | Workstation GPU | Compared |
| `Ministral-3-3B-Instruct-2512-Q4_K_S-imatbf16.gguf` | 1.9 GiB | `llama-quantize --imatrix <BF16 imatrix> … Q4_K_S` | Workstation GPU | Quality only |
| `Ministral-3-3B-Instruct-2512-Q4_K_M-imatbf16.gguf` | 2.0 GiB | `llama-quantize --imatrix <BF16 imatrix> … Q4_K_M` | Workstation GPU | Compared |
| `Ministral-3-3B-Instruct-2512-Q4_0-imat.gguf` | 1.9 GiB | `llama-quantize --imatrix <Q8_0 imatrix> … Q4_0` | Jetson | Cross-check only |

Files made on the workstation were copied to the Jetson, and their SHA-256 was compared
on both machines.

### Vision part, re-quantized from the official BF16 mmproj

Made with [`scripts/mmproj_requant.py`](../scripts/mmproj_requant.py) on the development
PC (llama.cpp has no tool for this). Weight matrices take the target format; norms and
the patch-embedding convolution stay in 32-bit floats, the same rule as the ggml-org file.

| File | Size | Format of the weight matrices | Result |
|---|---|---|---|
| `mmproj-lumen-F16.gguf` | 803 MiB | 16-bit float | same speed and answers as Q8_0 |
| `mmproj-lumen-Q8_0.gguf` | 428 MiB | 8 bits | same as the ggml-org file |
| `mmproj-lumen-Q5_0.gguf` | 278 MiB | 5 bits | no faster, slightly worse answers |
| `mmproj-lumen-Q4_0.gguf` | 228 MiB | 4 bits | no faster, slightly worse answers |

## 3. SHA-256 fingerprints

| File | SHA-256 |
|---|---|
| `Ministral-3-3B-Instruct-2512-BF16.gguf` | `17ef932bea952e007f9dad63151da5699132ec513d1033d618df7382e24aa3ee` |
| `Ministral-3-3B-Instruct-2512-BF16-mmproj.gguf` | `70ca26e41ecea9da997e2887462ad68b848fbf64da011ff4107bbe7353519ee0` |
| `Ministral-3-3B-Instruct-2512-Q8_0.gguf` | `8c2b72eb5861304fcfd5e82f1eddd6efa4115737f4239fd216a028a8852413ef` |
| `Ministral-3-3B-Instruct-2512-Q5_K_M.gguf` | `e23dd88b0e0951d3f5784d6d4092210cda2b006b251f33b226b283a6c9d1f6bb` |
| `Ministral-3-3B-Instruct-2512-Q4_K_M.gguf` | `9ed150d4367e68df0ac8e1540f6ddc65b42d0ee26378329d1ecbca60f93fc5f8` |
| `mmproj-Ministral-3-3B-Instruct-2512-Q8_0.gguf` | `57af826536cde496dde1e8343b8e72c89fdbd89084d58e18eb391ef34c39c9f2` |
| `imatrix-bf16-wikitrain-c512-n200.gguf` | `fae4a81f114cf51581509b020d66b1bfe1caaa0c8775c98dbcc77b387ae9a828` |
| `imatrix-q8_0-wikitrain-c512-n100.gguf` | `ccec4c53d763ee9edc55d5102bbef3e607e9183b872a06353a20e3e8ae03e566` |
| `Ministral-3-3B-Instruct-2512-IQ4_NL-imatbf16.gguf` | `93ad8475be278ba6ecba4643694ccddf582a2edb0be99c9b787d40a74f122860` |
| `Ministral-3-3B-Instruct-2512-Q4_0.gguf` | `e78611876bccf3a7d3a3ddcff3265d88e98d5ac3d9902f8959433d1586e15c39` |
| `Ministral-3-3B-Instruct-2512-Q4_0-imatbf16.gguf` | `b6c717300dd32faad6a4d3dd222729f8ef91dcdbc4170997b8196b92d24976bd` |
| `Ministral-3-3B-Instruct-2512-Q4_1-imatbf16.gguf` | `8999734d5704d1291b95fc1bbc6e780bf479b7bf0b159567ce38159391f836ff` |
| `Ministral-3-3B-Instruct-2512-Q4_K_S-imatbf16.gguf` | `975020ab5d7a270c0e696d47c65beeb89f0cc8c46a850b2b387b36d1e4e424cb` |
| `Ministral-3-3B-Instruct-2512-Q4_K_M-imatbf16.gguf` | `7d86bb0a8d356886e11beb8f3e88f2e5dfdd89cce7d7f2ebf8269c501895252c` |
| `Ministral-3-3B-Instruct-2512-Q4_0-imat.gguf` | `4ef7f44d8f32d7f2c623a53c880b6a4ed27560a15a7c5fe283ffc18fb35ae370` |
| `mmproj-lumen-F16.gguf` | `ee7cfc191044959a4913a69e5c6d866297de50b36e350a335824da8ea3f49641` |
| `mmproj-lumen-Q8_0.gguf` | `2250b35a3e1112e34481d142812e21389847d360b8979ac3dde139ff0cd28dff` |
| `mmproj-lumen-Q5_0.gguf` | `a47176d1028a00af0c227b3c31e72694246c5934db66a13672b16bb898e82e62` |
| `mmproj-lumen-Q4_0.gguf` | `8ace180bc08be5a5ae9cd8d5f602a8248ab415b9362f3020ffab54d76c7bfb49` |

Files made in this project can only be reproduced byte for byte with the same llama.cpp
commit, patches and calibration data. A different version may give a slightly
different file with the same quality.
