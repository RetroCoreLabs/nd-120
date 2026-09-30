#!/usr/bin/env python3
"""Trace MACL self-tests: show CSA around o002105-o002200 area to find which tests fail.
The test at o002105 checks MACL error count. Failed tests branch to o002155 (STERR).
Show each test address, branch taken, and resulting CSA."""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fst import open_wave

VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.fst")

WANT = {
    "csa":   "s_debug_csa",
    "lc":    "s_lc_3_0",
    "mclk":  "s_debug_mclk",
    "alu_f": "s_f_15_0",
    "alu_q": "s_q_15_0",
    "zf":    "s_zf",
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
                if scope:
                    scope.pop()
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
    print(f"  {k:<10}  id={sid!r}  {bits:3d}bit  {full}")

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
        if not line:
            continue
        if line[0] == "#":
            cur_t = int(line[1:])
            continue
        if line[0] in "bBrR":
            parts = line.split(None, 1)
            if len(parts) == 2:
                sid = parts[1].strip()
                if sid in id_map:
                    k = id_map[sid]
                    try:
                        v = int(parts[0][1:], 2)
                        events.append((cur_t, k, v))
                    except ValueError:
                        pass
        elif line[0] in "01xXzZ":
            sid = line[1:]
            if sid in id_map:
                k = id_map[sid]
                try:
                    v = int(line[0])
                    events.append((cur_t, k, v))
                except ValueError:
                    pass

print(f"Total events: {len(events)}")

# Find first entry to MACL test area (CSA in o002062-o002200 range)
MACL_LO = 0o002062
MACL_HI = 0o002200
STERR = 0o002155  # MACL error jump target

# Track state
cur_csa = 0
cur_lc = 0
cur_zf = 0
cur_f = 0
cur_q = 0

# Collect CSA sequence in MACL area
in_macl = False
macl_seq = []
macl_pass = 0
macl_fail = 0

for t, k, v in events:
    if k == "lc":
        cur_lc = v
    elif k == "zf":
        cur_zf = v
    elif k == "alu_f":
        cur_f = v
    elif k == "alu_q":
        cur_q = v
    elif k == "csa":
        prev_csa = cur_csa
        cur_csa = v

        in_range = MACL_LO <= v <= MACL_HI
        was_in_range = MACL_LO <= prev_csa <= MACL_HI

        if in_range and not was_in_range:
            in_macl = True
            macl_seq = []

        if in_macl:
            macl_seq.append((tick(t), v))

            # Detect STERR entry (test failure)
            if v == STERR and prev_csa != STERR:
                macl_fail += 1
                print(f"\nFAIL #{macl_fail}: jumped to STERR (o{STERR:06o}) from o{prev_csa:06o} at tick {tick(t)}")
                # Show last few CSA steps before failure
                print("  Last steps:")
                for sq_t, sq_csa in macl_seq[-8:]:
                    print(f"    tick {sq_t:8d}  CSA=o{sq_csa:06o}{'  <-- STERR' if sq_csa == STERR else ''}")

            # Detect test PASS: when CSA advances past a test without hitting STERR
            # Tests are spaced ~2 addresses apart, moving forward means passing
            if v == STERR + 1 and prev_csa == STERR:
                pass  # This is continuing after sterr

            # Detect end of MACL area
            if not in_range and was_in_range:
                in_macl = False
                print(f"\n--- Left MACL area at tick {tick(t)}, next CSA=o{v:06o} ---")
                print(f"    Failures: {macl_fail}")
                break

# Also dump the full CSA sequence in MACL area
print(f"\n=== Full CSA sequence in MACL area (o{MACL_LO:06o}-o{MACL_HI:06o}) ===")
# Re-collect
in_macl = False
macl_full = []
for t, k, v in events:
    if k == "csa":
        in_range = MACL_LO <= v <= MACL_HI
        was_prev = in_macl
        if in_range:
            macl_full.append((tick(t), v))
            in_macl = True
        elif was_prev and not in_range:
            macl_full.append((tick(t), v))  # Include first exit CSA
            break

print(f"Total steps in MACL area: {len(macl_full)}")
for sq_t, sq_csa in macl_full:
    marker = "  <-- STERR (FAIL)" if sq_csa == STERR else ""
    marker = "  <<< EXIT" if not (MACL_LO <= sq_csa <= MACL_HI) else marker
    print(f"  tick {sq_t:8d}  CSA=o{sq_csa:06o}{marker}")
