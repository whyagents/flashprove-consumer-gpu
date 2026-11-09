#!/usr/bin/env bash
# Track A / A3: first run of the sm_120 TEST-build prover on the bundled 8-layer synthetic model
# (target_small_f2_roomy), through upstream's UNCHANGED prover/examples/run_target_example.sh.
#  - cp_commit, cp_prove: exp/sm120 worktree, ./build.sh tests (only change: -arch=sm_120)
#  - cp_verify: the PRISTINE build from ~/work/flashprove @ 9e2bdd8f (independent of the patched tree)
#  - GPU memory is sampled every 250 ms with nvidia-smi; host RSS by /usr/bin/time -v (GPU_RUN).
# Expected first outcome: a failure at a kernel that asks for > 101,376 B of shared memory.
set -u
RUN=${1:-run1}
PIN=9e2bdd8ff5bf9c62f18263d7dac189b0400b260c
WT=$HOME/work/flashprove-sm120
PRISTINE=$HOME/work/flashprove
EV=$HOME/work/evidence/a3-$RUN
PROGS=$HOME/work/a3/progs
WORK=$HOME/work/a3/$RUN
mkdir -p "$EV" "$PROGS"
TB=$WT/prover/build/hc/test_build
for p in cp_commit cp_prove; do [ -x "$TB/$p" ] || { echo "missing $TB/$p"; exit 2; }; done
[ "$(git -C "$PRISTINE" rev-parse HEAD)" = "$PIN" ] && [ -z "$(git -C "$PRISTINE" status --porcelain)" ] || { echo "pristine checkout not clean at pin"; exit 2; }
ln -sfn "$TB/cp_commit" "$PROGS/cp_commit"
ln -sfn "$TB/cp_prove" "$PROGS/cp_prove"
ln -sfn "$PRISTINE/bin/cp_verify" "$PROGS/cp_verify"
{
  echo "run=$RUN start=$(date -u +%FT%TZ)"
  echo "sm120_head=$(git -C "$WT" rev-parse HEAD) pristine_head=$(git -C "$PRISTINE" rev-parse HEAD)"
  sha256sum "$TB/cp_commit" "$TB/cp_prove" "$PRISTINE/bin/cp_verify"
  /usr/lib/wsl/lib/nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader | sed 's/^/gpu_before=/'
  free -m | sed -n 2p | sed 's/^/host_mem_before=/'
} > "$EV/meta.txt"

/usr/lib/wsl/lib/nvidia-smi --query-gpu=timestamp,memory.used,utilization.gpu --format=csv,noheader -lms 250 > "$EV/vram.csv" 2>&1 &
SAMPLER=$!
export PATH="$HOME/cuda-13.2.86/nvidia/cu13/bin:$PATH"
BUILD=$PROGS GPU_RUN="/usr/bin/time -v" /usr/bin/time -v -o "$EV/total.time" \
  bash "$WT/prover/examples/run_target_example.sh" target_small_f2_roomy "$WORK" > "$EV/run_target_example.log" 2>&1
rc=$?
kill $SAMPLER 2>/dev/null; wait $SAMPLER 2>/dev/null
{
  echo "run_target_example_exit=$rc"
  echo "last_line=$(tail -n 1 "$EV/run_target_example.log")"
  echo "end=$(date -u +%FT%TZ)"
  awk -F', ' '{gsub(/ MiB/,"",$2); if ($2+0>m) m=$2+0} END {print "vram_peak_MiB=" m " samples=" NR}' "$EV/vram.csv"
  grep -E 'Elapsed|Maximum resident' "$EV/total.time" | sed 's/^\s*/total_/'
} >> "$EV/meta.txt"
# Copy the logs (not isk/: the provider's secret directory stays in the work dir, mode 0700).
for f in cp_commit.log cp_prove.log cp_verify.log; do [ -f "$WORK/$f" ] && cp "$WORK/$f" "$EV/"; done
for f in cp_commit.log cp_prove.log; do
  [ -f "$EV/$f" ] && { echo "--- $f: last 15 lines"; tail -n 15 "$EV/$f"; } >> "$EV/meta.txt"
done
[ -f "$EV/cp_verify.log" ] && { echo "--- cp_verify.log"; grep -E '^(covered:|commitment:|proof of work:|result-v1)' "$EV/cp_verify.log"; tail -n 1 "$EV/cp_verify.log"; } >> "$EV/meta.txt"
cat "$EV/meta.txt"
echo "--- run_target_example.log (last 30)"; tail -n 30 "$EV/run_target_example.log"
exit $rc
