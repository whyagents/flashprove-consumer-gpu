#!/usr/bin/env bash
# Track A / A15: are the TEST build's outputs byte-deterministic under fixed seeds? (prerequisite for the planned
# byte-identity comparison with unmodified upstream on an H100: docs/HIDING.md, docs/CLOUD-RUNBOOK.md)
#  cp_commit -test-seed FILE and cp_prove -test-coins FILE (test build only), target_small_f2_roomy, made-up-blocks,
#  upstream's own_choices.req. Two runs with the same seed files -> compare sha256 of key, leaf, proof, token.
# usage: a15_determinism.sh usage | run NAME
set -u
CR=$HOME/cleanroom; P=$CR/fp-prover; TB=$P/prover/build/hc/test_build; K=$P/prover/examples/target_small_f2_roomy
V=$HOME/work/flashprove/bin/cp_verify; EVB=$HOME/work/evidence
export PATH="$CR/cuda-13.2.86/nvidia/cu13/bin:$PATH"
SEEDS=$CR/a15-seeds
case ${1:-} in
usage)
  "$TB/cp_commit" 2>&1 | grep -i -E -A3 'test-seed' | head -16; echo "======"
  "$TB/cp_prove" 2>&1 | grep -i -E -A3 'test-coins' | head -16
  ;;
run)
  N=${2:?name}; W=$CR/runs/a15-$N; E=$EVB/a15; mkdir -p "$E" "$SEEDS"
  [ -e "$W" ] && { echo "$W exists"; exit 3; }
  # fixed, PUBLIC test seeds (synthetic weights only; a test seed hides nothing)
  [ -f "$SEEDS/seed.32" ] || printf 'why-research A15 fixed test seed!' | head -c 32 > "$SEEDS/seed.32"
  [ -f "$SEEDS/coins.32" ] || printf 'why-research A15 fixed testcoins' | head -c 32 > "$SEEDS/coins.32"
  mkdir -m 700 -p "$W" && mkdir "$W/config" "$W/in" && cp "$K"/{policy.txt,KL.bin,layout.txt} "$W/config/" && cp "$K/own_choices.req" "$W/in/example.req"
  cd "$W" || exit 2
  "$TB/cp_commit" -weights made-up-blocks -config config -M 1 -ivk ivk -isk isk -test-seed "$SEEDS/seed.32" > cp_commit.log 2>&1; rc_c=$?
  ID=$(sed -n 's/^commitment ID: //p' cp_commit.log | tr -d ' ')
  "$TB/cp_prove" -isk "$W/isk" -in "$W/in" -out "$W/out" -test-coins "$SEEDS/coins.32" > cp_prove.log 2>&1; rc_p=$?
  "$V" config ivk in/example.req out/example.y out/example.proof -id "$ID" > cp_verify.log 2>&1; rc_v=$?
  { echo "run=$N commit_exit=$rc_c prove_exit=$rc_p verify_exit=$rc_v last=\"$(tail -n 1 cp_verify.log)\" id=$ID"
    (cd "$W" && sha256sum ivk/key.bin ivk/leaf/0.bin out/example.proof out/example.y) | sed "s/^/$N /"; } | tee -a "$E/hashes.txt"
  cp cp_commit.log "$E/$N.cp_commit.log"; cp cp_prove.log "$E/$N.cp_prove.log"; cp cp_verify.log "$E/$N.cp_verify.log"
  ;;
*) echo "usage: $0 usage | run NAME"; exit 2 ;;
esac
