#!/usr/bin/env bash
# Track A / A5: independent check of a proof made on the RTX 5070 Ti by the exp/sm120 prover.
#  1. The PRISTINE cp_verify (~/work/flashprove @ 9e2bdd8f, sha256 checked against the A1 baseline)
#     is run directly, with the commitment ID that OUR cp_commit printed (AGENTS.md: never from the proof's files).
#  2. Tampered copies (in a scratch dir; the originals are not touched) must all be rejected.
# usage: a5_verify_and_tamper.sh RUN   (work dir ~/work/a3/RUN from a3_run_small.sh)
set -u
RUN=${1:-run9}
W=${WBASE:-$HOME/work/a3}/$RUN   # A6 clean room sets WBASE; the verifier stays the A1 one
EV=$HOME/work/evidence/a5-$RUN
J=${JUDGE:-$HOME/work/flashprove}          # the PRISTINE upstream checkout at 9e2bdd8f (the judge)
V=${V:-$J/bin/cp_verify}
# Our build's hash; another compiler may give another binary: then set EXPECT_V to the hash of YOUR pristine build.
EXPECT_V=${EXPECT_V:-7f9efc1e86a848a3715c6cc870e465ac2a1c5e8fd1eac09e4809023de7604394}
STORED_ID=$(cat "$J/examples/accepted-proof/ID.txt")
mkdir -p "$EV"
got_v=$(sha256sum "$V" | cut -d' ' -f1)
[ "$got_v" = "$EXPECT_V" ] || { echo "cp_verify hash $got_v != A1 baseline $EXPECT_V"; exit 2; }
[ -z "$(git -C "$J" status --porcelain)" ] || { echo "pristine checkout dirty"; exit 2; }
ID=$(sed -n 's/^commitment ID: //p' "$W/cp_commit.log" | tr -d ' ')
[[ $ID =~ ^[0-9a-f]{64}$ ]] || { echo "no commitment ID in cp_commit.log"; exit 2; }
{
  echo "run=$RUN date=$(date -u +%FT%TZ) verifier_sha256=$got_v pristine_head=$(git -C "$J" rev-parse HEAD)"
  echo "commitment_id_from_our_cp_commit=$ID"
  echo "stored_example_id=$STORED_ID (must differ)"
  sha256sum "$W/out/example.proof" "$W/out/example.y" "$W/in/example.req" "$W/ivk/key.bin"
  stat -c '%n %s bytes' "$W/out/example.proof"
  od -An -tu4 "$W/out/example.y" | sed 's/^/y_as_u32=/'
} > "$EV/meta.txt"

verify() { # name config ivk req y proof id -> one result line
  local name=$1; shift
  local log="$EV/verify-$name.log"
  /usr/bin/time -f "%e s %M kB" -o "$EV/verify-$name.time" "$V" "$@" > "$log" 2>&1
  local rc=$?
  printf '%-16s exit=%-3s last="%s" time=%s\n' "$name" "$rc" "$(tail -n 1 "$log")" "$(cat "$EV/verify-$name.time")"
}
T=$(mktemp -d)
cp -r "$W/config" "$W/ivk" "$T/"; cp "$W/in/example.req" "$W/out/example.y" "$W/out/example.proof" "$T/"
flip() { python3 -I -c 'import sys; p=sys.argv[1]; o=int(sys.argv[2]); b=bytearray(open(p,"rb").read()); i=o if o>=0 else len(b)//2; b[i]^=1; open(sys.argv[3],"wb").write(b)' "$@"; }
flip "$T/example.proof" -1 "$T/bit.proof"
head -c -100 "$T/example.proof" > "$T/short.proof"
flip "$T/example.req" -1 "$T/bit.req"
python3 -I -c 'import sys,struct; v=struct.unpack("<I",open(sys.argv[1],"rb").read(4))[0]; open(sys.argv[2],"wb").write(struct.pack("<I",v+1))' "$T/example.y" "$T/other.y"
{
  echo "--- honest (expected: exit 0, YES)"
  verify honest      "$T/config" "$T/ivk" "$T/example.req" "$T/example.y" "$T/example.proof" -id "$ID"
  verify honest2     "$T/config" "$T/ivk" "$T/example.req" "$T/example.y" "$T/example.proof" -id "$ID"
  echo "--- tampered (expected: non-zero exit, a NO line)"
  verify proof-bit   "$T/config" "$T/ivk" "$T/example.req" "$T/example.y" "$T/bit.proof"     -id "$ID"
  verify proof-short "$T/config" "$T/ivk" "$T/example.req" "$T/example.y" "$T/short.proof"   -id "$ID"
  verify req-bit     "$T/config" "$T/ivk" "$T/bit.req"     "$T/example.y" "$T/example.proof" -id "$ID"
  verify y-plus-1    "$T/config" "$T/ivk" "$T/example.req" "$T/other.y"   "$T/example.proof" -id "$ID"
  verify wrong-id    "$T/config" "$T/ivk" "$T/example.req" "$T/example.y" "$T/example.proof" -id "$STORED_ID"
  verify other-ivk   "$T/config" "$J/examples/accepted-proof/ivk" "$T/example.req" "$T/example.y" "$T/example.proof" -id "$ID"
} | tee "$EV/results.txt"
grep -E '^(covered:|commitment:|proof of work:|result-v1)' "$EV/verify-honest.log" > "$EV/honest-report-lines.txt"
cat "$EV/meta.txt"; cat "$EV/honest-report-lines.txt"
