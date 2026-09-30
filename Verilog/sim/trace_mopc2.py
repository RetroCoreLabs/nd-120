#!/usr/bin/env python3
"""
Trace sequencer signals (CSA, SC_6_3, COND, LC, regIW/regW) around MOPC
to diagnose why the sim hangs after the first MS20 dispatch.
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.vcd")

# -----------------------------------------------------------------------
# Extended signal discovery (search by substring in full scoped name)
# -----------------------------------------------------------------------
WANT = {
    "csa":     "s_debug_csa",
    "lc":      "s_lc_3_0",
    "fidbo":   "s_debug_fidbo",
    "sc63":    "s_sc_6_3_out",
    "cond":    "s_cond",         # s_cond in CGA (not s_cond_n)
    "regiw":   "regIW",
    "regw":    "regW",
    "etrue":   "s_etrue",
    "efalse":  "s_efalse",
    "mclk":    "s_debug_mclk",
}

def find_ids(vcd_path=VCD, want=WANT):
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
                            found[key] = (p[3], int(p[2]), full)
            elif s.startswith("$enddefinitions"):
                break
    return found

ids = find_ids()
print("Signal IDs found:")
for k, v in sorted(ids.items()):
    print("  %-10s  id=%-6s  width=%-3d  path=%s" % (k, v[0], v[1], v[2]))

missing = [k for k in WANT if k not in ids]
if missing:
    print("\nNOT FOUND:", missing)

id_map = {v[0]: k for k, v in ids.items()}

# -----------------------------------------------------------------------
# Extract all signals
# -----------------------------------------------------------------------
from collections import defaultdict

def extract(vcd_path, id_map, tstart=None, tend=None):
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
    if not changes or t < changes[0][0]:
        return None
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

data = extract(VCD, id_map)

csa_ch = data.get("csa", [])
lc_ch  = data.get("lc",  [])

# -----------------------------------------------------------------------
# Find first MS20 dispatch after tick 500000
# -----------------------------------------------------------------------
MS20 = 0x7F1  # o003761
first_ms20_t = None
for t, v in csa_ch:
    if v == MS20 and tick(t) > 500000:
        first_ms20_t = t
        break

if first_ms20_t is None:
    print("\nERROR: MS20 dispatch not found after tick 500000")
    sys.exit(1)

print("\nFirst MS20 dispatch at tick %d (t=%d ps)" % (tick(first_ms20_t), first_ms20_t))

# -----------------------------------------------------------------------
# Window: 50 ticks before to 1000 ticks after MS20
# -----------------------------------------------------------------------
WIN_BEFORE = 500   # 50 ticks
WIN_AFTER  = 10000 # 1000 ticks
t_lo = first_ms20_t - WIN_BEFORE
t_hi = first_ms20_t + WIN_AFTER

SIGS = ["csa", "lc", "sc63", "cond", "etrue", "efalse", "regiw", "regw", "mclk"]

all_events = []
for sig in SIGS:
    ch = data.get(sig, [])
    for t, v in ch:
        if t_lo <= t <= t_hi:
            all_events.append((t, sig, v))

all_events.sort(key=lambda x: (x[0], x[1]))

# -----------------------------------------------------------------------
# Print
# -----------------------------------------------------------------------
CSA_LABELS = {
    0x7F1: "MS20(PANVC1)",
    0x7F0: "STOP(PANVC0)",
    0x4DB: "o002333",
    0x4DC: "o002334-PUSH",
    0x4DD: "o002335-CHKPRES",
    0x4DE: "o002336-MOPC",
    0x4DF: "o002337",
    0x4E1: "o002341-OPCOM",
    0x000: "RESTART!",
}

print()
print("%10s  %-8s  %-25s  value" % ("tick", "signal", "label"))
print("-" * 70)

prev_csa = None
for t, sig, v in all_events:
    tk = tick(t)
    label = ""
    if sig == "csa":
        label = CSA_LABELS.get(v, "o%06o" % v)
        prev_csa = v
    elif sig == "lc":
        label = "LC=%d" % v
    elif sig == "sc63":
        sc_names = {0: "SEL_JUMP", 1: "SEL_RETURN", 2: "SEL_NEXT", 3: "SEL_REPEAT"}
        label = sc_names.get(v, "?")
    elif sig == "mclk":
        label = "MCLK=%d" % v
    elif sig == "regiw":
        label = "o%06o" % v
    elif sig == "regw":
        label = "o%06o" % v

    if sig in ("csa", "lc", "sc63", "regiw", "regw", "etrue", "efalse"):
        print("%10d  %-8s  %-25s  %s" % (tk, sig, label,
              ("o%06o" % v) if sig in ("csa","regiw","regw") else str(v)))
