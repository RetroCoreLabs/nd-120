#!/usr/bin/env python3
"""Trace LC_3_0 around COMM.CONTINUE → TVEC=016 dispatch to find why LC=0."""
from fst import open_wave
from collections import defaultdict

import os
VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.fst")

WANT = {
    "csa":    "s_debug_csa",
    "lc":     "s_lc_3_0",
    "pan_n":  "s_pan_n",
    "conn_n": "s_conn_n",
    "lcs_n":  "DEBUG_LCS_n",
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
    print(f"  {k:<10}  id={sid}  {bits}bit  {full}")
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

# Focus on the 2nd COMM.CONTINUE at tick 738953 (first one in execution phase)
# Window: 50 ticks before to 100 ticks after
T_CENTER = 738953
T_START  = (T_CENTER - 50) * 10
T_END    = (T_CENTER + 150) * 10

print(f"\nScanning ticks {T_CENTER-50} to {T_CENTER+150}...")
data = extract(VCD, id_map, T_START, T_END)

all_ev = []
for sig, evs in data.items():
    for t, v in evs:
        all_ev.append((t, sig, v))
all_ev.sort()

# Track current state
cur = {}
print(f"\n{'tick':>10}  {'sig':<10}  {'val':<12}  [csa  lc  pan_n  conn_n]")
print("-" * 70)
for t, sig, v in all_ev:
    cur[sig] = v
    if sig in ("csa",):
        val_str = f"o{v:06o}"
    elif sig == "lc":
        val_str = f"o{v:02o} ({v})"
    else:
        val_str = str(v)
    csa    = cur.get("csa", "?")
    lc     = cur.get("lc", "?")
    pan    = cur.get("pan_n", "?")
    conn   = cur.get("conn_n", "?")
    csa_s  = f"o{csa:06o}" if isinstance(csa, int) else "?"
    lc_s   = str(lc) if isinstance(lc, int) else "?"
    print(f"{tick(t):10d}  {sig:<10}  {val_str:<12}  [{csa_s}  LC={lc_s}  pan={pan}  conn={conn}]")

# Also print all LC values in the window
lc_evs = data.get("lc", [])
print(f"\nAll LC transitions in window ({len(lc_evs)}):")
for t, v in lc_evs:
    print(f"  tick {tick(t):10d}  LC={v} (o{v:02o})")
