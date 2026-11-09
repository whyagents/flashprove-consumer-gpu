#!/usr/bin/env bash
# Track A / A8 (session 004): the PRODUCTION (default) build of the exp/sm120 prover, in the clean-room
# tree (~/cleanroom/fp-prover, = git am of the 12 published patches), on the bundled synthetic small example.
# The production programs take no test options: cp_commit draws its own seed, weight hiding is in force,
# and both refuse a GPU with > 2 GiB in use (common/common.h:55). That check is NOT patched.
# Judge: the A1 cp_verify (sha256 7f9efc1e…), via a5_verify_and_tamper.sh, and the copy built beside cp_commit.
# usage: a8_production.sh precheck | build | run RUN | verify RUN
set -u
CR=$HOME/cleanroom
P=$CR/fp-prover
CUDA=$CR/cuda-13.2.86
WIN=${WHY_ROOT}
EVB=$HOME/work/evidence
export PATH="$CUDA/nvidia/cu13/bin:$PATH"
case ${1:-} in
precheck)
  E=$EVB/a8-precheck; mkdir -p "$E"
  {
    echo "date=$(date -u +%FT%TZ) head=$(git -C "$P" rev-parse HEAD) dirty=$(git -C "$P" status --porcelain | wc -l)"
    echo "sha_ni=$(grep -m1 -ow sha_ni /proc/cpuinfo || echo MISSING)"
    echo "--- ldconfig"; /sbin/ldconfig -p | grep -E 'libcuda|libcudart|libcublas' || echo "none listed"
    echo "--- gpu"; /usr/lib/wsl/lib/nvidia-smi --query-gpu=name,compute_cap,driver_version,memory.used,memory.total --format=csv,noheader
    echo "--- ulimit -l (locked memory, kB): $(ulimit -l)"
    echo "--- MemAvailable: $(grep MemAvailable /proc/meminfo)"
    echo "--- kernel: $(uname -r)"
    echo "--- gcc: $(gcc -dumpfullversion) g++: $(g++ -dumpfullversion)"
    echo "--- tools: $(type -P python3 ld nm objcopy strings ldd sha256sum flock | tr '\n' ' ')"
    echo "--- bin/cp_verify in tree: $(sha256sum "$P/bin/cp_verify" | cut -c1-16)…"
    echo "--- prover/check_nvcc_version.sh"; (cd "$P" && prover/check_nvcc_version.sh; echo "exit=$?")
  } 2>&1 | tee "$E/meta.txt"
  ;;
build)
  E=$EVB/a8-build; mkdir -p "$E"
  { echo "start=$(date -u +%FT%TZ) head=$(git -C "$P" rev-parse HEAD)"; nvcc --version | tail -1; } > "$E/meta.txt"
  (cd "$P" && verifier/build.sh > "$E/verifier.log" 2>&1); echo "verifier_build_exit=$?" >> "$E/meta.txt"
  (cd "$P/prover" && /usr/bin/time -v -o "$E/default.time" ./build.sh > "$E/default.log" 2>&1); echo "default_build_exit=$?" >> "$E/meta.txt"
  { echo "end=$(date -u +%FT%TZ)"; grep -E 'Elapsed|Maximum resident' "$E/default.time"
    echo "last_line=$(tail -n 1 "$E/default.log")"
    ls -la "$P/prover/build/hc/" 2>&1
    sha256sum "$P/prover/build/hc/cp_commit" "$P/prover/build/hc/cp_prove" "$P/prover/build/hc/cp_verify" 2>&1
    grep -E '^build.sh: (note|warning)' "$E/default.log" | sort -u
    grep -c 'warning #' "$E/default.log" | sed 's/^/compiler_warning_lines=/'
    grep -oE 'warning #[0-9]+-D' "$E/default.log" | sort | uniq -c; } >> "$E/meta.txt" 2>&1
  cat "$E/meta.txt"; echo "--- last 20 lines of the default build"; tail -n 20 "$E/default.log"
  ;;
run)
  RUN=${2:?run name}; E=$EVB/a8-$RUN; WORK=$CR/runs/$RUN; BUILD=$P/prover/build/hc
  [ -e "$WORK" ] && { echo "$WORK exists"; exit 3; }
  mkdir -p "$E"
  { echo "run=$RUN start=$(date -u +%FT%TZ) head=$(git -C "$P" rev-parse HEAD) build=production"
    sha256sum "$BUILD/cp_commit" "$BUILD/cp_prove" "$BUILD/cp_verify"
    /usr/lib/wsl/lib/nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader | sed 's/^/gpu_before=/'; } > "$E/meta.txt"
  /usr/lib/wsl/lib/nvidia-smi --query-gpu=timestamp,memory.used --format=csv,noheader -lms 250 > "$E/vram.csv" 2>&1 &
  SAMPLER=$!
  BUILD=$BUILD GPU_RUN="/usr/bin/time -v" bash "$P/prover/examples/run_target_example.sh" target_small_f2_roomy "$WORK" > "$E/run_target_example.log" 2>&1
  rc=$?
  kill $SAMPLER 2>/dev/null; wait $SAMPLER 2>/dev/null
  { echo "run_target_example_exit=$rc"; echo "last_line=$(tail -n 1 "$E/run_target_example.log")"; echo "end=$(date -u +%FT%TZ)"
    awk -F', ' '{gsub(/ MiB/,"",$2); if ($2+0>m) m=$2+0} END {print "vram_peak_MiB=" m " samples=" NR}' "$E/vram.csv"; } >> "$E/meta.txt"
  for f in cp_commit.log cp_prove.log cp_verify.log; do [ -f "$WORK/$f" ] && cp "$WORK/$f" "$E/"; done
  for f in cp_commit cp_prove; do [ -f "$E/$f.log" ] && grep -h -E 'Elapsed \(wall|Maximum resident' "$E/$f.log" | sed "s/^\s*/$f: /" >> "$E/meta.txt"; done
  [ -f "$E/cp_commit.log" ] && grep -h -iE 'hiding|test|refused|gpu-in-use|GPU memory' "$E/cp_commit.log" | cut -c1-200 | sed 's/^/commit| /' >> "$E/meta.txt"
  [ -f "$E/cp_prove.log" ] && grep -h -iE 'refused|gpu-in-use|GPU memory' "$E/cp_prove.log" | cut -c1-200 | sed 's/^/prove| /' >> "$E/meta.txt"
  [ -f "$E/cp_verify.log" ] && { echo "--- cp_verify.log"; grep -E '^(covered:|commitment:|proof of work:|result-v1)|hiding' "$E/cp_verify.log"; tail -n 1 "$E/cp_verify.log"; } >> "$E/meta.txt"
  cat "$E/meta.txt"; echo "--- run_target_example.log (last 25)"; tail -n 25 "$E/run_target_example.log"
  exit $rc
  ;;
verify)
  RUN=${2:?run name}
  WBASE=$CR/runs bash "$WIN/experiments/consumer-gpu/a5_verify_and_tamper.sh" "$RUN"
  ;;
*) echo "usage: $0 precheck | build | run RUN | verify RUN"; exit 2 ;;
esac
