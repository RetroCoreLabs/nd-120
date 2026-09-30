#!/usr/bin/env python3
"""run_stage_timer.py - boot, log in, start S3, then capture the stage-timer dump.

The probe free-runs from reset and freezes ~5.3 min after arming, so the totals
cover the whole boot plus the first part of a cold S3 start - which is exactly
the disc-heavy window we want. Everything is logged; the dump is hex records.
"""
import re, sys, time, serial

PORT = "/dev/ttyUSB1"
import os
# ND120_ORACLE_DIR: the environment, else local.mk at the repository root.
sys.path.insert(0, os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..")))
import configure  # noqa: E402
LOG = os.path.join(configure.setting_path("ND120_ORACLE_DIR", "/tmp"), "stage_timer_run.log")
GAP = 0.30

s = serial.Serial(PORT, 115200, bytesize=serial.SEVENBITS,
                  parity=serial.PARITY_EVEN, stopbits=serial.STOPBITS_ONE,
                  timeout=0.3)
log = open(LOG, "w", buffering=1)
buf = []

def note(m):
    line = "%s %s" % (time.strftime("%H:%M:%S"), m)
    print(line, flush=True); log.write(line + "\n")

def rx():
    d = s.read(512)
    if d:
        t = "".join(chr(b & 0x7F) for b in d)
        buf.append(t); log.write(t)

def wait(pat, to, what):
    rxp = re.compile(pat, re.I); t0 = time.time()
    while time.time() - t0 < to:
        rx()
        if rxp.search("".join(buf)[-8000:]):
            note("%s after %.1fs" % (what, time.time() - t0)); return True
    note("TIMEOUT on %s" % what); return False

def send(t, cr=True):
    for ch in t:
        s.write(ch.encode()); s.flush(); time.sleep(GAP)
    if cr: s.write(b"\r"); s.flush()

t_start = time.time()
note("=== stage timer run ===")
time.sleep(1); s.reset_input_buffer()
send("20500&")
if not wait(r"SINTRAN\s+III\s+RUNNING", 400, "banner"): sys.exit(2)
if not wait(r"Watchdog\s+has\s+started", 400, "watchdog"): sys.exit(2)
time.sleep(1)
s.write(b"\x1b"); s.flush()
if not wait(r"ENTER", 60, "ENTER prompt"): sys.exit(2)
send("SYSTEM"); time.sleep(2); rx()
s.write(b"\r"); s.flush(); time.sleep(2.5); rx()
send("SET-T-T,,93"); time.sleep(2.5); rx()
note("typing S3 at +%.0fs" % (time.time() - t_start))
send("S3")

note("waiting for the stage-timer dump (fires ~5.3 min after arming)")
deadline = time.time() + 600
recs = 0
while time.time() < deadline:
    rx()
    recs = len(re.findall(r"(?m)^\s*[0-9A-Fa-f]{4,5}\s*$", "".join(buf)))
    if recs >= 17:
        note("dump captured: %d hex records" % recs); break
else:
    note("no dump within 600 s (records seen: %d)" % recs)
s.close()
note("log: %s" % LOG)
