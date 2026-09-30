#!/usr/bin/env python3
r"""Python FST analysis (NO GTKWave) - trace where the banner char 'R'=0x52 becomes 0xFF
in the ND-120 datapath, using fst2vcd streaming via the repo's vcd_extract primitives.

Usage: analyze_charloss.py <fst> <anchor_csv> [byte_hex=52] [pre_ticks=250]
  <anchor_csv> has '# MARK fill tick=NNNN' rows marking the corrupting RAM writes.

Approach (per the vetted plan):
  1. read the corrupting-fill tick(s) from the anchor CSV
  2. enumerate FST signals, keep the CGA/ALU/WRF datapath lanes of interest
  3. one windowed streaming pass (tstart/tend in ps) -> per-signal change lists
  4. reconstruct per-tick snapshots over the window; print a compact text 'waveform'
     of every kept signal, AND report, per signal + byte lane, the last tick the lane
     held 0x52 and the tick it flipped to 0xFF (the replacing op).
"""
import sys, os, re, csv, functools
print = functools.partial(print, flush=True)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vcd_extract import parse_vcd_header, find_matching_signals, extract_signals, ps_to_tick

FST    = sys.argv[1]
ANCHOR = sys.argv[2]
BYTE   = int(sys.argv[3], 16) if len(sys.argv) > 3 else 0x52
PRE    = int(sys.argv[4]) if len(sys.argv) > 4 else 250
POST   = 8

# datapath lanes of interest (substring match, alias-aware)
WANT = [
    "ALU.s_f_15_0", "ALU.s_g_15_0", "ALU.s_d_15_0", "ALU.s_sw_15_0", "ALU.s_arg_15_0",
    "ALU.s_a_15_0", "ALU.s_fidbi_15_0", "s_FIDBI_15_0", "s_FIDBO_15_0",
    "ALU_RALU.s_af_15_0", "ALU_RALU.s_", "ALU.s_rn_15_0", "ALU.s_s_15_0",
    "ALU.s_cd_15_0", "ALU.s_dbr_15_0", "ALU.s_q_15_0",
    "WRF.RBLOCK.s_reg2_p_15_0", "WRF.RBLOCK.s_reg5_a_15_0", "WRF.RBLOCK.s_reg6_t_15_0",
    "ALU.s_csidbs4_0", "CSA_12_0",
]

def read_fill_ticks(path):
    ts = []
    with open(path) as f:
        for ln in f:
            m = re.match(r"#\s*MARK\s+fill\s+tick=(\d+)", ln)
            if m: ts.append(int(m.group(1)))
    return ts

def base(n):  # strip [hi:lo]
    return re.sub(r"\[\d+:\d+\]$", "", n)

def bin2int(v):
    try: return int(v, 2)
    except (ValueError, TypeError): return None

def lanes(v):
    if v is None: return (None, None)
    return ((v >> 8) & 0xFF, v & 0xFF)

def main():
    fill = read_fill_ticks(ANCHOR)
    if not fill:
        print("no '# MARK fill tick=' rows in", ANCHOR); return
    PREF = int(os.environ.get("FILL_TICK", "71644260"))
    target = min(fill, key=lambda t: abs(t - PREF))
    print("fill ticks:", fill[:8], "... using", target)
    t_lo = (target - PRE) * 10
    t_hi = (target + POST) * 10
    print("window ps [%d..%d]  ticks [%d..%d]" % (t_lo, t_hi, target - PRE, target + POST))

    hdr = parse_vcd_header(FST)
    print("total signals:", len(hdr))
    tgt = find_matching_signals(hdr, substring_match=WANT)
    print("matched datapath signals:", len(tgt))

    # extract from FST start (file is tiny/tight) so we know each signal's value AT window start
    res = extract_signals(FST, tgt, tstart=None, tend=t_hi)  # {name:[(ps,binval)]}
    # build per-signal (tick -> int) using last-value-before-tick
    names = sorted(res.keys())
    # reconstruct value at each tick in window by replay
    ticks = list(range(target - PRE, target + POST + 1))
    series = {}
    for nm in names:
        chg = [(ps_to_tick(t), bin2int(v) if isinstance(v, str) and set(v) <= set("01") else None)
               for (t, v) in res[nm]]
        cur = None; ci = 0; col = {}
        for tk in ticks:
            while ci < len(chg) and chg[ci][0] <= tk:
                cur = chg[ci][1]; ci += 1
            col[tk] = cur
        series[nm] = col

    # backward-walk: per signal+lane, last 0x52 -> next 0xFF
    print("\n=== byte-lane %02X -> 0xFF transitions (char-loss) ===" % BYTE)
    for nm in names:
        seen = None
        for tk in ticks:
            hi, lo = lanes(series[nm][tk])
            if BYTE in (hi, lo): seen = tk
            if 0xFF in (hi, lo) and seen is not None:
                lane = "hi" if lanes(series[nm][tk])[0] == 0xFF else "lo"
                print("  %-55s  0x%02X last@%d -> 0xFF(%s)@%d" % (base(nm).split('.')[-3:] and '.'.join(base(nm).split('.')[-3:]), BYTE, seen, lane, tk))
                break

    # compact waveform: print signals that CHANGE in the window, value per ~every tick where any change
    print("\n=== value trajectory (only signals that change in window) ===")
    changing = [nm for nm in names if len({series[nm][tk] for tk in ticks}) > 1]
    print("changing signals:", len(changing))
    for nm in changing:
        vals = series[nm]
        # print transitions only
        out = []
        prev = object()
        for tk in ticks:
            if vals[tk] != prev:
                out.append("t%d=%s" % (tk, "x" if vals[tk] is None else "%06o" % vals[tk]))
                prev = vals[tk]
        print("  %-50s %s" % ('.'.join(base(nm).split('.')[-3:]), " ".join(out[:24])))

if __name__ == "__main__":
    main()
