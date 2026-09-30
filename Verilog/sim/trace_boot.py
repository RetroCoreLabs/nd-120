#!/usr/bin/env python3
"""
Show CSA + LC trace to understand boot progress.
Finds key milestones: LCS_n going high, MACL tests, PANVC dispatch, OPCOM.
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.vcd")

WANT = {
    "csa":   "s_debug_csa",
    "lc":    "s_lc_3_0",
    "lcs_n": "s_debug_lcs_n",
}

def find_ids(vcd_path=VCD, want=WANT):
    scope = []
    found = {}
    with open(vcd_path, "r", buffering=8*1024*1024) as f:
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

ids = find_ids()
print("Signals found:", {k: v[2].split(".")[-1] for k, v in ids.items()})

id_map = {v[0]: k for k, v in ids.items()}

from collections import defaultdict

def extract_limited(vcd_path, id_map, tend=None):
    results = defaultdict(list)
    cur_t = 0
    in_data = False
    with open(vcd_path, "r", buffering=8*1024*1024) as f:
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
                if tend is not None and cur_t > tend:
                    break
                continue
            if line[0] in "bBrR":
                parts = line.split(None, 1)
                if len(parts) == 2:
                    val_str = parts[0][1:]
                    sid = parts[1].strip()
                    if sid in id_map:
                        try:
                            results[id_map[sid]].append((cur_t, int(val_str, 2)))
                        except ValueError:
                            pass
            elif line[0] in "01xXzZ":
                sid = line[1:]
                if sid in id_map:
                    try:
                        results[id_map[sid]].append((cur_t, int(line[0])))
                    except ValueError:
                        pass
    return dict(results)

def tick(t_ps):
    return t_ps // 10 + 1

print("Scanning VCD...")
data = extract_limited(VCD, id_map)

csa_ch  = data.get("csa",   [])
lc_ch   = data.get("lc",    [])
lcs_ch  = data.get("lcs_n", [])

print(f"CSA events:   {len(csa_ch)}")
print(f"LC events:    {len(lc_ch)}")
print(f"LCS_n events: {len(lcs_ch)}")

if csa_ch:
    t_end = csa_ch[-1][0]
    print(f"VCD ends at tick {tick(t_end)}")

# Find LCS_n going HIGH (end of loading)
lcs_hi_t = None
for t, v in lcs_ch:
    if v == 1 and tick(t) > 10000:
        lcs_hi_t = t
        break
if lcs_hi_t:
    print(f"\nLCS_n HIGH at tick {tick(lcs_hi_t)}")

# Find PANVC dispatches (CSA = 0x7F0-0x7FF range)
print("\nPANVC dispatches (o003760-o003777):")
panvc_count = 0
for t, v in csa_ch:
    if 0x7F0 <= v <= 0x7FF:
        lc_val = 0
        for lt, lv in lc_ch:
            if lt <= t:
                lc_val = lv
        print(f"  tick {tick(t):8d}  CSA=o{v:06o}  LC={lc_val}")
        panvc_count += 1
        if panvc_count >= 20:
            print("  ...")
            break

# Find RESTART (CSA = 0)
print("\nRESTART events (CSA=o000000):")
restart_count = 0
for t, v in csa_ch:
    if v == 0 and tick(t) > 10000:
        print(f"  tick {tick(t):8d}")
        restart_count += 1
        if restart_count >= 10:
            print("  ...")
            break
