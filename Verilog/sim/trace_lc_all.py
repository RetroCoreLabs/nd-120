#!/usr/bin/env python3
"""Dump all LC load events (LDLCN went LOW) and all LC value changes with CSA context."""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fst import open_wave
from collections import defaultdict

VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.fst")

WANT = {
    "csa":   "s_debug_csa",
    "lc":    "s_lc_3_0",
    "ldlcn": "s_ldlc_n",
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
                if scope:
                    scope.pop()
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
    print(f"  {k:<10}  id={sid!r}  {bits:3d}bit  {full}")

id_map = {v[0]: k for k, v in ids.items()}

def tick(t):
    return t // 10 + 1

cur_t = 0
in_data = False
cur_csa = 0
cur_lc  = 0

lc_loads = []   # (tick, csa, lc_value) — when LDLCN went LOW
lc_changes = [] # (tick, csa, lc_value) — all LC transitions

with open_wave(VCD) as f:
    for line in f:
        if not in_data:
            if "$enddefinitions" in line:
                in_data = True
            continue
        line = line.rstrip()
        if not line:
            continue
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
                        if k == "csa":
                            cur_csa = v
                        elif k == "lc":
                            lc_changes.append((cur_t, cur_csa, v))
                            cur_lc = v
                    except ValueError:
                        pass
        elif line[0] in "01xXzZ":
            sid = line[1:]
            if sid in id_map:
                k = id_map[sid]
                try:
                    v = int(line[0])
                    if k == "ldlcn" and v == 0:
                        lc_loads.append((cur_t, cur_csa))
                except ValueError:
                    pass

print(f"\n=== LDLCN LOW events (LC load pulses): {len(lc_loads)} ===")
print(f"{'tick':>10}  {'CSA':>10}")
for t, csa in lc_loads:
    print(f"{tick(t):10d}  o{csa:06o}")

print(f"\n=== LC value changes: {len(lc_changes)} ===")
print(f"{'tick':>10}  {'CSA':>10}  LC")
for t, csa, lc in lc_changes:
    print(f"{tick(t):10d}  o{csa:06o}  {lc} (o{lc:02o})")
