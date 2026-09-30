#!/usr/bin/env python3
# Grant-capture reader + decoder for the Tang masked-level-10 probe.
#   Verilog/fpga/tang-nano-20k/grant_capture.py  (repo-relative)
#
# Companion to scratch_piltrace.py. Requires a bitstream built with
# `define TANG_GRANT_CAPTURE (see src/tang20k_defines.v). That build repurposes
# the on-chip 512-sample analyzer to record {PIL[3:0], CSA[11:0]} and trigger
# when PIL enters level 10 (448 pre + 64 post). On the wedge the on-chip dumper
# SEIZES the console TX and streams 512 lines of 4 hex digits at 9600.
#
# This script: recover -> MACL -> P=0 -> single-step watching PIL; the moment
# PIL leaves 0 (the grant), it STOPS stepping and switches to raw-read mode,
# collects the 512 "HHHH" lines, and decodes each to PIL + CSA(octal), with
# microcode landmarks annotated. The CSA sequence into the PIL=10 sample is the
# decisive evidence: normal level-switch microcode (PLINT/PLVO/LVSWP) => the
# Am2914 grant cone is the cause; anything else => the mechanism is elsewhere.
#
# Usage:
#   python3 grant_capture.py            # full flow: step to the grant, then dump
#   python3 grant_capture.py --dumponly # board already wedged: just read+decode
#
# Protocol notes (from scratch_piltrace.py, learned 18-JUL): MOPC needs
# ~0.07 s/char pacing; a killed run leaves the parser mid-examine (ESC+CRs
# recover, else btn1); after the on-chip dump seizes TX the OPCOM console is
# dead until the next btn1 - that is EXPECTED (the CPU has wedged at level 10).
import serial, time, re, sys, os

PORT = "/dev/ttyUSB1"
LOG  = os.path.join(os.path.dirname(os.path.abspath(__file__)), "grant_capture.log")   # next to this script
out  = open(LOG, "w")
def say(*a):
    m = " ".join(str(x) for x in a); print(m); out.write(m + "\n"); out.flush()

# --- microcode landmarks (CSA octal) for annotation -------------------------
LANDMARKS = {
    0o0:    "trap/fetch base",
    0o16:   "PANEL-interrupt vector",
    0o17:   "MACRO-interrupt vector (PIC,RVECT->MACRI)",
    0o53:   "MACRI",
    0o54:   "MACRI",
    0o55:   "MACRI",
    0o56:   "MACRI -> ITSRV",
    0o1124: "EXT14 (internal-interrupt entry)",
    0o1133: "PLINT (level-in-Q entry)",
    0o1140: "PLVO (level switch)",
    0o1141: "PLVO+1 (COND,F=0 early return)",
    0o1146: "LVSWP (change-level routine)",
    0o1150: "LVSWP+2 (STS push)",
    0o1151: "LVSWP+3 (save loop)",
    0o1155: "LVSWP+7 (ACTLV/PIL update)",
    0o3740: "ITSRV (interrupt vector table, entry0 -> level 10)",
}
def annot(csa):
    if csa in LANDMARKS: return "  <- " + LANDMARKS[csa]
    if 0o1133 <= csa <= 0o1145: return "  <- PLINT/PLVO region"
    if 0o1146 <= csa <= 0o1162: return "  <- LVSWP region (level switch)"
    if 0o3740 <= csa <= 0o3757: return "  <- ITSRV vector table"
    return ""

# --- serial helpers (verbatim protocol from scratch_piltrace.py) ------------
s = serial.Serial(PORT, 115200, timeout=0.4)
time.sleep(0.3); s.reset_input_buffer()
def paced(d, cpd=0.07):
    if isinstance(d, str): d = d.encode('latin1')
    for b in d: s.write(bytes([b])); time.sleep(cpd)
def rd(w): time.sleep(w); return s.read(8000).decode('latin1', 'replace')
def parse_ird(txt):
    for line in txt.splitlines():
        if '/' in line:
            vals = re.findall(r'[0-7]{1,6}', line.split('/', 1)[1])
            if len(vals) >= 8:
                n = ['PANS','STS','OPR','PSR','PVL','IIC','PID','PIE']
                d = {k: int(v, 8) for k, v in zip(n, vals[:8])}
                d['PIL'] = (d['STS'] >> 8) & 0xF; return d
    return None
