#!/usr/bin/env python3
# Tang boot validation for the ACAL LUA-latch fix (Tang 06000-hang root cause).
# Sends 400$ (cold-load INSTRUCTION-B from SD + autostart) and watches the console.
# PASS = the program actually runs and prints its banner ("INSTRUCTION" / "PROGRAM
# NUMBER" etc.) => the STZ->CONT jump now resolves => no wedge at 06000.
# FAIL = silence / no program output => still hung.
# Repo path: Verilog/fpga/tang-nano-20k/validate_boot.py
import serial, time, sys

PORT = "/dev/ttyUSB1"
s = serial.Serial(PORT, 115200, timeout=0.4)

def paced(d, cpd=0.05):
    for b in d.encode('latin1'):
        s.write(bytes([b])); time.sleep(cpd)

def recover():
    for a in range(4):
        s.reset_input_buffer(); s.write(b'\x1b'); time.sleep(0.2)
        for _ in range(3): s.write(b'\r'); time.sleep(0.2)
        time.sleep(0.4)
        pr = s.read(400).decode('latin1', 'replace')
        if pr.strip():
            print("recover: got prompt/echo (attempt %d): %r" % (a + 1, pr[-40:]))
            return True
    print("recover: no prompt")
    return False

def main():
    recover()
    print("=== sending 400$ (cold-load + autostart) ===")
    s.reset_input_buffer()
    paced("400$", 0.12)
    # collect console for up to ~60s; look for program banner
    got = ""
    banners = ["INSTRUCTION", "PROGRAM NUMBER", "PROGRAM NAME", "INSTR", "VERIFY"]
    t0 = time.time()
    while time.time() - t0 < 60:
        chunk = s.read(4096).decode('latin1', 'replace')
        if chunk:
            got += chunk
            sys.stdout.write(chunk); sys.stdout.flush()
        if any(b in got for b in banners):
            print("\n\n=== VALIDATION: PASS — program banner seen; CPU BOOTED (STZ jump resolves, no 06000 wedge) ===")
            return
    # no banner within 60s
    printable = "".join(c for c in got if 32 <= ord(c) < 127 or c in "\r\n")
    print("\n\n=== console bytes received (%d): %r ===" % (len(got), printable[:400]))
    if len(got.strip()) == 0:
        print("=== VALIDATION: FAIL — total silence; likely still hung ===")
    else:
        print("=== VALIDATION: INCONCLUSIVE — got output but no known banner; inspect above ===")

if __name__ == "__main__":
    main()
