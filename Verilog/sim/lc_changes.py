#!/usr/bin/env python3
"""Show all LC changes with CSA context."""

import os
VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.vcd")
id_csa = "s_"
id_lc  = ",D"

csa_changes = []
lc_changes  = []
cur_t = 0

with open(VCD, "r", buffering=8*1024*1024) as f:
    in_data = False
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
                val = parts[0][1:]
                sid = parts[1].strip()
                if sid == id_csa:
                    try:
                        csa_changes.append((cur_t, int(val, 2)))
                    except Exception:
                        pass
                elif sid == id_lc:
                    try:
                        lc_changes.append((cur_t, int(val, 2)))
                    except Exception:
                        pass
        elif line[0] in "01xXzZ":
            sid = line[1:]
            if sid == id_csa:
                try:
                    csa_changes.append((cur_t, int(line[0])))
                except Exception:
                    pass
            elif sid == id_lc:
                try:
                    lc_changes.append((cur_t, int(line[0])))
                except Exception:
                    pass


def csa_at(t):
    lo, hi = 0, len(csa_changes) - 1
    if not csa_changes or t < csa_changes[0][0]:
        return 0
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if csa_changes[mid][0] <= t:
            lo = mid
        else:
            hi = mid - 1
    return csa_changes[lo][1]


print("All LC changes with CSA context:")
print("%10s  %8s  %8s   %s" % ("tick", "LC(oct)", "LC(dec)", "CSA(oct)"))
print("-" * 55)
for t, lc in lc_changes:
    tick = t // 10 + 1
    csa = csa_at(t)
    print("%10d  o%06o  %8d   o%06o" % (tick, lc, lc, csa))
