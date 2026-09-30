#!/usr/bin/env python3
"""Trace all CSIDBS=o21 (MAPANS) occurrences alongside CSA and surrounding signals."""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fst import open_wave

VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.fst")

WANT = {
    "csa":    "s_debug_csa",
    "mclk":   "s_debug_mclk",
    "csidbs": "s_csidbs_4_0",
    "alu_f":  "DELILAH.ALU.s_f_15_0",
    "g2n":    "CHIP_33B.G2_n",
    "lua":    "s_LUA_12_0",
}

def find_ids(vcd_path, want):
    scope = []
    found = {}
    with open_wave(vcd_path) as f:
        for line in f:
            s = line.strip()
            if s.startswith("$scope"):
                p = s.split()
                if len(p) >= 3: scope.append(p[2])
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
    print("  %-10s  id=%r  %3dbit  %s" % (k, sid, bits, full))
missing = set(WANT) - set(ids)
if missing:
    print("MISSING:", missing)
print()

id_map = {v[0]: k for k, v in ids.items()}
MAPANS_CODE = 0o21  # CSIDBS=o21

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

# Find all CSIDBS=o21 events
mapans_times = [(t, v) for t, k, v in events if k == "csidbs" and v == MAPANS_CODE]
print("Total CSIDBS=o21 occurrences: %d" % len(mapans_times))
if mapans_times:
    print("First 10 occurrences:")
    for t, v in mapans_times[:10]:
        # Find CSA at that tick
        csa_at_t = None
        for et, ek, ev in events:
            if et > t + 20: break
            if ek == "csa": csa_at_t = ev
        print("  tick %8d  csidbs=o%06o  (CSA at that time: %s)" % (
            t//10+1, v,
            ("o%06o" % csa_at_t) if csa_at_t is not None else "?"))

print()

# Show context around first CSIDBS=o21
if mapans_times:
    first_t = mapans_times[0][0]
    print("=== Context around first CSIDBS=o21 (tick %d) ===" % (first_t//10+1))
    print("  %8s  %-10s  %s" % ("tick", "signal", "value"))
    for t, k, v in events:
        if t < first_t - 30: continue
        if t > first_t + 60: break
        if k in ("csa", "csidbs", "lua"):
            print("  %8d  %-10s  o%06o" % (t//10+1, k, v))
        elif k == "alu_f":
            print("  %8d  %-10s  o%06o  bit15=%d" % (t//10+1, k, v, (v>>15)&1))
        else:
            print("  %8d  %-10s  %d" % (t//10+1, k, v))
