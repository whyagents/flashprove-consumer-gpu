# Results in full

These are the experiment write-ups exactly as recorded (paths anonymized). Raw logs and checksums: `../evidence/`.

## Answers to reviewers' questions

**Were the three identical judge builds on different machines?** No. All three builds of `cp_verify` (sha256 `7f9efc1e…4394`) were made
**on this one machine** with the same g++ 13.3, from three separate clones: the pristine judge, the clean-room verifier clone, and the copy
built into the patched tree. That shows the build is reproducible here and that the judge was not contaminated by the patched tree. It does not show
reproducibility across machines. Please report your hash in a replication report.

**Does the TinyStories commitment ID match FlashProve-L4's?** No, and it should not. `cp_commit` draws a **fresh secret seed** for every
commitment (that is what makes the weights hidden), so the commitment ID differs on every run, even on the same machine with the same
weights. Our three runs gave three different IDs (`27fae67f…`, `ecdafc84…`, `996af999…`), and L4's is `2cde2d3a…`.

**Then why is the answer token the right cross-hardware test?** Under the exact-match policy, a `YES` means the proved token is the committed
integer model's own first choice for that request. That choice depends only on the committed integers and the request, not on the seed or the
hardware. So the same weights and the same request must give the same token anywhere: L4 gave 310, and our three runs gave 310. We also
checked in both directions: **L4's published proof is accepted by our verifier**, and our own float reference picks 310 at that position
(margin 6.7 logits).

**Can the commitment itself be compared across machines?** Yes, in principle, under `-public-weights` with the same seed file. Then the
commitment is a deterministic function of the weights and the configuration. Our S2 runs confirm this on one machine: two commitments with the
same seed file were byte-identical. Comparing against another machine is part of the planned H100 run ([`CLOUD-RUNBOOK.md`](CLOUD-RUNBOOK.md)).

**Do the patches in `hiding/` preserve zero-knowledge?** That is argued patch by patch in [`HIDING.md`](HIDING.md). It is not yet verified byte for byte.

**Could any output byte depend on patches 7 or 8?**
- **Patch 7** lowers a *ceiling* (the maximum shared memory a kernel may request). It does not change any launch's request. A launch that needed more would abort the run, not compute differently.
- **Patch 8** splits a histogram into four passes instead of two. Each key falls into exactly one pass, and the output is the same array of integer counts. Integer atomic adds give the same sum in any order.

---

# Result A5: a FlashProve proof made on an RTX 5070 Ti, accepted by the unchanged upstream verifier

Session 002, 2026-11-09 (UTC). Status: **ACHIEVED for the stated scope. Not yet independently replicated
on another machine.**

## The claim, stated precisely

On one NVIDIA GeForce RTX 5070 Ti (consumer Blackwell, compute capability 12.0, 16 GB, WDDM, under
WSL2 Ubuntu 24.04), a CUDA build of FlashProve's `cp_commit` and `cp_prove`, made from upstream commit
`9e2bdd8f` plus 12 small patches (branch `exp/sm120`, head `7b849bf7`), did the following:
1. committed to the bundled 8-layer **synthetic-weight** model `target_small_f2_roomy`;
2. proved one 64-token request with the exact-match policy;
3. had that proof **accepted by the unmodified upstream `cp_verify`**, built from pristine `9e2bdd8f` on the
   same machine's CPU: exit 0, last line `YES`, `r=15 e=64 T=64 tokens=16..63`, using the commitment ID
   that our own `cp_commit` printed.

This held in **3 of 3** fresh end-to-end runs (new seed, commitment and proof each time). In each run,
**6 of 6** tampered inputs were rejected (18/18 in total).

## Label (charter rule E)

> **Superseded in part by A7 (session 003):** `zkwasm/FlashProve-L4` (2026-11-04) had already ported the CUDA
> prover to an NVIDIA L4 (sm_89), with the production build and real pretrained weights. See `docs/prior-art.md`.
> So this result is **a second, independent port**, the first one *reported* on consumer Blackwell (sm_120) / 16 GB / WSL2.
> It is weaker than the L4 work in two ways: a test build and synthetic weights. The bullets below were written before that was known.

- **Original modification and new working capability**, narrowly: the CUDA prover on consumer Blackwell
  (sm_120), with a 16 GB card that also drives the display, under WSL2.
- **Not** "the first FlashProve proof off an H100": the MLX/Metal rewrite by jp4g on an Apple M5 Pro was
  accepted by `cp_verify` on 2026-11-06 (see `docs/prior-art.md`).
- **Not** a proof about any real model. The weights are synthetic.
- Prior-art status for "first CUDA FlashProve proof on a consumer NVIDIA GPU": nothing found as of
  2026-11-09. That covers web search, all 5 upstream issues/PRs, the newest 100 forks and compares of every
  fork pushed after release. GitHub code search was **not** run (it needs authentication). Do not say "first"
  publicly until that gap is closed.

## Evidence (all in `evidence/logs/session-002/a5/`, SHA256SUMS over 142 files)

