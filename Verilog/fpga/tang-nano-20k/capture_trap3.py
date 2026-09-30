#!/usr/bin/env python3
"""
capture_trap3.py - drive the Tang Nano 20K through the PAGING test-3 eject and
decode the TANG_TRAP_CAPTURE analyzer dump (Issue D root-cause probe).

Repo path: Verilog/fpga/tang-nano-20k/capture_trap3.py

Prereq: bitstream built with `define TANG_TRAP_CAPTURE (src/tang20k_defines.v)
and SRAM-loaded (make load-gowin). Board on /dev/ttyUSB1 @ 9600 8N1.

Flow: boot floppy (1560&) -> TPE> -> load pag -> run -> test 3, then listen.
Outcomes it classifies:
  DUMP     - the analyzer fired (CSA held at vector 7, or frozen-CSA hang) and
             streamed 512 hex words. Decoded: bits15:12=TVEC, bit11=TRAPN,
             bits10:0=CSA (printed in octal). The last ~32 samples are
             post-trigger; the lead-in shows the dispatch INTO vector 7.
  EJECT    - the TPE banner reappeared with NO dump = the CPU restarted but
             vector 7 was never held and the CSA never froze -> the eject is
             NOT the vector-7 path on silicon (decisive negative).
  SILENT   - neither within the listen window.
"""
import re
import sys
import time

import serial

PORT = "/dev/ttyUSB1"
BAUD = 115200
CHAR_PACE = 0.13  # MOPC has no RX FIFO; pace every char

HEXLINE = re.compile(rb"^[0-9A-Fa-f]{4}$")


def send(ser, text):
    for ch in text:
        ser.write(ch.encode("ascii"))
        ser.flush()
        time.sleep(CHAR_PACE)


def wait_for(ser, needle, timeout, log):
    """Collect bytes until needle (bytes) seen or timeout. Returns (found, buf)."""
    deadline = time.time() + timeout
    buf = b""
    while time.time() < deadline:
        chunk = ser.read(256)
        if chunk:
            buf += chunk
            sys.stdout.write(chunk.decode("ascii", "replace"))
            sys.stdout.flush()
            log.write(chunk)
            if needle in buf:
                return True, buf
    return False, buf


def decode_dump(words):
    print("\n==== TRAP CAPTURE DECODE (oldest first) ====")
    print("idx  TVEC  TRAPN  CSA(oct)")
    prev = None
    for i, w in enumerate(words):
        tvec = (w >> 12) & 0xF
        trapn = (w >> 11) & 1
        csa = w & 0x7FF
        cur = (tvec, trapn, csa)
        if cur != prev:  # compress runs
            print("%3d   %2d     %d    %06o" % (i, tvec, trapn, csa))
            prev = cur
    print("==== last 40 samples verbatim ====")
    for i, w in enumerate(words[-40:]):
        tvec = (w >> 12) & 0xF
        trapn = (w >> 11) & 1
        csa = w & 0x7FF
        print("%3d   TVEC=%2d TRAPN=%d CSA=%06o" % (len(words) - 40 + i, tvec, trapn, csa))


def main():
    logpath = "trap3_session.log"
    ser = serial.Serial(PORT, BAUD, timeout=0.2)
    log = open(logpath, "wb")
    print("== capture_trap3: booting floppy ==")
    time.sleep(1.0)
    ser.reset_input_buffer()

    send(ser, "1560&")
    ok, _ = wait_for(ser, b"TPE", 240, log)
    if not ok:
        print("\nFAIL: no TPE banner after 1560& (240s)")
        return 1
    time.sleep(3)

    send(ser, "load pag\r")
    ok, _ = wait_for(ser, b"Test number", 180, log)
    if not ok:
        # some builds prompt back at TPE> first, then run
        send(ser, "run\r")
        ok, _ = wait_for(ser, b"Test number", 120, log)
        if not ok:
            print("\nFAIL: never reached the Test number prompt")
            return 1

    send(ser, "3\r")
    print("\n== test 3 running; listening for dump / eject (600s) ==")

    deadline = time.time() + 600
    buf = b""
    while time.time() < deadline:
        chunk = ser.read(256)
        if not chunk:
            continue
        buf += chunk
        sys.stdout.write(chunk.decode("ascii", "replace"))
        sys.stdout.flush()
        log.write(chunk)
        lines = buf.replace(b"\r\n", b"\n").replace(b"\r", b"\n").split(b"\n")
        hexlines = [l for l in lines if HEXLINE.match(l)]
        if len(hexlines) >= 512:
            words = [int(l, 16) for l in hexlines[-512:]]
            decode_dump(words)
            print("\nRESULT: DUMP (analyzer fired) - see decode above; raw in %s" % logpath)
            return 0
        if b"TPE Monitor" in buf and len(hexlines) < 8:
            # banner reappeared without a dump; keep listening briefly for a
            # late dump (hold_cnt delays it ~10 s after the trigger)
            tail_ok, tail = wait_for(ser, b"\x00NEVER\x00", 30, log)
            buf += tail
            lines = buf.replace(b"\r\n", b"\n").replace(b"\r", b"\n").split(b"\n")
            hexlines = [l for l in lines if HEXLINE.match(l)]
            if len(hexlines) >= 512:
                words = [int(l, 16) for l in hexlines[-512:]]
                decode_dump(words)
                print("\nRESULT: DUMP after banner - see decode; raw in %s" % logpath)
                return 0
            print("\nRESULT: EJECT with NO dump - vector 7 never held, CSA never froze on silicon.")
            print("        => the silicon eject is NOT the vector-7 path (decisive negative).")
            return 0
    print("\nRESULT: SILENT - neither dump nor banner within 600s; raw in %s" % logpath)
    return 2


if __name__ == "__main__":
    sys.exit(main())
