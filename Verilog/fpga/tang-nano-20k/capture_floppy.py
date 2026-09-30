#!/usr/bin/env python3
# Boot from FLOPPY on the Tang: at the OPCOM '#' prompt, '1560&' loads the boot
# image from the SD-FAT-served FLOPPY1.IMG (device 1560 octal, '&' = mass/binary
# boot-and-run) and runs it. Prints whatever the loaded program emits, or a '?'/
# error if the floppy isn't ready (e.g. the contiguity checker rejected a
# fragmented FLOPPY1.IMG at mount). This is the floppy-only Tang build
# (TANG_FLOPPY; no tape / no 400$).
# Repo path: Verilog/fpga/tang-nano-20k/capture_floppy.py
import serial, time, sys

s = serial.Serial("/dev/ttyUSB1", 115200, timeout=0.5)

def paced(x, cpd=0.09):
    for c in x.encode('latin1'): s.write(bytes([c])); time.sleep(cpd)

def main():
    # confirm the '#' prompt (CPU booted to OPCOM)
    s.reset_input_buffer(); s.write(b'\r'); time.sleep(1)
    pr = s.read(300).decode('latin1', 'replace')
    print("prompt check:", repr(pr[-40:]))
    if '#' not in pr:
        print("!! not at OPCOM '#' - press btn1 (Master Clear) first, or power-cycle")
    print("=== sending 1560& (boot from floppy) ===")
    s.reset_input_buffer()
    paced("1560&")
    buf = ""
    t0 = time.time()
    while time.time() - t0 < 60:
        c = s.read(8000).decode('latin1', 'replace')
        if c:
            buf += c
            sys.stdout.write(c); sys.stdout.flush()
    print("\n\n=== RAW (repr, last 400) ===")
    print(repr(buf[-400:]))

if __name__ == "__main__":
    main()