def parse_rd(txt):
    for line in txt.splitlines():
        if '/' in line:
            v = re.findall(r'[0-7]{1,6}', line.split('/', 1)[1])
            if len(v) >= 8: return {'STS': int(v[0], 8), 'P': int(v[2], 8)}
    return None
def ird():  s.reset_input_buffer(); paced("IRD\r"); return rd(1.5)
def lvl0(): s.reset_input_buffer(); paced("<RD\r");  return rd(1.2)
def recover():
    for a in range(8):
        s.reset_input_buffer(); s.write(b'\x1b'); time.sleep(0.2)
        for _ in range(3): s.write(b'\r'); time.sleep(0.2)
        time.sleep(0.4); s.read(400)
        if parse_ird(ird()) is not None:
            say("recover: clean prompt (attempt %d)" % (a + 1)); return True
    say("recover: FAILED - needs btn1/reflash"); return False

# --- the on-chip dump: read raw, collect 512 "HHHH" lines, decode -----------
HEXLINE = re.compile(r'^[0-9A-Fa-f]{4}$')
def collect_dump(max_wait=25.0):
    say("=== waiting for the on-chip capture dump (hold delay a few s, then "
        "512 lines stream ~3-4 s) ===")
    buf = ""; samples = []; t0 = time.time(); last_len = 0; quiet = 0
    while time.time() - t0 < max_wait:
        chunk = s.read(4096).decode('latin1', 'replace')
        if chunk:
            buf += chunk; quiet = 0
        else:
            quiet += 1
        # pull complete lines
        while '\n' in buf:
            line, buf = buf.split('\n', 1)
            line = line.strip('\r \t')
            if HEXLINE.match(line):
                samples.append(int(line, 16))
        if len(samples) != last_len:
            last_len = len(samples)
        if len(samples) >= 512:
            break
        if len(samples) > 0 and quiet > 6:   # stream ended early
            break
    return samples

def decode(samples):
    if not samples:
        say("NO hex samples captured. Either the capture did not trigger "
            "(PIL never reached 10), the dump has not started yet, or the "
            "bitstream lacks TANG_GRANT_CAPTURE. Check the build define.")
        return
    say("=== captured %d samples (oldest first) ===" % len(samples))
    # word bits: [15]=CSBIT20 [14]=SC6 [13]=MCLK_EN [12]=0 [11:0]=CSBIT_11_0 (raw microword field MASEL sees)
    def dec(v):
        return dict(csbit20=(v>>15)&1, SC6=(v>>14)&1, MCLK_EN=(v>>13)&1, csbit=v&0x0FFF)
    say("=== de-duplicated raw-microword CSBIT_11_0 sequence (oldest -> newest) ===")
    prev=None
    for v in samples:
        if v!=prev:
            d=dec(v)
            say("  CSBIT_11_0=%04o(=0x%03X) csbit20=%d SC6=%d MCLK_EN=%d" %
                (d['csbit'],d['csbit'],d['csbit20'],d['SC6'],d['MCLK_EN']))
            prev=v
    dl=dec(samples[-1])
    say("=== RAW MICROWORD AT THE STALL (STZ word => CSBIT_11_0 should be 0x065, csbit20=0) ===")
    say("  CSBIT_11_0=%04o oct (0x%03X)  csbit20=%d  SC6=%d" %
        (dl['csbit'],dl['csbit'],dl['csbit20'],dl['SC6']))
    csbits=set(dec(v)['csbit'] for v in samples)
    c20s=set(dec(v)['csbit20'] for v in samples)
    say("=== VERDICT ===")
    say("  CSBIT_11_0 seen: %s   csbit20 seen: %s" %
        (sorted('0x%03X'%c for c in csbits), sorted(c20s)))
    if 0x065 in csbits and c20s=={0}:
        say("  => CSBIT_11_0=0x065 CORRECT (STZ microword is intact): WCS read is FINE. The jmpaddr=16000 must come from the JMP mux / s_jmp_3_0 or a MASEL compute bug. Focus: ILC_MUX / s_jmp_3_0 and the s_jmpaddr assembly.")
    elif 0xC00 in csbits or (0x800 in csbits) or c20s=={1}:
        say("  => CSBIT_11_0=0x%03X = the ADDRESS 06000 (0xC00) NOT the STZ data (0x065) => the WCS control-store READ returns the ADDRESS/garbage on silicon. ROOT CAUSE = WCS (control-store BSRAM) read path in FF/Tang. Read the WCS module + CSBITS pipeline." % (list(csbits)[0] if len(csbits)==1 else 0xC00))
    else:
        say("  => CSBIT_11_0=%s - compare to 0x065 (STZ) vs 0xC00 (address)." % sorted('0x%03X'%c for c in csbits))

