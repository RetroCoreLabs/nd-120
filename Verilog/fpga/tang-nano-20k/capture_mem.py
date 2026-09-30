#!/usr/bin/env python3
# Capture the OPCOM microprogrammed memory-test (`bank#`) hang on the Tang.
# At the OPCOM '#' prompt, `0#` runs the memory test of bank 0: success echoes a
# second '#', failure gives '?' + error fields, HANG = neither. If it wedges the
# on-chip TANG_GRANT_CAPTURE dumps 512 CSA samples so we see WHERE the memory-test
# microcode stalls. No 400$ / INSTRUCTION-B needed - this is pure OPCOM.
# Requires the board freshly Master-Cleared (btn1) so it is at the '#' prompt.
# Repo path: Verilog/fpga/tang-nano-20k/capture_mem.py
import serial, time, sys

BANK = sys.argv[1] if len(sys.argv) > 1 else "0"   # bank number to test
s = serial.Serial("/dev/ttyUSB1", 115200, timeout=0.5)

def paced(x, cpd=0.10):
    for c in x.encode('latin1'): s.write(bytes([c])); time.sleep(cpd)

def main():
    # confirm we are at '#'
    s.reset_input_buffer(); s.write(b'\r'); time.sleep(1)
    pr = s.read(300).decode('latin1', 'replace')
    print("prompt check:", repr(pr[-40:]))
    if '#' not in pr:
        print("!! not at OPCOM '#' prompt - press btn1 (Master Clear) first")
        return
    print("=== running memory test: %s#  (expect a 2nd '#' on pass, '?' on fail, hang = capture) ===" % BANK)
    s.reset_input_buffer()
    paced(BANK + "#")
    buf = ""
    t0 = time.time()
    while time.time() - t0 < 130:
        c = s.read(8000).decode('latin1', 'replace')
        if c:
            buf += c
            sys.stdout.write(c); sys.stdout.flush()
        hexn = sum(1 for ln in buf.splitlines() if len(ln.strip()) == 4 and all(ch in '0123456789abcdefABCDEF' for ch in ln.strip()))
        if hexn >= 400:
            break
        # fast exit if the test returned pass/fail
        tail = buf[len(BANK)+1:]
        if '?' in tail or (tail.count('#') >= 1 and time.time() - t0 > 3):
            time.sleep(1); buf += s.read(4000).decode('latin1', 'replace'); break
    lines = [ln.strip() for ln in buf.splitlines() if len(ln.strip()) == 4 and all(ch in '0123456789abcdefABCDEF' for ch in ln.strip())]
    print("\n=== RESULT ===")
    if lines:
        vals = [int(x, 16) & 0x1FFF for x in lines]
        seq = []
        for v in vals:
            if not seq or seq[-1] != v: seq.append(v)
        print("  MEMORY-TEST WEDGED. de-duplicated CSA into the stall (octal):")
        for v in seq[-14:]:
            print("    CSA = o%06o" % v)
        last = vals[-1]
        print("  STALL CSA = o%06o (held %d/%d samples)" % (last, sum(1 for v in vals if v == last), len(vals)))
    elif '?' in buf[len(BANK)+1:]:
        print("  memory test FAILED (returned '?') - not a hang; error fields printed above")
    elif buf[len(BANK)+1:].count('#') >= 1:
        print("  memory test PASSED (returned a 2nd '#')")
    else:
        print("  inconclusive - raw tail:", repr(buf[-160:]))

if __name__ == "__main__":
    main()
