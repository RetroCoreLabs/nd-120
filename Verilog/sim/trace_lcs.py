#!/usr/bin/env python3
"""Trace LCS_n transitions to understand loading sequence."""
import os
VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.vcd")
WANT = {"lcs_n": "DEBUG_LCS_n"}

scope = []
found = {}
with open(VCD, "r", buffering=8*1024*1024) as f:
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
                for key, substr in WANT.items():
                    if key not in found and substr in full:
                        found[key] = (p[3], int(p[2]), full)
        elif s.startswith("$enddefinitions"):
            break

print("Found:", {k: (sid, full) for k, (sid, bits, full) in found.items()})
id_map = {v[0]: k for k, v in found.items()}

lcs_evs = []
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
            if cur_t > 600000 * 10:
                break
            continue
        elif line[0] in "01xXzZ":
            sid = line[1:]
            if sid in id_map:
                try:
                    lcs_evs.append((cur_t, int(line[0])))
                except:
                    pass

print("\nAll LCS_n transitions (first 600K ticks): " + str(len(lcs_evs)))
for t, v in lcs_evs[:30]:
    print("  tick " + str(t//10+1) + "  LCS_n=" + str(v))
