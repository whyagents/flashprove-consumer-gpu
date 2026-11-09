#!/usr/bin/env bash
# Track A / A9 (session 004): a REAL pretrained model (TinyStories260K, as converted and published by
# zkwasm/FlashProve-L4 @ eac41543, Apache-2.0) proved on the RTX 5070 Ti by the production build.
#  - third-party files go to ~/third_party/FlashProve-L4 (a pinned clone; treated as data, none of its scripts run)
#  - every file used is checked against the repo's own MANIFEST.json (sha256)
#  - from their upstream patch only the hunks for the 6 model-shape files are applied (git apply --include),
#    on a NEW branch `real-model` of the clean-room tree; our 12 sm_120 patches stay as they are
#  - judge: the A1 cp_verify (7f9efc1e…), with the commitment ID from OUR cp_commit
# usage: a9_real_model.sh fetch | patch | build | run RUN | verify RUN
set -u
L4SHA=eac41543adb3e287e3d98c3c657b8f3cc7b64bb1
TP=$HOME/third_party/FlashProve-L4
CR=$HOME/cleanroom
P=$CR/fp-prover
CUDA=$CR/cuda-13.2.86
V=$HOME/work/flashprove/bin/cp_verify
EXPECT_V=7f9efc1e86a848a3715c6cc870e465ac2a1c5e8fd1eac09e4809023de7604394
EVB=$HOME/work/evidence
export PATH="$CUDA/nvidia/cu13/bin:$PATH"
MODEL=$TP/models/stories260K/flashprove32
CONF=$TP/runs/real-config-tu9cL1
FILES=(models/stories260K/flashprove32/model.gguf models/stories260K/flashprove32/wsums.txt
       models/stories260K/flashprove32/fold.txt models/stories260K/flashprove32/shape.json
       runs/real-config-tu9cL1/policy.txt runs/real-config-tu9cL1/KL.bin runs/real-config-tu9cL1/layout.txt
       runs/real-config-tu9cL1/example.req upstream-l4-small-model.patch
       runs/real-l4-v8/out/example.y runs/real-l4-v8/trusted-ID.txt)
SHAPE_FILES=(prover/weights_blocks/gguf_source.cuh prover/weights_commitment/fold_source.cuh
             prover/weights_commitment/fold_weights.cuh prover/hash_commitment/hf_commit_weights.cuh
             prover/weights_commitment/worst_case.cuh weight_sums/weight_sums.cpp)
case ${1:-} in
fetch)
  E=$EVB/a9-fetch; mkdir -p "$E" "$HOME/third_party"
  [ -e "$TP" ] && { echo "$TP exists; not touching it"; exit 3; }
  # git/curl from WSL to GitHub got "connection reset" (2026-11-09); the pinned snapshot was fetched on
  # Windows from codeload.github.com/zkwasm/FlashProve-L4/tar.gz/$L4SHA into its own scratch folder.
  TGZ=${TGZ:?path of the downloaded tarball}
  mkdir "$TP" && tar -xzf "$TGZ" -C "$TP" --strip-components=1 --no-same-owner --no-same-permissions || exit 2
  { echo "source=codeload tarball of $L4SHA tarball_sha256=$(sha256sum "$TGZ" | cut -d' ' -f1) date=$(date -u +%FT%TZ) du=$(du -sh "$TP" | cut -f1)"
    # MANIFEST.json: check each file we use against the repo's own record (python -I: no local imports).
    python3 -I -c '
import json, hashlib, sys
root = sys.argv[1]; m = json.load(open(root + "/MANIFEST.json"))
entries = m.get("files", m) if isinstance(m, dict) else m
table = {}
if isinstance(entries, dict):
    for k, v in entries.items(): table[k] = v if isinstance(v, str) else v.get("sha256")
else:
    for e in entries: table[e.get("path")] = e.get("sha256")
bad = 0
for f in sys.argv[2:]:
    got = hashlib.sha256(open(root + "/" + f, "rb").read()).hexdigest()
    want = table.get(f)
    ok = want == got
    bad += not ok
    print(("OK  " if ok else "BAD ") + f + " " + got + ("" if ok else " manifest=" + str(want)))
print("manifest_mismatches=%d" % bad)
' "$TP" "${FILES[@]}"
    echo "--- shape.json"; cat "$MODEL/shape.json"; echo
    echo "--- their answer token: $(od -An -tu4 "$TP/runs/real-l4-v8/out/example.y" | tr -d ' ')  their ID: $(cat "$TP/runs/real-l4-v8/trusted-ID.txt")"
    echo "--- policy.txt (shape lines)"; grep -E '^(lt|L|d|H|G|dh|f|fe|NE|V|table|C|theta|cap) ' "$CONF/policy.txt"
  } 2>&1 | tee "$E/meta.txt"
  ;;
