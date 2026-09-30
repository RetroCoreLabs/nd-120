#!/usr/bin/env python3
"""Trace CSA transitions during MACL execution - look for o002001 restarts."""
from collections import defaultdict

import os
VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.vcd")
WANT = {
    "csa": "s_debug_csa",
    "lcs_n": "DEBUG_LCS_n",
    "pan_n": "CPU_BOARD.IO.DGA.DGA_POW.s_pan_n",
    "rtc_n": "CPU_BOARD.IO.DGA.DGA_POW.s_rtc_n",
    "conn_n": "CPU_BOARD.IO.DGA.DGA_POW.s_conn_n",
}

def find_ids(vcd_path, want):
    scope = []
    found = {}
    with open(vcd_path, "r", buffering=8*1024*1024) as f:
        for line in f:
            s = line.strip()
            if s.startswith(""):
                p = s.split()
                if len(p) >= 3: scope.append(p[2])
            elif s.startswith(""):
                if scope: scope.pop()
            elif s.startswith(""):
                p = s.split()
                if len(p) >= 5:
                    full = ".".join(scope + [p[4]])
                    for key, substr in want.items():
                        if key not in found and substr in full:
                            found[key] = (p[3], int(p[2]), full)
            elif s.startswith(""):
                break
    return found

ids = find_ids(VCD, WANT)
print("Signals found:")
for k, (sid, bits, full) in sorted(ids.items()):
    print(f"  {k:<10}  {bits:3d}bit  {full.split('TOP.ND120_TOP.')[-1]}")
missing = [k for k in WANT if k not in ids]
if missing: print(f"NOT FOUND: {missing}")

id_map = {v[0]: k for k, v in ids.items()}

def tick(t): return t // 10 + 1

# Scan first 800K ticks
T_START = 0
T_END = 800000 * 10

results = defaultdict(list)
cur_t = 0
in_data = False
with open(VCD, "r", buffering=8*1024*1024) as f:
    for line in f:
        if not in_data:
            if "" in line: in_data = True
            continue
        line = line.rstrip()
        if not line: continue
        if line[0] == "#":
            cur_t = int(line[1:])
            if cur_t > T_END: break
            continue
        if cur_t < T_START: continue
        if line[0] in "bBrR":
            parts = line.split(None, 1)
            if len(parts) == 2:
                sid = parts[1].strip()
                if sid in id_map:
                    try: results[id_map[sid]].append((cur_t, int(parts[0][1:], 2)))
                    except: pass
        elif line[0] in "01xXzZ":
            sid = line[1:]
            if sid in id_map:
                try: results[id_map[sid]].append((cur_t, int(line[0])))
                except: pass

csa_evs = results.get("csa", [])
rtc_evs = results.get("rtc_n", [])
pan_evs = results.get("pan_n", [])

print(f"\nCSA total transitions: {len(csa_evs)}")
print(f"RTC_n transitions: {len(rtc_evs)}")
print(f"PAN_n transitions: {len(pan_evs)}")

# Count o002001 hits (MACL restart)
macl_restarts = [(t, v) for t, v in csa_evs if v == 0o002001]
print(f"\nCSA=o002001 (MACL init) count: {len(macl_restarts)}")
for t, v in macl_restarts[:20]:
    print(f"  tick {tick(t):10d}")

# Count RTC pulses (rtc_n transitions to 0)
rtc_pulses = [(t, v) for t, v in rtc_evs if v == 0]
print(f"\nRTC pulses (rtc_n=0): {len(rtc_pulses)}")
for t, v in rtc_pulses[:10]:
    print(f"  tick {tick(t):10d}")

# Show max CSA reached before o557167 (where LCS_n goes high)
lcs_evs = results.get("lcs_n", [])
lcs_high_t = None
for t, v in lcs_evs:
    if v == 1:
        lcs_high_t = t
        print(f"\nLCS_n goes HIGH at tick {tick(t)}")
        break

if lcs_high_t:
    # After LCS, what is max CSA?
    post_lcs = [(t, v) for t, v in csa_evs if t > lcs_high_t]
    if post_lcs:
        max_csa = max(v for t, v in post_lcs)
        print(f"Max CSA after LCS: o{max_csa:06o}")
        # How many steps at o002335 (MS20)?
        ms20 = [(t, v) for t, v in post_lcs if v == 0o002335]
        print(f"CSA=o002335 (MS20) hits: {len(ms20)}")
        if ms20:
            print(f"  First at tick {tick(ms20[0][0])}")
        mopc = [(t, v) for t, v in post_lcs if v == 0o002336]
        print(f"CSA=o002336 (MOPC) hits: {len(mopc)}")
        if mopc:
            print(f"  First at tick {tick(mopc[0][0])}")

