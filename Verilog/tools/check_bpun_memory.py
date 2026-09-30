#!/usr/bin/env python3
###############################################################################
# check_bpun_memory.py - verify that what a BPUN tape boot ACTUALLY put in
# memory matches the BPUN file, by diffing an OPCOM memory dump against the
# file's own G section.
#
# Why: on the Tang the '400$' boot reads BOOT.BPUN off the SD card, and the
# board LEDs only prove "at least one byte was served" - they cannot prove the
# whole file arrived intact. Dumping memory at the OPCOM prompt and comparing
# it here is the quick, decisive check (a serial re-load takes 45+ minutes).
#
# Paths, from the repository root, no guessing:
#   BPUN     Verilog/runSim/INSTRUCTION-B.BPUN
#   this     Verilog/tools/check_bpun_memory.py
#
# USAGE
#   1) Print the OPCOM commands to type (1K-word blocks by default):
#        ./check_bpun_memory.py --bpun ../runSim/INSTRUCTION-B.BPUN --commands
#   2) Capture the console output to a file (minicom log, script(1), tee...).
#   3) Compare:
#        ./check_bpun_memory.py --bpun ../runSim/INSTRUCTION-B.BPUN --dump cap.log
#
# The dump parser accepts the OPCOM '<' format, verified against a real
# session 14-JUL-2026:
#     #0<20
#     000000 /125025 000001 000002 000003 000004 000005 000006 000007
#     000010 /000010 000011 000012 000013 000014 000015 000016 000017
#     000020 /045006
# i.e. "ADDR /VAL" then up to 7 more bare VALs, all octal, 8 words per line.
# Echoed command lines, '#' prompts and CR are ignored. Partial dumps are fine:
# only the addresses present are compared, and what is missing is reported.
#
# NOTE the ramp is REAL: INSTRUCTION-B genuinely holds 000001..000017 in words
# 1..15. That is the program, not a fault - do not "fix" it.
#
# Ronny Hansen
###############################################################################
import argparse
import re
import sys


def parse_bpun(path):
    """Parse a BPUN tape image. Mirrors loadfile() in
    Verilog/runSim/Run120.cpp (sections A-I):
      A  chars up to '!'   B/C octal numbers   D '!'
      E  load address (2 bytes, MSB first)     F word count
      G  F words (MSB first)                   H checksum of G  I action code
    """
    d = open(path, "rb").read()
    i = 0
    B = C = 0
    while True:
        if i >= len(d):
            raise SystemExit("%s: no '!' delimiter - not a BPUN?" % path)
        w = d[i] & 0o177
        i += 1
        if w == ord("!"):
            break
        if w == ord("\n"):
            continue
        if w == ord("\r"):
            B, C = C, 0
        elif ord("0") <= w <= ord("7"):
            C = (C << 3) | (w - ord("0"))
        else:
            B = C = 0

    def gw():
        nonlocal i
        v = (d[i] << 8) | d[i + 1]
        i += 2
        return v

    E = gw()
    F = gw()
    words = [gw() for _ in range(F)]
    H = gw()
    I = gw()
    return {
        "B": B, "C": C, "load": E, "count": F,
        "words": words, "checksum": H, "execute": I,
        "computed": sum(words) & 0xFFFF,
    }


# "000000 /125025 000001 ..."  -> addr, [values]
LINE_RE = re.compile(r"^\s*([0-7]{1,6})\s*/\s*((?:[0-7]{1,6}\s*)+)$")


def parse_dump(path):
    """Return {addr: value} from a captured OPCOM '<' dump."""
    mem = {}
    for raw in open(path, "r", errors="replace"):
        line = raw.replace("\r", "").rstrip("\n")
        line = line.lstrip("#").strip()
        if not line or "<" in line:      # skip prompts and echoed commands
            continue
        m = LINE_RE.match(line)
        if not m:
            continue
        addr = int(m.group(1), 8)
        for tok in m.group(2).split():
            mem[addr] = int(tok, 8)
            addr += 1
    return mem


def emit_commands(info, block):
    lo = info["load"]
    hi = info["load"] + info["count"] - 1
    print("# OPCOM dump commands for %s words at %06o..%06o (%d-word blocks)"
          % (info["count"], lo, hi, block))
    print("# Type these at the OPCOM prompt AFTER '400$' has loaded the program.")
    a = lo
    n = 0
    while a <= hi:
        b = min(a + block - 1, hi)
        print("%o<%o" % (a, b))
        a = b + 1
        n += 1
    print("# %d commands. Capture the console to a file, then re-run with --dump." % n)


def main():
    ap = argparse.ArgumentParser(
        description="Diff an OPCOM memory dump against a BPUN file.")
    ap.add_argument("--bpun", required=True, help="the BPUN file (source of truth)")
    ap.add_argument("--dump", help="captured OPCOM '<' console output")
    ap.add_argument("--commands", action="store_true",
                    help="print the OPCOM commands to type, then exit")
    ap.add_argument("--block", type=lambda s: int(s, 0), default=1024,
                    help="block size in words for --commands and the summary "
                         "(default 1024)")
    args = ap.parse_args()

    info = parse_bpun(args.bpun)
    ok = info["checksum"] == info["computed"]
    print("BPUN  %s" % args.bpun)
    print("  load address %06o   word count %06o (%d)"
          % (info["load"], info["count"], info["count"]))
    print("  checksum %06o  computed %06o  -> %s"
          % (info["checksum"], info["computed"], "MATCH" if ok else "MISMATCH"))
    print("  execute %06o  B %06o" % (info["execute"], info["B"]))
    if not ok:
        print("  the FILE ITSELF is corrupt - fix that before blaming the SD path")
        return 2

    if args.commands or not args.dump:
        if not args.dump:
            print()
        emit_commands(info, args.block)
        return 0

    mem = parse_dump(args.dump)
    if not mem:
        print("\n%s: no dump lines recognised. Expected 'ADDR /VAL VAL ...' in "
              "octal." % args.dump)
        return 2

    base = info["load"]
    words = info["words"]
    checked = bad = 0
    first_bad = None
    blocks = {}
    for addr, got in sorted(mem.items()):
        idx = addr - base
        if idx < 0 or idx >= len(words):
            continue                      # outside the program image
        want = words[idx]
        checked += 1
        blk = idx // args.block
        s = blocks.setdefault(blk, [0, 0])
        s[0] += 1
        if got != want:
            bad += 1
            s[1] += 1
            if first_bad is None:
                first_bad = (addr, want, got)

    print("\nDUMP  %s" % args.dump)
    print("  words compared %d of %d (%.1f%% of the image)"
          % (checked, info["count"], 100.0 * checked / info["count"]))
    missing = info["count"] - checked
    if missing:
        print("  NOT dumped: %d words - those are UNVERIFIED, not proven good"
              % missing)

    print("\nPer-%d-word block:" % args.block)
    for blk in sorted(blocks):
        n, b = blocks[blk]
        lo = base + blk * args.block
        print("  %06o..%06o  %5d words  %s"
              % (lo, lo + n - 1, n, "OK" if b == 0 else "%d BAD" % b))

    print()
    if bad == 0:
        print("RESULT: PASS - every dumped word matches the BPUN file.")
        if missing:
            print("        (but %d words were never dumped - dump them to make "
                  "this a full proof)" % missing)
        return 0
    a, want, got = first_bad
    print("RESULT: FAIL - %d of %d dumped words differ." % (bad, checked))
    print("        first at %06o: file has %06o, memory has %06o" % (a, want, got))
    print("        -> the bytes that reached memory are NOT the file's.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
