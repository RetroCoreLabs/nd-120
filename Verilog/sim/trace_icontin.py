#!/usr/bin/env python3
"""Trace ICONTIN/CONTINUE chain at tick 1 to find where 0 comes from."""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fst import open_wave

VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.fst")

# Grab ALL signals matching icontin, continue, xcon
SUBSTRINGS = ["icontin", "ICONTIN", "continue", "CONTINUE", "xcon", "XCON", "s_high"]

def find_ids_by_substrings(vcd_path, substrings):
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
                    for sub in substrings:
                        if sub.lower() in full.lower():
                            found[full] = (p[3], int(p[2]))
                            break
            elif s.startswith("$enddefinitions"):
                break
    return found

ids = find_ids_by_substrings(VCD, SUBSTRINGS)
print("All CONTINUE/ICONTIN related signals:")
for full, (sid, bits) in sorted(ids.items()):
    print("  id=%-6r  %3dbit  %s" % (sid, bits, full))

id_to_full = {v[0]: k for k, v in ids.items()}

# Read only tick 1 values (initial values in VCD are set before first timestamp)
state = {}
cur_t = 0
in_data = False
got_first_time = False

with open_wave(VCD) as f:
    for line in f:
        if not in_data:
            if "$enddefinitions" in line:
                in_data = True
            # Also capture initial values before $enddefinitions
            s = line.strip()
            if s and s[0] in "01xXzZ":
                sid = s[1:]
                if sid in id_to_full:
                    state[id_to_full[sid]] = int(s[0])
            elif s.startswith("b") or s.startswith("B"):
                parts = s.split()
                if len(parts) >= 2:
                    sid = parts[1]
                    if sid in id_to_full:
                        try: state[id_to_full[sid]] = int(parts[0][1:], 2)
                        except ValueError: pass
            continue
        line = line.rstrip()
        if not line: continue
        if line[0] == "#":
            cur_t = int(line[1:])
            if cur_t > 50:  # Only read first few ticks
                break
            continue
        if line[0] in "bBrR":
            parts = line.split(None, 1)
            if len(parts) == 2:
                sid = parts[1].strip()
                if sid in id_to_full:
                    try: state[id_to_full[sid]] = int(parts[0][1:], 2)
                    except ValueError: pass
        elif line[0] in "01xXzZ":
            sid = line[1:]
            if sid in id_to_full:
                try: state[id_to_full[sid]] = int(line[0])
                except ValueError: pass

print("\nValues at/near tick 1:")
for full in sorted(state.keys()):
    v = state[full]
    print("  %d  %s" % (v, full))
