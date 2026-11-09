#!/usr/bin/env bash
# Track A / A16: upstream's own GPU test of the lookup forest (prover/hiding/, touched by patches 7, 8, 10, 11) on sm_120.
#  As SUITE.md rows build.forest_lookup_test, build.npsc_checks and gpu.forest_lookup_test, unchanged, plus
#  psc_rows.sh data_cheats (malicious provers: crossed, key, multiplicity), in a worktree at the 12-patch commit cee61ddf.
#  Expected (SUITE.md): "forest_lookup_test: 10 of 10 groups run and written", "forest_lookup_check: 10 of 10 groups passed".
# usage: a16_lookup_tests.sh build | run
set -u
CR=$HOME/cleanroom; T=$HOME/testroom; S=$HOME/testroom-out; EVB=$HOME/work/evidence; E=$EVB/a16
export PATH="$CR/cuda-13.2.86/nvidia/cu13/bin:$PATH"
mkdir -p "$E"
case ${1:-} in
build)
  [ -e "$T" ] || git -C "$CR/fp-prover" worktree add -q --detach "$T" cee61ddfc7aa6274df37beb769799fdbb86d7328 || exit 2
  { echo "worktree head=$(git -C "$T" rev-parse HEAD) dirty=$(git -C "$T" status --porcelain | wc -l)"
    mkdir -p "$S/npsc.f2"
    (cd "$T/prover" && CUDA_VISIBLE_DEVICES= OUT=$S/npsc.f2 ./build.sh --field 2 forest_lookup_test) > "$E/build-forest_lookup_test.log" 2>&1
    echo "build_forest_lookup_test_exit=$? last=$(tail -n 1 "$E/build-forest_lookup_test.log")"
    (cd "$T" && prover/tests/psc_rows.sh checks "$S/npsc_checks") > "$E/build-checks.log" 2>&1
    echo "build_checks_exit=$? last=$(tail -n 1 "$E/build-checks.log")"; } | tee "$E/build.txt"
  ;;
run)
  W=$S/w-honest-$(date +%H%M%S); C=$S/w-cheats-$(date +%H%M%S)
  { mkdir -p "$W"
    (cd "$T/prover" && "$S/npsc.f2/forest_lookup_test" "$W" && "$S/npsc_checks/forest_lookup_check.f2" "$W") > "$E/honest.log" 2>&1
    echo "honest_exit=$?"; grep -E 'groups (run|passed)|0 - 1 = ' "$E/honest.log"
    (cd "$T" && prover/tests/psc_rows.sh data_cheats "$S/npsc.f2" "$S/npsc_checks" "$C") > "$E/cheats.log" 2>&1
    echo "cheats_exit=$?"; tail -n 12 "$E/cheats.log"; } | tee "$E/run.txt"
  ;;
*) echo "usage: $0 build | run"; exit 2 ;;
esac
