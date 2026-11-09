#!/usr/bin/env python3
"""Apply one exp/sm120 patch spec (JSON) to the FlashProve worktree and commit it.

Spec: {"id": "...", "file": "prover/...", "old": "...", "new": "...", "why": "...", "semantics": "..."}
'old' must occur exactly once in 'file'. Run with: python3 -I apply_patch.py SPEC.json [WORKTREE]
"""
import json, os, subprocess, sys

spec_path = sys.argv[1]
wt = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/work/flashprove-sm120")
spec = json.load(open(spec_path))
path = os.path.join(wt, spec["file"])
src = open(path).read()
n = src.count(spec["old"])
if n != 1:
    already = src.count(spec["new"])
    sys.exit(f"{spec['id']}: 'old' occurs {n} times in {spec['file']} ('new' occurs {already} times); not applied")
open(path, "w").write(src.replace(spec["old"], spec["new"]))
msg = f"exp/sm120 {spec['id']}: {spec['why']}\n\nSemantics: {spec['semantics']}"
subprocess.run(["git", "-C", wt, "add", spec["file"]], check=True)
subprocess.run(["git", "-C", wt, "commit", "-q", "-m", msg], check=True)
head = subprocess.run(["git", "-C", wt, "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
print(f"{spec['id']}: applied to {spec['file']} as {head}")
