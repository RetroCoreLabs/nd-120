#!/usr/bin/env python3
"""Trace CSA sequence after MACL tests complete (from o002141 exit to first PANVC dispatch)."""
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

# Find the tick where MACL exits at o002141 → o003666
# Then show all CSA values until we reach o000050 (PANEL loop) for the first time
cur_csa = 0
cur_lc = 0
recording = False
seq = []
MACL_EXIT = 0o003666
PANEL = 0o000050

for t, k, v in events:
    if k == "lc":
        cur_lc = v
    if k == "csa":
        prev = cur_csa
        cur_csa = v

        if v == MACL_EXIT and not recording:
            recording = True
            seq = [(tick(t), v, cur_lc)]
            print(f"Recording starts at tick {tick(t)}, CSA=o{v:06o}")
            continue

        if recording:
            seq.append((tick(t), v, cur_lc))
            # Stop when we've been in PANEL loop for a while
            if len(seq) > 500:
                break
            if v == PANEL and len(seq) > 10:
                # Find first time we hit panel
                break

print(f"\nCSA sequence from o003666 (MACL exit) to first PANEL (o000050):")
print(f"  {'tick':>10}  {'CSA':>10}  LC")
for sq_t, sq_csa, sq_lc in seq:
    notable = ""
    if sq_csa in (0o002235, 0o002236):
        notable = "  *** COMM.START / OPCOM entry ***"
    elif sq_csa == 0o000050:
        notable = "  <<< PANEL loop"
    elif sq_csa == 0o000000:
        notable = "  <<< RESTART"
    elif sq_csa == 0o002001:
        notable = "  <<< exec start"
    elif sq_csa == 0o002203:
        notable = "  <<< STOP handler"
    print(f"  tick {sq_t:8d}  o{sq_csa:06o}  LC={sq_lc}{notable}")
