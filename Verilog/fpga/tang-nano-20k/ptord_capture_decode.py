#!/usr/bin/env python3
"""
ptord_capture_decode.py - boot the Tang and decode the ORDERING ring
(TANG_PTORD_CAPTURE build), or decode an existing log.

Full path:
  Verilog/fpga/tang-nano-20k/ptord_capture_decode.py

WHAT IT ANSWERS (23-AUG-2026, Phase 1b of PLAN-pf-campaign-prio.md, git 043c460)
  Two facts measured on the same silicon boot cannot both describe the same
  moment: the handler WRITES a granting page-table entry (raw index 0o1032,
  data 066001) for the faulting page, and a COMMITTED ACCESS at that same page
  is still caught with an entry that grants nothing. This ring holds both
  event kinds in time order, so ring order settles which came first.

    a no-permit access AFTER a granting write
        -> the map RAM is not retaining or not returning the entry: a defect
           in the page-table RAM read path (the Issue-D family)
    every no-permit access BEFORE the write
        -> paging works; the halt cause is elsewhere, and the next target is
           the fault at Perror 064406

WHAT THE RING HOLDS
  One 20-bit hex record per line. The top nibble is the record kind:
    0xB  page-table write traffic at raw index 0o1032 only; low 16 bits are
         DBG_PTW from CPU_MMU_24:
           word A: [15:14]=10 [13:3]=addr (raw LA_20_10) [2:0]=data[15:13]
           word B: [15:14]=11 [13:1]=data[12:0]          [0]=0
           tag 01 = an IDB->PT write ATTEMPT (no RAM strobe)
    0xC  a no-permit access at that page; low 12 bits = running access count
    0xD  a page-fault vector at that page; low 12 bits = running fault count
  At most 4 consecutive access markers are recorded between writes so the
  writes cannot be evicted; the counters state the TRUE totals, so any
  suppressed run shows up as a jump in the count rather than silently.

USAGE
    python3 ptord_capture_decode.py [--port /dev/ttyUSB1] [--minutes 20]
    python3 ptord_capture_decode.py --decode-file <log>

23-AUG-2026  Ronny Hansen
"""

import argparse
import re
import sys
import time

BOOT_CMD = "20500&"
CHAR_GAP = 0.30  # this console drops characters without a gap

SW_XOR = 0o1400
TARGET_RAW = 0o1032  # software 0o432 - the refaulting page


def sw(raw10):
    return (raw10 & 0x3FF) ^ SW_XOR


def extract_samples(text):
    """20-bit records - the top nibble is the record kind, so do NOT mask it."""
    out = []
    for h in re.findall(r"(?m)^\s*([0-9a-fA-F]{4,5})\s*$", text):
        out.append(int(h, 16) & 0xFFFFF)
    return out


def decode(samples):
    """Return the event list in ring order.

    Each element is one of:
      ("write",   raw_addr, data16)
      ("attempt", raw_addr, data_hi3)
      ("access",  count)
      ("fault",   count)
    """
    events = []
    pend = None
    dropped = 0
    for v in samples:
        kind = (v >> 16) & 0xF
        w = v & 0xFFFF
        if kind == 0xC:
            events.append(("access", w & 0xFFF))
            continue
        if kind == 0xD:
            events.append(("fault", w & 0xFFF))
            continue
        if kind != 0xB:
            continue                       # not a record this build emits
        tag = (w >> 14) & 0x3
        if tag == 0b01:
            events.append(("attempt", (w >> 3) & 0x7FF, w & 0x7))
        elif tag == 0b10:
            if pend is not None:
                dropped += 1
            pend = ((w >> 3) & 0x7FF, w & 0x7)
        elif tag == 0b11:
            if pend is None:
                dropped += 1
                continue
            addr, hi3 = pend
            events.append(("write", addr, (hi3 << 13) | ((w >> 1) & 0x1FFF)))
            pend = None
    return events, dropped


