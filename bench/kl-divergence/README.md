# Quality measurement (KL divergence)

These scripts measure how far each quantized model is from the original BF16 model.
For every token of the wikitext-2 test set, they compare the full next-token
distribution of the quantized model with that of the BF16 model (`llama-perplexity
--kl-divergence`). Results are summarized in [`../results.md`](../results.md), section O6.

They need a GPU that can hold the BF16 model (about 7 GB) and a recent CUDA toolkit,
so they do not run on the Jetson TX2. The published numbers were produced on an NVIDIA
workstation with a recent NVIDIA GPU (CUDA 13.0), with the same llama.cpp commit and patches, built by the
unchanged `scripts/build_llama.sh`. Quality is a property of the GGUF file, so it does
not depend on the machine that measures it; speed is measured on the Jetson.

Run from anywhere, in this order:

| Script | What it does |
|---|---|
| `fetch_models.sh` | downloads the official GGUF files and wikitext-2 into `models/` and `bench/data/`, checking SHA-256 |
| `kld_series_bf16.sh` | BF16 reference on the full test set, importance matrix (imatrix) on the train split, Q4_0 + imatrix, then KL divergence of Q8_0, Q5_K_M, Q4_K_M, Q4_0, Q4_0 + imatrix |
| `kld_candidates.sh` | quantizes IQ4_NL, Q4_1, Q4_K_S and Q4_K_M with the same imatrix and measures their KL divergence |

The reference logits file is large (tens of GB for the full test set). Logs go to
`bench/quality/` and are not versioned.
