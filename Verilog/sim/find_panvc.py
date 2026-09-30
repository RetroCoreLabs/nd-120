#!/usr/bin/env python3
"""Find PANVC dispatch events in VCD and show LC value at each."""
from collections import defaultdict

import os
VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.vcd")

# --- header parse ---
scope = []
id_csa = None
id_lc  = None
w_csa  = 13
w_lc   = 4

with open(VCD, 'r', buffering=8*1024*1024) as f:
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
                if "s_debug_csa" in full or "CSA_12_0" in full:
                    # prefer s_debug_csa (top-level debug wire)
                    if id_csa is None or "s_debug_csa" in full:
                        id_csa = p[3]
                        w_csa  = int(p[2])
                if "s_lc_3_0" in full:
                    id_lc = p[3]
                    w_lc  = int(p[2])
        elif s.startswith("$enddefinitions"):
            break

print(f"id_csa={id_csa!r}  id_lc={id_lc!r}")
if not id_csa or not id_lc:
    raise SystemExit("Could not find signal IDs — check VCD header")

# --- data scan ---
csa_changes = []
lc_changes  = []
cur_t = 0

with open(VCD, 'r', buffering=8*1024*1024) as f:
    in_data = False
    for line in f:
        if not in_data:
            if line.strip().startswith("$enddefinitions"):
                in_data = True
            continue
        line = line.rstrip()
        if not line:
            continue
        if line[0] == '#':
            cur_t = int(line[1:])
            continue
        if line[0] in 'bBrR':
            parts = line.split(None, 1)
            if len(parts) == 2:
                val_str = parts[0][1:]
                sid     = parts[1].strip()
                if sid == id_csa:
                    try:
                        csa_changes.append((cur_t, int(val_str, 2)))
                    except ValueError:
                        pass
                elif sid == id_lc:
                    try:
                        lc_changes.append((cur_t, int(val_str, 2)))
                    except ValueError:
                        pass
        elif line[0] in '01xXzZ':
            sid = line[1:]
            if sid == id_csa:
                try:
                    csa_changes.append((cur_t, int(line[0])))
                except ValueError:
                    pass
            elif sid == id_lc:
                try:
                    lc_changes.append((cur_t, int(line[0])))
                except ValueError:
                    pass

print(f"CSA changes: {len(csa_changes)}  LC changes: {len(lc_changes)}")

# --- LC lookup ---
def lc_at(t):
    lo, hi = 0, len(lc_changes) - 1
    if not lc_changes or t < lc_changes[0][0]:
        return 0
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if lc_changes[mid][0] <= t:
            lo = mid
        else:
            hi = mid - 1
    return lc_changes[lo][1]

# --- PANVC range: o03760-o03767 = 0x7F0-0x7F7 ---
print()
print(f"{'tick':>10}  {'CSA(oct)':>10}  {'LC(oct)':>8}  {'LC(dec)':>8}")
print("-" * 45)
for t, csa in csa_changes:
    if 0x7F0 <= csa <= 0x7F7:
        lc = lc_at(t)
        tick = t // 10 + 1
        print(f"{tick:>10}  o{oct(csa)[2:]:>09}  o{oct(lc)[2:]:>6}     {lc:>5}")
