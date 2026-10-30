#!/usr/bin/env python3
"""
BMCL: the bus master clear reaches the I/O cards, at power-up and when the
operator types MACL.

What is checked, on the whole machine (VND120_TOP, the Verilog bus devices
with the Winchester), through the probe engine:

 1. Power-up: the cards' reset (CORE.s_card_rst_n) is held while the master
    clear routine runs and is released once MACL2 has written SIOC = 030140.
 2. Operator MACL: typing MACL at the microprogram console runs the master
    clear routine again (DELILAH-L CS 002001, SIOC = 030120, bit 5 = 0 drives
    EMCL_n low, MCL = NOT(EMCL_n AND CLEAR_n) goes active, and the bus MCL~
    the core puts out goes low - ND3202D.v: MCL = ~s_mcl). The cards' reset
    must go low and come back, and the Winchester's own reset input with it.

Why it matters: ND-11.015.01 sec 3.4.8 "Return to zero by pushing the master
clear button". Before ND120_CORE routed MCL to the cards, an operator master
clear never reached them.

BUILD THE ENGINE FIRST (FF mode is mandatory, see wd_disctema.py):

    make probe-wd USE_LATCHES=0

RUN (from Verilog/sim):

    python3 test_bmcl.py

No disc image is needed: nothing here reads the disc.

Verdict: TB_RESULT: PASS / TB_RESULT: FAIL <reason>

Ronny Hansen
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from nd120_probe import Probe  # noqa: E402

CARD_RST = "CARD_RST_N"
MCL_N = "MCL_n"   # the bus MCL~ out of the core: 0 = master clear active
EMCL_N = "EMCL_n"
CHUNK = 200_000


def fail(p, why):
    # What the console shows says whether MACL ever reached the micro program.
    print("[info] console tail: %r" % (p.console_text()[-400:],), flush=True)
    print("TB_RESULT: FAIL %s" % why, flush=True)
    p.close()
    sys.exit(1)


def wait_for(p, signal, value, maxticks, what, chunk=CHUNK):
    """Step in chunks until `signal` reads `value`. Returns the ticks used.
    The chunk must be shorter than the pulse looked for: the master clear
    lasts about as long as the self-test (some 200,000 ticks at power-up)."""
    done = 0
    while done < maxticks:
        v = p.get(signal)
        if v is None:
            fail(p, "%s cannot be read (%s)" % (signal, what))
        if v == value:
            return done
        p.run(chunk)
        done += chunk
    fail(p, "%s never read %d within %d ticks (%s)" % (signal, value, maxticks, what))


os.chdir(HERE)
p = Probe(engine=os.path.join(HERE, "obj_dir_probe_wd", "VND120_TOP"),
          wsl=False, echo_console=False, timeout=120)
p.start()

# 1. power-up
t = wait_for(p, CARD_RST, 1, 400_000_000, "power-up master clear never ended")
print("[ ok ] power-up: cards out of reset after %d ticks, MCL_n=%s" % (t, p.get(MCL_N)),
      flush=True)
if p.get(MCL_N) != 1:
    fail(p, "MCL still active after the cards were released")

# Let the console settle at the microprogram prompt.
p.run(6_000_000)

# 2. operator MACL. The engine parses the literal two characters \r into a CR.
print("[info] console before MACL: %r" % (p.console_text()[-200:],), flush=True)
p.send("MACL\\r")
t = wait_for(p, CARD_RST, 0, 60_000_000, "typing MACL did not reset the cards",
             chunk=10_000)
print("[ ok ] MACL: cards in reset %d ticks after the command" % t, flush=True)
if p.get(MCL_N) != 0 or p.get(EMCL_N) != 0:
    fail(p, "cards in reset but MCL is not active / EMCL_n is not low")
print("[ ok ] MACL: EMCL_n low, MCL active", flush=True)
t = wait_for(p, CARD_RST, 1, 400_000_000, "the cards stayed in reset after MACL")
print("[ ok ] MACL: cards released %d ticks later" % t, flush=True)

print("TB_RESULT: PASS (BMCL reaches the cards at power-up and on MACL)", flush=True)
p.close()
