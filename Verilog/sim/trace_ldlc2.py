#!/usr/bin/env python3
"""Trace MCLK, LDLCN, LC at o000016 to see if LDLC actually fires."""
from fst import open_wave
from collections import defaultdict

import os
VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.fst")

WANT = {
    "csa":    "s_debug_csa",
    "lc":     "s_lc_3_0",
    "ldlcn":  "s_ldlc_n",
    "mclk":   "s_debug_mclk",
    "cscomm": "s_cscomm_4_0",
    "csidbs": "s_csidbs_4_0",
    "idb":    "s_cpu_idb_15_0",
    "cd":     "s_cpu_cd_15_0",
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
missing = [k for k in WANT if k not in ids]
if missing:
    print(f"NOT FOUND: {missing}")

id_map = {v[0]: k for k, v in ids.items()}

def tick(t):
    return t // 10 + 1

def extract(vcd_path, id_map, tstart, tend):
    results = defaultdict(list)
    cur_t = 0
    in_data = False
    with open_wave(vcd_path) as f:
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
                if cur_t > tend:
                    break
                continue
            if cur_t < tstart:
                continue
            if line[0] in "bBrR":
                parts = line.split(None, 1)
                if len(parts) == 2:
                    sid = parts[1].strip()
                    if sid in id_map:
                        try:
                            results[id_map[sid]].append((cur_t, int(parts[0][1:], 2)))
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

# Wide window around TVEC dispatch (FST-relative ticks, startTrace=730000)
# Absolute tick 738961 -> FST tick 8961
T_CENTER = 8961
T_START  = (T_CENTER - 5) * 10
T_END    = (T_CENTER + 12) * 10

print(f"\nScanning ticks {T_CENTER-5} to {T_CENTER+12}...")
data = extract(VCD, id_map, T_START, T_END)

all_ev = []
for sig, evs in data.items():
    for t, v in evs:
        all_ev.append((t, sig, v))
all_ev.sort()

print(f"\n{'tick':>10}  {'sig':<10}  {'value':<20}")
print("-" * 44)
cur = {}
for t, sig, v in all_ev:
    cur[sig] = v
    if sig == "csa":
        val_str = f"o{v:06o}"
    elif sig in ("cscomm", "csidbs", "lc"):
        val_str = f"o{v:02o}={v}"
    elif sig in ("idb","cd"):
        val_str = f"o{v:06o}"
    else:
        val_str = str(v)
    print(f"{tick(t):10d}  {sig:<10}  {val_str}")

# Summary
lc_evs = data.get("lc", [])
ldlcn_evs = data.get("ldlcn", [])
mclk_evs = data.get("mclk", [])

print(f"\nLC events: {len(lc_evs)}")
for t, v in lc_evs:
    print(f"  tick {tick(t)}: LC={v} o{v:02o}")

print(f"\nLDLCN events: {len(ldlcn_evs)}")
for t, v in ldlcn_evs:
    print(f"  tick {tick(t)}: LDLCN={v}")

print(f"\nMCLK events (0=rising→falling, 1=low→high): {len(mclk_evs)}")
for t, v in mclk_evs:
    print(f"  tick {tick(t)}: MCLK={v}")
