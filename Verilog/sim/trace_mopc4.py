#!/usr/bin/env python3
"""Extended MOPC trace: show full CSA sequence for each PANVC dispatch (up to 200 steps each)."""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fst import open_wave

VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.fst")

WANT = {
    "csa":   "s_debug_csa",
    "lc":    "s_lc_3_0",
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

print(f"Total events: {len(events)}")

cur_csa = 0
cur_lc = 0
in_dispatch = False
dispatch_seq = []
dispatch_count = 0
MAX_DISPATCHES = 3  # Show first 3 full dispatches
MAX_STEPS = 200

for t, k, v in events:
    if k == "lc":
        cur_lc = v

    if k == "csa":
        prev_csa = cur_csa
        cur_csa = v

        if in_dispatch:
            dispatch_seq.append((tick(t), v))
            # Stop when we return to the PANEL loop or get 200 steps
            if v in (0o000050, 0o000051, 0o000000) or len(dispatch_seq) >= MAX_STEPS:
                in_dispatch = False
                entry = dispatch_seq[0][1] if dispatch_seq else -1
                print(f"\n--- Dispatch #{dispatch_count}: entry=o{entry:06o}, {len(dispatch_seq)} steps ---")
                for sq_tick, sq_csa in dispatch_seq:
                    print(f"  tick {sq_tick:8d}  CSA=o{sq_csa:06o}")

        # Detect dispatch: from o000052 jumping away (not to o000053)
        if prev_csa == 0o000052 and v not in (0o000050, 0o000051, 0o000052, 0o000053):
            if dispatch_count < MAX_DISPATCHES:
                dispatch_count += 1
                in_dispatch = True
                dispatch_seq = [(tick(t), v)]

print(f"\nDone. Dispatches shown: {dispatch_count}")
