# Contributing

Thank you for looking. The most valuable contributions, in order:

1. **Replication reports.** Run the kit on your hardware and [open a report](../../issues/new?template=replication-report.yml).
   Another consumer GPU, native Linux, or a failure at a specific step are all useful.
2. **Patch reviews.** Each patch claims to keep the computed values exact. If you see a case where it doesn't, please open an issue
   with the file and line.
3. **Corrections to our claims.** If a statement in the README or `docs/` overstates something, or misses prior art, tell us.
   We would rather narrow a claim than defend a wrong one.

House rules, inherited from FlashProve's own `AGENTS.md`:
- Run as an ordinary user. Never get past an error with `sudo`, `chmod`, `chown` or `rm`.
- Never change a source file to change a *result*. Patches change how the prover runs, never what the verifier accepts.
- Take a commitment ID only from your own `cp_commit` output or the stored examples, never from a proof's files.
- Report the exit code **together with** the last line of `cp_verify`.
- **Never share anything from `isk/`**: it is the prover's secret.
