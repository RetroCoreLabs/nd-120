#!/usr/bin/env python3
# Capture the STACK-test hang on the Tang. Boots INSTRUCTION-B (400$), runs the
# STACK program-command at the '>' prompt, and when the CPU wedges the on-chip
# TANG_GRANT_CAPTURE dumps 512 hex words over the console. With the current
# probe word (s_cap_src = CSA_12_0), the dump tells us WHERE the STACK microcode
# stalls (the octal microcode address), the same first step used for the boot hang.
# Repo path: Verilog/fpga/tang-nano-20k/capture_stack.py
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
        # give it more time / a CR to reach the '>' prompt
        boot += rd(6)
    print("\n=== sending STACK at the > prompt ===")
    s.reset_input_buffer(); paced("STACK\r")
    # collect until the capture dump appears (many 4-hex-digit lines) or timeout
    buf = ""
    t0 = time.time()
    hexlines = 0
    while time.time() - t0 < 130:
        chunk = s.read(8000).decode('latin1', 'replace')
        if chunk:
            buf += chunk
            sys.stdout.write(chunk); sys.stdout.flush()
        # count 4-hex-digit dump lines
        hexlines = sum(1 for ln in buf.splitlines() if len(ln.strip()) == 4 and all(c in "0123456789abcdefABCDEF" for c in ln.strip()))
        if hexlines >= 400:
            break
    # decode the dump: 4-hex-digit lines = CSA_12_0 samples
    lines = [ln.strip() for ln in buf.splitlines() if len(ln.strip()) == 4 and all(c in "0123456789abcdefABCDEF" for c in ln.strip())]
    print("\n\n=== DUMP DECODE (%d hex samples) ===" % len(lines))
    if not lines:
        print("  no capture dump seen - STACK may not have wedged, or console lost it.")
        print("  raw tail:", repr(buf[-200:]))
        return
    vals = [int(x, 16) & 0x1FFF for x in lines]
    # dedup consecutive
    seq = []
    for v in vals:
        if not seq or seq[-1] != v: seq.append(v)
    print("  de-duplicated CSA sequence into the stall (octal):")
    for v in seq[-12:]:
        print("    CSA = o%06o" % v)
    last = vals[-1]
    n = sum(1 for v in vals if v == last)
    print("  STALL CSA = o%06o  (held %d/%d samples)" % (last, n, len(vals)))

if __name__ == "__main__":
    main()
