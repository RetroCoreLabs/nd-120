#!/usr/bin/env python3
"""Trace what happens after o000051 (PANVC) when LC=1 fires.
Shows the CSA sequence following each T.JMPAOPR dispatch."""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fst import open_wave

VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.fst")

WANT = {
    "csa":   "s_debug_csa",
    "lc":    "s_lc_3_0",
    "ldlcn": "s_ldlc_n",
    "mclk":  "s_debug_mclk",
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

id_map = {v[0]: k for k, v in ids.items()}

def tick(t):
    return t // 10 + 1

# Collect all events
events = []  # (t, key, value)

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

# Build time-ordered state machine
# Find: when CSA=o000051 and LC changes to non-zero → show next N CSA values

CSA_PANVC_LOOP = 0o000051  # PANVC wait loop address

print(f"\n=== Tracing CSA sequence after o000051 (PANVC) dispatches ===")
print(f"Total events: {len(events)}")

# State tracking
cur_csa = 0
cur_lc = 0
last_csa_change_t = 0

# Track CSA sequence: when we see CSA=o000051 with LC>0, capture next 20 CSA values
dispatch_count = 0
MAX_DISPATCHES = 5  # Show first 5 PANVC dispatches

in_dispatch = False
dispatch_seq = []
dispatch_lc = 0
dispatch_t = 0

for t, k, v in events:
    if k == "csa":
        prev_csa = cur_csa
        cur_csa = v

        # Track dispatch sequence
        if in_dispatch:
            dispatch_seq.append((t, v))
            if len(dispatch_seq) >= 30:
                in_dispatch = False
                print(f"\nDispatch #{dispatch_count} at tick {tick(dispatch_t)}, LC={dispatch_lc}:")
                print(f"  CSA sequence (up to 30 steps):")
                for seq_t, seq_csa in dispatch_seq:
                    print(f"    tick {tick(seq_t):8d}  CSA=o{seq_csa:06o}")

        # Check for PANVC dispatch: CSA was at o000050 or o000051, now jumping elsewhere
        if prev_csa == CSA_PANVC_LOOP and v != CSA_PANVC_LOOP and v != 0o000050:
            if cur_lc > 0 and dispatch_count < MAX_DISPATCHES:
                dispatch_count += 1
                in_dispatch = True
                dispatch_seq = [(t, v)]
                dispatch_lc = cur_lc
                dispatch_t = t

    elif k == "lc":
        cur_lc = v

print(f"\nTotal PANVC dispatches found: {dispatch_count}")
print(f"(Showing first {MAX_DISPATCHES})")

# Also show: what is the max tick in the waveform
if events:
    max_t = max(e[0] for e in events)
    print(f"\nWaveform ends at tick {tick(max_t)}")
