#!/usr/bin/env python3
"""Trace signal state AT o002335 — print last-known value of each signal at that tick."""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fst import open_wave

VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.fst")

WANT = {
    "csa":      "s_debug_csa",
    "epans_n":  "IDBS.s_epans_n",
    "pancal_ep":"PANCAL.s_epans",
    "g2n":      "CHIP_33B.G2_n",
    "y2":       "CHIP_33B.Y2",
    "pres":     "PANCAL.s_pres",
    "idb_pan":  "IO.s_idb_15_0_pancal_out",
    "alu_f":    "DELILAH.ALU.s_f_15_0",
    "term_n":   "s_debug_cc_term",
    "mclk":     "s_debug_mclk",
}

def find_ids(vcd_path, want):
    scope = []
    found = {}
    with open_wave(vcd_path) as f:
        for line in f:
            s = line.strip()
            if s.startswith("$scope"):
                p = s.split()
                if len(p) >= 3:
                    scope.append(p[2])
            elif s.startswith("$upscope"):
                if scope: scope.pop()
            elif s.startswith("$var"):
                p = s.split()
                if len(p) >= 5:
                    full = ".".join(scope + [p[4]])
                    for key, substr in want.items():
                        if key not in found and substr in full:
                            found[key] = (p[3], int(p[2]), full)
            elif s.startswith("$enddefinitions"):
                break
    return found

ids = find_ids(VCD, WANT)
print("Signals found:")
for k, (sid, bits, full) in sorted(ids.items()):
    print("  %-12s  id=%r  %3dbit  %s" % (k, sid, bits, full))
missing = set(WANT) - set(ids)
if missing:
    print("MISSING:", missing)
print()

id_map = {v[0]: k for k, v in ids.items()}
state = {k: None for k in WANT}

TARGET = 0o002335
TARGET_NEXT = 0o002336

# Snapshots: (tick, dict of states) whenever CSA = o002335
snapshots = []
cur_t = 0
in_data = False
found_target = False

with open_wave(VCD) as f:
    for line in f:
        if not in_data:
            if "$enddefinitions" in line:
                in_data = True
            continue
        line = line.rstrip()
        if not line: continue
        if line[0] == "#":
            cur_t = int(line[1:])
            continue
        if line[0] in "bBrR":
            parts = line.split(None, 1)
            if len(parts) == 2:
                sid = parts[1].strip()
                if sid in id_map:
                    k = id_map[sid]
                    try:
                        v = int(parts[0][1:], 2)
                        state[k] = v
                        if k == "csa" and v == TARGET:
                            snapshots.append((cur_t, dict(state)))
                            found_target = True
                        if k == "csa" and v == TARGET_NEXT and found_target:
                            snapshots.append((cur_t, dict(state)))
                    except ValueError: pass
        elif line[0] in "01xXzZ":
            sid = line[1:]
            if sid in id_map:
                k = id_map[sid]
                try:
                    v = int(line[0])
                    state[k] = v
                    if k == "csa" and v == TARGET:
                        snapshots.append((cur_t, dict(state)))
                        found_target = True
                    if k == "csa" and v == TARGET_NEXT and found_target:
                        snapshots.append((cur_t, dict(state)))
                except ValueError: pass

if not snapshots:
    print("o002335 not found in events!")
    sys.exit(0)

for t, snap in snapshots:
    csa_val = snap.get("csa", 0)
    print("=== CSA=o%06o at tick %d ===" % (csa_val if csa_val else 0, t//10+1))
    for sig in sorted(snap.keys()):
        v = snap[sig]
        if v is None:
            print("  %-12s = (no event seen)" % sig)
        elif sig == "csa":
            print("  %-12s = o%06o" % (sig, v))
        elif sig in ("idb_pan", "alu_f", "y2"):
            print("  %-12s = o%06o  bit15=%d  bit0=%d" % (sig, v, (v>>15)&1, v&1))
        else:
            print("  %-12s = %d" % (sig, v))
    print()
