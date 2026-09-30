#!/usr/bin/env python3
"""Trace EPANS and MIPANS IDB[15] during MS20 execution around o002335."""
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

id_map = {v[0]: k for k, v in ids.items()}

events = []
cur_t = 0
in_data = False

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
                    try: v = int(parts[0][1:], 2); events.append((cur_t, k, v))
                    except ValueError: pass
        elif line[0] in "01xXzZ":
            sid = line[1:]
            if sid in id_map:
                k = id_map[sid]
                try: v = int(line[0]); events.append((cur_t, k, v))
                except ValueError: pass

# Find o002335 in events, show all events in range
TARGET = 0o002335
found_t = None
for t, k, v in events:
    if k == "csa" and v == TARGET:
        found_t = t
        break

if found_t is None:
    print("o002335 not found!")
    sys.exit(0)

print("\nAll events around o002335 (tick %d +/- 15):" % (found_t//10+1))
print("  %8s  %-12s  %s" % ("tick", "signal", "value"))
for t, k, v in events:
    if t < found_t - 30: continue
    if t > found_t + 50: break
    if k in ("idb_pan", "alu_f", "y2"):
        print("  %8d  %-12s  0x%04x  bit15=%d" % (t//10+1, k, v, (v>>15)&1))
    else:
        print("  %8d  %-12s  %d" % (t//10+1, k, v))
