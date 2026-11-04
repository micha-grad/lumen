#!/usr/bin/env bash
# Build llama.cpp for lumen.
#
# Nothing board-specific is hardcoded: every value is either a parameter
# (environment variable) or discovered on the machine running the build.
#
#   BACKEND=cuda|cpu         backend to build (default: cuda)
#   CUDA_ARCH=<sm>           e.g. 62; default: detected from the GPU
#   CUDA_STD=<14|17>         C++ standard for .cu files; default: 14 if nvcc < 11
#                            (nvcc 10.x has no -std=c++17), otherwise left to llama.cpp
#   CC / CXX                 host compilers (default: gcc-8 / g++-8 if present)
#   CMAKE                    cmake binary (default: PATH, then ~/.local/bin/cmake)
#   JOBS                     parallel build jobs (default: nproc)
#   LLAMA_SRC / BUILD_DIR    source and build directories
#   TARGETS                  build targets (default: the tools lumen uses;
#                            "all" builds everything, including llama-server,
#                            which does not compile with GCC 8)
#   EXTRA_CMAKE_ARGS         appended to the configure line
#   PATCH_DIR                patches applied to LLAMA_SRC before configuring
#                            (default: third_party/patches/llama.cpp)
#
# Logs: $BUILD_DIR/configure.log, $BUILD_DIR/build.log, and a tegrastats RAM log
# in $BUILD_DIR/tegrastats.log (when tegrastats is available).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LLAMA_SRC="${LLAMA_SRC:-$ROOT/third_party/llama.cpp}"
BACKEND="${BACKEND:-cuda}"
BUILD_DIR="${BUILD_DIR:-$LLAMA_SRC/build-$BACKEND}"
JOBS="${JOBS:-$(nproc)}"
CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
PATCH_DIR="${PATCH_DIR:-$ROOT/third_party/patches/llama.cpp}"
TARGETS="${TARGETS:-llama-mtmd-cli llama-completion llama-bench llama-quantize}"

if [ -z "${CMAKE:-}" ]; then
    CMAKE="$(command -v cmake || true)"
    [ -n "$CMAKE" ] || CMAKE="$HOME/.local/bin/cmake"
fi
CC="${CC:-$(command -v gcc-8 || command -v gcc)}"
CXX="${CXX:-$(command -v g++-8 || command -v g++)}"

detect_cuda_arch() {
    local tmp
    tmp="$(mktemp -d)"
    cat > "$tmp/arch.cu" <<'CU'
#include <cstdio>
int main() {
    cudaDeviceProp p;
    if (cudaGetDeviceProperties(&p, 0) != cudaSuccess) return 1;
    printf("%d%d\n", p.major, p.minor);
    return 0;
}
CU
    "$CUDA_HOME/bin/nvcc" -ccbin "$CXX" -o "$tmp/arch" "$tmp/arch.cu" >/dev/null 2>&1 \
        && "$tmp/arch"
    local rc=$?
    rm -rf "$tmp"
    return $rc
}

nvcc_major() {
    "$CUDA_HOME/bin/nvcc" --version | sed -n 's/.*release \([0-9]*\)\..*/\1/p'
}

# Apply each patch once: skip it if it is already applied (reverse-apply check).
apply_patches() {
    local p
    [ -d "$PATCH_DIR" ] || return 0
    for p in "$PATCH_DIR"/*.patch; do
        [ -e "$p" ] || continue
        if git -C "$LLAMA_SRC" apply --reverse --check "$p" 2>/dev/null; then
            echo "patch already applied: $(basename "$p")"
        else
            git -C "$LLAMA_SRC" apply "$p"
            echo "patch applied: $(basename "$p")"
        fi
    done
}

apply_patches
mkdir -p "$BUILD_DIR"

args=(
    -S "$LLAMA_SRC" -B "$BUILD_DIR"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_C_COMPILER="$CC"
    -DCMAKE_CXX_COMPILER="$CXX"
    -DGGML_NATIVE=ON
    -DLLAMA_OPENSSL=OFF
    -DLLAMA_BUILD_TESTS=OFF
    -DLLAMA_USE_PREBUILT_UI=OFF    # no network download of the server web UI
)

# GCC < 9 ships std::filesystem in a separate library. CMAKE_CXX_STANDARD_LIBRARIES
# lands at the end of every link line, after the objects that need it.
if [ "$("$CXX" -dumpversion | cut -d. -f1)" -lt 9 ]; then
    args+=(-DCMAKE_CXX_STANDARD_LIBRARIES=-lstdc++fs)
fi

case "$BACKEND" in
    cuda)
        CUDA_ARCH="${CUDA_ARCH:-$(detect_cuda_arch)}" \
            || { echo "error: could not detect the CUDA arch; set CUDA_ARCH" >&2; exit 1; }
        args+=(
            -DGGML_CUDA=ON
            -DCMAKE_CUDA_COMPILER="$CUDA_HOME/bin/nvcc"
            -DCMAKE_CUDA_HOST_COMPILER="$CXX"
            -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCH"
        )
        if [ -z "${CUDA_STD:-}" ] && [ "$(nvcc_major)" -lt 11 ]; then
            CUDA_STD=14
        fi
        [ -n "${CUDA_STD:-}" ] && args+=(-DCMAKE_CUDA_STANDARD="$CUDA_STD")
        ;;
    cpu)
        args+=(-DGGML_CUDA=OFF)
        ;;
    *)
        echo "error: unknown BACKEND '$BACKEND' (cuda|cpu)" >&2
        exit 1
        ;;
esac

# shellcheck disable=SC2206
args+=(${EXTRA_CMAKE_ARGS:-})

echo "backend=$BACKEND cmake=$CMAKE cc=$CC cxx=$CXX jobs=$JOBS cuda_arch=${CUDA_ARCH:-n/a} cuda_std=${CUDA_STD:-n/a}"
echo "src=$LLAMA_SRC build=$BUILD_DIR commit=$(git -C "$LLAMA_SRC" rev-parse --short HEAD 2>/dev/null || echo unknown)"

TS_PID=""
if command -v tegrastats >/dev/null 2>&1; then
    tegrastats --interval 2000 --logfile "$BUILD_DIR/tegrastats.log" &
    TS_PID=$!
fi
cleanup() { [ -n "$TS_PID" ] && kill "$TS_PID" 2>/dev/null || true; }
trap cleanup EXIT

"$CMAKE" "${args[@]}" 2>&1 | tee "$BUILD_DIR/configure.log"
target_args=()
if [ "$TARGETS" != "all" ]; then
    # shellcheck disable=SC2206
    target_args=(--target $TARGETS)
fi
echo "targets=$TARGETS"
time "$CMAKE" --build "$BUILD_DIR" -j "$JOBS" "${target_args[@]}" 2>&1 | tee "$BUILD_DIR/build.log"
