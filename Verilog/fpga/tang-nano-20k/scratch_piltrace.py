#!/usr/bin/env python3
# Definitive PIL step-trace on the Tang (grant-fix verification), NO free-run.
#   Verilog/fpga/tang-nano-20k/scratch_piltrace.py  (repo-relative)
# Sets P to the cold-start entry (20 octal, the autoload start) and SINGLE-STEPS
# through the cold start watching PIL. Stepping is controlled - it cannot wedge
# the console the way `261.` free-run-to-breakpoint does. Guards the verdict so
# it never claims "holds" on missing (?) readings.
import serial, time, re, sys, os

LOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "piltrace.log")   # next to this script
out = open(LOG, "w")
def say(*a):
    m=" ".join(str(x) for x in a); print(m); out.write(m+"\n"); out.flush()

s = serial.Serial('/dev/ttyUSB1', 9600, timeout=0.4)
time.sleep(0.3); s.reset_input_buffer()
def paced(d,cpd=0.07):
    if isinstance(d,str): d=d.encode('latin1')
    for b in d: s.write(bytes([b])); time.sleep(cpd)
def rd(w): time.sleep(w); return s.read(4000).decode('latin1')
def parse_ird(txt):
    for line in txt.splitlines():
        if '/' in line:
            vals=re.findall(r'[0-7]{1,6}', line.split('/',1)[1])
            if len(vals)>=8:
                n=['PANS','STS','OPR','PSR','PVL','IIC','PID','PIE']
                d={k:int(v,8) for k,v in zip(n,vals[:8])}
                d['PIL']=(d['STS']>>8)&0xF; return d
    return None
def parse_rd(txt):
    # <RD line: "<addr> /STS 0 P B L A T X"  -> values are AFTER the '/'
    for line in txt.splitlines():
        if '/' in line:
            v=re.findall(r'[0-7]{1,6}', line.split('/',1)[1])
            if len(v)>=8: return {'STS':int(v[0],8),'P':int(v[2],8)}
    return None
def ird(): s.reset_input_buffer(); paced("IRD\r"); return rd(1.5)
def lvl0(): s.reset_input_buffer(); paced("<RD\r"); return rd(1.2)

def recover():
    for a in range(8):
        s.reset_input_buffer(); s.write(b'\x1b'); time.sleep(0.2)
        for _ in range(3): s.write(b'\r'); time.sleep(0.2)
        time.sleep(0.4); s.read(400)
        if parse_ird(ird()) is not None:
            say("recover: clean prompt (attempt %d)"%(a+1)); return True
    say("recover: FAILED - needs btn1/reflash"); return False

if not recover():
    say("ABORT: press btn1 then rerun"); s.close(); out.close(); sys.exit(1)

say("=== MACL ==="); s.reset_input_buffer(); paced("MACL\r"); rd(1.6)
b0=lvl0(); r0=parse_rd(b0)
say("after MACL: P=%s (raw=%r)" % (oct(r0['P']) if r0 else '?', b0[:70]))

# Set P = 0 (octal), the 0! cold-start entry (the failing boot path), via
# examine+deposit. 0! is what dies on Tang - step through it to find where.
say("=== set P=0 (0! cold-start entry - the failing boot path) ===")
s.reset_input_buffer(); paced("P/"); time.sleep(0.5); pre=s.read(100).decode('latin1')
paced("0\r"); time.sleep(0.5); post=s.read(100).decode('latin1')
say("P/ echo=%r  deposit echo=%r"%(pre,post))
# verify
rP=parse_rd(lvl0()); say("P now = %s"%(oct(rP['P']) if rP else '?'))

say("=== single-step 40 x from 0! entry, watch PIL (expect PIL=0 if fix holds) ===")
granted=False; missing=0; readings=0; seen261=False
for i in range(1,41):
    s.reset_input_buffer(); paced("Z"); time.sleep(0.25); s.read(50)
    d=parse_ird(ird()); r=parse_rd(lvl0())
    P=r['P'] if r else None
    if P is not None and 0o255 <= P <= 0o270: seen261=True
    if d is None: missing+=1
    else:
        readings+=1
        if d['PIL']!=0: granted=True
    g=("  <<<< GRANT PIL=%d PIE=%s"%(d['PIL'],oct(d['PIE']))) if (d and d['PIL']!=0) else ""
    say("step %2d: P=%-9s STS=%-8s PIL=%s PID=%s PIE=%s%s" %
        (i, oct(P) if P is not None else '?', oct(d['STS']) if d else '?',
         d['PIL'] if d else '?', oct(d['PID']) if d else '?',
         oct(d['PIE']) if d else '?', g))
    if granted: break   # caught it - stop

say("=== stats: %d real readings, %d missing, passed-261-region=%s ==="%(readings,missing,seen261))
if granted:
    say("=== VERDICT: MASKED GRANT STILL FIRES on silicon - fix INSUFFICIENT ===")
elif missing>0:
    say("=== VERDICT: INCONCLUSIVE (%d steps had no data - console desync) ==="%missing)
else:
    say("=== VERDICT: PIL=0 for all %d readings - NO masked grant, fix HOLDS ==="%readings)
s.close(); out.close()
