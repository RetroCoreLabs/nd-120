#!/usr/bin/env python3
###############################################################################
# gen_mic_map.py - ND-110 <-> ND-120 microcode symbol/address mapping
#
# Parses the two assembler listings:
#   ND-110: ND-110-RASK.LISTING.TXT      (working instruction tests, golden)
#   ND-120: ND-120-DELILAH-K.LISTING.TXT (our RTL's microcode)
#
# and emits a mapping document that lets trace-compare tooling translate a
# micro-address seen on one machine into the corresponding symbol + address
# on the other. Symbols are the join key; the addresses differ between the
# two microcode versions.
#
# Listing line format (both files):
#   LLLL  AAAAAA  <source>
# where LLLL is the listing line number, AAAAAA the octal micro-address the
# NEXT emitted word lands at, and a symbol definition is "NAME:" at the
# start of the source field.
#
# Usage:
#   python3 gen_mic_map.py [--nd110 FILE] [--nd120 FILE] [-o OUT.md] [--tsv OUT.tsv]
#
# Defaults match the repo layout on this machine (see DEFAULT_* below).
# The .tsv output is the machine-readable table for mechanical unit-test
# validation; the .md is the human document.
###############################################################################

import argparse
import os
import re
import sys

# Local settings: the environment first, then local.mk at the repository
# root (written by configure.py - see CONTRIBUTING.md "Local settings").
sys.path.insert(0, os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..")))
import configure  # noqa: E402

# The listings live in the sibling ND110Compile repository, found through
# ND_REPOS (the folder that holds the other ND checkouts; the environment,
# else local.mk at the repository root):
#   $ND_REPOS/ND110Compile/ND110Compile/uCode/<listing>
ND_REPOS = configure.setting_path("ND_REPOS")


def _nd110compile_listing(name):
    """A listing in $ND_REPOS/ND110Compile, or None when ND_REPOS is not set."""
    if not ND_REPOS:
        return None
    return os.path.join(ND_REPOS, "ND110Compile", "ND110Compile", "uCode", name)


def _shown(path):
    """The path as the generated document writes it: $ND_REPOS in place of the
    folder it names, so no machine path lands in the committed .md."""
    if ND_REPOS and path.startswith(ND_REPOS):
        return "$ND_REPOS" + path[len(ND_REPOS):].replace("\\", "/")
    return path


DEFAULT_ND110 = _nd110compile_listing("ND-110-RASK.LISTING.TXT")
DEFAULT_ND120 = _nd110compile_listing("ND-120-DELILAH-K.LISTING.TXT")

LINE_RE = re.compile(r"^(\d{4,})\s\s([0-7]{6})\s\s(.*)$")
LABEL_RE = re.compile(r"^\s*([A-Z][A-Z0-9]*)\s*:(?!=)")


def parse_listing(path):
    """Return (symbols, dupes): symbols = {name: (octal_addr_str, line_no)},
    dupes = list of (name, addr, line_no) for re-definitions."""
    symbols = {}
    dupes = []
    with open(path, "r", errors="replace") as f:
        for raw in f:
            m = LINE_RE.match(raw.rstrip("\n"))
            if not m:
                continue
            line_no, addr, src = m.groups()
            # strip comments (% to end of line)
            src = src.split("%", 1)[0]
            lm = LABEL_RE.match(src)
            if not lm:
                continue
            name = lm.group(1)
            if name in symbols:
                dupes.append((name, addr, line_no))
            else:
                symbols[name] = (addr, line_no)
    return symbols, dupes


def ocr_norm(name):
    """Collapse the classic OCR confusions seen between the two listings.
    The ND-110 file is OCR-sourced; O/0 and I/1 twins of the same label are
    spelling variants of ONE symbol, not two symbols."""
    return name.replace("O", "0").replace("I", "1").replace("L", "1")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--nd110", default=DEFAULT_ND110)
    ap.add_argument("--nd120", default=DEFAULT_ND120)
    ap.add_argument("-o", "--out", default="ND110-ND120-MIC-MAP.md")
    ap.add_argument("--tsv", default="nd110_nd120_mic_map.tsv")
    args = ap.parse_args()
    if not args.nd110 or not args.nd120:
        ap.error("set ND_REPOS to the folder that holds the ND110Compile checkout, "
                 "or pass --nd110 and --nd120")

    s110, d110 = parse_listing(args.nd110)
    s120, d120 = parse_listing(args.nd120)

    common = sorted(set(s110) & set(s120), key=lambda n: int(s120[n][0], 8))
    only110 = sorted(set(s110) - set(s120), key=lambda n: int(s110[n][0], 8))
    only120 = sorted(set(s120) - set(s110), key=lambda n: int(s120[n][0], 8))

    # OCR reconciliation pass 1: normalized-name join (0/O, 1/I/L twins).
    # Pass 2: same-address join for what's left (catches e.g. TAPOS/TAPGS).
    # Ambiguous normalized names (2+ candidates on either side) stay unpaired.
    ocr_pairs = []  # (name110, name120, how)
    n110 = {}
    for n in only110:
        n110.setdefault(ocr_norm(n), []).append(n)
    n120 = {}
    for n in only120:
        n120.setdefault(ocr_norm(n), []).append(n)
    for key, l110 in n110.items():
        l120 = n120.get(key, [])
        if len(l110) == 1 and len(l120) == 1:
            ocr_pairs.append((l110[0], l120[0], "name"))
    paired110 = set(p[0] for p in ocr_pairs)
    paired120 = set(p[1] for p in ocr_pairs)
    a120 = {}
    for n in only120:
        if n not in paired120:
            a120.setdefault(s120[n][0], []).append(n)
    for n in [x for x in only110 if x not in paired110]:
        cands = a120.get(s110[n][0], [])
        if len(cands) == 1:
            ocr_pairs.append((n, cands[0], "addr"))
            paired110.add(n)
            paired120.add(cands[0])
    only110 = [n for n in only110 if n not in paired110]
    only120 = [n for n in only120 if n not in paired120]

    same = [n for n in common if s110[n][0] == s120[n][0]]
    moved = [n for n in common if s110[n][0] != s120[n][0]]

    # machine-readable table
    with open(args.tsv, "w") as f:
        f.write("symbol\tnd110_addr\tnd120_addr\tstatus\n")
        for n in common:
            st = "same" if s110[n][0] == s120[n][0] else "moved"
            f.write("%s\t%s\t%s\t%s\n" % (n, s110[n][0], s120[n][0], st))
        for n110name, n120name, how in ocr_pairs:
            f.write("%s\t%s\t%s\tocr:%s=%s\n"
                    % (n110name, s110[n110name][0], s120[n120name][0], how, n120name))
        for n in only110:
            f.write("%s\t%s\t-\tonly-110\n" % (n, s110[n][0]))
        for n in only120:
            f.write("%s\t-\t%s\tonly-120\n" % (n, s120[n][0]))

    # human document
    with open(args.out, "w") as f:
        w = f.write
        w("# ND-110 <-> ND-120 microcode symbol map\n\n")
        w("GENERATED by tests/instruction-verify/gen_mic_map.py - do not hand-edit.\n\n")
        w("Sources:\n")
        w("- ND-110 (RASK, golden instruction-test machine): `%s`\n" % _shown(args.nd110))
        w("- ND-120 (DELILAH version K, our RTL): `%s`\n\n" % _shown(args.nd120))
        w("Purpose: translate micro-addresses between the two machines when\n")
        w("comparing execution listings from the ND-110 instruction tests\n")
        w("against our ND-120 RTL traces. Symbols are the join key; the\n")
        w("machine-readable table is `%s`.\n\n" % args.tsv)
        w("| population | count |\n|---|---|\n")
        w("| symbols in both, SAME address | %d |\n" % len(same))
        w("| symbols in both, MOVED | %d |\n" % len(moved))
        w("| OCR spelling twins (reconciled) | %d |\n" % len(ocr_pairs))
        w("| only in ND-110 | %d |\n" % len(only110))
        w("| only in ND-120 | %d |\n\n" % len(only120))

        w("## Symbols present in both (sorted by ND-120 address)\n\n")
        w("| symbol | ND-110 addr | ND-120 addr | delta (oct) |\n")
        w("|---|---|---|---|\n")
        for n in common:
            a1, a2 = int(s110[n][0], 8), int(s120[n][0], 8)
            d = a2 - a1
            ds = "0" if d == 0 else ("%+o" % d)
            w("| %s | %s | %s | %s |\n" % (n, s110[n][0], s120[n][0], ds))

        w("\n## OCR spelling twins (same symbol, listing spellings differ)\n\n")
        w("The ND-110 listing is OCR-sourced; these labels are ONE symbol with\n")
        w("0/O- or 1/I/L-confused spellings (or same-address orphans). Trace\n")
        w("tooling must treat the two spellings as identical.\n\n")
        w("| ND-110 spelling | ND-120 spelling | ND-110 addr | ND-120 addr | matched by |\n")
        w("|---|---|---|---|---|\n")
        for n110name, n120name, how in ocr_pairs:
            w("| %s | %s | %s | %s | %s |\n"
              % (n110name, n120name, s110[n110name][0], s120[n120name][0], how))

        w("\n## Only in ND-110 (no ND-120 counterpart - expect divergence here)\n\n")
        w("| symbol | ND-110 addr |\n|---|---|\n")
        for n in only110:
            w("| %s | %s |\n" % (n, s110[n][0]))

        w("\n## Only in ND-120 (no ND-110 counterpart - expect divergence here)\n\n")
        w("| symbol | ND-120 addr |\n|---|---|\n")
        for n in only120:
            w("| %s | %s |\n" % (n, s120[n][0]))

        if d110 or d120:
            w("\n## Duplicate label definitions (parser kept the FIRST)\n\n")
            for tag, dl in (("ND-110", d110), ("ND-120", d120)):
                for name, addr, ln in dl:
                    w("- %s: `%s` redefined at %s (listing line %s)\n" % (tag, name, addr, ln))

    print("ND-110 symbols: %d (%d duplicate defs)" % (len(s110), len(d110)))
    print("ND-120 symbols: %d (%d duplicate defs)" % (len(s120), len(d120)))
    print("common: %d (same=%d moved=%d), only-110: %d, only-120: %d"
          % (len(common), len(same), len(moved), len(only110), len(only120)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
