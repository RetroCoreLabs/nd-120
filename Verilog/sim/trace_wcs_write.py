#!/usr/bin/env python3
"""Trace the complete WCS write sequence for the first few addresses during LCS loading.
Focus on what value WCS[0] ends up with, and how it compares to execution read."""
from collections import defaultdict

import os
VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.vcd")

WANT = {
    "csa":      "s_debug_csa",
    "lcs_n":    "DEBUG_LCS_n",
    "lua":      "CPU_BOARD.CPU.CS.ACAL.LUA_12_0",
    "wcstb_n":  "CPU_BOARD.CPU.CS.CTL.s_wcstb_n",
    "ww_n":     "CPU_BOARD.CPU.CS.CTL.WW_3_0_n",
    "maclk":    "CPU_BOARD.CPU.CS.ACAL.MACLK",
    "term_n":   "s_term_n",
    "wcs_in":   "CPU_BOARD.CPU.CS.WCS.CSBITS_63_0",
    "wcs_out":  "CPU_BOARD.CPU.CS.WCS.CSBITS_63_0_OUT",
    "csbits":   "CPU_BOARD.CPU.CS.CSBITS",   # final CSBITS going to CPU
}

def find_ids(vcd_path, want):
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

ids = find_ids(VCD, WANT)
print("Signals found:")
for k, (sid, bits, full) in sorted(ids.items()):
    print(f"  {k:<12}  {bits:3d}bit  {full.split('TOP.ND120_TOP.')[-1]}")

missing = [k for k in WANT if k not in ids]
if missing:
    print(f"NOT FOUND: {missing}")

id_map = {v[0]: k for k, v in ids.items()}

def extract(vcd_path, id_map, tstart=None, tend=None):
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
            if tstart is not None and cur_t < tstart:
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

def tick(t):
    return t // 10 + 1

# Scan ticks 1-200: capture full write sequence for address 0
T_START = 0
T_END = 200 * 10

print(f"\nScanning ticks 1-200 (initial LCS loading)...")
data = extract(VCD, id_map, T_START, T_END)

# Merge all events
all_ev = []
for sig, evs in data.items():
    for t, v in evs:
        all_ev.append((t, sig, v))
all_ev.sort()

cur = {}
prev_csa = None

print(f"\n{'tick':>8}  {'sig':<12}  {'val':<24}  csa:lua  wcstb  ww")
print("-" * 75)

for t, sig, v in all_ev:
    cur[sig] = v
    if sig in ("csa", "lua"):
        val_str = f"o{v:06o}"
    elif sig in ("wcs_in", "wcs_out", "csbits"):
        val_str = f"o{v:022o}"
    else:
        val_str = str(v)

    csa = cur.get("csa", "?")
    lua = cur.get("lua", "?")
    cl = f"o{csa:05o}:o{lua:05o}" if isinstance(csa, int) and isinstance(lua, int) else "?:?"
    wcs = str(cur.get("wcstb_n", "?"))
    ww  = str(cur.get("ww_n", "?"))

    if sig in ("csa", "lua", "wcstb_n", "wcs_in", "wcs_out", "csbits", "lcs_n"):
        print(f"{tick(t):8d}  {sig:<12}  {val_str:<24}  {cl}  {wcs:>5}  {ww}")

# Also: find the final stable wcs_out value for address 0 before CSA changes
print("\n--- WCS_IN final stable value at address 0 ---")
wcs_in_evs = data.get("wcs_in", [])
csa_evs    = data.get("csa", [])

# Find when CSA changes from 0 to 1
csa_change_t = None
prev = 0
for t, v in csa_evs:
    if prev == 0 and v != 0:
        csa_change_t = t
        break
    prev = v

if csa_change_t:
    print(f"CSA changes from 0 to o{prev:06o}→{v:06o} at tick {tick(csa_change_t)}")
    # Find the last wcs_in value before csa_change_t
    for t, v in reversed(wcs_in_evs):
        if t <= csa_change_t:
            print(f"Last wcs_in at CSA=0: tick {tick(t):8d}  o{v:022o}")
            break
else:
    print("CSA never changed from 0 in this window")

# Now scan the execution phase — what does WCS[0] output when CSA=0 after LCS_n HIGH
print("\n--- Scanning execution phase for first CSA=0 occurrence ---")
T_LCS_HIGH = 557167 * 10  # from earlier analysis
T_EXEC_END = (T_LCS_HIGH + 5000) * 10

data2 = extract(VCD, id_map, T_LCS_HIGH, T_LCS_HIGH + 200*10)
all_ev2 = []
for sig, evs in data2.items():
    for t, v in evs:
        all_ev2.append((t, sig, v))
all_ev2.sort()

cur2 = {}
print(f"\n{'tick':>10}  {'sig':<12}  {'val':<24}  csa:lua")
for t, sig, v in all_ev2:
    cur2[sig] = v
    if sig in ("csa", "lua"):
        val_str = f"o{v:06o}"
    elif sig in ("wcs_in", "wcs_out", "csbits"):
        val_str = f"o{v:022o}"
    else:
        val_str = str(v)
    csa = cur2.get("csa", "?")
    lua = cur2.get("lua", "?")
    cl = f"o{csa:05o}:o{lua:05o}" if isinstance(csa, int) and isinstance(lua, int) else "?:?"
    if sig in ("csa", "lcs_n", "wcs_out", "csbits", "lua"):
        print(f"{tick(t):10d}  {sig:<12}  {val_str:<24}  {cl}")
