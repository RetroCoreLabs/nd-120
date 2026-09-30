#!/usr/bin/env python3
# Capture the SEGMENT "reboots" symptom on the Tang. Boots INSTRUCTION-B (400$),
# runs the SEGMENT program-command at the '>' prompt, and watches for one of THREE
# outcomes:
#   1. REBOOT  - the INSTRUCTION-B (or OPCOM) banner reappears = the CPU reset.
#   2. WEDGE   - the on-chip TANG_GRANT_CAPTURE dumps 512 CSA samples (hang).
#   3. NORMAL  - the SEGMENT test prints "== END OF TEST ==" and returns to '>'.
# Unlike stack/byte-string (soak loops) and the memory test (stale-state), a reboot
# is a genuine event, so this is the symptom most likely to be a REAL bug.
# Requires the board freshly power-cycled (clean SDRAM) so 400$ boots correctly.
# Repo path: Verilog/fpga/tang-nano-20k/capture_seg.py
import serial, time, sys

s = serial.Serial("/dev/ttyUSB1", 115200, timeout=0.5)

def paced(x, cpd=0.09):
    for c in x.encode('latin1'): s.write(bytes([c])); time.sleep(cpd)

def rd(w):
    time.sleep(w); return s.read(20000).decode('latin1', 'replace')

def recover():
    for _ in range(4):
        s.reset_input_buffer(); s.write(b'\x1b'); time.sleep(0.2)
        s.write(b'\r'); time.sleep(0.3)
        if s.read(200).strip(): return True
    return False

def main():
    recover()
    print("=== 400$ (boot INSTRUCTION-B) ===")
    s.reset_input_buffer(); paced("400$")
    boot = rd(8)
    sys.stdout.write(boot)
    if "INSTRUCTION" not in boot:
        boot += rd(6)
        sys.stdout.write(boot[len(boot):])
    if "INSTRUCTION" not in boot:
        print("\n!! did not reach INSTRUCTION-B '>' prompt - power-cycle + retry")
        return
    print("\n=== sending SEGMENT at the > prompt ===")
    s.reset_input_buffer(); paced("SEGMENT\r")
    buf = ""
    t0 = time.time()
    outcome = None
    while time.time() - t0 < 130:
        chunk = s.read(8000).decode('latin1', 'replace')
        if chunk:
            buf += chunk
            sys.stdout.write(chunk); sys.stdout.flush()
        # 1. reboot = the boot banner reappears
        if buf.count("INSTRUCTION") >= 2 or "OPCOM" in buf or "ND-120" in buf:
            outcome = "REBOOT"; time.sleep(1); buf += s.read(8000).decode('latin1','replace'); break
        # 2. wedge = many 4-hex-digit capture lines
        hexlines = sum(1 for ln in buf.splitlines() if len(ln.strip()) == 4 and all(c in "0123456789abcdefABCDEF" for c in ln.strip()))
        if hexlines >= 400:
            outcome = "WEDGE"; break
        # 3. normal completion
        if "END OF TEST" in buf:
            outcome = "NORMAL"; time.sleep(1); buf += s.read(8000).decode('latin1','replace'); break
    print("\n\n=== OUTCOME: %s ===" % (outcome or "TIMEOUT/inconclusive"))
    if outcome == "WEDGE":
        lines = [ln.strip() for ln in buf.splitlines() if len(ln.strip()) == 4 and all(c in "0123456789abcdefABCDEF" for c in ln.strip())]
        vals = [int(x, 16) & 0x1FFF for x in lines]
        seq = []
        for v in vals:
            if not seq or seq[-1] != v: seq.append(v)
        print("  de-duplicated CSA sequence into the stall (octal):")
        for v in seq[-12:]:
            print("    CSA = o%06o" % v)
        last = vals[-1]
        print("  STALL CSA = o%06o  (held %d/%d samples)" % (last, sum(1 for v in vals if v == last), len(vals)))
    elif outcome == "REBOOT":
        print("  The CPU RESET during SEGMENT - banner reappeared. This is a REAL event")
        print("  (not a soak loop / stale state). The capture probe did NOT fire, so it")
        print("  is a fast reset, not a CSA-stable wedge. Next: probe TRAP/reset cause.")
    elif outcome == "NORMAL":
        print("  SEGMENT completed with END OF TEST - no reboot on a clean board.")
    else:
        print("  raw tail:", repr(buf[-200:]))

if __name__ == "__main__":
    main()
