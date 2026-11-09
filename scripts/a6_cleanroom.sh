#!/usr/bin/env bash
# Track A / A6: clean-room replication of A5 from the PUBLISHED patch files only.
#  - prover tree: a fresh clone (--no-local: objects copied, not linked) of upstream at the pin, plus
#    `git am` of experiments/consumer-gpu/patches/format-patch/*.patch; its tree must equal exp/sm120's.
#  - toolchain: a second, separate pip install of nvcc 13.2.86 (no pip cache) below ~/cleanroom.
#  - verifier: built from a THIRD clone at the pin with no patches; the proofs are judged by it and by
#    the A1 cp_verify (sha256 7f9efc1e…), never by anything built from the patched tree.
# usage: a6_cleanroom.sh setup | build | run RUN | verify RUN
set -u
PIN=9e2bdd8ff5bf9c62f18263d7dac189b0400b260c
SM120_HEAD=7b849bf7ab3e36956e971acfd260ed1c2a1fb109
CR=$HOME/cleanroom
SRC=$HOME/work/flashprove
WIN=${WHY_ROOT}
EVB=$HOME/work/evidence
CUDA=$CR/cuda-13.2.86
P=$CR/fp-prover
VT=$CR/fp-verifier
export PATH="$CUDA/nvidia/cu13/bin:$PATH"
stage=${1:-}
case $stage in
setup)
  [ -e "$CR" ] && { echo "$CR exists already; not touching it"; exit 3; }
  mkdir -p "$CR/patches" "$EVB/a6-setup"; E=$EVB/a6-setup
  cp "$WIN"/experiments/consumer-gpu/patches/format-patch/*.patch "$CR/patches/"
  (cd "$CR/patches" && sha256sum *.patch) > "$E/patches.sha256"
  echo "patch files: $(ls "$CR/patches" | wc -l)" | tee "$E/meta.txt"
  [ "$(git -C "$SRC" rev-parse HEAD)" = "$PIN" ] && [ -z "$(git -C "$SRC" status --porcelain)" ] || { echo "source checkout not clean at pin"; exit 2; }
  git clone -q --no-local --no-checkout "$SRC" "$P" && git -C "$P" checkout -q -b cleanroom "$PIN" || exit 2
  git -C "$P" config user.name why-research-cleanroom; git -C "$P" config user.email why-research@localhost
  git -C "$P" am -q "$CR"/patches/*.patch > "$E/git-am.log" 2>&1; echo "git_am_exit=$?" | tee -a "$E/meta.txt"
  t_cr=$(git -C "$P" rev-parse 'HEAD^{tree}'); t_x=$(git -C "$HOME/work/flashprove-sm120" rev-parse "$SM120_HEAD^{tree}")
  { echo "cleanroom_head=$(git -C "$P" rev-parse HEAD) commits_on_pin=$(git -C "$P" rev-list --count "$PIN"..HEAD)"
    echo "cleanroom_tree=$t_cr"; echo "exp_sm120_tree=$t_x"; [ "$t_cr" = "$t_x" ] && echo "trees_equal=yes" || echo "trees_equal=NO"
    echo "--- diff --stat pin..HEAD"; git -C "$P" diff --stat "$PIN" HEAD
    echo "verifier_dir_changed_by_patches=$(git -C "$P" diff --name-only "$PIN" HEAD -- verifier | wc -l)"; } | tee -a "$E/meta.txt"
  git clone -q --no-local --no-checkout "$SRC" "$VT" && git -C "$VT" checkout -q --detach "$PIN" || exit 2
  echo "verifier_clone_head=$(git -C "$VT" rev-parse HEAD) dirty=$(git -C "$VT" status --porcelain | wc -l)" | tee -a "$E/meta.txt"
  # nvcc: upstream's documented pip route (prover/docs/build.md), the same lines as a2_install_cuda.sh.
  mkdir "$CUDA"
  python3 -m pip install -q --no-cache-dir --target "$CUDA" "cuda-toolkit[nvcc,cublas,cccl,crt,nvvm,cudart]==13.2.2" > "$E/pip.log" 2>&1
  echo "pip_exit=$?" | tee -a "$E/meta.txt"
  lib="$CUDA/nvidia/cu13/lib"
  for n in cublasLt cublas cudart; do ln -s lib$n.so.13 "$lib/lib$n.so"; done
  mkdir "$lib/stubs"; ln -s "$(/sbin/ldconfig -p | awk '/libcuda\.so\.1 .*x86-64/ { print $NF; exit }')" "$lib/stubs/libcuda.so"
  chmod -R go-w "$CUDA"
  { nvcc --version | tail -2; echo "cuda_du=$(du -sh "$CUDA" | cut -f1)"; } | tee -a "$E/meta.txt"
  ;;
build)
  E=$EVB/a6-build; mkdir -p "$E"
  { echo "start=$(date -u +%FT%TZ) nvcc=$(command -v nvcc)"; nvcc --version | tail -1; } > "$E/meta.txt"
  (cd "$VT" && /usr/bin/time -v -o "$E/verifier.time" verifier/build.sh > "$E/verifier.log" 2>&1); echo "verifier_build_exit=$?" >> "$E/meta.txt"
  { sha256sum "$VT/bin/cp_verify" "$SRC/bin/cp_verify"; echo "verifier_clone_dirty=$(git -C "$VT" status --porcelain | wc -l)"; } >> "$E/meta.txt"
  # upstream's order: cp_commit's build copies ../bin/cp_verify beside it (for cp_commit's own self-check);
  # verifier/ is untouched by the patches. The JUDGE stays $VT/bin/cp_verify and the A1 binary.
  (cd "$P" && verifier/build.sh > "$E/prover-tree-verifier.log" 2>&1); echo "prover_tree_verifier_build_exit=$?" >> "$E/meta.txt"
  sha256sum "$P/bin/cp_verify" >> "$E/meta.txt"
  (cd "$P/prover" && /usr/bin/time -v -o "$E/tests.time" ./build.sh tests > "$E/tests.log" 2>&1); echo "tests_build_exit=$?" >> "$E/meta.txt"
  { echo "end=$(date -u +%FT%TZ)"; grep -E 'Elapsed|Maximum resident' "$E/tests.time"
    sha256sum "$P/prover/build/hc/test_build/cp_commit" "$P/prover/build/hc/test_build/cp_prove"
    sha256sum "$HOME/work/flashprove-sm120/prover/build/hc/test_build/cp_commit" "$HOME/work/flashprove-sm120/prover/build/hc/test_build/cp_prove" | sed 's/^/a5_build: /'; } >> "$E/meta.txt" 2>&1
  cat "$E/meta.txt"; echo "--- last 15 lines of the tests build"; tail -n 15 "$E/tests.log"
  ;;
run)
  RUN=${2:?run name}; E=$EVB/a6-$RUN; PROGS=$CR/progs; WORK=$CR/runs/$RUN
  [ -e "$WORK" ] && { echo "$WORK exists"; exit 3; }
  mkdir -p "$E" "$PROGS" "$CR/runs"
  TB=$P/prover/build/hc/test_build
  for p in cp_commit cp_prove; do [ -x "$TB/$p" ] || { echo "missing $TB/$p"; exit 2; }; done
  [ -x "$VT/bin/cp_verify" ] || { echo "missing clean-room cp_verify"; exit 2; }
  ln -sfn "$TB/cp_commit" "$PROGS/cp_commit"; ln -sfn "$TB/cp_prove" "$PROGS/cp_prove"; ln -sfn "$VT/bin/cp_verify" "$PROGS/cp_verify"
  { echo "run=$RUN start=$(date -u +%FT%TZ) cleanroom_head=$(git -C "$P" rev-parse HEAD) verifier_head=$(git -C "$VT" rev-parse HEAD)"
    sha256sum "$TB/cp_commit" "$TB/cp_prove" "$VT/bin/cp_verify"
    /usr/lib/wsl/lib/nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader | sed 's/^/gpu_before=/'; } > "$E/meta.txt"
  BUILD=$PROGS GPU_RUN="/usr/bin/time -v" /usr/bin/time -v -o "$E/total.time" \
    bash "$P/prover/examples/run_target_example.sh" target_small_f2_roomy "$WORK" > "$E/run_target_example.log" 2>&1
  rc=$?
  { echo "run_target_example_exit=$rc"; echo "last_line=$(tail -n 1 "$E/run_target_example.log")"; echo "end=$(date -u +%FT%TZ)"
    grep -E 'Elapsed' "$E/total.time" | sed 's/^\s*/total_/'; } >> "$E/meta.txt"
  for f in cp_commit.log cp_prove.log cp_verify.log; do [ -f "$WORK/$f" ] && cp "$WORK/$f" "$E/"; done
  [ -f "$E/cp_verify.log" ] && { echo "--- cp_verify.log (clean-room verifier, via upstream's example script)"; grep -E '^(covered:|commitment:|proof of work:|result-v1)' "$E/cp_verify.log"; tail -n 1 "$E/cp_verify.log"; } >> "$E/meta.txt"
  cat "$E/meta.txt"; exit $rc
  ;;
verify)
  RUN=${2:?run name}
  WBASE=$CR/runs bash "$WIN/experiments/consumer-gpu/a5_verify_and_tamper.sh" "$RUN"
  ;;
*) echo "usage: $0 setup | build | run RUN | verify RUN"; exit 2 ;;
esac
