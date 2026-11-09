# The four patches that touch `prover/hiding/`, and why hiding should be unaffected

**The question a reviewer should ask.** In FlashProve, *soundness* lives in the verifier: a modified prover can only produce
proofs that are rejected, and every proof here is judged by the unchanged upstream `cp_verify`. *Zero-knowledge* (weight hiding)
lives in the **prover**. A `YES` from the verifier says nothing about whether the masks are still there. Upstream itself notes that,
by a reading of its code, one self-check in `cp_commit` is all that stands between a fault that loses every pad and a public file
without pads.

Four of our 12 patches touch files under `prover/hiding/`. Here is, patch by patch, why we expect no output byte to change, and so no
change to hiding. **This is an argument from the code and from upstream's own statements, not a byte-for-byte verification.**
How we plan to verify it is at the end.

## What `prover/hiding/` contains
Despite its name, the patched files implement the **lookup argument** (`Forest`: product trees over lookup keys and table rows;
`hiding/forest.cuh`, header). Values are hidden there by sumchecks on masked values, and the masks come from the transcript and
the coin derivation (`prover/hiding/transcript.cuh`, `blocks/coins/`). **None of the patches touches** the transcript, the coin or seed
derivation, the pads, the mask sampling, or any file outside the kernels named below.

Upstream states the property that matters directly (`prover/hiding/forest.cuh`, lines 11–12):
> "Storage, lanes (parallel streams) and the choice of kernels do not change the proof's bytes."

## Patch by patch

| Patch | Change | Can an output byte depend on it? |
|---|---|---|
| **0007** `hiding/forest_table.cuh` | The *maximum* dynamic shared memory allowed for kernel `h_idk<1>` goes from 131,072 to 65,536 B. Launches are unchanged: they still ask for `4 << k` bytes. | **No.** An attribute is a ceiling, not an input. Every launch with k ≤ 14 runs the identical kernel with the identical request. A launch with k = 15 would now **fail loudly** (`CK` aborts the run); it cannot run differently. No configuration we ran reached k = 15, since every run completed. |
| **0008** `hiding/count_keys16.cuh` | The key histogram is built in **4 passes of 16,384 bins** instead of 2 passes of 32,768 bins. Each pass counts only the keys whose top bits select it, then adds its bins into the same output array. | **No.** Each key falls in exactly one quarter, as it fell in exactly one half before. The output is the same array of integer counts. The additions are integer `atomicAdd`s, so their order cannot change a sum. |
| **0010** `hiding/forest_keys.cuh` (`Form<PackedSrc>`) | A read-only packed table (2^16 entries of 16 bits) is **read from GPU global memory** via `__ldg`, instead of being staged into shared memory first. A barrier is kept where the staging function used to end with one. | **No.** The same values are read: the table is never written during the kernel. Only where the bytes live changes, which upstream's header calls "storage". |
| **0011** `hiding/forest.cuh` | `FOREST_FUSED` 1 → 0. The Gram passes write their digits to GPU memory and multiply them with cuBLASLt, instead of using the fused kernels (tiled for sm_90; one asks for 219,136 B of shared memory). | **No, by upstream's own design.** `FOREST_FUSED=0` is a mode upstream supports (it can be set with `-DFOREST_FUSED=0`). Its sums are exact integer products, and upstream says the choice of kernels does not change the proof's bytes. One caveat: no test in upstream's suite runs this mode; only a benchmark flips it. |

The other eight patches are outside `hiding/`. Of those, the ones that change computation regroup exact integer sums (patches 2, 3, 4, 9),
switch to an upstream alternative path (6), or change memory policy or placement (5, 12). See the README's patch table.

## Done so far (2026-11-09)
- **Upstream's own GPU test of the lookup forest passes with our patches on sm_120** (SUITE.md row `gpu.forest_lookup_test`):
  `10 of 10 groups run and written`, `forest_lookup_check: 10 of 10 groups passed`. The checker runs the **verifier's** functions.
  Upstream's malicious-prover tests (`psc_rows.sh data_cheats`) are all refused: crossed 2/2, key 8/8, multiplicity 8/8.
  This tests the lookup argument's correctness, including the `FOREST_FUSED=0` path. It does not test hiding.
- **Determinism:** under fixed test seeds, two runs of the patched test build give byte-identical key, leaf and proof files
  (reference hashes in [`CLOUD-RUNBOOK.md`](CLOUD-RUNBOOK.md)). So a byte comparison with unmodified upstream is possible.

## How we will verify it (planned)
Under a fixed test seed (`-test-coins`, test build), FlashProve's outputs are expected to be deterministic. The plan:
1. **On this card:** check that two runs with the same seed give byte-identical keys and proofs.
2. **On a rented H100 running *unmodified* upstream:** repeat with the same seed and inputs.
3. **Compare.** Byte-identical files would show that no patch changes any output byte, masks included. That would settle the hiding
   question for these configurations.

Until then, the README's limits say: *"four patches touch the hiding module; preservation is argued from the code, not verified byte for byte."*