check-l4)
  # Their published L4 proof, judged here by our A1 verifier, with their committer's ID (their trusted-ID.txt).
  E=$EVB/a9-check-l4; mkdir -p "$E"; R=$TP/runs/real-l4-v8
  [ "$(sha256sum "$V" | cut -d' ' -f1)" = "$EXPECT_V" ] || { echo "verifier hash mismatch"; exit 2; }
  "$V" "$CONF" "$R/ivk" "$R/in/example.req" "$R/out/example.y" "$R/out/example.proof" -id "$(tr -d ' \n' < "$R/trusted-ID.txt")" > "$E/verify.log" 2>&1
  rc=$?
  { echo "their_proof exit=$rc last=\"$(tail -n 1 "$E/verify.log")\" id=$(tr -d ' \n' < "$R/trusted-ID.txt")"
    cmp -s "$R/in/example.req" "$CONF/example.req" && echo "their in/example.req = config example.req: yes" || echo "their in/example.req differs from config example.req"
    grep -E '^(covered:|result-v1)' "$E/verify.log" | cut -c1-300; } | tee "$E/meta.txt"
  ;;
patch)
  E=$EVB/a9-patch; mkdir -p "$E"
  [ -z "$(git -C "$P" status --porcelain)" ] || { echo "clean-room tree dirty"; exit 2; }
  git -C "$P" switch -q -c real-model || exit 2
  inc=(); for f in "${SHAPE_FILES[@]}"; do inc+=(--include="$f"); done
  git -C "$P" apply --check "${inc[@]}" "$TP/upstream-l4-small-model.patch" > "$E/apply-check.log" 2>&1; echo "apply_check_exit=$?" | tee "$E/meta.txt"
  git -C "$P" apply "${inc[@]}" "$TP/upstream-l4-small-model.patch" >> "$E/apply.log" 2>&1; echo "apply_exit=$?" | tee -a "$E/meta.txt"
  git -C "$P" add -A
  git -C "$P" commit -q -m "p13: accept the 256/32 small model shape (model-shape hunks only of zkwasm/FlashProve-L4 @ $L4SHA upstream-l4-small-model.patch, Apache-2.0)" \
    -m "Files: ${SHAPE_FILES[*]}. No kernel, verifier, protocol or format change. Upstream width/head 5120/128 kept."
  { echo "head=$(git -C "$P" rev-parse HEAD) branch=$(git -C "$P" branch --show-current)"
    git -C "$P" diff --stat HEAD~1 HEAD; echo "verifier_files_changed=$(git -C "$P" diff --name-only HEAD~1 HEAD -- verifier | wc -l)"
    git -C "$P" diff HEAD~1 HEAD > "$E/p13.diff"; } | tee -a "$E/meta.txt"
  ;;
build)
  E=$EVB/a9-build; mkdir -p "$E"
  echo "start=$(date -u +%FT%TZ) head=$(git -C "$P" rev-parse HEAD)" > "$E/meta.txt"
  (cd "$P" && verifier/build.sh > "$E/verifier.log" 2>&1); echo "verifier_build_exit=$?" >> "$E/meta.txt"
  # OUT: its own directory, so the A8 production programs (12 patches only) in prover/build/hc stay as built.
  (cd "$P/prover" && OUT=$CR/build-real /usr/bin/time -v -o "$E/default.time" ./build.sh > "$E/default.log" 2>&1); echo "default_build_exit=$?" >> "$E/meta.txt"
  { echo "end=$(date -u +%FT%TZ)"; grep -E 'Elapsed' "$E/default.time"; echo "last_line=$(tail -n 1 "$E/default.log")"
    sha256sum "$CR/build-real/hc/cp_commit" "$CR/build-real/hc/cp_prove" "$CR/build-real/hc/cp_verify"; } >> "$E/meta.txt" 2>&1
  cat "$E/meta.txt"; tail -n 8 "$E/default.log"
  ;;
