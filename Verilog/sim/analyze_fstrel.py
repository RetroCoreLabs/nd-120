#!/usr/bin/env python3
r"""FST-relative datapath trace around the R corruption (FIDBO/A_REG=0x00FF).
FST timestamps are 0-based (reset when fst_on fired ~71.600M abs). The R fill maps to
FST-rel ~441455 ps. Snapshot all CGA/ALU/WRF datapath signals over a window before it,
print each signal's value trajectory, and find where byte 0x52 ('R') becomes 0xFF."""
import sys, re, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vcd_extract import parse_vcd_header, find_matching_signals, extract_signals

FST = sys.argv[1] if len(sys.argv) > 1 else "lbyt_full.fst"
CENTER = int(sys.argv[2]) if len(sys.argv) > 2 else 441455   # FST-rel ps of corruption
PRE = int(sys.argv[3]) if len(sys.argv) > 3 else 3000        # ps before
POST = 300
WANT = ["ALU.s_f_15_0","ALU.s_g_15_0","ALU.s_d_15_0","ALU.s_sw_15_0","ALU.s_arg_15_0",
        "ALU.s_a_15_0","ALU.s_b_15_0","ALU.s_fidbi_15_0","s_FIDBI_15_0","s_FIDBO_15_0",
        "ALU_RALU.s_af_15_0","ALU_RALU.s_lf_15_0","ALU_RALU.s_fn_15_0","ALU_RALU.s_a_15_0",
        "ALU_RALU.s_b_15_0","ALU_RALU.s_rn_15_0","ALU_RALU.s_s_15_0","ALU_RALU.s_r_15_0",
        "ALU.s_cd_15_0","ALU.s_dbr_15_0","ALU.s_q_15_0","ALU.s_csidbs4_0",
        "A_REG_5.regFF","T_REG_6.regFF","s_reg2_p_15_0","CSA_12_0"]
def b2i(v):
    try: return int(v,2)
    except: return None
def lanes(x): return (None,None) if x is None else ((x>>8)&0xFF, x&0xFF)

hdr = parse_vcd_header(FST)
tgt = find_matching_signals(hdr, substring_match=WANT)
# dedupe by chosen name (keep one id per unique full name)
print("matched", len(tgt), "signal ids")
res = extract_signals(FST, tgt, tstart=None, tend=CENTER+POST)
lo, hi = CENTER-PRE, CENTER+POST

def short(nm): return '.'.join(nm.replace("TOP.","").split('.')[-2:])
# value at time t (last change <= t)
def val_at(chg, t):
    v=None
    for (tt,vv) in chg:
        if tt<=t: v=vv
        else: break
    return b2i(v)

# collect the distinct timestamps (ps) in window across all sigs, for a compact trajectory
edges=set()
series={}
for nm,chg in res.items():
    series[short(nm)] = chg
    for (t,_) in chg:
        if lo<=t<=hi: edges.add(t)
edges=sorted(edges)

print("\n=== char-loss: byte 0x52 -> 0xFF per signal (FST-rel ps) ===")
for nm in sorted(series):
    chg=series[nm]; seen=None; hit=None
    for t in edges:
        hi8,lo8 = lanes(val_at(chg,t))
        if 0x52 in (hi8,lo8): seen=t
        if 0xFF in (hi8,lo8) and seen is not None:
            lane="hi" if hi8==0xFF else "lo"; hit=(seen,t,lane); break
    if hit: print("  %-26s 0x52@%d -> 0xFF(%s)@%d" % (nm,hit[0],hit[2],hit[1]))

print("\n=== trajectory of key signals across window (ps: octal-val) ===")
KEY=["s_FIDBO_15_0","s_g_15_0","s_f_15_0","s_af_15_0","s_lf_15_0","s_fn_15_0",
     "s_a_15_0","s_b_15_0","s_rn_15_0","s_s_15_0","s_r_15_0","s_sw_15_0","s_arg_15_0",
     "s_fidbi_15_0","s_FIDBI_15_0","s_cd_15_0","s_dbr_15_0","regFF","s_csidbs4_0"]
for k in KEY:
    matches=[nm for nm in series if nm.split('.')[-1]==k or nm.endswith(k)]
    for nm in matches[:2]:
        chg=series[nm]; out=[]; prev=object()
        for t in edges:
            v=val_at(chg,t)
            if v!=prev: out.append("%d:%s"%(t,"x" if v is None else "%06o"%v)); prev=v
        if len(out)>1: print("  %-26s %s"%(nm," ".join(out[:16])))
