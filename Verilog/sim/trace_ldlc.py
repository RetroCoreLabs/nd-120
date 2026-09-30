#!/usr/bin/env python3
"""Trace LDLCN, LC, CSCOMM around o000016 to confirm if LDLC fires."""
from fst import open_wave
from collections import defaultdict

import os
VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.fst")

WANT = {
    "csa":    "s_debug_csa",
    "lc":     "s_lc_3_0",
    "ldlcn":  "s_ldlc_n",
    "cscomm": "s_cscomm_4_0",
    "csidbs": "s_csidbs_4_0",
    "csbits": "s_csbits",
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

# Focus tight window around first COMM.CONTINUE in execution (tick 738953)
T_CENTER = 738961  # CSA=o000016
T_START  = (T_CENTER - 3) * 10
T_END    = (T_CENTER + 10) * 10

print(f"\nScanning ticks {T_CENTER-3} to {T_CENTER+10}...")
data = extract(VCD, id_map, T_START, T_END)

all_ev = []
for sig, evs in data.items():
    for t, v in evs:
        all_ev.append((t, sig, v))
all_ev.sort()

print(f"\n{'tick':>10}  {'sig':<10}  {'val':<18}  [csa  ldlcn  lc  cscomm  csidbs]")
print("-" * 80)
cur = {}
for t, sig, v in all_ev:
    cur[sig] = v
    if sig == "csa":
        val_str = f"o{v:06o}"
    elif sig in ("cscomm", "csidbs", "lc"):
        val_str = f"o{v:02o}={v}"
    elif sig == "ldlcn":
        val_str = str(v)
    elif sig == "csbits":
        # Show bits[41:32] to see CSIDBS+CSCOMM region
        val_str = f"[41:32]={((v>>32) & 0x3FF):010b}"
    else:
        val_str = str(v)
    csa    = cur.get("csa", "?")
    ldlcn  = cur.get("ldlcn", "?")
    lc     = cur.get("lc", "?")
    cscomm = cur.get("cscomm", "?")
    csidbs = cur.get("csidbs", "?")
    csa_s  = f"o{csa:06o}" if isinstance(csa, int) else "?"
    print(f"{tick(t):10d}  {sig:<10}  {val_str:<18}  [{csa_s}  ldlcn={ldlcn}  lc={lc}  comm=o{cscomm:02o} idbs=o{csidbs:02o}]" if isinstance(cscomm,int) and isinstance(csidbs,int) else f"{tick(t):10d}  {sig:<10}  {val_str:<18}")

# Show unique CSCOMM values around o000016
print("\n--- CSCOMM seen at CSA=o000016 ---")
csa_evs = data.get("csa", [])
comm_evs = data.get("cscomm", [])
idbs_evs = data.get("csidbs", [])

t_pan = None
for t, v in csa_evs:
    if v == 0o000016:
        t_pan = t
        print(f"CSA=o000016 at tick {tick(t)}")
        break

if t_pan:
    # Find CSCOMM/CSIDBS values near this tick
    for t, v in comm_evs:
        if abs(t - t_pan) <= 50:
            print(f"  CSCOMM at tick {tick(t)}: o{v:02o} ({v})")
    for t, v in idbs_evs:
        if abs(t - t_pan) <= 50:
            print(f"  CSIDBS at tick {tick(t)}: o{v:02o} ({v})")

print("\nExpected for LDLC: CSCOMM = o17 (=15 = 0b01111)")
