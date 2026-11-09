#!/usr/bin/env bash
# Track A / A13 scaling study (session 004). What fits in 16 GB, measured, not estimated.
#  S2: Maverick-WIDTH layers (d 5120, H 40, G 8, dh 128; L 4, NE 16, f 2048, V 2048, T 256) = upstream's
#      target_small_file_f2, on make_model's synthetic GGUF (530 MB), via upstream's UNCHANGED test
#      prover/tests/record_on_public_weights.sh with our production programs (A8 build, 12 patches).
#      VRAM sampled every 250 ms; host RSS per program by /usr/bin/time -v (GPU_RUN).
# usage: a13_scaling.sh s2 RUN
set -u
CR=$HOME/cleanroom
P=$CR/fp-prover
B=$P/prover/build/hc                       # A8 production programs (cee61ddf; sha256 cp_commit 1b39a3d9…)
MM=$P/prover/build/make_model              # from the clean-room tests build
K=$P/prover/examples/target_small_file_f2
EVB=$HOME/work/evidence
export PATH="$CR/cuda-13.2.86/nvidia/cu13/bin:$PATH"
case ${1:-} in
s2)
  RUN=${2:?run name}; E=$EVB/a13-$RUN; W=$CR/runs/$RUN; M=$CR/models/small_file_f2
  mkdir -p "$E"
  { echo "run=$RUN start=$(date -u +%FT%TZ) tree=$(git -C "$P" rev-parse HEAD)"
    sha256sum "$B/cp_commit" "$B/cp_prove" "$B/cp_verify" "$MM"
    echo "model.txt: $(cat "$K/model.txt")"
    grep -E '^(table|lt|L|d|H|G|dh|f|fe|NE|V) ' "$K/policy.txt" | tr '\n' ';'; echo
    /usr/lib/wsl/lib/nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader | sed 's/^/gpu_before=/'
    free -m | sed -n 2p | sed 's/^/host_mem_before=/'; } > "$E/meta.txt"
  if [ ! -d "$M" ]; then
    mkdir -p "$CR/models"
    # shellcheck disable=SC2046
    /usr/bin/time -v -o "$E/make_model.time" "$MM" "$M" $(cat "$K/model.txt") > "$E/make_model.log" 2>&1
    echo "make_model_exit=$? $(grep -E 'Elapsed' "$E/make_model.time" | sed 's/^\s*//')" >> "$E/meta.txt"
  fi
  { echo "model files: $(ls -la "$M" | tail -n +2 | awk '{print $5, $9}' | tr '\n' ';')"; du -sh "$M"; } >> "$E/meta.txt"
  used=$(/usr/lib/wsl/lib/nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1 | tr -d ' ')
  if [ "${used:-99999}" -ge 1400 ]; then  # the production programs refuse > 2 GiB in use, their own context included
    echo "GPU memory in use: ${used} MiB (need < 1400). Model files are ready; close GPU apps and run again. No GPU step run." | tee -a "$E/meta.txt"
    rmdir "$E" 2>/dev/null; exit 5
  fi
  /usr/lib/wsl/lib/nvidia-smi --query-gpu=timestamp,memory.used --format=csv,noheader -lms 250 > "$E/vram.csv" 2>&1 &
  S=$!
  # time's report goes to a SEPARATE file (appending it to the program's log would change the log's last line, which the test reads)
  GPU_RUN="/usr/bin/time -a -o $E/per-call.time -f %e_s|%M_kB|%x|%C" /usr/bin/time -v -o "$E/total.time" bash "$P/prover/tests/record_on_public_weights.sh" "$B" "$W" "$K" "$M" > "$E/test.log" 2>&1
  rc=$?
  kill $S 2>/dev/null; wait $S 2>/dev/null
  { echo "record_on_public_weights_exit=$rc"; echo "last_line=$(tail -n 1 "$E/test.log")"; echo "end=$(date -u +%FT%TZ)"
    grep -E 'Elapsed' "$E/total.time" | sed 's/^\s*/total_/'
    awk -F', ' '{gsub(/ MiB/,"",$2); if ($2+0>m) m=$2+0} END {print "vram_peak_MiB=" m " samples=" NR}' "$E/vram.csv"
    for f in "$W"/*.cp_commit.log "$W"/*.cp_prove.log; do [ -f "$f" ] || continue
      echo "$(basename "$f"): $(grep -h -E 'Elapsed \(wall' "$f" | sed 's/.*: //') | RSS $(grep -h 'Maximum resident' "$f" | sed 's/.*: //') kB"; done
    [ -f "$E/per-call.time" ] && { echo "--- per call (seconds|max RSS|exit|command)"; sed -E 's#/home/[^ ]*/(cp_[a-z]+) .*#\1#' "$E/per-call.time"; }
    grep -h -E 'GPU memory (before the first batch|: .* in use at the start)' "$W"/*.cp_prove.log 2>/dev/null | cut -c1-120
    for f in "$W"/*.cp_verify.log "$W"/*cp_verify*; do [ -f "$f" ] && echo "$(basename "$f"): $(tail -n 1 "$f")"; done 2>/dev/null | sort -u
    find "$W" -name 'example.proof' -exec stat -c 'proof %n %s bytes' {} \; 2>/dev/null | sed "s#$W/##"; } >> "$E/meta.txt"
  cp "$W"/*.log "$E/" 2>/dev/null
  cat "$E/meta.txt"; echo "--- test.log (last 25)"; tail -n 25 "$E/test.log"
  ;;
*) echo "usage: $0 s2 RUN"; exit 2 ;;
esac
