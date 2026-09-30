#!/usr/bin/env python3
"""Narrow window around tick 738956: capture TVEC input signals at each TCLK edge."""
from collections import defaultdict

import os
VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.vcd")

# Use exact VCD signal IDs found by trace_tvec.py
WANT = {
    "csa":        "s_debug_csa",
    "tvec":       "s_tvec_3_0",        # TVEC inside DELILAH
    "tclk":       "s_tclk",
    "mclk":       "s_debug_mclk",
    "term_n":     "s_term_n",
    "aluclk":     "s_aluclk",
    # TVGEN inputs (active-high inside CGA_TRAP)
    "dstop_n":    "s_dstop_n",         # DSTOPN — active-high
    "dstopn_grp": "s_dstopn_group",    # raw NAND gate output
    "ifetchn_g":  "s_ifetchn_group",   # IFETCHN from DCD (active-low)
    "ifetch":     "s_ifetch",          # IFETCH inside TVGEN
    "intrqn":     "s_intrq_n",         # INTRQN (active-low)
    "iclirq":     "s_iclirq_group",    # combined INTRQ group
    "pan_n":      "s_pan_n",           # PAN_n from board (active-low)
    "vacc_n":     "s_vacc_n",          # VACC_n
    "sstop_n":    "s_sstop_n",         # SSTOP_n
    "trap_n":     "s_trap_n",
    "lcs_n":      "s_debug_lcs_n",
    # Look for TVGEN-internal signals
    "xftrapn":    "XFTRAPN",
    "xvtrapn":    "XVTRAPN",
    "xintrqn":    "XINTRQN",
}

def find_ids(vcd_path, want):
    scope = []; found = {}
    with open(vcd_path, "r", buffering=8*1024*1024) as f:
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
    print(f"  {k:14s}  {full.split('.')[-2]+'.'+full.split('.')[-1]}")

id_map = {v[0]: k for k, v in ids.items()}

def extract(vcd_path, id_map, tstart, tend):
    results = defaultdict(list)
    cur_t = 0; in_data = False
    with open(vcd_path, "r", buffering=8*1024*1024) as f:
        for line in f:
            if not in_data:
                if "$enddefinitions" in line: in_data = True
                continue
            line = line.rstrip()
            if not line: continue
            if line[0] == "#":
                cur_t = int(line[1:])
                if cur_t > tend: break
                continue
            if cur_t < tstart: continue
            if line[0] in "bBrR":
                parts = line.split(None, 1)
                if len(parts) == 2:
                    val_str = parts[0][1:]; sid = parts[1].strip()
                    if sid in id_map:
                        try: results[id_map[sid]].append((cur_t, int(val_str, 2)))
                        except ValueError: results[id_map[sid]].append((cur_t, val_str))
            elif line[0] in "01xXzZ":
                sid = line[1:]
                if sid in id_map:
                    try: results[id_map[sid]].append((cur_t, int(line[0])))
                    except ValueError: pass
    return dict(results)

def tick(t): return t // 10 + 1

# Tight window: 200 ticks before restart (o002172 is around tick 738700-738960)
# From trace_restart.py we know: CSA=o002152 at tick 738836, then MACL2, then jumps
T_LO = (738700) * 10
T_HI = (738980) * 10

print(f"\nWindow: tick {tick(T_LO)} to tick {tick(T_HI)}")
data = extract(VCD, id_map, T_LO, T_HI)

# Build per-signal timeline
all_ev = []
for sig, evs in data.items():
    for t, v in evs:
        all_ev.append((t, sig, v))
all_ev.sort()

# Track current values
cur = {}

def fmt_val(sig, v):
    if sig == "csa" and isinstance(v, int): return f"o{v:06o}"
    if sig == "tvec" and isinstance(v, int): return f"o{v:02o}({v:04b})"
    return str(v)

print(f"\n{'tick':>10}  {'signal':<14}  value  {'dstop':>6} {'ifetchn':>8} {'iclirq':>7} {'pan_n':>6} {'tvec':>8}  {'tclk':>5}")
print("-"*95)
for t, sig, v in all_ev:
    cur[sig] = v
    if sig in ("csa", "tvec", "tclk", "trap_n", "xftrapn", "xvtrapn"):
        dstop  = cur.get("dstop_n", "?")
        ife    = cur.get("ifetchn_g", "?")
        iclirq = cur.get("iclirq", "?")
        pan    = cur.get("pan_n", "?")
        tvec_s = fmt_val("tvec", cur.get("tvec", "?"))
        tclk   = cur.get("tclk", "?")
        print(f"{tick(t):10d}  {sig:<14}  {fmt_val(sig, v):<7}  {str(dstop):>6} {str(ife):>8} {str(iclirq):>7} {str(pan):>6} {tvec_s:>10}  {str(tclk):>5}")
