#!/usr/bin/env python3
"""Show full CSIDBS=o20 window to see exact timing relative to MCLK and TERM_n."""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fst import open_wave

VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.fst")

WANT = {
    "csa":    "s_debug_csa",
    "mclk":   "s_debug_mclk",
    "csidbs": "s_csidbs_4_0",
    "g2n":    "CHIP_33B.G2_n",
    "lua":    "s_LUA_12_0",
    "alu_f":  "DELILAH.ALU.s_f_15_0",
    "maclk":  "ACAL.s_maclk",
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
    print("  %-10s  id=%r  %3dbit  %s" % (k, sid, bits, full))
missing = set(WANT) - set(ids)
if missing:
    print("MISSING:", missing)
print()

id_map = {v[0]: k for k, v in ids.items()}

TARGET_CSA = 0o002335

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

found_t = None
for t, k, v in events:
    if k == "csa" and v == TARGET_CSA:
        found_t = t
        break

if found_t is None:
    print("o002335 not found!")
    sys.exit(0)

print("First o002335 at tick %d" % (found_t//10+1))
print()
# Show from tick before o002335 all the way through o002337
print("=== Events from tick %d to tick %d ===" % (
    (found_t - 10)//10+1, (found_t + 150)//10+1))
print("  %8s  %-10s  %s" % ("tick", "signal", "value"))

for t, k, v in events:
    if t < found_t - 10: continue
    if t > found_t + 150: break
    if k in ("csa", "csidbs", "lua"):
        print("  %8d  %-10s  o%06o" % (t//10+1, k, v))
    elif k == "alu_f":
        print("  %8d  %-10s  o%06o  bit15=%d" % (t//10+1, k, v, (v>>15)&1))
    else:
        print("  %8d  %-10s  %d" % (t//10+1, k, v))