| Run | cp_commit wall | cp_prove wall | prove RSS | proof bytes | commitment ID (prefix) | honest | tampered rejected |
|---|---|---|---|---|---|---|---|
| run9 | 20.46 s | 2.39 s | 925 MB | 4,151,204 | 4cbdd099371e | 2/2 YES | 6/6 |
| run10 | 21.37 s | 2.20 s | 924 MB | 4,149,260 | ec1865bec8a7 | 2/2 YES | 6/6 |
| run11 | 21.69 s | 2.04 s | 925 MB | 4,152,724 | a814f8fd2d09 | 2/2 YES | 6/6 |

- Tamper set (`experiments/consumer-gpu/a5_verify_and_tamper.sh`):
  - one bit of the proof flipped → `NO: proof-refused`;
  - last 100 bytes of the proof cut → `NO: proof-refused`;
  - one bit of the request flipped → `NO: proof-refused`;
  - the answer token y + 1 → `NO: reply-differs`;
  - the stored example's commitment ID → `NO: model-statement`;
  - the stored example's `ivk/` → `NO: model-statement`.
- Verifier identity: sha256 `7f9efc1e86a848a3715c6cc870e465ac2a1c5e8fd1eac09e4809023de7604394`, the same
  binary as the A1 baseline that accepted upstream's stored proof. Its `result-v1 … build=93afdaf5…9595`
  equals the A1 value. The pristine checkout was clean (0 dirty entries) at every check.
- Upstream reporting lines (run9):
  - `covered: r=15 e=64 T=64 C=256 theta=256 cap=0 … positions=15..63 tokens=16..63 y=yes next-token=no policy=exact-match above-clip=0`
  - `commitment: 49 closeness rounds … binding of the weights rests on the theorem on codes (ePrint 2025/2055, Theorem 4.6), taken as given`
  - `proof of work: up to 32 bits counted in 38 rounds; with it the least round has 128.00 bits, without it 96.23 bits` (upstream: not a security level)
