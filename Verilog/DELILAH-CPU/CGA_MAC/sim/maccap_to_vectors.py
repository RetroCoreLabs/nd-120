#!/usr/bin/env python3
"""Convert a [maccap] dump from a live boot into replay vectors for
CGA_MAC_replay_tb.v.

The dump is produced by the ND120_MAC_CAPTURE probe in ND120_TOP.v, which
records every CGA_MAC input and output on every sysclk into a ring and dumps
the ring when the failing JPL lands on 144162.

Usage:  maccap_to_vectors.py <dump-file> [out-file] [--last N]
Writes maccap_vectors.txt (one 171-bit binary word per line) next to the tb.
"""
import re, sys

# The dump file is required: it is a capture log kept outside the repository.
if len(sys.argv) < 2:
    sys.exit("usage: maccap_to_vectors.py <dump-file> [out-file] [--last N]")
DUMP = sys.argv[1]
OUT  = sys.argv[2] if len(sys.argv) > 2 else "maccap_vectors.txt"
LAST = None
if "--last" in sys.argv:
    LAST = int(sys.argv[sys.argv.index("--last") + 1])

# [maccap] idx MCLKEN CSMREQ DOUBLE ILCSN MCLK PONI PTM WR3 WR7 CMIS CSCOMM
#          RB CD FIDBO PR BR XR | ECCR LA LSHADOW MCA NLCA PCR VEX
rows = []
for ln in open(DUMP, errors="replace"):
    if not ln.startswith("[maccap] "):
        continue
    body = ln.split(None, 1)[1].strip()
    if body.startswith("TRIGGER") or body.startswith("idx"):
        continue
    L, _, R = body.partition("|")
    lf = L.split()
    rf = R.split()
    if len(lf) < 18 or len(rf) < 7:
        continue
    try:
        # left: idx then 9 bits, cmis, cscomm, then 6 octal words
        bits = [int(x, 2) for x in lf[1:10]]
        cmis, cscomm = int(lf[10], 8), int(lf[11], 8)
        rb, cd, fidbo, pr, br, xr = (int(x, 8) for x in lf[12:18])
        eccr = int(rf[0], 2); la = int(rf[1], 8); lsh = int(rf[2], 2)
        mca = int(rf[3], 8); nlca = int(rf[4], 8); pcr = int(rf[5], 8)
        vex = int(rf[6], 2)
    except ValueError:
        continue
    v = 0
    for b in bits:            v = (v << 1) | b          # 9
    v = (v << 2) | cmis                                  # 11
    v = (v << 5) | cscomm                                # 16
    for w in (rb, cd, fidbo, pr, br, xr): v = (v << 16) | w   # 112
    v = (v << 1) | eccr
    v = (v << 14) | la
    v = (v << 1) | lsh
    v = (v << 10) | mca
    v = (v << 16) | nlca
    v = (v << 16) | pcr
    v = (v << 1) | vex                                   # 171
    rows.append(v)

if LAST:
    rows = rows[-LAST:]
with open(OUT, "w") as f:
    for v in rows:
        f.write(format(v, "0171b") + "\n")
print("wrote %d vectors to %s" % (len(rows), OUT))
if not rows:
    print("NOTE: no [maccap] lines found - the capture has not triggered yet.")
