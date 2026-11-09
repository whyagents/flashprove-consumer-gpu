# Results in full

These are the experiment write-ups exactly as recorded (paths anonymized). Raw logs and checksums: `../evidence/`.

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