- GPU memory:
  - `cp_prove` itself reports `GPU memory before the first batch, GB: 4.074 of 17.094 in use` (that figure includes the desktop's share).
  - The nvidia-smi total peak was 8,794–8,811 MiB, with about 520–545 MiB in use before the run. The peak is during `cp_commit`, whose slab takes free memory by design.

## The patch set (`experiments/consumer-gpu/patches/`: JSON specs with rationale, plus `format-patch/`)

| # | File | Change | Class | Why it keeps values |
|---|---|---|---|---|
| 1 | prover/build.sh | `-arch=sm_90a` → `sm_120` | build | native SASS from nvcc 13.2.86 (an sm_90a build runs here only by driver JIT) |
| 2 | prover/prover/base.cuh | `k_ws<4,32>` → `<4,16>` | static smem 59,136 B > 48 KiB | exact integer sums, regrouped |
| 3 | hash_commitment/hf_range_windows.cuh | `COUNT_BITS` 15 → 14 | dyn smem 128 KiB | upstream's split / two-pass paths |
| 4 | engine/tiled.cuh | `TILED_STAGES` 3 → 2 | dyn smem 110,592 B | double instead of triple buffering; exact int8 MMA |
| 5 | hash_commitment/hf_commit_once.cuh | `HF_ONCE_ENGINE_ROOM` 24 → 6 GiB | memory policy | upstream: "No byte of an output file depends on this number" |
| 6 | weights_blocks/experts.cuh | `EXPERTS_IN_ONE_LAUNCH` 1 → 0 | dyn smem > 132 KB (tiled for 227 KB) | upstream's cuBLAS host-loop form: "meant to give the same sums" |
| 7 | hiding/forest_table.cuh | `h_idk<1>` attribute 128 → 64 KiB | dyn smem attribute | launches still ask for 4 << k; k = 15 would fail loudly |
| 8 | hiding/count_keys16.cuh | 2 halves → 4 quarters | dyn smem 128 KiB | each key counted once, same bins |
| 9 | engine/fold.cuh | byte-fold limit 100 → 96 KiB | dyn smem 102,400 B | upstream's field-arithmetic fallback |
| 10 | hiding/forest.cuh | `FOREST_FUSED` 1 → 0 | dyn smem 219,136 B | upstream's cuBLASLt mode; "all sums are exact" |
| 11 | hiding/forest_keys.cuh | packed table read from global, not staged | dyn smem 131,328 B | the same read-only values |
| 12 | hash_commitment/hf_keeper.cu | `pinned_room`: `cudaMallocHost`, not `cudaHostRegister` | **WSL2** | `canUseHostPointerForRegisteredMem = 0` under WSL2 |

Total: 12 files, +34/−28 lines. None of the patches touches `verifier/`, the protocol, the parameter files,
the Fiat–Shamir transcript or the model kit.

## Why a patched prover does not weaken the result

Soundness in FlashProve is a property of the verifier. A buggy prover can only produce proofs that are
rejected. Under the stated assumptions, it cannot make `cp_verify` accept a false statement. Every patch
here is judged by the **unchanged** verifier, and the tamper set shows that verifier still rejects.

## What this does NOT show

- Nothing about a real or served model. Synthetic weights only; GPT-OSS is not involved.
- **Weight hiding: not shown.** These are test builds (`./build.sh tests`), which print `THIS PROGRAM WAS BUILT
  FOR TESTS ALONE … it may hide nothing`. The verifier printed `weight hiding: NOT CHECKED BY THIS CALL` in
  `cp_commit`'s self-check. No `-test-coins` were passed: `cp_commit` drew its own seed.
- Not the production (default) build. It also refuses a GPU with > 2 GiB in use. Not run.
- Not full size (Maverick shape, 280 GB RAM), not batches, not serving.
- The **Lean** verifier was not run. The `YES` is from the C++ `cp_verify`, which is tested, not proved.
- Native Linux was not tried. Patch 12 is WSL2-specific, and it is unknown whether native Linux on this card needs it.
- No performance claim. The timings are n = 3, wall clock from `/usr/bin/time`, on WSL2, with a desktop on
  the same GPU. A published H100 replication (wakesync, PR #26) reports `cp_prove` 2.35 s and `cp_commit` 18.8 s for
  upstream's small example. That is similar, but its programs, hardware and timing method differ. Treat the
  comparison as "same order of magnitude on this tiny model", nothing more.
- The `FOREST_FUSED=0` and `EXPERTS_IN_ONE_LAUNCH=0` paths are less exercised upstream than the defaults.
  Here they produced accepted proofs, but they have not been tested beyond that.

## Reproduce

On a Windows 11 machine with an RTX 50-series GPU and WSL2 Ubuntu 24.04:
1. `apt-get install g++ make python3-pip python3-venv unzip binutils time` (as root, setup only).
2. As a normal user: clone FlashProve, check out `9e2bdd8f` into `~/work/flashprove`, and run `experiments/baseline/a1_verifier_baseline.sh` (pristine verifier).
3. `experiments/consumer-gpu/a2_install_cuda.sh` (nvcc 13.2.86 via pip).
4. `a3_setup_branch.sh`, then `git am patches/format-patch/*.patch` onto the worktree, or apply the JSON specs in order with `patches/apply_patch.py`.
5. `BUILD_TARGETS=tests a4_iterate.sh runN` (about 10 min build), or `a3_build.sh`.
6. `a3_run_small.sh runN`, then `a5_verify_and_tamper.sh runN`.

Step 4 note (from A6): build the verifier in the patched tree too (`verifier/build.sh`) before `./build.sh tests`;
`cp_commit`'s build copies `../bin/cp_verify` beside it for its self-check.

## Independent checks still owed (before any public claim)

1. Replication on a second machine or by a second person, starting from the published patch set.
   **A6 (session 003): replicated on the same machine** from the patch files alone (clean clone, `git am`, a separate
   nvcc install, a separately built verifier): 3/3 `YES`, 18/18 tampers rejected. See `RESULT-A6.md`.
2. ~~The Lean verifier on one of these proofs.~~ **Not possible:** upstream's Lean `verify` covers the full-size format
   only and rejects the small example's files (`lean/THEOREM.md:303`). So: never call these proofs "Lean-verified".
3. GitHub code search and a direct look for RTX 40/50 reports, to close the prior-art gap.
4. Optionally: native Linux on this GPU, to see whether patch 12 is needed there.

---

# Result A6: clean-room replication, and the Lean verifier's reach

Session 003, 2026-11-09 (UTC). Two questions, two answers:

| Question | Answer | Label |
|---|---|---|
| Can the A5 result be rebuilt from the patch files alone, with nothing else from the A4/A5 tree? | **Yes.** 3 of 3 fresh runs `YES`; 18 of 18 tampers rejected | original experiment (replication, same machine) |
| Can upstream's Lean verifier check one of our proofs? | **No, by design.** Upstream's Lean `verify` covers the full-size (Maverick-shape) format only and rejects the small example's files | finding from upstream's documents (not run) |

## 1. Clean-room replication

### What was isolated
- **Source.** A fresh clone (`git clone --no-local`, so objects are copied, not hard-linked) of the pristine checkout at
  `9e2bdd8f`. Then `git am` of the 12 files in `experiments/consumer-gpu/patches/format-patch/`, the artifacts that
  would be published. `git am` exit 0. The resulting tree is `c4a72cd21e4f…`, **byte-identical to `exp/sm120` @
  `7b849bf7`'s tree**, so the patch files carry the whole change, with nothing left behind in the A4 worktree. The
  diff stat is the same (12 files, +34/−28), and 0 files under `verifier/` changed.
- **Toolchain.** A second, separate install of nvcc 13.2.86 + cuBLAS (`pip --no-cache-dir`, 957 MB) under
  `~/cleanroom/`, not the A2 copy. upstream's `build.sh` value check passed: `compiler_sample: 324 values are the same on the GPU and on the CPU`.
- **Judge.** A third clone at the pin, with no patches, whose `verifier/build.sh` gave a `cp_verify` with sha256 `7f9efc1e…4394`.
  That is **bit-identical to the A1 binary**, so the verifier build is reproducible here. Each proof was judged by the
  clean-room verifier (inside upstream's example script) and again by the A1 binary (`a5_verify_and_tamper.sh`).
- **Not isolated.** It ran on the same machine, the same WSL2 distro and driver, the same Python, and it was carried out
  by the same agent. Upstream's sources come from the same local clone, but every object is fixed by the commit hash `9e2bdd8f`.

### Results

| Run | commitment ID (from our `cp_commit`) | proof bytes | y | cp_commit wall | cp_prove wall | cp_prove RSS | verdict | tampered rejected |
|---|---|---|---|---|---|---|---|---|
| cr1 | `565c612e40cf645e5f72f86fc44a5b874a2bf8a67f8f70858d85f5257b7d3a2a` | 4,159,780 | 284 | 20.00 s | 2.28 s | 949 MB | exit 0, `YES` (×3) | 6/6 |
| cr2 | `0f85de4c04e72978d236fee2cefd7bc186534c64559ac18972abf09951c0aafe` | 4,150,372 | 284 | 23.15 s | 2.27 s | 946 MB | exit 0, `YES` (×3) | 6/6 |
| cr3 | `4e08f3432946dc92129ea6f51a7cb81aa0b12f97701355bb8d89b48f310f3468` | 4,150,172 | 284 | 24.96 s | 1.99 s | 947 MB | exit 0, `YES` (×3) | 6/6 |

- In each run, `YES` came three times: once from the clean-room verifier inside `run_target_example.sh`, and twice from the A1 binary.
- Each run used a new seed, a new commitment ID and a new proof. The answer token y = 284 matches run9: the same model shape and the same request.
- cr1's report lines:
  - `covered: r=15 e=64 T=64 … tokens=16..63 y=yes policy=exact-match above-clip=0`;
  - `commitment: 49 closeness rounds … (ePrint 2025/2055, Theorem 4.6), taken as given`;
  - `proof of work: up to 32 bits counted in 38 rounds; with it the least round has 128.00 bits, without it 96.23 bits`;
  - `result-v1 status=0 claim=exact-match … build=93afdaf5…9595`, the same `build=` value as A1 and A5.
- Tampers, the same set as A5, with the same answer every time:
  - proof bit, proof cut short and request bit → `NO: proof-refused`;
  - y + 1 → `NO: reply-differs`;
  - the stored example's ID and the stored example's `ivk/` → `NO: model-statement`.
- The prover binaries' sha256 values differ from A5's (`cp_commit` `223f8752…` vs `699be8b7…`). That was expected and is not a finding: the binaries carry a run path to their own CUDA library directory.

### One stumble (recorded, not hidden)
The first clean-room build failed at `cp_commit` with `build.sh: cp_commit wants a cp_verify beside it, a copy of
../bin/cp_verify: build the verifier first`. My script had built the verifier only in the separate judge clone. The fix
was upstream's own order: run `verifier/build.sh` in the prover's tree too (that copy is used only for `cp_commit`'s self-check), then
build again. No source or option changed. The log of that attempt is `evidence/logs/session-003/a6/a6-build-attempt1-console.txt`.
**This belongs in the reproduction steps:** build the verifier in the patched tree before `./build.sh tests`.

## 2. The Lean verifier on our proofs: out of scope by design

The source is upstream @ `9e2bdd8f`:
- `lean/THEOREM.md:300-303`: the theorem holds for "one fixed proof format and model size … **The small example's
  files are out of scope: `verify` rejects them.**"
- `lean/IntegerModel/Reply.lean:79-86`: the integer model is defined at `ppref`, Maverick's sizes, which is "its only size, but for the number of tokens".
- `tools/lean-verify/README.md:129-130`: "On the small examples the command gives no verdict: it wants a request file of 4,104 bytes."

Our requests are 264 bytes, for `target_small_f2_roomy` at T = 64. So a Lean run on our proofs could only end with
`NO VERDICT` or `REJECT`, and neither would say anything about our port. What it would take to Lean-check a GPU proof from this card:
- a **full-size** commitment and proof;
- upstream's full-size route needs about 280 GB of host RAM for `cp_commit`, and this machine has 32 GB (15 GB visible to WSL2);
- so it is not feasible here. A full-size proof from consumer hardware would be a separate, much larger project.

**Not done, and why:** running the Lean verifier on upstream's *stored* full-size example. That would only show that Lean
runs on this machine; it would test nothing about the port. It would cost:
- about 7–11 GB of package downloads and about 26 GB of disk;
- 9–16 GB of RAM per call, which would need raising WSL2's memory cap in `.wslconfig` (not approved);
- 20–40 min per call.

It could be useful later, as a baseline for anyone who wants a Lean-checked full-size proof.

**Consequence for the claim:** the `YES` on the consumer-GPU proofs rests on the C++ `cp_verify` (tested, not proved)
and has to stay worded that way. "Lean-verified" must not appear in any claim about these proofs.

## What A6 changes

- "Replication from the published patch set" is now done on the same machine, from the patch files alone.
- A second machine or a second person has still not replicated it. The charter's bar for a public claim
  (independent replication) is not met yet.
- The Lean check is removed from the to-do list for this claim, with the reason above, and replaced by a wording rule.

---

# Results A8 and A9: production build, and a real pretrained model, on the RTX 5070 Ti

Session 004, 2026-11-09 (UTC). These close the two gaps between our A5 result and the prior art
`zkwasm/FlashProve-L4`: there, a production build and real weights; here before, a test build and synthetic weights.

| | A8: production build | A9: real model (TinyStories260K) |
|---|---|---|
| Prover source | clean-room tree, upstream `9e2bdd8f` + our 12 patches (`cee61ddf`) | the same + p13: the 6 model-shape files from L4's patch (`aa59d930`, branch `real-model`) |
| Build | `./build.sh` (default/serving), 8 min 49 s, exit 0 | `OUT=~/cleanroom/build-real ./build.sh`, 8 min 39 s, exit 0 |
| Weights | upstream's synthetic `made-up-blocks`, `target_small_f2_roomy` | TinyStories260K as converted by L4 (`model.gguf` sha256 `36d8c24c…`, matches their MANIFEST) |
| Request | upstream's `own_choices.req` (T = 64) | L4's `example.req` (T = 256), the same bytes as theirs |
| Claim (verifier's `covered:`) | `r=15 e=64`, tokens 16..63 + y, exact match | `r=255 e=256`, next token, exact match |
| Fresh runs accepted | **3/3** (exit 0, `YES`) | **3/3** (exit 0, `YES`) |
| Answer token | 284, 284, 284 | **310, 310, 310** (L4 published 310) |
| Tampered inputs rejected | **18/18** | **15/15** |
| cp_commit / cp_prove wall | 15.6–25.7 s / 2.06–2.20 s | 4.8–5.1 s / 1.96–2.10 s |
| Proof size | 4.15–4.16 MB | 5.60–5.61 MB |
| GPU memory | prover's start: 1.335 GB in use (limit 2 GiB); nvidia-smi total peak about 9.4 GiB | prover's start: under the limit; peak about 9.47 GiB |

Judge in every case: the A1 `cp_verify` (sha256 `7f9efc1e…4394`, built from pristine `9e2bdd8f`), with the
commitment ID printed by **our** `cp_commit`. The copies of `cp_verify` that both builds put beside `cp_commit` are bit-identical to it.

## Commitment IDs (from our cp_commit)
- pr1 `9de61cbbfd1ec4520840dbda5894107c9992e9e8c4ff33b095822c49e033449a`
- pr2 `98931736c616a77f6ea792debe931a565a1b591cb9d2526230e3b2ceb7c9e379`
- pr3 `e42c72a2d328b02a8759e03ca4ba5a2f40286faac07c17c63767499f22863840`
- ts1 `27fae67f46a381433eb60103fd64922a1188dceaf219a5aec406444fb388f410`
- ts2 `ecdafc8426511e4c18420c69585da0579fe6fe9362f6fb2f3b23a78ee98fd37e`
- ts3 `996af999b20828b056b01eba21a41f1e83b71194650ed44dabf0d9ab73d44710`

The report lines of ts1:
- `covered: r=255 e=256 T=256 … positions=255..255 tokens=none y=yes next-token=yes policy=exact-match above-clip=0`
- `commitment: 47 closeness rounds … (ePrint 2025/2055, Theorem 4.6), taken as given`
- `proof of work: up to 8 bits counted in 40 rounds; with it the least round has 128.00 bits, without it 120.31 bits`
- `result-v1 status=0 claim=next-token … build=93afdaf5…9595`

Upstream says none of these bit counts is a security level.

## Tamper sets
- **A8**, the same six as A5: proof bit flipped and proof cut short → `proof-refused`; request bit flipped → `proof-refused`;
  y + 1 → `reply-differs`; the stored example's ID and the stored example's `ivk/` → `model-statement`.
- **A9**: proof bit and request bit → `proof-refused`; y + 1 → `reply-differs`; **L4's own commitment ID** → `model-statement`; **L4's own `ivk/`** → `model-statement`.

## Is it really the production build?
- The production programs refuse a GPU with more than 2 GiB in use (`common/common.h:55`). At 3.3 GiB they were not run.
  The user closed desktop apps, and then the prover reported `1.335 GB are in use at the start`. The check was not patched.
- No production log contains the test build's banner (`… BUILT FOR TESTS …`). The same grep finds it twice in a test-build log (cr1), so the check can see it.
- No `-test-coins` was passed: `cp_commit` drew its own seed each time.
- `weight hiding: NOT CHECKED BY THIS CALL (it rests on how the commitment was made)`: `cp_verify` never checks
  hiding. The production build is the one whose commitments are *made* to hide. That hiding holds is upstream's
  argument (`docs/how-hiding-is-checked.md`), not something these runs show.

## Also done: their proof, our verifier
L4's published proof (`runs/real-l4-v8`, ID `2cde2d3a…` from their committer) is **accepted by our A1
`cp_verify`**: exit 0, `YES`, `r=255 e=256 T=256`, exact match. That re-checks their result on the verifier side, on other hardware and OS.

## Labels (charter rule E)
- **A8: original experiment.** The port works in the production build, on a desktop GPU, once the desktop's GPU memory use is under 2 GiB.
- **A9: replication of L4's real-model result on different hardware** (Ada L4 → Blackwell RTX 5070 Ti, Linux VM → Windows/WSL2),
  using **their** model conversion and reader hunks, with **our** independent shared-memory port and WSL2 fix. Every proof's answer token equals their published token.
- **Combined, the narrow new statement:** production-build FlashProve proofs of a real pretrained model's next token,
  made on a consumer GeForce Blackwell GPU (16 GB) under WSL2, accepted by upstream's unchanged C++ verifier.
  "First" is not claimed: code search was skipped.

## A10 (session 004): our own float check of the proved token

`experiments/consumer-gpu/a10_float_reference.py`: a TinyStories260K forward pass written here from llama2.c's
model definition, standard library only (no numpy, no L4 code), float64.
- **Checkpoint identity:** `stories260K.bin` sha256 `b0a507e7…2696` and `tok512.bin` `037cb335…c312` equal **Hugging Face's
  own LFS hashes** for `karpathy/tinyllamas` (repo head `0bd21da7`). The file is read to its last byte (1,056,540 of 1,056,540).
- **Validation:** greedy decoding from BOS reproduces Karpathy's published temperature-0 sample word for word, up to "…but it
  was too high" (60 tokens; smallest top-2 logit margin 0.133).
- **Result:** after the exact request we proved (sha256 `cf17bc02…`, T = 256, the 64-token story prefix ×4, r = 255),
  the float model's next token is **310** (`ily`; the request ends in "L"). The runner-up is 294 (`at`), with a **logit margin of
  6.71**, far beyond any float32/float64 difference.
- **So:** the proved integer token equals the original float model's greedy token at this position, **by our check**.
- **Not done:** upstream's Python integer model (`integrations/vllm/integer_model`). It needs PyTorch, and its reader still has
  the 5120/128 limit that L4 did not patch. Agreement at other positions is still only L4's record (63/64).

## What this does NOT show
- **What "the real model" means.** The proof is about the committed integers: TinyStories260K's weights converted by L4's rule,
  padded to width 256 with zero experts, run as upstream's integer model (Llama 4 style). It is not the floating-point model.
  **A10 checked the proved position ourselves:** the float model also gives 310, with margin 6.71. L4's record that
  their integer reference agrees with greedy decoding at 63 of 64 positions remains theirs and unchecked.
- The conversion was not redone here. The `model.gguf`, `wsums.txt` and the config are L4's files, checked only against their own manifest.
- One request, one next-token claim per proof (`tokens=none`). n = 3 per experiment. No performance claim.
- Not Lean-checked (out of scope by design, A-007). The C++ `cp_verify` is tested, not proved.
- Tiny model (260K parameters; 4.4M stored elements after padding). This says nothing about whether a larger model fits in 16 GB.
- Native Linux was not tried. The WSL2 pinned-memory patch (p12) is still in the tree. That question needs bare-metal
  Linux: under WSL2 the GPU always goes through Windows' graphics driver, so WSL2 cannot answer it. Status: results are WSL2-only.

---

# Result A13/S2: Maverick-width layers on a 16 GB consumer GPU (session 004, 2026-11-09)

**Question:** do FlashProve's production programs, with our 12-patch port, commit to, prove and verify a model at **Llama 4 Maverick's
full attention width** on the RTX 5070 Ti (16 GB, WSL2)?

**Configuration:** upstream `prover/examples/target_small_file_f2`, unchanged:
- **shape:** d 5120, H 40, G 8, dh 128, i.e. Maverick's width, heads and head size;
- **smaller than Maverick:** L 4 layers, NE 16 experts, f 2048 / fe 1024, V 2048;
- **window:** T 256 (lt 8); table line `8 26 …`.

**Weights:** synthetic, written by upstream's `make_model` from the folder's model.txt (2 GGUF files, 528,941,088 bytes; made in 4.5 s on the CPU).

**Procedure:** upstream's **unchanged** test `prover/tests/record_on_public_weights.sh`, run with our production programs (A8 build: cp_commit
`1b39a3d9…`, cp_prove `0a64a28d…`, cp_verify `7f9efc1e…`, which is bit-identical to the A1 judge). The test makes 9 calls:
1. commit under a drawn seed (hiding mode);
2. commit with `-public-weights`;
3. call 2 again, which must give the same bytes;
4. prove without the option, which must refuse;
5. prove with the option;
6. verify (→ YES);
7. verify under another ID (→ NO);
8. prove on call 1's commitment;
9. verify that (→ YES).

## Results (n = 3)

| | s2-1 | s2-2 | s2-3 |
|---|---|---|---|
| Test verdict | 1 "not as expected" (**our wrapper's artifact**, see below) | **all as expected** | **all as expected** |
| Call 1: commit, drawn seed | 42.65 s, RSS 1.46 GB | 45.10 s | 42.45 s |
| Calls 2, 3: commit, public weights | 43.0 / 39.2 s; the two key directories identical | 43.3 / 38.0 s; identical | 43.1 / 44.9 s; identical |
| Call 8 → 9: prove (drawn) → verify | 3.22 s, RSS 2.08 GB → **YES** | 6.12 s → **YES** | 3.42 s → **YES** |
| Call 5 → 6: prove (public) → verify | 3.22 s → **YES** | 3.32 s → **YES** | 5.27 s → **YES** |
| Call 7: verify under another ID | `NO: model-statement` | the same | the same |
| Call 4: prove a public commitment without the option | refused, `p258 end 1 cp-isk-seed-public` | refused (as expected) | refused (as expected) |
| Proof sizes | 5,943,652 / 5,943,604 B | 5,947,348 / 5,946,964 B | 5,940,052 / 5,950,964 B |
| nvidia-smi total GPU peak (250 ms samples) | 15,820 MiB | 15,862 MiB | 15,859 MiB |
| GPU in use before | 1,038 MiB | 558 MiB | 530 MiB |
| Whole test, wall clock | 2:16 | 2:18 | 2:22 |

Commitment IDs from our cp_commit (drawn / public):
- s2-1 `f2bcacb8b937586408bb03d8afaac04a13a3e6b46e75d8d8fbc2eaf6a7e0e685` / `5d951f792f3fe286cf3fcd987e5c8d23e3e1dbf0543b2857ccfbec0622dcbc47`
- s2-2 `41aabe8e47e1032f436f99919ef688e5e3e866c70c12e5f30cb05b2e765592de` / `6d47f0ee0ecc6d364979e202a03e2aa347f236d1629ff020ae3cb65cd509f8f4`
- s2-3 `7e535a382c506791bb546a755509f814e7ff83f82e10d84cff80fba7ce0046ec` / `5d580d66167058b78ce5d45e2d074d7d6e457672485de9e17a1e82ff59f314e3`

**The s2-1 "not as expected", explained.** The test reads the *last line* of call 4's log. Our measurement prefix
(`GPU_RUN="/usr/bin/time -v"`) appended time's report to that log, so the last line became `Exit status: 1`. The line cp_prove itself
printed just before that is exactly the expected `p258 end 1 cp-isk-seed-public`. Runs 2 and 3 send time's report to a separate file
and pass completely. That is a fault in our instrumentation, not in the program.

**GPU memory, read with care.** The ~15.5 GiB peak (15,820–15,862 MiB) occurs during cp_commit. The commit slab is sized from **free** GPU memory by design
(`hf_commit_once.cuh`: "the free memory less 2 GiB …"), so the peak shows what the program *took*, not what it *needs*.
The prove phase's own peak was not separated yet (next: split the VRAM trace by call windows, or cap with `-gpu-memory`).

## Labels and limits
- **Original experiment, positive.** The production build of our port handles Maverick-width layers (the widest matrices of the full model)
  on a 16 GB consumer card. It commits in about 40 s and proves in 3–6 s, and the unchanged verifier accepts. Both the hiding mode and the public-weights mode work.
- **Not the full model:** 4 layers, not 48; 16 experts, not 128; FFN 2048, not 16,384; vocabulary 2,048, not 202,048; T 256, not 1,024.
  Host RAM peaked at about 2.1 GB, far from the full model's about 280 GB.
- Synthetic weights. One request (synthetic tokens, a next-token claim). n = 3, wall clock, WSL2. No performance claim.
- Weight hiding: the drawn-seed mode ran, but nothing here tests what is hidden (upstream's own caveat in the test header).

## What it tells the scaling question
Width is **not** the limit on this card. The next axes are batch size (S1) and depth or vocabulary; the latter need a parameter file for the
new shape, which no upstream tool writes (upstream does ship the scale fit and the layout tool). Evidence: `evidence/logs/session-004/a13/`.

*Corrected 2026-11-12. This paragraph first said that upstream ships no tools for scale files.*

---

# Results A13/S1 (batch scaling), A15 (determinism), A16 (upstream lookup tests): session 004, 2026-11-09

## A13/S1: batch size on a 16 GB consumer GPU
**Method:** upstream's **unchanged** `driver/measure_rate.py`.
- It runs the production `cp_prove` as a spool service for 3 full batches of B requests.
- It notes each batch's release from outside, and samples GPU memory once a second.
- It then checks **every** proof with a separate `cp_verify` (our A8 build's copy, bit-identical to the A1 judge). It prints no rate unless every proof was accepted.
- Requests: windows of synthetic tokens, a next-token claim each. Programs: the A8 production build (12 patches).

| B (requests per batch) | **small** (target_small_f2_roomy: d 512, L 8, T 64) rate, tok/s | s per request | GPU peak (MiB, total incl. ~660 desktop) | cp_prove host RSS (MiB) | **Maverick width** (target_small_file_f2: d 5120, H 40, L 4, T 256) rate, tok/s | s per request | GPU peak (MiB) | RSS (MiB) |
|---|---|---|---|---|---|---|---|---|
| 1 | 59.57 | 1.074 | 5,693 | 964 | 91.69 | 2.791 | 7,942 | 2,068 |
| 4 | 97.74 | 0.654 | 5,950 | 1,092 | 266.46 | 0.960 | 8,395 | 2,241 |
| 8 | 94.87 | 0.674 | 6,198 | 1,206 | 296.80 | 0.862 | 8,655 | 2,428 |
| 16 | 114.16 | 0.560 | 6,259 | 1,400 | 279.19 | 0.916 | 8,782 | 2,714 |
| 32 | 103.04 | 0.621 | 6,487 | 1,759 | 283.55 | 0.902 | 9,084 | 3,165 |
| **64 (max)** | 110.68 | 0.578 | **6,902** | 2,479 | 294.94 | 0.867 | **9,554** | 4,234 |

- **Every proof accepted: 375/375 (small) and 375/375 (Maverick width).** No request failed; every run's exit code was 0.
- **64 is the largest batch the parameter files allow** (`slots 64`), and it fits with headroom. At Maverick width the GPU peaks at 9.3 GiB (9,554 MiB)
  while proving (including the desktop's ~0.66 GiB), leaving about 6.6 GiB free.
- The rate is measure_rate's definition: B × T tokens divided by the mean interval between batch releases. Only 2 intervals per point, so the numbers are noisy.
  **No performance claim:** upstream's H100 figure (111 tok/s at batch 24) is for the full 48-layer Maverick, so it is not comparable.
- Commitments: small `00b47919634d8a2c…` (fresh, production); Maverick width `7e535a382c506791…` (S2 run s2-3, hiding mode).

## A15: determinism under fixed test seeds (groundwork for the byte-identity test)
**Method:** test build (12 patches), `target_small_f2_roomy`, `made-up-blocks`, upstream's `own_choices.req`. `cp_commit -test-seed` and `cp_prove -test-coins` used
fixed 32-byte files (public test seeds, synthetic weights only). The run was done twice into fresh directories.

| file | run a | run b |
|---|---|---|
| commitment ID | `4942be953206913cf3c97c443df610f7ed9c03c0bc1b99437c17c2a11095cfb6` | identical |
| ivk/key.bin | `69f94db22375a925…0751` | identical |
| ivk/leaf/0.bin | `64a4fb799ccd54c5…ba14` | identical |
| out/example.proof | `152b7bf02689e62f…3e77` | identical |
| out/example.y | `871cd8edd0dbd8de…98fb` (token 284) | identical |
| A1 judge | exit 0, `YES` | exit 0, `YES` |

**Byte-deterministic on this card.** The same seed files and inputs on unmodified upstream (an H100) should therefore reproduce these exact hashes, if no patch changes an output byte.
Those hashes are the reference for the planned comparison (docs/CLOUD-RUNBOOK.md in the public repo).

## A16: upstream's own GPU test of the lookup forest (`prover/hiding/`, touched by patches 7, 8, 10, 11)
**Method:** SUITE.md rows `build.forest_lookup_test`, `build.npsc_checks` and `gpu.forest_lookup_test`, run as written. The build was made in a worktree at the
12-patch commit `cee61ddf` (so with `FOREST_FUSED=0`), for sm_120. The checker runs the **verifier's** functions on the files. We also ran
`psc_rows.sh data_cheats`: malicious provers that the checker must refuse.

| Check | Expected (SUITE.md) | Got |
|---|---|---|
| forest_lookup_test | `10 of 10 groups run and written` | **10 of 10 groups run and written** |
| forest_lookup_check | `10 of 10 groups passed` | **10 of 10 groups passed** |
| field sanity line | `0 - 1 = 0xffffffff00000000` | the same |
| cheats: crossed / key / multiplicity | (not in SUITE.md) | **2/2, 8/8, 8/8 cheating provers' files refused** |

**Reading:** the patched lookup forest (including the non-fused `FOREST_FUSED=0` path that patch 11 selects) produces lookup proofs that the
verifier's functions accept for all 10 test groups, and the checker still refuses all 18 cheats. This is upstream's correctness test of
the lookup argument. **It is not a test of hiding, and not a byte comparison with unpatched code.** The byte comparison is the planned H100 step.

## Labels
- S1: original experiment. A15: original experiment (a prerequisite). A16: upstream's own test, reproduced on new hardware with our patches.
- One machine, WSL2. Synthetic weights.
