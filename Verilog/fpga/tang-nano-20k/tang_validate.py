#!/usr/bin/env python3
###############################################################################
# tang_validate.py - drive the INSTRUCTION-B validator on the Tang Nano 20K
#
# Full path:
#   Verilog/fpga/tang-nano-20k/tang_validate.py  (repo-relative)
#
# WHAT IT DOES
#   Talks to the running ND-120 on the Tang Nano 20K over the OPCOM console
#   UART (default /dev/ttyUSB1 @ 9600 8N1). It:
#     1. confirms the OPCOM monitor prompt ('#'),
#     2. optionally reflashes the bitstream over JTAG for a clean cold reset
#        (--reset jtag  ->  `make load-gowin`),
#     3. cold-loads and starts INSTRUCTION-B from the SD/tape boot image
#        (sends '400$'),
#     4. types each INSTRUCTION-B area command and watches the console until
#        that area prints its own 'END OF TEST' (PASS) or the per-area
#        timeout elapses with no END OF TEST (HANG - the exact failure Ronny
#        reports for RUN / BYTE-STRING / STACK / SEGMENT / 0! / 400$).
#
#   The HARD machine verdict per area is EOT-reached vs HANG, because that is
#   the ground-truth marker the campaign uses and it needs no assumption about
#   unseen error-summary text. Lines containing ERROR/FAIL are counted as an
#   ADVISORY and echoed, and the whole console is saved to a log so the error
#   count can be eyeballed / grepped afterwards.
#
# PROTOCOL FACTS (grounded, not assumed)
#   - Console UART is 9600 8N1 (src/ND120_TANG20K_TOP.v).
#   - Boot + area command is '400$<AREA>\r' - same stream the runSim gate
#     Verilog/tests/instruction-verify/run_area_test.sh feeds the sim.
#   - Each area ends with '== END OF TEST ==' (CAMPAIGN-STATUS.md).
#   - Area names come from README.md / CAMPAIGN-STATUS.md. SEGMENT is an extra
#     on-device menu item Ronny listed that the campaign does not gate.
#
# USAGE
#   python3 tang_validate.py                      # boot + run default areas
#   python3 tang_validate.py --areas ARGUMENT,RUN # just these
#   python3 tang_validate.py --reset jtag         # clean reflash first
#   python3 tang_validate.py --quick              # the 4 Ronny says hang
#   python3 tang_validate.py --no-boot --areas STACK   # already booted
#
# Requires: pyserial (import serial).  Reset jtag requires `make load-gowin`
# to work from this directory (openFPGALoader in PATH / oss-cad-suite).
###############################################################################

import argparse
import os
import re
import subprocess
import sys
import time

try:
    import serial
except ImportError:
    sys.stderr.write("ERROR: pyserial not installed (pip install pyserial)\n")
    sys.exit(2)

HERE = os.path.dirname(os.path.abspath(__file__))

# Campaign-testable areas, ordered fast-first so the quick ones report before
# the long BYTE-STRING / RUN sweeps. 48-BITS-FLOATING is omitted (N/A on this
# 32-bit-float machine). SEGMENT is an on-device menu item Ronny flagged.
DEFAULT_AREAS = [
    "ARGUMENT", "REGISTER-OPERATIONS", "BIT-OPERATIONS", "SEQUENCE",
    "MEMORY-REFERENCE", "SHIFT-INSTRUCTIONS", "STACK", "BCD",
    "ND100-24BIT", "ND100-CX", "PRIVILEGED", "32-BITS-FLOATING",
    "SEGMENT", "BYTE-STRING", "RUN",
]

# The four Ronny reports as hanging on silicon.
QUICK_AREAS = ["STACK", "SEGMENT", "BYTE-STRING", "RUN"]

# Per-area timeout overrides (seconds). These areas sweep for a very long time
# by design (BYTE-STRING = designed MIN repeat loop; RUN = full interrupt
# stress). Everything else uses --area-timeout.
AREA_TIMEOUT = {
    "BYTE-STRING": 600,
    "RUN": 600,
    "32-BITS-FLOATING": 180,
    "BCD": 180,
}

EOT_RE = re.compile(rb"END\s+OF\s+TEST", re.IGNORECASE)
ERR_RE = re.compile(rb"\b(ERROR|FAIL|FAULT)\b", re.IGNORECASE)


class Console:
    def __init__(self, port, baud, logfh, echo=True):
        self.s = serial.Serial(port, baud, timeout=0.3)
        self.log = logfh
        self.echo = echo
        time.sleep(0.2)
        self.s.reset_input_buffer()

    def _emit(self, chunk):
        if not chunk:
            return
        if self.echo:
            sys.stdout.write(chunk.decode("latin1"))
            sys.stdout.flush()
        self.log.write(chunk.decode("latin1"))
        self.log.flush()

    def send(self, text):
        if isinstance(text, str):
            text = text.encode("latin1")
        self.s.write(text)

    def read_until(self, pattern=None, timeout=30.0, quiet=None):
        """Read until `pattern` (compiled regex) matches the accumulated
        buffer, or `timeout` elapses, or (if `quiet` set) no new byte arrives
        for `quiet` seconds after some output was seen. Returns (buf, reason)
        where reason in {'match','quiet','timeout'}."""
        buf = b""
        t0 = time.time()
        last_rx = None
        while time.time() - t0 < timeout:
            chunk = self.s.read(256)
            if chunk:
                buf += chunk
                self._emit(chunk)
                last_rx = time.time()
                if pattern is not None and pattern.search(buf):
                    return buf, "match"
            else:
                if quiet is not None and last_rx is not None \
                        and (time.time() - last_rx) >= quiet:
                    return buf, "quiet"
        return buf, "timeout"

    def close(self):
        try:
            self.s.close()
        except Exception:
            pass


