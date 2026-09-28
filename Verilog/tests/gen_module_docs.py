#!/usr/bin/env python3
"""
gen_module_docs.py - generate a symbol PNG + README for EVERY module in the tree.

WHY THIS EXISTS
    module_doc.py documents one module. Pointing it at two modules by hand
    proves the tool works; it does not document the design. This walks the
    whole tree so the documentation cannot quietly cover 2 modules out of 432
    while looking finished.

WHAT IT PRODUCES
    For <component>/circuit/FOO.v:
        <component>/circuit/doc/FOO.png
        <component>/circuit/doc/FOO.md

WHAT IT SKIPS, AND SAYS SO
    - anything under a sim/ directory and any *_tb.v  (testbenches are not
      modules of the design)
    - VENDOR-GENERATED IP: Xilinx MIG (ip/ trees, mig_7series_*), Gowin PLLs,
      and Vivado's .Xil scratch. Those are not our design, they are hundreds of
      files, and documenting them buries the 300-odd modules that ARE ours.
    - git SUBMODULES (any folder below the top with its own .git entry, e.g.
      fpga/mega65/m2m). They are other people's repos: writing doc/ folders
      into them would leave their working trees dirty, and the code is not
      ours to document.
    - files with no module declaration
    Every skip and every failure is listed at the end. A sweep that silently
    drops files is worse than no sweep, because the count looks complete.

USAGE
    cd Verilog
    python3 tests/gen_module_docs.py                 # whole tree
    python3 tests/gen_module_docs.py --root DELILAH-CPU
    python3 tests/gen_module_docs.py --dry-run
    python3 tests/gen_module_docs.py --jobs 8
"""

import argparse
import concurrent.futures as cf
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
VROOT = os.path.dirname(HERE)                     # Verilog/
MODULE_DOC = os.path.join(HERE, "module_doc.py")

MODULE_RE = re.compile(r"^\s*module\s+([A-Za-z_][A-Za-z0-9_$]*)", re.M)


def find_sources(root):
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        # a submodule has its own .git entry - skip it and everything under
        # it (see WHAT IT SKIPS above). The repo top itself is above VROOT,
        # so it is never seen here.
        if os.path.exists(os.path.join(dirpath, ".git")):
            dirnames[:] = []
            continue
        parts = set(dirpath.replace("\\", "/").split("/"))
        if "sim" in parts or "obj_dir" in parts or ".git" in parts:
            continue
        if "ip" in parts or ".Xil" in parts or "user_design" in parts:
            continue   # vendor-generated IP - see WHAT IT SKIPS above
        dirnames[:] = [d for d in dirnames
                       if d not in ("sim", ".git", "doc") and not d.startswith("obj_dir")]
        for fn in filenames:
            if not fn.endswith(".v"):
                continue
            if fn.endswith("_tb.v"):
                continue
            if fn.startswith("mig_7series_") or fn.startswith("gowin_"):
                continue   # vendor IP that lives outside an ip/ directory
            out.append(os.path.join(dirpath, fn))
    return sorted(out)


def modules_in(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            return MODULE_RE.findall(fh.read())
    except OSError:
        return []


def one(path, dry):
    mods = modules_in(path)
    if not mods:
        return ("skip", path, "no module declaration")
    outdir = os.path.join(os.path.dirname(path), "doc")
    if dry:
        return ("ok", path, "would write %d module(s) to %s" % (len(mods), outdir))
    os.makedirs(outdir, exist_ok=True)
    made = []
    for m in mods:
        # path is absolute here. That is fine: module_doc.py turns it into a
        # repo-relative path before it writes the doc, so no machine path
        # (/mnt/e/..., E:\...) ends up in a committed file.
        cmd = [sys.executable, MODULE_DOC, path, "-o", outdir, "--module", m]
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
        if r.returncode != 0:
            err = (r.stderr or r.stdout).strip().splitlines()
            return ("fail", path, "%s: %s" % (m, err[-1] if err else "exit %d" % r.returncode))
        made.append(m)
    return ("ok", path, ", ".join(made))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=VROOT,
                    help="subtree to sweep (default: the whole Verilog tree)")
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 4) // 2))
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    root = args.root if os.path.isabs(args.root) else os.path.join(VROOT, args.root)
    srcs = find_sources(root)
    print("sweeping %d Verilog source files under %s" % (len(srcs), root))
    print("jobs: %d%s" % (args.jobs, "   (dry run)" if args.dry_run else ""))

    ok, skipped, failed = [], [], []
    with cf.ThreadPoolExecutor(max_workers=args.jobs) as ex:
        futs = {ex.submit(one, s, args.dry_run): s for s in srcs}
        done = 0
        for fut in cf.as_completed(futs):
            done += 1
            try:
                kind, path, note = fut.result()
            except Exception as exc:                      # noqa: BLE001
                kind, path, note = "fail", futs[fut], repr(exc)
            rel = os.path.relpath(path, VROOT)
            if kind == "ok":
                ok.append((rel, note))
            elif kind == "skip":
                skipped.append((rel, note))
            else:
                failed.append((rel, note))
            if done % 25 == 0 or done == len(srcs):
                print("  %d/%d  ok=%d skip=%d fail=%d"
                      % (done, len(srcs), len(ok), len(skipped), len(failed)))

    print("\n" + "=" * 70)
    print("documented : %d files" % len(ok))
    print("skipped    : %d files" % len(skipped))
    print("FAILED     : %d files" % len(failed))
    if skipped:
        print("\nskipped (no module declaration):")
        for rel, note in sorted(skipped)[:40]:
            print("  %s" % rel)
        if len(skipped) > 40:
            print("  ... and %d more" % (len(skipped) - 40))
    if failed:
        print("\nFAILURES - these are NOT documented:")
        for rel, note in sorted(failed):
            print("  %-60s %s" % (rel, note))
    print("=" * 70)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
