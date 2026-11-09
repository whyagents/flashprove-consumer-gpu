#!/usr/bin/env bash
# Track A / A3: build cp_verify and the TEST prover (./build.sh tests: cp_prove + cp_commit with test
# options, and make_model) in the exp/sm120 worktree. Upstream: about half an hour, often silent.
set -u
WT=$HOME/work/flashprove-sm120
EV=$HOME/work/evidence
export PATH="$HOME/cuda-13.2.86/nvidia/cu13/bin:$PATH"
cd "$WT" || exit 2
{
  echo "start=$(date -u +%FT%TZ) head=$(git rev-parse HEAD) branch=$(git rev-parse --abbrev-ref HEAD)"
  nvcc --version | tail -1
} > "$EV/a3-build-meta.txt"
/usr/bin/time -v -o "$EV/a3-build-verifier.time" verifier/build.sh > "$EV/a3-build-verifier.log" 2>&1
echo "verifier_build_exit=$?" >> "$EV/a3-build-meta.txt"
cd prover
/usr/bin/time -v -o "$EV/a3-build-tests.time" ./build.sh tests > "$EV/a3-build-tests.log" 2>&1
echo "tests_build_exit=$?" >> "$EV/a3-build-meta.txt"
echo "end=$(date -u +%FT%TZ)" >> "$EV/a3-build-meta.txt"
grep -E 'Elapsed|Maximum resident' "$EV/a3-build-tests.time" >> "$EV/a3-build-meta.txt"
ls -la build/hc/test_build build/make_model 2>&1 >> "$EV/a3-build-meta.txt"
cat "$EV/a3-build-meta.txt"
echo "--- last 25 lines of the tests build"; tail -n 25 "$EV/a3-build-tests.log"
