#!/usr/bin/env python3
"""Trace CONN latch and CONTINUE signal in DGA POW."""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fst import open_wave

VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.fst")

WANT = {
    "csa":      "s_debug_csa",
    "conn_n":   "POW.s_conn_n",
    "cont_n":   "POW.s_continue_n",
    "stp":      "POW.s_stp",
    "stp_n":    "POW.s_stp_n",
    "a579":     "POW.s_a579_out_n",
    "a580":     "POW.a580_nand_out",
    "start":    "POW.s_start",
    "start_n":  "POW.s_start_n",
    "sstop_n":  "POW.s_sstop_n",
    "clear_n":  "POW.s_clear_n",
    "stop_n":   "POW.s_stop_n",
    "idb2":     "POW.s_idb2",
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
    print("  %-12s  id=%r  %3dbit  %s" % (k, sid, bits, full))

missing = set(WANT) - set(ids)
if missing:
    print("\nMISSING: %s" % missing)

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

print("\nTotal events: %d" % len(events))

# Build state, show changes when conn_n changes
state = {k: None for k in WANT}

changes = []
for t, k, v in events:
    old = state[k]
    state[k] = v
    if k == "conn_n" and old != v:
        changes.append((t, v, dict(state)))

print("\nconn_n changes: %d" % len(changes))
for t, v, snap in changes[:10]:
    print("\n  tick %8d: conn_n -> %d" % (tick(t), v))
    for sig in ["csa", "cont_n", "stp", "stp_n", "a579", "a580", "start", "start_n", "sstop_n", "clear_n", "stop_n", "idb2"]:
        sv = snap.get(sig)
        if sv is not None:
            if sig == "csa":
                print("    %-12s = o%06o" % (sig, sv))
            else:
                print("    %-12s = %d" % (sig, sv))

# Show events around first conn_n change
if changes:
    first_conn_t = changes[0][0]
    print("\n=== Events around first conn_n change at tick %d ===" % tick(first_conn_t))
    for i, (t, k, v) in enumerate(events):
        if t == first_conn_t and k == "conn_n":
            start_i = max(0, i - 60)
            end_i = min(len(events), i + 60)
            for t2, k2, v2 in events[start_i:end_i]:
                marker = " <-- CONN_N" if (t2 == first_conn_t and k2 == "conn_n") else ""
                if k2 in ("conn_n", "cont_n", "stp", "start", "a579", "a580", "sstop_n", "start_n", "stop_n", "csa"):
                    if k2 == "csa":
                        print("  tick %8d  %-12s = o%06o%s" % (tick(t2), k2, v2, marker))
                    else:
                        print("  tick %8d  %-12s = %d%s" % (tick(t2), k2, v2, marker))
            break