def jtag_reflash():
    print(">>> reflashing bitstream over JTAG (make load-gowin) for clean reset ...")
    r = subprocess.run(["make", "load-gowin"], cwd=HERE,
                       capture_output=True, text=True)
    sys.stdout.write(r.stdout[-2000:])
    if r.returncode != 0:
        sys.stderr.write(r.stderr[-2000:])
        print("!!! make load-gowin failed")
        return False
    # SDRAM content decays on reconfig; give the board a moment to come up.
    time.sleep(3)
    return True


def confirm_prompt(con, timeout=6.0):
    con.send(b"\r")
    buf, reason = con.read_until(re.compile(rb"#"), timeout=timeout)
    return b"#" in buf


def boot(con, boot_timeout, boot_quiet):
    print("\n>>> cold-loading INSTRUCTION-B from SD/tape (400$) ...")
    # OPCOM command letters ($, &, !, /) are ACTION chars: they execute the
    # instant they are typed - do NOT append CR (a trailing CR after $ gets a
    # '?' reject). '400$' = bootstrap-load from device 400 (SD-tape seam).
    con.send(b"400$")
    # Boot is 'done' when output has flowed and then gone quiet at a prompt.
    buf, reason = con.read_until(pattern=None, timeout=boot_timeout, quiet=boot_quiet)
    booted = len(buf.strip()) > 0
    print("\n--- boot settled after %s (%d bytes, reason=%s)"
          % (_fmt_bytes_seen(buf), len(buf), reason))
    return booted, buf


def _fmt_bytes_seen(buf):
    return "%d console bytes" % len(buf)


def run_area(con, area, timeout):
    print("\n=== AREA %s (timeout %ds) ===" % (area, timeout))
    con.send((area + "\r").encode("latin1"))
    buf, reason = con.read_until(EOT_RE, timeout=timeout)
    errs = len(ERR_RE.findall(buf))
    if reason == "match":
        verdict = "PASS" if errs == 0 else "REACHED-EOT-WITH-ERRORS"
    else:
        verdict = "HANG"
    return {
        "area": area, "verdict": verdict, "reason": reason,
        "errlines": errs, "bytes": len(buf),
    }


def main():
    ap = argparse.ArgumentParser(description="Tang Nano 20K INSTRUCTION-B validator")
    ap.add_argument("--port", default="/dev/ttyUSB1")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--areas", default="all",
                   help="'all', 'quick', or comma list e.g. STACK,RUN")
    ap.add_argument("--reset", choices=["none", "jtag"], default="none",
                   help="jtag = reflash bitstream first (clean cold reset)")
    ap.add_argument("--no-boot", action="store_true",
                   help="skip 400$ (program already loaded/running)")
    ap.add_argument("--boot-timeout", type=float, default=45.0)
    ap.add_argument("--boot-quiet", type=float, default=3.0,
                   help="seconds of console silence that means 'boot settled'")
    ap.add_argument("--area-timeout", type=float, default=90.0)
    ap.add_argument("--quiet", action="store_true", help="do not echo console live")
    ap.add_argument("--log", default=None, help="console log path (default: scratch)")
    args = ap.parse_args()

    if args.areas == "all":
        areas = list(DEFAULT_AREAS)
    elif args.areas == "quick":
        areas = list(QUICK_AREAS)
    else:
        areas = [a.strip() for a in args.areas.split(",") if a.strip()]

    logpath = args.log or os.path.join(HERE, "tang_validate.console.log")
    logfh = open(logpath, "w")
    print("Console log: %s" % logpath)

    if args.reset == "jtag":
        if not jtag_reflash():
            sys.exit(1)

    con = Console(args.port, args.baud, logfh, echo=not args.quiet)
    try:
        if not confirm_prompt(con):
            print("!!! no '#' monitor prompt on %s @ %d - board wedged or wrong port"
                  % (args.port, args.baud))
            print("    (try --reset jtag for a clean reflash, or check `make usb`)")
            # keep going only if the user explicitly skips boot
            if not args.no_boot:
                sys.exit(1)

        if not args.no_boot:
            booted, _ = boot(con, args.boot_timeout, args.boot_quiet)
            if not booted:
                print("!!! 400$ produced NO console output within %.0fs => BOOT HANG"
                      % args.boot_timeout)
                print("    This is the cold-start wedge. Verdict: FAIL (boot).")
                sys.exit(1)

        results = []
        for area in areas:
            to = AREA_TIMEOUT.get(area, args.area_timeout)
            results.append(run_area(con, area, to))
    finally:
        con.close()
        logfh.close()

    # Summary
    print("\n" + "=" * 62)
    print("INSTRUCTION-B validation summary (Tang Nano 20K silicon)")
    print("=" * 62)
    print("%-22s %-22s %8s %8s" % ("AREA", "VERDICT", "ERR-LINES", "BYTES"))
    npass = nhang = nerr = 0
    for r in results:
        print("%-22s %-22s %8d %8d"
              % (r["area"], r["verdict"], r["errlines"], r["bytes"]))
        if r["verdict"] == "PASS":
            npass += 1
        elif r["verdict"] == "HANG":
            nhang += 1
        else:
            nerr += 1
    print("-" * 62)
    print("PASS=%d  HANG=%d  EOT-WITH-ERRORS=%d  (of %d areas)"
          % (npass, nhang, nerr, len(results)))
    print("Full console: %s" % logpath)
    # exit 0 only if every requested area reached END OF TEST cleanly
    sys.exit(0 if (nhang == 0 and nerr == 0 and results) else 1)


if __name__ == "__main__":
    main()