# ---------------------------------------------------------------------------
def main():
    dumponly = "--dumponly" in sys.argv
    freerun  = "--freerun" in sys.argv
    if dumponly:
        say("=== --dumponly: reading raw UART for the dump (board already wedged) ===")
        decode(collect_dump()); s.close(); out.close(); return

    if freerun:
        # FREE-RUN root cause: MACL to the '#' monitor, then '0!' (free-run cold
        # start, NO single-step so no injected panel-stop PAN). The on-chip
        # capture triggers on the microcode HANG (CSA stable) or PIL->10 and
        # dumps the {PIL,CSA} path leading into the stall.
        if not recover():
            say("ABORT: press btn1 then rerun"); s.close(); out.close(); sys.exit(1)
        s.reset_input_buffer(); paced("\r"); pr=rd(1.2)
        say("prompt: %r" % pr[-20:])
        # 400$ = cold-load INSTRUCTION-B from SD/tape AND autostart the cold
        # start (== the 0! path). Self-contained (no pre-loaded program needed).
        # The tape load is ~60 s of silence, then the cold start runs and hangs;
        # the on-chip hang detector then dumps the {PIL,CSA} path into the stall.
        say("=== 400$  (cold-load + autostart cold start) - long wait for load+hang+dump ===")
        s.reset_input_buffer(); paced("400$", 0.12)
        say("=== waiting up to 130s for the hang-trigger dump ({PIL,CSA} path) ===")
        decode(collect_dump(max_wait=130.0))
        say("=== NOTE: console dead (dumper holds TX). btn1 to recover. ===")
        s.close(); out.close(); return

    if not recover():
        say("ABORT: press btn1 then rerun"); s.close(); out.close(); sys.exit(1)
    say("=== MACL ==="); s.reset_input_buffer(); paced("MACL\r"); rd(1.6)
    r0 = parse_rd(lvl0()); say("after MACL: P=%s" % (oct(r0['P']) if r0 else '?'))
    say("=== set P=0 (0! cold-start entry) ===")
    s.reset_input_buffer(); paced("P/"); time.sleep(0.5); s.read(100)
    paced("0\r"); time.sleep(0.5); s.read(100)
    rP = parse_rd(lvl0()); say("P now = %s" % (oct(rP['P']) if rP else '?'))

    say("=== single-step, watching PIL; on grant (PIL!=0) switch to dump ===")
    fired = False
    for i in range(1, 61):
        s.reset_input_buffer(); paced("Z"); time.sleep(0.25); s.read(50)
        d = parse_ird(ird()); r = parse_rd(lvl0())
        P = r['P'] if r else None
        pil = d['PIL'] if d else None
        say("step %2d: P=%-9s STS=%-8s PIL=%s PID=%s PIE=%s" % (
            i, oct(P) if P is not None else '?', oct(d['STS']) if d else '?',
            pil if pil is not None else '?', oct(d['PID']) if d else '?',
            oct(d['PIE']) if d else '?'))
        if pil is not None and pil != 0:
            say("=== GRANT: PIL=%d at step %d -> stop stepping, read the on-chip "
                "capture dump ===" % (pil, i))
            fired = True; break
    if not fired:
        say("=== PIL stayed 0 for all steps - no grant, so the on-chip capture "
            "did not trigger. Nothing to dump. (Did the wedge move?) ===")
        s.close(); out.close(); return
    decode(collect_dump())
    say("=== NOTE: console is now dead (dumper holds TX / CPU wedged). Press "
        "btn1 to recover the board. ===")
    s.close(); out.close()

if __name__ == "__main__":
    main()
