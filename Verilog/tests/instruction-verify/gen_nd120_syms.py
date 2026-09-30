#!/usr/bin/env python3
###############################################################################
# gen_nd120_syms.py - ND-120 micro-address -> symbol/source table
#
# Parses the DELILAH listing and emits a TSV consumed by the runSim trace
# instrumentation (ND120_TRACE_VERIFY): for every control-store address,
#   <octal addr>\t<LABEL or LABEL+n>\t<flattened source text>
# A microword often spans several listing lines; they are joined. Numeric
# "NNN/" origin directives reset the label context (their words show an
# empty symbol, matching the golden traces' unlabeled `0/` fetch word).
###############################################################################

import os
import re
import sys

# Local settings: the environment first, then local.mk at the repository
# root (written by configure.py - see CONTRIBUTING.md "Local settings").
sys.path.insert(0, os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..")))
import configure  # noqa: E402

# The listing lives in the sibling ND110Compile repository, found through
# ND_REPOS (the folder that holds the other ND checkouts): the environment,
# else local.mk at the repository root.
_ND_REPOS = configure.setting_path("ND_REPOS")
DEFAULT_SRC = (os.path.join(_ND_REPOS, "ND110Compile", "ND110Compile",
                            "uCode", "ND-120-DELILAH-K.LISTING.TXT")
               if _ND_REPOS else None)
LINE_RE = re.compile(r"^(\d{4,})\s\s([0-7]{6})\s\s(.*)$")
LABEL_RE = re.compile(r"^\s*([A-Z][A-Z0-9]*)\s*:(?!=)")
ORIGIN_RE = re.compile(r"^\s*([0-7]+)\s*/")


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SRC
    if not src:
        sys.exit("gen_nd120_syms.py: give the DELILAH listing as the first argument, "
                 "or set ND_REPOS to the folder that holds the ND110Compile checkout")
    out = sys.argv[2] if len(sys.argv) > 2 else "nd120_symbols.tsv"

    words = {}  # addr(int) -> [source pieces]
    label_at = {}  # addr -> label
    with open(src, errors="replace") as f:
        for raw in f:
            m = LINE_RE.match(raw.rstrip("\n"))
            if not m:
                continue
            addr = int(m.group(2), 8)
            text = m.group(3).split("%", 1)[0].strip()
            if not text:
                continue
            lm = LABEL_RE.match(text)
            if lm:
                label_at.setdefault(addr, lm.group(1))
            if ORIGIN_RE.match(text):
                # origin directive: no source contribution, breaks label flow
                label_at.setdefault(addr, "")
                continue
            words.setdefault(addr, []).append(" ".join(text.split()))

    with open(out, "w") as f:
        cur_label, cur_base = "", 0
        for addr in sorted(words):
            if addr in label_at:
                cur_label, cur_base = label_at[addr], addr
            if cur_label:
                off = addr - cur_base
                sym = cur_label if off == 0 else "%s+%o" % (cur_label, off)
            else:
                sym = ""
            f.write("%06o\t%s\t%s\n" % (addr, sym, " ".join(words[addr])))
    print("wrote %s: %d words, %d labels" % (out, len(words), len(label_at)))


if __name__ == "__main__":
    sys.exit(main())
