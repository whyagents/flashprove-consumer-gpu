#!/usr/bin/env bash
# Track A / A3: an isolated worktree on branch exp/sm120 with ONE change: nvcc -arch=sm_90a -> sm_120
# in prover/build.sh (the default build's and the test build's nvcc_base). The pristine checkout
# ~/work/flashprove (with its cp_verify) is left untouched, so it stays the independent verifier.
set -eu
PIN=9e2bdd8ff5bf9c62f18263d7dac189b0400b260c
SRC=$HOME/work/flashprove
WT=$HOME/work/flashprove-sm120
cd "$SRC"
if [ ! -d "$WT" ]; then git worktree add -q -b exp/sm120 "$WT" "$PIN"; fi
cd "$WT"
git config user.name "why-research"
git config user.email "why-research@localhost"
echo "arch occurrences in prover/build.sh before:"; grep -n -- '-arch=' prover/build.sh
if grep -q -- '-arch=sm_90a' prover/build.sh; then
  sed -i 's/-arch=sm_90a/-arch=sm_120/' prover/build.sh
  git add prover/build.sh
  git commit -q -m "exp/sm120: build for sm_120 (RTX 5070 Ti) instead of sm_90a

Only the nvcc architecture flag changes. Native SASS keeps nvcc 13.2.86 as the
code generator (an sm_90a build runs on sm_120 only through driver PTX JIT)."
fi
echo "after:"; grep -n -- '-arch=' prover/build.sh
echo "branch=$(git rev-parse --abbrev-ref HEAD) head=$(git rev-parse HEAD) base=$(git merge-base HEAD $PIN)"
git diff --stat "$PIN" HEAD
git diff "$PIN" HEAD > "$HOME/work/evidence/a3-patch.diff"
