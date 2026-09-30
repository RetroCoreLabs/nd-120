#!/usr/bin/env python3
"""Trace CGA_TRAP_TVGEN inputs (INTRQ, PAN, DSTOPN, IFETCH, VACC, VTRAPN, FTRAPN, LEV1, LEV2)
around the COMM.CONTINUE restart at tick ~738956 to understand why TVEC=0 instead of o016."""
import sys
from collections import defaultdict

import os
VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.vcd")

# Search for these substrings anywhere in the full hierarchical signal name
WANT = {
    "csa":      "s_debug_csa",
    "lcs_n":    "s_debug_lcs_n",
    "ifetch":   "s_ifetch",
    "intrq":    "s_iclirq_group",    # iclirq = combined INTRQ into CGA_TRAP
    "pan":      "s_pan",
    "dstop_n":  "s_dstop_n",
    "vtrapn":   "s_vtrapn",
    "ftrapn":   "s_ftrapn",
    "vacc":     "s_vacc",
    "lev1":     "s_lev1",
    "lev2":     "s_lev2",
    "trap_n":   "s_trap_n",         # output TRAP_n from CGA_TRAP
    "tvec":     "s_tvec",
    "tclk":     "s_tclk",
    "mclk":     "s_debug_mclk",
    "aluclk":   "s_aluclk",
    "sstop_n":  "s_sstop_n",
    "term_n":   "s_term_n",
    "run":      "s_run",
}

def find_ids(vcd_path, want):
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

print("Scanning VCD header for signals...")
ids = find_ids(VCD, WANT)
print("Found signals:")
for k, (sid, bits, full) in sorted(ids.items()):
    print(f"  {k:12s}  {bits:3d}bit  {full}")

# Dump ALL signal paths containing "tvec" or "trap" for debugging
print("\n--- Searching for all tvec/trap/dstop/ifetch/intrq/pan signals in VCD header ---")
scope2 = []; candidates = []
with open(VCD, "r", buffering=8*1024*1024) as f:
    for line in f:
        s = line.strip()
        if s.startswith("$scope"):
            p = s.split()
            if len(p) >= 3: scope2.append(p[2])
        elif s.startswith("$upscope"):
            if scope2: scope2.pop()
        elif s.startswith("$var"):
            p = s.split()
            if len(p) >= 5:
                full = ".".join(scope2 + [p[4]])
                name_lower = full.lower()
                if any(kw in name_lower for kw in ["tvec","trap_n","dstop","ifetch","intrq","s_pan","vtrap","ftrap","s_vacc","s_lev"]):
                    candidates.append(f"  {p[3]:6s}  {p[2]:3s}bit  {full}")
        elif s.startswith("$enddefinitions"):
            break
for c in candidates[:60]:
    print(c)
if len(candidates) > 60:
    print(f"  ... ({len(candidates)-60} more)")

id_map = {v[0]: k for k, v in ids.items()}

def extract(vcd_path, id_map, tstart, tend):
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
                if cur_t > tend: break
                continue
            if cur_t < tstart: continue
            if line[0] in "bBrR":
                parts = line.split(None, 1)
                if len(parts) == 2:
                    val_str = parts[0][1:]; sid = parts[1].strip()
                    if sid in id_map:
                        try: results[id_map[sid]].append((cur_t, int(val_str, 2)))
                        except ValueError: results[id_map[sid]].append((cur_t, parts[0][1:]))
            elif line[0] in "01xXzZ":
                sid = line[1:]
                if sid in id_map:
                    results[id_map[sid]].append((cur_t, line[0]))
    return dict(results)

def tick(t): return t // 10 + 1

# Scan 400 ticks before and after the restart at tick 738956
RESTART_TICK = 738956
T_LO = (RESTART_TICK - 400) * 10
T_HI = (RESTART_TICK + 200) * 10

print(f"\nExtracting signals tick {RESTART_TICK-400} to {RESTART_TICK+200}...")
data = extract(VCD, id_map, T_LO, T_HI)

# Merge all events into a timeline
all_ev = []
for sig, evs in data.items():
    for t, v in evs:
        all_ev.append((t, sig, v))
all_ev.sort()

# Track last known values for all signals
last = {}
print(f"\n{'tick':>10}  {'signal':<14}  value")
print("-"*60)
for t, sig, v in all_ev:
    tk = tick(t)
    last[sig] = v
    if sig == "csa":
        print(f"{tk:10d}  {sig:<14}  o{int(v):06o}" if isinstance(v, int) else f"{tk:10d}  {sig:<14}  {v}")
    else:
        print(f"{tk:10d}  {sig:<14}  {v}")

# Print final state of all signals
print("\n--- Signal state summary at end of window ---")
for sig in sorted(WANT.keys()):
    v = last.get(sig, "NOT FOUND")
    print(f"  {sig:<14}  {v}")