run)
  RUN=${2:?run name}; E=$EVB/a9-$RUN; W=$CR/runs/$RUN; B=$CR/build-real/hc
  [ -e "$W" ] && { echo "$W exists"; exit 3; }
  mkdir -p "$E" && mkdir -m 700 "$W" && mkdir "$W/config" "$W/in" "$W/home" "$W/tmp" || exit 2
  cp "$CONF/policy.txt" "$CONF/KL.bin" "$CONF/layout.txt" "$W/config/"; cp "$CONF/example.req" "$W/in/example.req"
  { echo "run=$RUN start=$(date -u +%FT%TZ) head=$(git -C "$P" rev-parse HEAD) build=production model=TinyStories260K(L4 conversion)"
    sha256sum "$B/cp_commit" "$B/cp_prove" "$MODEL/model.gguf" "$W/in/example.req" "$W/config/policy.txt"
    /usr/lib/wsl/lib/nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader | sed 's/^/gpu_before=/'; } > "$E/meta.txt"
  /usr/lib/wsl/lib/nvidia-smi --query-gpu=timestamp,memory.used --format=csv,noheader -lms 250 > "$E/vram.csv" 2>&1 &
  S=$!
  cd "$W" || exit 2
  /usr/bin/time -v "$B/cp_commit" -weights "$MODEL" -config config -M 1 -ivk ivk -isk isk -worst-case-table worst-case.txt > cp_commit.log 2>&1; rc_c=$?
  ID=$(sed -n 's/^commitment ID: //p' cp_commit.log | tr -d ' ')
  rc_p=skipped
  if [ $rc_c -eq 0 ] && [[ $ID =~ ^[0-9a-f]{64}$ ]]; then
    /usr/bin/time -v env HOME="$W/home" TMPDIR="$W/tmp" "$B/cp_prove" -isk "$W/isk" -in "$W/in" -out "$W/out" > cp_prove.log 2>&1; rc_p=$?
  fi
  kill $S 2>/dev/null; wait $S 2>/dev/null
  { echo "cp_commit_exit=$rc_c id=$ID"; echo "cp_prove_exit=$rc_p"; echo "end=$(date -u +%FT%TZ)"
    awk -F', ' '{gsub(/ MiB/,"",$2); if ($2+0>m) m=$2+0} END {print "vram_peak_MiB=" m " samples=" NR}' "$E/vram.csv"
    for f in cp_commit cp_prove; do [ -f $f.log ] && grep -h -E 'Elapsed \(wall|Maximum resident' $f.log | sed "s/^\s*/$f: /"; done
    [ -f out/example.y ] && echo "answer_token=$(od -An -tu4 out/example.y | tr -d ' ') (L4 published: 310)"
    [ -f out/example.proof ] && stat -c 'proof_bytes=%s' out/example.proof
    echo "--- cp_commit.log tail"; tail -n 12 cp_commit.log | cut -c1-240
    echo "--- cp_prove.log tail"; [ -f cp_prove.log ] && tail -n 12 cp_prove.log | cut -c1-240; } >> "$E/meta.txt"
  cp cp_commit.log "$E/"; [ -f cp_prove.log ] && cp cp_prove.log "$E/"
  cat "$E/meta.txt"
  ;;
verify)
  RUN=${2:?run name}; E=$EVB/a9-$RUN; W=$CR/runs/$RUN
  [ "$(sha256sum "$V" | cut -d' ' -f1)" = "$EXPECT_V" ] || { echo "verifier hash mismatch"; exit 2; }
  ID=$(sed -n 's/^commitment ID: //p' "$W/cp_commit.log" | tr -d ' ')
  T=$(mktemp -d); cp -r "$W/config" "$W/ivk" "$T/"; cp "$W/in/example.req" "$W/out/example.y" "$W/out/example.proof" "$T/"
  python3 -I -c 'import sys; b=bytearray(open(sys.argv[1],"rb").read()); b[len(b)//2]^=1; open(sys.argv[2],"wb").write(b)' "$T/example.proof" "$T/bit.proof"
  python3 -I -c 'import sys; b=bytearray(open(sys.argv[1],"rb").read()); b[len(b)//2]^=1; open(sys.argv[2],"wb").write(b)' "$T/example.req" "$T/bit.req"
  python3 -I -c 'import sys,struct; v=struct.unpack("<I",open(sys.argv[1],"rb").read(4))[0]; open(sys.argv[2],"wb").write(struct.pack("<I",v+1))' "$T/example.y" "$T/other.y"
  L4ID=$(tr -d ' \n' < "$TP/runs/real-l4-v8/trusted-ID.txt")
  one() { local n=$1; shift; "$V" "$@" > "$E/verify-$n.log" 2>&1; printf '%-12s exit=%-3s last="%s"\n' "$n" "$?" "$(tail -n 1 "$E/verify-$n.log")"; }
  {
    echo "verifier_sha256=$EXPECT_V id_from_our_cp_commit=$ID"
    one honest    "$T/config" "$T/ivk" "$T/example.req" "$T/example.y" "$T/example.proof" -id "$ID"
    one proof-bit "$T/config" "$T/ivk" "$T/example.req" "$T/example.y" "$T/bit.proof"     -id "$ID"
    one req-bit   "$T/config" "$T/ivk" "$T/bit.req"     "$T/example.y" "$T/example.proof" -id "$ID"
    one y-plus-1  "$T/config" "$T/ivk" "$T/example.req" "$T/other.y"   "$T/example.proof" -id "$ID"
    one l4-id     "$T/config" "$T/ivk" "$T/example.req" "$T/example.y" "$T/example.proof" -id "$L4ID"
    one l4-ivk    "$T/config" "$TP/runs/real-l4-v8/ivk" "$T/example.req" "$T/example.y" "$T/example.proof" -id "$ID"
    echo "--- honest report lines"; grep -E '^(covered:|commitment:|proof of work:|result-v1)|hiding' "$E/verify-honest.log"
  } | tee "$E/verify.txt"
  ;;
*) echo "usage: $0 fetch | patch | build | run RUN | verify RUN"; exit 2 ;;
esac
