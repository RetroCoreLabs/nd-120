#!/usr/bin/env python3
"""Show CSA changes in the window just before LC=1 at o000051 (tick ~738968)."""

import os
VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.vcd")
id_csa = "s_"
id_lc  = ",D"

# Time window: tick 738700 to 739200 (covers LC=0 at o001156 through LC=1 at o000051)
TICK_LO = 738700
TICK_HI = 739200

csa_events = []
lc_events  = []
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

        tick = cur_t // 10 + 1
        if tick < TICK_LO:
            continue
        if tick > TICK_HI:
            break

        if line[0] in "bBrR":
            parts = line.split(None, 1)
            if len(parts) == 2:
                val = parts[0][1:]
                sid = parts[1].strip()
                if sid == id_csa:
                    try:
                        csa_events.append((cur_t, int(val, 2), "CSA"))
                    except Exception:
                        pass
                elif sid == id_lc:
                    try:
                        lc_events.append((cur_t, int(val, 2), "LC"))
                    except Exception:
                        pass
        elif line[0] in "01xXzZ":
            sid = line[1:]
            if sid == id_csa:
                try:
                    csa_events.append((cur_t, int(line[0]), "CSA"))
                except Exception:
                    pass
            elif sid == id_lc:
                try:
                    lc_events.append((cur_t, int(line[0]), "LC"))
                except Exception:
                    pass

# Merge and sort
all_events = sorted(csa_events + lc_events, key=lambda x: x[0])

print("CSA and LC events around first LC=1 at o000051:")
print("%10s  %-6s  %s" % ("tick", "signal", "value(oct)"))
print("-" * 35)
for t, v, sig in all_events:
    tick = t // 10 + 1
    marker = " <-- LC becomes 1" if (sig == "LC" and v == 1) else ""
    print("%10d  %-6s  o%06o%s" % (tick, sig, v, marker))
