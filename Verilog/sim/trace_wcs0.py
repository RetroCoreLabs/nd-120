#!/usr/bin/env python3
"""Trace WCS write at address 0 (CSA=0) during early LCS loading.
Key question: what microcode content gets written to WCS[0]?"""
from collections import defaultdict

import os
VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.vcd")

# Signals to track — using substring match in full signal path
WANT = {
    "csa":      "s_debug_csa",
    "lcs_n":    "DEBUG_LCS_n",
    "lua":      "CPU_BOARD.CPU.CS.ACAL.LUA_12_0",   # LUA from ACAL
    "wcstb_n":  "CPU_BOARD.CPU.CS.CTL.s_wcstb_n",
    "ww_n":     "CPU_BOARD.CPU.CS.CTL.WW_3_0_n",
    "maclk":    "CPU_BOARD.CPU.CS.ACAL.MACLK",
    "term_n":   "s_term_n",
    "prom":     "CPU_BOARD.CPU.CS.PROM.regData",     # 16-bit PROM output
    "wcs_in":   "CPU_BOARD.CPU.CS.WCS.CSBITS_63_0",  # 64-bit WCS input
    "wcs_out":  "CPU_BOARD.CPU.CS.WCS.CSBITS_63_0_OUT",  # 64-bit WCS output
    "ecsl_n":   "CPU_BOARD.CPU.CS.CTL.s_ecsl_n",
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
    print(f"  {k:<12}  {bits:3d}bit  id={sid:6s}  {full.split('TOP.ND120_TOP.')[-1]}")

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

# Scan first 1000 ticks — covers initial LCS loading of address 0
T_START = 0
T_END = 1000 * 10

print(f"\nScanning ticks 1-1000 (LCS loading of first addresses)...")
data = extract(VCD, id_map, T_START, T_END)

# Merge all events into timeline
all_ev = []
for sig, evs in data.items():
    for t, v in evs:
        all_ev.append((t, sig, v))
all_ev.sort()

cur = {}
print(f"\n{'tick':>8}  {'sig':<12}  {'val':<24}  "
      f"{'csa':>8}  {'lua':>8}  {'wcstb_n':>8}  {'ww_n':>6}  {'prom':>6}")
print("-" * 100)

for t, sig, v in all_ev:
    cur[sig] = v
    # Format val
    if sig in ("csa", "lua"):
        val_str = f"o{v:06o}"
    elif sig in ("wcs_in", "wcs_out"):
        val_str = f"o{v:022o}"
    elif sig == "prom":
        val_str = f"o{v:06o}"
    else:
        val_str = str(v)

    csa  = f"o{cur['csa']:06o}"  if 'csa'  in cur else '?'
    lua  = f"o{cur['lua']:06o}"  if 'lua'  in cur else '?'
    wcs  = str(cur.get('wcstb_n', '?'))
    ww   = str(cur.get('ww_n', '?'))
    prom = f"o{cur['prom']:06o}" if 'prom' in cur else '?'

    print(f"{tick(t):8d}  {sig:<12}  {val_str:<24}  {csa:>8}  {lua:>8}  {wcs:>8}  {ww:>6}  {prom:>6}")

# Also show what WCS[0] contains just before LCS_n goes high
print("\n--- WCS read output at CSA=0 transitions ---")
csa_evs  = data.get("csa", [])
wcs_out  = data.get("wcs_out", [])
wcs_in_e = data.get("wcs_in", [])

wcs_timeline = sorted([(t, "out", v) for t, v in wcs_out] +
                       [(t, "in",  v) for t, v in wcs_in_e])
for t, kind, v in wcs_timeline[:20]:
    print(f"  tick {tick(t):8d}  wcs_{kind} = o{v:022o}")
