#!/usr/bin/env bash
# Track A / A13-S1: batch scaling with upstream's UNCHANGED driver/measure_rate.py (production cp_prove as a spool service;
# every proof checked by a separate cp_verify; no rate printed unless all are accepted).
#  small : target_small_f2_roomy (T 64), a fresh production commitment on made-up-blocks
#  wide  : target_small_file_f2 (Maverick width, T 256), the hiding-mode commitment of S2 run s2-3
# usage: a14_batch.sh commit-small | sweep small|wide "1 4 8 16 32 64"
set -u
CR=$HOME/cleanroom; P=$CR/fp-prover; B=$P/prover/build/hc; EVB=$HOME/work/evidence
export PATH="/usr/lib/wsl/lib:$CR/cuda-13.2.86/nvidia/cu13/bin:$PATH"   # nvidia-smi for measure_rate's GPU sampling
SMALL=$CR/runs/s1-small-commit
gpu_ok() { local u; u=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1 | tr -d ' '); echo "gpu_in_use=${u}MiB"; [ "${u:-99999}" -lt 1400 ]; }
case ${1:-} in
commit-small)
  [ -e "$SMALL" ] && { echo "$SMALL exists"; exit 3; }
  gpu_ok || { echo "close GPU apps first"; exit 5; }
  mkdir -m 700 -p "$SMALL" && mkdir "$SMALL/config" && cp "$P/prover/examples/target_small_f2_roomy/"{policy.txt,KL.bin,layout.txt} "$SMALL/config/"
  (cd "$SMALL" && "$B/cp_commit" -weights made-up-blocks -config config -M 1 -ivk ivk -isk isk > cp_commit.log 2>&1); echo "cp_commit_exit=$?"
  sed -n 's/^commitment ID: //p' "$SMALL/cp_commit.log" | tr -d ' ' | tee "$SMALL/ID.txt"
  ;;
sweep)
  which=${2:?small|wide}; sizes=${3:-"1 4 8 16 32 64"}
  case $which in
    small) C=$SMALL/config; I=$SMALL/isk; V=$SMALL/ivk; ID=$(cat "$SMALL/ID.txt") ;;
    wide)  W=$CR/runs/s2-3; C=$W/config; I=$W/without/isk; V=$W/without/ivk; ID=$(sed -n 's/^commitment ID: //p' "$W/1.cp_commit.log" | tr -d ' ') ;;
    *) echo "small|wide"; exit 2 ;;
  esac
  E=$EVB/a14-$which; mkdir -p "$E"
  echo "sweep=$which id=$ID sizes=[$sizes] start=$(date -u +%FT%TZ) cp_prove=$(sha256sum "$B/cp_prove" | cut -c1-16) cp_verify=$(sha256sum "$B/cp_verify" | cut -c1-16)" | tee -a "$E/summary.txt"
  for b in $sizes; do
    gpu_ok >> "$E/summary.txt" || { echo "B=$b: GPU in use too high; stopping" | tee -a "$E/summary.txt"; break; }
    WK=$CR/runs/s1-$which-b$b-$(date +%H%M%S)
    (cd "$P" && /usr/bin/time -v -o "$E/b$b.time" python3 -B driver/measure_rate.py --programs "$B" --isk "$I" --ivk "$V" --config "$C" \
        --id "$ID" --work "$WK" --batch "$b" --batches 3) > "$E/b$b.log" 2>&1
    rc=$?
    { echo "--- B=$b exit=$rc wall=$(grep -h 'Elapsed' "$E/b$b.time" | sed 's/.*: //')"
      grep -h -i -E 'steady rate|rate:|interval|peak|GPU memory|accepted|refused|failed|no rate|exit code' "$E/b$b.log" | cut -c1-220 | head -20
      tail -n 3 "$E/b$b.log" | cut -c1-220; } | tee -a "$E/summary.txt"
    [ $rc -eq 0 ] || { echo "B=$b failed: stopping the sweep here" | tee -a "$E/summary.txt"; break; }
  done
  ;;
*) echo "usage: $0 commit-small | sweep small|wide [sizes]"; exit 2 ;;
esac