def report(events, dropped):
    writes = [e for e in events if e[0] == "write"]
    attempts = [e for e in events if e[0] == "attempt"]
    accesses = [e for e in events if e[0] == "access"]
    faults = [e for e in events if e[0] == "fault"]
    print("")
    print("=" * 70)
    print(" ORDERING RING - raw page %06o (software %06o)" % (TARGET_RAW, sw(TARGET_RAW)))
    print(" %d records: %d writes, %d attempts, %d access markers, %d fault markers"
          % (len(events), len(writes), len(attempts), len(accesses), len(faults)))
    if dropped:
        print(" %d unpaired write words (ring wrapped mid-pair)" % dropped)
    print("=" * 70)
    if not events:
        print(" RING EMPTY. Either the trigger fired before SINTRAN ran, or the")
        print(" probe path is dead - check the console log for the ERRFATAL.")
        print("=" * 70)
        return

    print("")
    print(" full ring in time order (oldest first):")
    for e in events:
        if e[0] == "write":
            addr, data = e[1], e[2]
            st = (data >> 9) & 0x7F
            grants = "GRANTS" if (st & 0x70) else "grants nothing"
            print("   WRITE   raw %06o -> sw %06o  data %06o  "
                  "WPM=%d RPM=%d FPM=%d WIP=%d PGU=%d  %s"
                  % (addr, sw(addr), data,
                     (st >> 6) & 1, (st >> 5) & 1, (st >> 4) & 1,
                     (st >> 3) & 1, (st >> 2) & 1, grants))
        elif e[0] == "attempt":
            print("   ATTEMPT raw %06o -> sw %06o  data[15:13]=%o (no RAM strobe)"
                  % (e[1], sw(e[1]), e[2]))
        elif e[0] == "access":
            print("   ACCESS  no-permit, running count %d" % e[1])
        else:
            print("   FAULT   page-fault vector, running count %d" % e[1])

    # The verdict: is there a no-permit access after the last GRANTING write?
    last_grant = None
    for i, e in enumerate(events):
        if e[0] == "write" and (((e[2] >> 9) & 0x70) != 0):
            last_grant = i
    print("")
    print("=" * 70)
    if last_grant is None:
        print(" VERDICT: no GRANTING write to this page is in the ring.")
        print(" Either the handler never wrote one in this window, or the ring")
        print(" wrapped past it. Compare the access counter values against the")
        print(" number of access markers to see whether the window was short.")
    else:
        after = [e for e in events[last_grant + 1:] if e[0] == "access"]
        if after:
            print(" VERDICT: %d no-permit access(es) AFTER the granting write." % len(after))
            print(" The entry was written and the same page still reads as")
            print(" granting nothing - the page-table RAM is not retaining or")
            print(" not returning it. Next: the PT RAM read path (Issue-D family).")
        else:
            print(" VERDICT: every no-permit access precedes the granting write.")
            print(" Paging is doing its job on this page. The halt cause is")
            print(" elsewhere - next target is the fault at Perror 064406.")
    print("=" * 70)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="/dev/ttyUSB1")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--minutes", type=float, default=20.0)
    ap.add_argument("--log", default="ptord_capture_run.log")
    ap.add_argument("--decode-file")
    args = ap.parse_args()

    if args.decode_file:
        text = open(args.decode_file, "r", errors="replace").read()
        events, dropped = decode(extract_samples(text))
        report(events, dropped)
        return 0

    import serial  # here so --decode-file works without pyserial

    s = serial.Serial(args.port, args.baud, timeout=0.5)
    log = open(args.log, "w", buffering=1)

    def emit(line):
        stamp = time.strftime("%H:%M:%S")
        print("%s %s" % (stamp, line), flush=True)
        log.write("%s %s\n" % (stamp, line))

    emit("port %s @ %d, deadline %.0f min" % (args.port, args.baud, args.minutes))
    time.sleep(1.0)
    s.reset_input_buffer()
    emit("sending %r one character at a time (%.2fs gap)" % (BOOT_CMD, CHAR_GAP))
    for ch in BOOT_CMD:
        s.write(ch.encode())
        s.flush()
        time.sleep(CHAR_GAP)
    s.write(b"\r")
    s.flush()

    deadline = time.time() + args.minutes * 60
    buf = ""
    raw = []
    reopens = 0
    while time.time() < deadline:
        try:
            chunk = s.read(256)
        except Exception as exc:                      # noqa: BLE001
            reopens += 1
            emit("serial error (%s) - reopening, attempt %d"
                 % (exc.__class__.__name__, reopens))
            try:
                s.close()
            except Exception:
                pass
            time.sleep(2.0)
            try:
                s = serial.Serial(args.port, args.baud, timeout=0.5)
            except Exception as exc2:                 # noqa: BLE001
                emit("reopen failed: %s" % exc2)
                time.sleep(3.0)
            continue
        if not chunk:
            continue
        text = chunk.decode("latin-1", errors="replace")
        raw.append(text)
        log.write(text)
        buf += text
        while "\n" in buf:
            line, buf = buf.split("\n", 1)
            line = line.rstrip("\r")
            if line.strip():
                print(time.strftime("%H:%M:%S") + " | " + line, flush=True)

    s.close()
    emit("collection finished")
    events, dropped = decode(extract_samples("".join(raw)))
    report(events, dropped)
    return 0


if __name__ == "__main__":
    sys.exit(main())
