#!/usr/bin/env bash
# Serve Qwen3.8-27B on one 24GB NVIDIA GPU with llama.cpp + MTP speculative decoding.
# Opt-in; setup.sh never runs this. Read README.md first.
#
#   ./llm-serve/install.sh            # build, download (~17.6GB), install unit, start
set -euo pipefail

LLAMA_TAG="${LLAMA_TAG:-b10566}"          # first nightly series with MTP (PR #22673)
GGUF_REPO="unsloth/Qwen3.8-27B-GGUF"
GGUF_GLOB="*UD-Q4_K_XL*"
DIR="$(cd "$(dirname "$0")" && pwd)"

info(){ echo -e "\033[0;34m[INFO]\033[0m $1"; }
ok(){   echo -e "\033[0;32m[  OK]\033[0m $1"; }
die(){  echo -e "\033[0;31m[FAIL]\033[0m $1" >&2; exit 1; }

command -v nvidia-smi >/dev/null || die "no NVIDIA driver (nvidia-smi missing)"

# 1. Toolchain. There is NO prebuilt Linux CUDA llama.cpp binary (the nightlies
#    ship cpu/vulkan/sycl for Linux and CUDA only for Windows), so we compile.
#    Ubuntu's nvidia-cuda-toolkit is CUDA 12.4, whose nvcc refuses gcc 15 --
#    gcc-13 is installed purely as the CUDA host compiler.
info "Installing build toolchain (CUDA 12.4 + gcc-13 host compiler)"
sudo apt-get install -y nvidia-cuda-toolkit gcc-13 g++-13 cmake ninja-build libcurl4-openssl-dev
command -v nvcc >/dev/null || die "nvcc not found after install"

# 2. Compute capabilities: every NVIDIA GPU in the box, so a second card (even a
#    Volta) can run the same binary. CUDA 12.4 still supports sm_70.
ARCHS=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | tr -d '.' | sort -u | paste -sd';')
[ -n "$ARCHS" ] || ARCHS=89
info "CUDA architectures: $ARCHS"

# 3. Source, pinned.
if [ ! -d "$HOME/llama.cpp/.git" ]; then
    git clone --depth 1 --branch "$LLAMA_TAG" https://github.com/ggml-org/llama.cpp.git "$HOME/llama.cpp"
fi
cd "$HOME/llama.cpp"
grep -rq 'draft-mtp' common/ || die "this llama.cpp has no MTP support -- need >= b10419"

# 4. Build. GGML_NATIVE tunes CPU code to this host; fine for a machine-local build.
info "Building llama-server (this takes a few minutes)"
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=ON \
      -DCMAKE_CUDA_ARCHITECTURES="$ARCHS" -DCMAKE_CUDA_HOST_COMPILER=g++-13 \
      -DLLAMA_CURL=ON -DGGML_NATIVE=ON >/dev/null
cmake --build build --config Release -j "$(nproc)" --target llama-server llama-cli llama-bench
ok "built $(./build/bin/llama-server --version 2>&1 | head -1)"

# 5. Model. Unsloth's dynamic quant keeps the MTP head (stored Q4_0) -- some
#    community GGUFs strip it, and without it there is no speculative decoding.
#    Full precision KV-wise; the onnx-style int4 tricks do not apply here.
info "Downloading $GGUF_REPO ($GGUF_GLOB, ~17.6GB) -- resumes if interrupted"
command -v uv >/dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
command -v hf >/dev/null || uv tool install -q "huggingface_hub[cli]"
mkdir -p "$HOME/models"
hf download "$GGUF_REPO" --local-dir "$HOME/models/$GGUF_REPO" --include "$GGUF_GLOB"
f=$(ls "$HOME/models/$GGUF_REPO"/*.gguf | head -1)
[ "$(head -c 4 "$f")" = "GGUF" ] || die "downloaded file is not a GGUF"
ok "model: $f"

# 6. Service. Runs as your user; the API is unauthenticated unless you add
#    --api-key-file (see the unit's comments) -- fine on a trusted LAN only.
mkdir -p "$HOME/.config/systemd/user"
install -m 0644 "$DIR/qwen38.service" "$HOME/.config/systemd/user/qwen38.service"
systemctl --user daemon-reload
systemctl --user enable --now qwen38.service
for _ in $(seq 1 60); do
    curl -s -m 2 localhost:8081/health 2>/dev/null | grep -q '"ok"' && break; sleep 3
done
curl -s -m 2 localhost:8081/health | grep -q '"ok"' || die "server did not come up: journalctl --user -u qwen38"
ok "serving: http://$(hostname -I | awk '{print $1}'):8081/v1  (web UI at /)"
echo
echo "Baseline vs MTP on your card:  ./build/bin/llama-bench -m \"$f\" -ngl 999 -fa 1 -n 256"
echo "Then compare against the 'predicted_per_second' timings the server reports per request."
