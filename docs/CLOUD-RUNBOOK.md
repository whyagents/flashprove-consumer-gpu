# Runbook: native Linux on rented GPUs (planned)

Three rented machines answer the open questions in about an hour each. Anyone can run this; replication reports are welcome.

| Machine | Answers | Rough cost |
|---|---|---|
| **RTX 3090** (sm_86, 24 GB), native Linux | Does the port build and prove on Ampere? Is patch 12 (WSL2 pinned memory) needed on native Linux? | about $0.30/h |
| **RTX 4090** (sm_89, 24 GB), native Linux | The same for Ada, the consumer twin of the L4 | about $0.50/h |
| **H100** (sm_90a), native Linux, **unmodified upstream** | Byte-for-byte check of the patches, including hiding ([`HIDING.md`](HIDING.md)) | about $2–3/h |

**Host requirements:** a VM or bare-metal container with full syscalls. Avoid gVisor-style sandboxes, because `cp_commit` needs
`madvise(MADV_WIPEONFORK)`. You also need an x86-64 CPU with SHA extensions (`grep -m1 -ow sha_ni /proc/cpuinfo`), at least 10 GB of free RAM,
Ubuntu 24.04, and g++ 13.

## A. Consumer cards (3090 / 4090)
For sm_86 or sm_89, change patch 1's flag (`-arch=sm_120`) to the card's architecture; everything else is the same.
1. Follow the README's "Reproduce it" steps 1–5, first with patches 1–11 only (**without** patch 12).
2. If `cp_commit` fails at `hf_open_side.cuh` with `invalid argument`, apply patch 12 and record that it is needed on native Linux too.
3. Run `run_target_example.sh target_small_f2_roomy` three times; check each with `scripts/a5_verify_and_tamper.sh`.

## B. Byte identity on H100 (unmodified upstream vs our patches)
Goal: identical bytes from identical inputs under a fixed seed.
1. **Determinism here: done.** Two test-build runs with the same seeds were byte-identical on the RTX 5070 Ti (`scripts/a15_determinism.sh`).
   - Seed files: 32 bytes each. `cp_commit -test-seed`: the ASCII text `why-research A15 fixed test seed!`. `cp_prove -test-coins`: `why-research A15 fixed testcoins`.
   - Configuration and request: `target_small_f2_roomy` with `made-up-blocks`, `-M 1`, and the request `own_choices.req`.
   - Reference: commitment ID `4942be953206913cf3c97c443df610f7ed9c03c0bc1b99437c17c2a11095cfb6`
     - `ivk/key.bin` sha256 `69f94db22375a92531466aa8160b5cf33fed390ac6178c5889c244603d770751`
     - `ivk/leaf/0.bin` sha256 `64a4fb799ccd54c5674c70688102e64cf50e8f730b21b8c8a630fc6b1a3bba14`
     - `out/example.proof` sha256 `152b7bf02689e62f9639fd667a8efa8babcab59a07efe9b9286cbf7e8eec3e77`
     - `out/example.y` sha256 `871cd8edd0dbd8de891216d6409fba14bb5f0f72b880c5fcc512218b282298fb` (token 284)
2. **On the H100:** build **unmodified** upstream `9e2bdd8f` (`./build.sh tests`), run the same seed and inputs, and `sha256sum` key, leaf and proof.
3. **Compare** with the hashes from this card. Equal hashes mean the 12 patches change no output byte, masks included.

Report: GPU, driver, OS, exit codes, last lines, IDs, and the sha256 of each output file.
