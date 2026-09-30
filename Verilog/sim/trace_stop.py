#!/usr/bin/env python3
"""Trace XSTP (stop flip-flop) to see when it's set/cleared."""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fst import open_wave

VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.fst")

WANT = {
    "csa":   "s_debug_csa",
    "xstp":  "s_debug_cc_term",  # try various debug signals
    "run":   "s_run",
}

# Try to find XSTP signal - it may be under different paths
WANT2 = {
    "csa":   "s_debug_csa",
    "xstp1": "XSTP",
    "xstp2": "s_stp",
    "stp_n": "s_stp_n",
    "run":   "s_run",
    "clear": "s_clear_n",
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
                    name = p[4]
                    for key, substr in want.items():
                        if key not in found and substr in full:
                            found[key] = (p[3], int(p[2]), full)
            elif s.startswith("$enddefinitions"):
                break
    return found

ids = find_ids(VCD, WANT2)
print("Signals found:")
for k, (sid, bits, full) in sorted(ids.items()):
    print(f"  {k:<10}  id={sid!r}  {bits:3d}bit  {full}")

id_map = {v[0]: k for k, v in ids.items()}

def tick(t):
    return t // 10 + 1

events = []
cur_t = 0
in_data = False

with open_wave(VCD) as f:
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
            continue
        if line[0] in "bBrR":
            parts = line.split(None, 1)
            if len(parts) == 2:
                sid = parts[1].strip()
                if sid in id_map:
                    k = id_map[sid]
                    try:
                        v = int(parts[0][1:], 2)
                        events.append((cur_t, k, v))
                    except ValueError:
                        pass
        elif line[0] in "01xXzZ":
            sid = line[1:]
            if sid in id_map:
                k = id_map[sid]
                try:
                    v = int(line[0])
                    events.append((cur_t, k, v))
                except ValueError:
                    pass

print(f"\nTotal events: {len(events)}")
print(f"\nFirst 50 events with XSTP/STP/CLEAR signals:")
count = 0
for t, k, v in events:
    if k in ("xstp1", "xstp2", "stp_n", "clear"):
        print(f"  tick {tick(t):8d}  {k}={v}")
        count += 1
        if count >= 50:
            break

# Count how often each appears
print("\nAll XSTP/STP changes:")
for t, k, v in events:
    if k in ("xstp1", "xstp2", "stp_n"):
        print(f"  tick {tick(t):8d}  {k}={v}")
