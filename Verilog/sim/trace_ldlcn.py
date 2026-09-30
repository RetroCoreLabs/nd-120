#!/usr/bin/env python3
"""Count all LDLCN events in first 2M ticks to see if it ever fires."""
from fst import open_wave
from collections import defaultdict

import os
VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.fst")

WANT = {
    "ldlcn": "s_ldlc_n",
    "lc":    "s_lc_3_0",
    "csa":   "s_debug_csa",
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
    print(f"  {k:<10}  id={sid!r}  {bits}bit  {full}")

id_map = {v[0]: k for k, v in ids.items()}
T_END = 2000000 * 10

ldlcn_evs = []
lc_evs = []
csa_evs_ldlc = []

cur_t = 0
in_data = False
cur_csa = 0

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
            if cur_t > T_END:
                break
            continue
        if line[0] in "bBrR":
            parts = line.split(None, 1)
            if len(parts) == 2:
                sid = parts[1].strip()
                if sid in id_map:
                    try:
                        k = id_map[sid]
                        v = int(parts[0][1:], 2)
                        if k == "ldlcn":
                            ldlcn_evs.append((cur_t, v))
                        elif k == "lc":
                            lc_evs.append((cur_t, v))
                        elif k == "csa":
                            cur_csa = v
                    except ValueError:
                        pass
        elif line[0] in "01xXzZ":
            sid = line[1:]
            if sid in id_map:
                try:
                    k = id_map[sid]
                    v = int(line[0])
                    if k == "ldlcn":
                        ldlcn_evs.append((cur_t, v))
                        if v == 0:  # LDLCN active
                            csa_evs_ldlc.append((cur_t, cur_csa))
                    elif k == "lc":
                        lc_evs.append((cur_t, v))
                    elif k == "csa":
                        cur_csa = v
                except ValueError:
                    pass

def tick(t):
    return t // 10 + 1

print(f"\nTotal LDLCN events (transitions): {len(ldlcn_evs)}")
if ldlcn_evs:
    print("First 10:")
    for t, v in ldlcn_evs[:10]:
        print(f"  tick {tick(t):10d}  LDLCN={v}")
    print("Last 5:")
    for t, v in ldlcn_evs[-5:]:
        print(f"  tick {tick(t):10d}  LDLCN={v}")

print(f"\nTimes LDLCN went LOW (=active=load): {len(csa_evs_ldlc)}")
for t, csa in csa_evs_ldlc[:10]:
    print(f"  tick {tick(t):10d}  CSA=o{csa:06o}")

print(f"\nTotal LC changes: {len(lc_evs)}")
print("First 10 LC changes:")
for t, v in lc_evs[:10]:
    print(f"  tick {tick(t):10d}  LC={v} (o{v:02o})")
