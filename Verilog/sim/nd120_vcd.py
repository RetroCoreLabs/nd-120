#!/usr/bin/env python3
"""
Shared VCD utilities for ND-120 analysis.
Dynamically discovers signal IDs from the VCD header.
"""
import re

import os
VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.vcd")

# Signal name substrings to search for (matched against full scoped name)
WANT = {
    "csa":   "s_debug_csa",
    "lc":    "s_lc_3_0",
    "fidbo": "s_debug_fidbo",
}


def find_ids(vcd_path=VCD, want=WANT):
    """Parse VCD header, return {key: (id, width)} for each wanted signal."""
    scope = []
    found = {}
    with open(vcd_path, "r", buffering=8*1024*1024) as f:
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
                            found[key] = (p[3], int(p[2]))
            elif s.startswith("$enddefinitions"):
                break
    return found


def extract(vcd_path, id_map, tstart=None, tend=None):
    """
    Stream VCD data section.
    id_map: {signal_id: key_name}
    Returns {key_name: [(time_ps, int_value), ...]}
    """
    from collections import defaultdict
    results = defaultdict(list)
    cur_t = 0
    in_data = False
    with open(vcd_path, "r", buffering=8*1024*1024) as f:
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
                if tend is not None and cur_t > tend:
                    break
                continue
            if tstart is not None and cur_t < tstart:
                continue
            if line[0] in "bBrR":
                parts = line.split(None, 1)
                if len(parts) == 2:
                    val_str = parts[0][1:]
                    sid = parts[1].strip()
                    if sid in id_map:
                        try:
                            results[id_map[sid]].append((cur_t, int(val_str, 2)))
                        except ValueError:
                            pass
            elif line[0] in "01xXzZ":
                sid = line[1:]
                if sid in id_map:
                    try:
                        results[id_map[sid]].append((cur_t, int(line[0])))
                    except ValueError:
                        pass
    return dict(results)


def val_at(changes, t):
    """Binary search: value of signal at time t (last change <= t)."""
    if not changes or t < changes[0][0]:
        return 0
    lo, hi = 0, len(changes) - 1
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if changes[mid][0] <= t:
            lo = mid
        else:
            hi = mid - 1
    return changes[lo][1]


def tick(t_ps):
    return t_ps // 10 + 1
