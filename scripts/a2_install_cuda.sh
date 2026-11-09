#!/usr/bin/env bash
# Track A / A2: install CUDA 13.2 Update 2 (nvcc 13.2.86) from NVIDIA's PyPI packages into a user
# directory. These are upstream's lines from prover/docs/build.md ("One way to get that compiler"),
# made into a script. Needs no root. The NVIDIA packages are under NVIDIA's EULA.
set -eu
cuda=$HOME/cuda-13.2.86
if [ -e "$cuda" ]; then echo "$cuda exists already; not touching it"; exit 3; fi
mkdir "$cuda"
python3 -m pip install --target "$cuda" "cuda-toolkit[nvcc,cublas,cccl,crt,nvvm,cudart]==13.2.2"
lib="$cuda/nvidia/cu13/lib"
for n in cublasLt cublas cudart; do ln -s lib$n.so.13 "$lib/lib$n.so"; done
mkdir "$lib/stubs"
ln -s "$(/sbin/ldconfig -p | awk '/libcuda\.so\.1 .*x86-64/ { print $NF; exit }')" "$lib/stubs/libcuda.so"
chmod -R go-w "$cuda"
export PATH="$cuda/nvidia/cu13/bin:$PATH"
nvcc --version
echo "du: $(du -sh "$cuda" | cut -f1)"
