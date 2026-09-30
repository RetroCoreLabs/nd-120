#!/usr/bin/env python3
"""Trace PRES, CLOSC, MAPANS, ICLIRQ and PANVC dispatches after LCS_n HIGH."""
import sys
from collections import defaultdict

import os
VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.vcd")

WANT = {
    "csa":     "s_debug_csa",
    "lcs":     "s_debug_lcs_n",
    "lc":      "s_lc_3_0",
    "pres":    "s_pres",
    "mapans":  "s_mapans",
    "closc":   "s_closc",
    "iclirq":  "s_iclirq_group",
    "run":     "s_run",
}

def find_ids(vcd_path=VCD, want=WANT):
    scope = []; found = {}
    with open(vcd_path, "r", buffering=8*1024*1024) as f:
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

ids = find_ids()
print("Signals found:", list(ids.keys()))
id_map = {v[0]: k for k, v in ids.items()}

def extract(vcd_path, id_map, tstart=None, tend=None):
    results = defaultdict(list)
    cur_t = 0; in_data = False
    with open(vcd_path, "r", buffering=8*1024*1024) as f:
        for line in f:
            if not in_data:
                if "$enddefinitions" in line: in_data = True
                continue
            line = line.rstrip()
            if not line: continue
            if line[0] == "#":
                cur_t = int(line[1:])
                if tend is not None and cur_t > tend: break
                continue
            if tstart is not None and cur_t < tstart: continue
            if line[0] in "bBrR":
                parts = line.split(None, 1)
                if len(parts) == 2:
                    val_str = parts[0][1:]; sid = parts[1].strip()
                    if sid in id_map:
                        try: results[id_map[sid]].append((cur_t, int(val_str, 2)))
                        except ValueError: pass
            elif line[0] in "01xXzZ":
                sid = line[1:]
                if sid in id_map:
                    try: results[id_map[sid]].append((cur_t, int(line[0])))
                    except ValueError: pass
    return dict(results)

def tick(t): return t // 10 + 1

# Full scan - look at everything after LCS_n HIGH (tick ~557167)
T_START = 5560000   # tick 556000 — just before LCS_n HIGH
T_END   = 10000000  # tick 1000000 — end of sim

print(f"Scanning from tick {tick(T_START)} to tick {tick(T_END)}...")
data = extract(VCD, id_map, tstart=T_START, tend=T_END)

for sig in ["lcs", "pres", "closc", "mapans", "iclirq", "run"]:
    evs = data.get(sig, [])
    print(f"\n{sig} ({len(evs)} transitions):")
    for t, v in evs:
        print(f"  tick {tick(t):8d}  val={v}")

# LC changes
lc_evs = data.get("lc", [])
print(f"\nLC ({len(lc_evs)} events), first 20:")
for t, v in lc_evs[:20]:
    print(f"  tick {tick(t):8d}  LC={v}")

# PANVC dispatches = CSA in range o003760-o003777 = 0x7F0-0x7FF
csa_evs = data.get("csa", [])
print(f"\nPANVC dispatches after LCS_n HIGH (o003760-o003777):")
count = 0
for t, v in csa_evs:
    if 0x7F0 <= v <= 0x7FF:
        print(f"  tick {tick(t):8d}  CSA=o{v:06o}")
        count += 1
        if count >= 20:
            print("  ...")
            break
if count == 0:
    print("  NONE")

# RESTARTs = CSA=0 after tick 10000
print(f"\nRESTARTs (CSA=o000000):")
for t, v in csa_evs:
    if v == 0 and tick(t) > 10000:
        print(f"  tick {tick(t):8d}")
