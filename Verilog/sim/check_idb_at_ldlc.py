#!/usr/bin/env python3
"""Find what drives IDB at COMM.LDLC (o000051) at tick ~738968."""

import os
VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.vcd")

# Find signal IDs for signals of interest
want_names = {
    "s_debug_fidbo",   # FIDBO on top-level debug
    "s_debug_csa",     # CSA
}

import re

scope = []
found_ids = {}

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
                base = re.sub(r'\[\d+:\d+\]$', '', full)
                for wn in want_names:
                    if wn in base and wn not in found_ids:
                        found_ids[wn] = (p[3], int(p[2]))
                        print("Found: %s  ID=%s  w=%s  full=%s" % (wn, p[3], p[2], full))
        elif s.startswith("$enddefinitions"):
            break

print("\nSearching for changes near tick 738950-739000...")
print("%10s  %-20s  value(oct)" % ("tick", "signal"))
print("-" * 50)

id_map = {v[0]: (k, v[1]) for k, v in found_ids.items()}
cur_t = 0
TICK_LO = 738950
TICK_HI = 739010

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
                if sid in id_map:
                    name, width = id_map[sid]
                    try:
                        v = int(val, 2)
                        print("%10d  %-20s  o%06o  (dec=%d)" % (tick, name, v, v))
                    except Exception:
                        print("%10d  %-20s  %s" % (tick, name, val))
        elif line[0] in "01xXzZ":
            sid = line[1:]
            if sid in id_map:
                name, width = id_map[sid]
                try:
                    v = int(line[0])
                    print("%10d  %-20s  o%06o  (dec=%d)" % (tick, name, v, v))
                except Exception:
                    pass
