#!/usr/bin/env python3
"""Find EPANS, PANCAL, and IDB signals in the FST."""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fst import open_wave

VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.fst")
SUBS = ["epans", "EPANS", "pres", "pancal", "PANCAL", "idb_15_0_chip",
        "debug_csa", "s_f_15_0", "idb_15_0_out", "EPANSN"]

scope = []
found = []
count = 0
with open_wave(VCD) as f:
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
                count += 1
                for sub in SUBS:
                    if sub.lower() in full.lower():
                        found.append(full)
                        break
        elif s.startswith("$enddefinitions"):
            break

print("Total signals: %d" % count)
for x in sorted(found):
    print(x)
