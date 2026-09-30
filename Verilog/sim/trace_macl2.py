#!/usr/bin/env python3
"""Trace MACL execution — count restarts, find MOPC, check RTC timing."""
from collections import defaultdict

import os
VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.vcd")

WANT = {
    "csa":    "s_debug_csa",
    "lcs_n":  "DEBUG_LCS_n",
    "pan_n":  "s_pan_n",
    "rtc_n":  "s_rtc_n",
    "conn_n": "s_conn_n",
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
    print(f"  {k:<10}  id={sid}  {bits}bit  {full}")
missing = [k for k in WANT if k not in ids]
if missing:
    print(f"NOT FOUND: {missing}")

id_map = {v[0]: k for k, v in ids.items()}

def tick(t):
    return t // 10 + 1

# Scan first 2M ticks
T_END = 2000000 * 10

results = defaultdict(list)
cur_t = 0
in_data = False
with open(VCD, "r", buffering=8*1024*1024) as f:
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
            if cur_t > T_END:
                break
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

csa_evs  = results.get("csa",    [])
rtc_evs  = results.get("rtc_n",  [])
pan_evs  = results.get("pan_n",  [])
conn_evs = results.get("conn_n", [])
lcs_evs  = results.get("lcs_n",  [])

print(f"\nCSA total transitions: {len(csa_evs)}")
print(f"RTC_n transitions:     {len(rtc_evs)}")
print(f"PAN_n transitions:     {len(pan_evs)}")
print(f"CONN_n transitions:    {len(conn_evs)}")

# LCS_n goes HIGH = end of loading
lcs_high_t = None
for t, v in lcs_evs:
    if v == 1:
        lcs_high_t = t
        print(f"\nLCS_n HIGH at tick {tick(t)}")
        break

# Count o002001 hits (MACL restart)
macl_hits = [(t, v) for t, v in csa_evs if v == 0o002001]
print(f"\nCSA=o002001 (MACL init) count: {len(macl_hits)}")
for t, v in macl_hits[:10]:
    print(f"  tick {tick(t):12d}")

# Count RTC pulses
rtc_lo = [(t, v) for t, v in rtc_evs if v == 0]
print(f"\nRTC pulses (rtc_n→0): {len(rtc_lo)}")
for t, v in rtc_lo[:10]:
    print(f"  tick {tick(t):12d}")

# PAN_n going LOW (panel interrupt active)
pan_lo = [(t, v) for t, v in pan_evs if v == 0]
print(f"\nPAN_n LOW events: {len(pan_lo)}")
for t, v in pan_lo[:10]:
    print(f"  tick {tick(t):12d}")

# Find MS20 (o002335) and MOPC (o002336)
ms20_hits  = [(t, v) for t, v in csa_evs if v == 0o002335]
mopc_hits  = [(t, v) for t, v in csa_evs if v == 0o002336]
comm_hits  = [(t, v) for t, v in csa_evs if v == 0o002172]

print(f"\nCSA=o002335 (MS20)  hits: {len(ms20_hits)}")
if ms20_hits:
    print(f"  First: tick {tick(ms20_hits[0][0])}, Last: tick {tick(ms20_hits[-1][0])}")
print(f"CSA=o002336 (MOPC)  hits: {len(mopc_hits)}")
if mopc_hits:
    print(f"  First: tick {tick(mopc_hits[0][0])}, Last: tick {tick(mopc_hits[-1][0])}")
print(f"CSA=o002172 (COMM)  hits: {len(comm_hits)}")
if comm_hits:
    print(f"  First: tick {tick(comm_hits[0][0])}, Last: tick {tick(comm_hits[-1][0])}")

# Show CSA after last COMM.CONTINUE (to see dispatch path)
if comm_hits:
    last_comm_t = comm_hits[-1][0]
    print(f"\nCSA sequence after last COMM (tick {tick(last_comm_t)}):")
    post = [(t, v) for t, v in csa_evs if t >= last_comm_t]
    for t, v in post[:20]:
        print(f"  tick {tick(t):12d}  CSA=o{v:06o}")
