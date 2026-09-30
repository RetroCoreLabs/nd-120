#!/usr/bin/env python3
"""Trace CSA+LC around the first RESTART after LCS_n goes HIGH."""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.vcd")
WANT = {
    "csa": "s_debug_csa",
    "lc":  "s_lc_3_0",
    "lcs": "s_debug_lcs_n",
    "sc63": "s_sc_6_3_out",
    "regiw": "regIW",
}

def find_ids(vcd_path=VCD, want=WANT):
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

ids = find_ids()
id_map = {v[0]: k for k, v in ids.items()}
print("Found:", list(ids.keys()))

from collections import defaultdict
def extract(vcd_path, id_map, tstart=None, tend=None):
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
                if tend is not None and cur_t > tend: break
                continue
            if tstart is not None and cur_t < tstart: continue
            if line[0] in "bBrR":
                parts = line.split(None, 1)
                if len(parts) == 2:
                    val_str = parts[0][1:]; sid = parts[1].strip()
                    if sid in id_map:
                        try: results[id_map[sid]].append((cur_t, int(val_str, 2)))
                        except ValueError: pass
            elif line[0] in "01xXzZ":
                sid = line[1:]
                if sid in id_map:
                    try: results[id_map[sid]].append((cur_t, int(line[0])))
                    except ValueError: pass
    return dict(results)

def tick(t): return t // 10 + 1

# Target: first restart after LCS_n HIGH (tick ~557167 -> t=5571660ps)
# Look 500 ticks before, 200 ticks after restart at tick 738956 -> t=7389550ps
RESTART_T = 7389560 - 500   # a bit before the restart
t_lo = RESTART_T - 5000
t_hi = RESTART_T + 3000

print(f"Window: tick {tick(t_lo)} to tick {tick(t_hi)}")

data = extract(VCD, id_map, tstart=t_lo, tend=t_hi)
csa_ch = data.get("csa", [])
lc_ch  = data.get("lc", [])
sc_ch  = data.get("sc63", [])
iw_ch  = data.get("regiw", [])

CSA_LABELS = {
    0x7F1: "MS20(PANVC1)", 0x7F0: "STOP(PANVC0)",
    0x4DB: "o002333", 0x4DC: "o002334", 0x4DD: "o002335",
    0x4DE: "o002336-MOPC", 0x4DF: "o002337",
    0x4E1: "o002341-OPCOM", 0x000: "**RESTART**",
}
SC_NAMES = {0: "SEL_JUMP", 1: "SEL_JUMP+POP", 2: "SEL_JUMP+LOAD", 3: "SEL_JUMP+PUSH",
            4: "SEL_RET", 5: "SEL_RET+POP", 8: "SEL_NEXT", 9: "SEL_NEXT+POP",
            11: "SEL_NEXT+PUSH", 12: "SEL_REPEAT"}

all_ev = []
for t, v in csa_ch: all_ev.append((t, "csa", v))
for t, v in lc_ch:  all_ev.append((t, "lc",  v))
for t, v in sc_ch:  all_ev.append((t, "sc63", v))
for t, v in iw_ch:  all_ev.append((t, "iw",  v))
all_ev.sort()

print("\n%10s  %-8s  %-22s  value" % ("tick", "signal", "label"))
print("-"*65)
for t, sig, v in all_ev:
    tk = tick(t)
    label = ""
    if sig == "csa":
        label = CSA_LABELS.get(v, "")
        print("%10d  %-8s  %-22s  o%06o" % (tk, sig, label, v))
    elif sig == "lc":
        print("%10d  %-8s  LC=%-19d  %d" % (tk, sig, v, v))
    elif sig == "sc63":
        label = SC_NAMES.get(v, "?")
        print("%10d  %-8s  %-22s  %d" % (tk, sig, label, v))
    elif sig == "iw":
        print("%10d  %-8s  %-22s  o%06o" % (tk, sig, "", v))
