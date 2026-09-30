#!/usr/bin/env python3
"""Show all g2n/epans_n transitions across the whole simulation alongside CSA."""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fst import open_wave

VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.fst")

WANT = {
    "csa":   "s_debug_csa",
    "g2n":   "CHIP_33B.G2_n",
    "alu_f": "DELILAH.ALU.s_f_15_0",
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
                if len(p) >= 3: scope.append(p[2])
            elif s.startswith("$upscope"):
                if scope: scope.pop()
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
    print("  %-8s  id=%r  %3dbit  %s" % (k, sid, bits, full))
print()

# Build separate event lists per signal
id_to_keys = {}
for k, (sid, bits, full) in ids.items():
    if sid not in id_to_keys:
        id_to_keys[sid] = []
    id_to_keys[sid].append(k)

id_map = {v[0]: k for k, v in ids.items()}

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
        if not line: continue
        if line[0] == "#":
            cur_t = int(line[1:])
            continue
        if line[0] in "bBrR":
            parts = line.split(None, 1)
            if len(parts) == 2:
                sid = parts[1].strip()
                if sid in id_map:
                    k = id_map[sid]
                    try: v = int(parts[0][1:], 2); events.append((cur_t, k, v))
                    except ValueError: pass
        elif line[0] in "01xXzZ":
            sid = line[1:]
            if sid in id_map:
                k = id_map[sid]
                try: v = int(line[0]); events.append((cur_t, k, v))
                except ValueError: pass

print("Total events: %d" % len(events))

# Count g2n transitions
g2n_transitions = [(t, v) for t, k, v in events if k == "g2n"]
print("g2n transitions total: %d" % len(g2n_transitions))
if g2n_transitions:
    print("First 5:")
    for t, v in g2n_transitions[:5]:
        print("  tick %8d  g2n=%d" % (t//10+1, v))
    print("Last 5:")
    for t, v in g2n_transitions[-5:]:
        print("  tick %8d  g2n=%d" % (t//10+1, v))
print()

# Build state and find all g2n=0 windows alongside CSA
state_csa = 0
state_g2n = 1
state_alu_f = 0

# Find first occurrence of CSA=o002335 (=1245)
TARGET = 0o002335
first_target_t = None
for t, k, v in events:
    if k == "csa" and v == TARGET:
        first_target_t = t
        break

if first_target_t is None:
    print("o002335 not found")
    sys.exit(0)

print("First o002335 at tick %d" % (first_target_t//10+1))
print()

# Show all events in window: first_target_t -60 to +100 ns (raw units)
print("=== All events tick %d to tick %d ===" % (
    (first_target_t-60)//10+1, (first_target_t+100)//10+1))
print("  %8s  %-8s  %s" % ("tick", "signal", "value"))

# Reset state to track properly
state = {"csa": 0, "g2n": 1, "alu_f": 0, "mclk": 0}

for t, k, v in events:
    state[k] = v
    if t < first_target_t - 60: continue
    if t > first_target_t + 100: break
    if k == "alu_f":
        print("  %8d  %-8s  o%06o  bit15=%d" % (t//10+1, k, v, (v>>15)&1))
    elif k == "csa":
        print("  %8d  %-8s  o%06o" % (t//10+1, k, v))
    else:
        print("  %8d  %-8s  %d" % (t//10+1, k, v))
