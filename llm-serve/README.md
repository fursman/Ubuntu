# llm-serve -- Qwen3.8-27B on one 24GB GPU

Opt-in. `setup.sh` never touches this. It builds llama.cpp from source with CUDA,
downloads Unsloth's `UD-Q4_K_XL` GGUF (~17.6GB), and installs a user systemd
unit serving an OpenAI-compatible API plus a web UI on port 8081.

```
./llm-serve/install.sh
```

## Why this stack, and not vLLM

Every decision below was measured on an RTX 4090 (Ada, 24GB, compute 8.9).

| candidate | verdict |
|---|---|
| vLLM + NVFP4 (its own 24GB recipe) | **Blackwell-only.** Ada has no NVFP4 kernels. |
| vLLM + official FP8 | ~28GB of weights. Does not fit 24GB. |
| vLLM + community AWQ-4bit | 27.8GB on disk (keeps the 48 Gated-DeltaNet layers in BF16) and its own recipe uses `--tensor-parallel-size 2`. Does not fit one card. |
| **llama.cpp + MTP draft head** | Fits, and the model ships its own speculative-decoding head. |

vLLM becomes the answer the day a second 24GB card arrives. Until then it is
the wrong tool for a single Ada GPU with this model.

## The numbers

| | tok/s |
|---|---|
| decode, no speculation (`llama-bench` tg256) | 47.8 |
| **decode with MTP** (real 600-token generation) | **70.0** |
| prompt processing (pp512) | 2,957 |
| 65K-token prompt prefill | ~2,090 |

MTP acceptance ~0.52 on prose, ~0.84 on agent-style output. The gain scales
with output length; very short replies benefit less.

## Context and KV cache

Qwen3.8-27B is a hybrid: 48 of 64 layers are Gated DeltaNet (fixed-size state),
only 16 hold a real KV cache. That makes long context unusually cheap, but the
**MTP draft head needs its own context buffers**, so the native 256K does not
fit alongside it on 24GB:

| context (q4_0 KV, MTP on) | fits? |
|---|---|
| 262144 | no -- `failed to create MTP context` |
| 229376 | no |
| **196608** | **yes** (22.7GB) |

**q4_0 vs q8_0 KV was A/B'd** on the same 65K-token needle prompt (fact at 40%
depth, temperature 0): both recalled the exact string, prefill 2097 vs 2083
tok/s, decode 71.0 vs 70.0. q4 costs nothing measurable and buys 50% more
context, so it is the default. Caveat: a single needle rules out gross recall
loss, not subtle long-context reasoning degradation.

## Things that will bite you

- **No Linux CUDA prebuilt exists** for llama.cpp; the nightlies ship CUDA only
  for Windows. Hence the build. Ubuntu's CUDA 12.4 `nvcc` refuses gcc 15 --
  `gcc-13` is installed purely as the CUDA host compiler.
- **Build for every GPU's compute capability.** A build with only `sm_89` dies
  with `ggml-cuda.cu: CUDA error` the moment it touches a Volta card. The
  installer reads the capabilities from `nvidia-smi`.
- **The model ignores `/no_think`** and reasons anyway. Budget for it in
  `max_tokens` (40 tokens produced an *empty* answer -- the whole budget went to
  the `<think>` block) and read `reasoning_content` separately from `content`.
- **`curl /` returns HTTP 415 "gzip is not supported"** -- the embedded web UI is
  stored gzipped. Browsers are fine; use `curl --compressed`.
- **Prefix cache**: a repeated identical prompt returns in ~2s vs ~32s uncached.
  Compare prefill tok/s across configs, not wall time.
- **Spec decode is single-stream.** `--parallel 1` on purpose; more slots erase
  the MTP gain.
- **A composited desktop on the same GPU silently halves throughput.** Serve
  from a headless or iGPU-driven session.

## Agent mode (optional, security-sensitive)

llama-server can expose `read_file`, `write_file`, `edit_file`,
`exec_shell_command`, `file_glob_search`, `grep_search` and `get_info` to the
model. They are driven by the **web UI's** tool loop (a bare `/v1/chat`
request does not get them) and run **unsandboxed as your user**. If you enable
`--agent`, also set `--api-key-file` and pin `--cors-origins` to the UI's
origin -- otherwise anyone on the LAN can read, write and execute on the box.
A fresh agent's first move is typically `grep -ri` across your entire home
directory, including 17GB of model weights; tell it not to in the system prompt.
