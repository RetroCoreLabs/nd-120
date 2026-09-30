#!/usr/bin/env python3
"""Trace MS20 execution in detail."""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fst import open_wave

VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.fst")

WANT = {
    "csa":    "s_debug_csa",
    "lc":     "s_lc_3_0",
    "mclk":   "s_debug_mclk",
    "alu_f":  "s_f_15_0",
    "alu_q":  "s_q_15_0",
    "zf":     "s_zf",
    "cond":   "s_cond",
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
    print("  %-8s  id=%-6r  %3dbit  %s" % (k, sid, bits, full))

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

print("Total events:", len(events))

MS20_ENTRY = 0o002333
RESTART    = 0o000000

state = {k: 0 for k in WANT}
in_ms20 = False
ms20_start_t = 0
ms20_events = []

for t, k, v in events:
    state[k] = v
    if k == "csa":
        if v == MS20_ENTRY and not in_ms20:
            in_ms20 = True
            ms20_start_t = t
            ms20_events = []
        if in_ms20:
            ms20_events.append((t, dict(state)))
            if v == RESTART and len(ms20_events) > 2:
                break
            if len(ms20_events) > 200:
                break

print("\n=== MS20 detail (first entry tick %d) ===" % tick(ms20_start_t))
print("  %-10s  %-8s  %-5s  %-8s  %-8s  %-5s  %-5s" % (
    "tick", "CSA", "LC", "ALU_F", "ALU_Q", "ZF", "COND"))

prev_csa = -1
for t, snap in ms20_events:
    csa = snap.get("csa", 0)
    if csa != prev_csa:
        lc   = snap.get("lc", 0)
        f    = snap.get("alu_f", 0)
        q    = snap.get("alu_q", 0)
        zf   = snap.get("zf", 0)
        cond = snap.get("cond", 0)
        note = ""
        if csa == 0o002335: note = "  <-- MIPANS check"
        elif csa == 0o002336: note = "  <-- MOPC entry"
        elif csa == 0o000000: note = "  <-- RESTART"
        elif csa in (0o000513, 0o000514): note = "  <-- subroutine"
        print("  tick %8d  o%06o  LC=%-3d  F=o%06o  Q=o%06o  ZF=%d  COND=%d%s" % (
            tick(t), csa, lc, f, q, zf, cond, note))
        prev_csa = csa
