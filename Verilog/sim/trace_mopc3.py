#!/usr/bin/env python3
"""Trace signals around o002336→o002337→o000000 to find why MOPC restarts."""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fst import open_wave

VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.fst")

WANT = {
    "csa":    "s_debug_csa",
    "lc":     "s_lc_3_0",
    "mclk":   "s_debug_mclk",
    "lcs":    "s_debug_lcs_n",
    "run":    "s_run",
    "mr":     "s_debug_mr_n",
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

# Build per-tick state
# Find the first o002336 visit and print all events around it ±20 ticks
cur = {k: 0 for k in WANT}
cur["mr"] = 1  # active low, start high

# Find first occurrence of CSA=o002336
target_tick = None
for t, k, v in events:
    if k == "csa" and v == 0o002336:
        target_tick = tick(t)
        break

if target_tick is None:
    print("CSA=o002336 never seen!")
else:
    print(f"\nFirst visit to o002336 at tick {target_tick}")
    print(f"Showing all events from tick {target_tick-5} to {target_tick+60}:\n")

    t_low  = (target_tick - 5) * 10
    t_high = (target_tick + 60) * 10

    for t, k, v in events:
        if t < t_low:
            continue
        if t > t_high:
            break
        if k == "csa":
            print(f"  tick {tick(t):8d}  CSA=o{v:06o}")
        elif k == "mclk":
            print(f"  tick {tick(t):8d}  MCLK={'1' if v else '0'}")
        elif k == "lcs":
            print(f"  tick {tick(t):8d}  LCS_n={'1' if v else '0'}")
        elif k == "run":
            print(f"  tick {tick(t):8d}  RUN={'1' if v else '0'}")
        elif k == "mr":
            print(f"  tick {tick(t):8d}  MR_n={'1' if v else '0'}")
        elif k == "lc":
            print(f"  tick {tick(t):8d}  LC={v} (o{v:02o})")
