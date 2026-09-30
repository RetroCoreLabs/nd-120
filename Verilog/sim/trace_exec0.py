#!/usr/bin/env python3
"""Trace CSA=o000000 moment during execution — what does WCS[0] return?
Also trace LUA to see if it correctly points to 0."""
from collections import defaultdict

import os
VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.vcd")

WANT = {
    "csa":      "s_debug_csa",
    "lcs_n":    "DEBUG_LCS_n",
    "lua":      "CPU_BOARD.CPU.CS.ACAL.LUA_12_0",
    "term_n":   "s_term_n",
    "wcs_out":  "CPU_BOARD.CPU.CS.WCS.CSBITS_63_0_OUT",
    "csbits":   "CPU_BOARD.CPU.CS.CSBITS",
    "maclk":    "CPU_BOARD.CPU.CS.ACAL.MACLK",
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

# Focus on the COMM.CONTINUE → o000000 moment
# From trace_tvec2.py: CSA=o002172 at tick 738953, CSA=o000000 at tick 738956
T_CENTER = 738953
T_START  = (T_CENTER - 5) * 10
T_END    = (T_CENTER + 20) * 10

print(f"\nScanning ticks {T_CENTER-5} to {T_CENTER+20}...")
data = extract(VCD, id_map, T_START, T_END)

all_ev = []
for sig, evs in data.items():
    for t, v in evs:
        all_ev.append((t, sig, v))
all_ev.sort()

cur = {}
print(f"\n{'tick':>10}  {'sig':<12}  {'val':<24}  csa:lua  maclk  term_n")
print("-" * 85)
for t, sig, v in all_ev:
    cur[sig] = v
    if sig in ("csa", "lua"):
        val_str = f"o{v:06o}"
    elif sig in ("wcs_out", "csbits"):
        val_str = f"o{v:022o}"
    else:
        val_str = str(v)
    csa = cur.get("csa", "?")
    lua = cur.get("lua", "?")
    cl = f"o{csa:05o}:o{lua:05o}" if isinstance(csa, int) and isinstance(lua, int) else "?:?"
    mclk = str(cur.get("maclk", "?"))
    tn   = str(cur.get("term_n", "?"))
    print(f"{tick(t):10d}  {sig:<12}  {val_str:<24}  {cl}  {mclk:>6}  {tn:>7}")

# Summary: what is the WCS_OUT value when CSA=o000000?
print("\n--- Summary ---")
csa_evs = data.get("csa", [])
wcs_evs = data.get("wcs_out", [])
lua_evs = data.get("lua", [])

# Find moment when CSA=0
for t, v in csa_evs:
    if v == 0:
        print(f"CSA=0 at tick {tick(t)}")
        # Find wcs_out around this time
        for wt, wv in wcs_evs:
            if abs(wt - t) <= 50:  # within 5 ticks
                print(f"  wcs_out at tick {tick(wt)}: o{wv:022o}")

print("\nExpected: WCS[0] = o0200000010140012342001 (written during LCS loading)")
print("          Then CSA should step to o000050 (or via trap)")
