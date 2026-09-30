#!/usr/bin/env python3
r"""
tpe_paging_capture.py - Phase 1 of the nd120-mmu-shadow-ram investigation.

Boots the REAL TPE "INSTRUCTION VERIFY" (INSTRUCTION-B, program 204384B) inside
the nd120 PROBE (Verilog floppy autoload `1560&`, image = runSim/FLOPPY1.IMG),
drives it to the memory-reference test, and CAPTURES the real MMU paging bring-up
plus the store to logical 177777 (VPN 63) - the store that the RTL reads back as 0.

WHY (the retired sim/HANDOFF-csharp-paging-capture.md, summarised in HISTORY.md
"Retired documents", + memory nd120-mmu-shadow-ram):
the RTL fails every TPE memory-WRITE op that touches logical 177777 under PAGING.
This script gets the GROUND TRUTH from the RTL itself: every page-table / shadow
write (s_wmap_n==0) with its logical-page index (s_la_20_10) and the PPN/PT data
being written, plus the PON enable point.

ANTI-ASSUME DISCIPLINE:
  * The example mmu_177777_probe.py assumed the top page is s_la_20_10==o3777 (the
    top of the full 21-bit space). But TPE's logical 177777 is a 16-bit address:
    177777>>10 = o77 = VPN 63. We do NOT hardcode which index is "the" store; we
    LOG EVERY shadow write with its LA + data and let the analysis identify o77.
  * A CONTROL rule (shadow write to a NON-o77 page) is kept so a harness that never
    issues the top-page store cannot masquerade as a bug.
  * MAIN[177777] is backdoor-examined before/after (main-RAM only; the MMU shadow
    array is a separate memory - "landed in shadow" is inferred from the strobe).

Runs the ENGINE only under WSL. Run this script itself under WSL:
    cd Verilog/sim          # from the repository root
    python3 examples/tpe_paging_capture.py
Outputs (in sim/):
    tpe_paging.csv      - compact PRE/POST windows around every shadow write
    tpe_paging_win.fst  - full-hierarchy FST gated on the top-page (o77) store
    tpe_paging_events.log- one line per captured EVENT/LOG (also printed)
"""

import os
import sys
import time

# Import the driver from the parent sim/ directory.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from nd120_probe import Probe   # noqa: E402

# sim/ is this file's parent folder; runSim/ sits next to it.
SIM_DIR   = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENGINE    = os.path.join(SIM_DIR, "obj_dir_probe_floppy", "VND120_TOP")
FLOPPY    = os.path.join(os.path.dirname(SIM_DIR), "runSim", "FLOPPY1.IMG")

# Full VPI paths for the PTE write-data buses (verified to resolve).
MMU       = "ND120_TOP.CORE.CPU_BOARD.CPU.MMU"
PPN_IN    = MMU + ".s_pt_ppn_25_10_in"   # data written into the PPN chips (22G/23G)
PT_IN     = MMU + ".s_pt_pt_15_0_in"     # data written into the PT chips  (24G/25G)

# Tick budget knobs (overridable via env).
BOOT_TICKS = int(os.environ.get("TPE_BOOT_TICKS", "2000000"))    # to MOPC prompt
PROMPT_TICKS = int(os.environ.get("TPE_PROMPT_TICKS", "8000000"))# after 1560& -> ">"
STEP       = int(os.environ.get("TPE_STEP", "10000000"))          # run chunk
MAXTICKS   = int(os.environ.get("TPE_MAXTICKS", "300000000"))     # total after "run"
# VPN under test: logical 177777 (16-bit) -> page o77. Overridable if analysis
# shows TPE uses a wider logical space.
TOPPAGE    = os.environ.get("TPE_TOPPAGE", "o77")


def main():
    os.environ["ND120_FLOPPY_IMG"] = FLOPPY
    evlog = open(os.path.join(SIM_DIR, "tpe_paging_events.log"), "w")

    def note(msg):
        print(msg)
        evlog.write(msg + "\n"); evlog.flush()

    # wsl=False: we already run under WSL, so spawn the ELF directly and let it
    # inherit ND120_FLOPPY_IMG from our environment.
    with Probe(engine=ENGINE, wsl=False, bpun=None, echo_console=True,
               timeout=120) as p:
        note("=== Phase 1: boot TPE in the PROBE ===")
        note("[boot] running %d ticks to the MOPC prompt..." % BOOT_TICKS)
        p.run(BOOT_TICKS)

        note("[boot] sending '1560&' (Verilog floppy autoload)...")
        p.send("1560&")

        # Run until the TPE banner / '>' prompt appears.
        note("[boot] running up to %d ticks for the TPE prompt..." % PROMPT_TICKS)
        got_prompt = False
        stepped = 0
        while stepped < PROMPT_TICKS:
            p.run(min(STEP, PROMPT_TICKS - stepped))
            stepped += STEP
            con = p.console_text()
            if "INSTRUCTION-B" in con or "command HELP" in con:
                got_prompt = True
                break
        if not got_prompt:
            note("VERDICT: TPE did NOT reach its banner within %d ticks. Console tail:"
                 % PROMPT_TICKS)
            note(repr(p.console_text()[-400:]))
            note("STOP - Phase 1 blocked (harness did not come up).")
            return
        note("[boot] TPE banner seen. Console tail:")
        note(repr(p.console_text()[-200:]))

        # -- Instrument BEFORE issuing 'run'. --------------------------------
        note("\n=== installing capture rules ===")
        p.watch_group("MMU")
        p.watch(PPN_IN)
        p.watch(PT_IN)
        p.set(pre=8, post=8)
        p.open(os.path.join(SIM_DIR, "tpe_paging.csv"))
        p.capture(fst=os.path.join(SIM_DIR, "tpe_paging_win.fst"))

        # Every shadow / page-table write: LA + PPN/PT data land in the CSV window.
        p.rule("shadow_any", "MMU.s_wmap_n==0", ["csv"])
        # The store under test: shadow write whose logical page == TOPPAGE (o77).
        p.rule("top_store", "MMU.s_wmap_n==0 && MMU.s_la_20_10==%s" % TOPPAGE,
               ['log:"TOP-PAGE shadow store"', "csv", "fst_on", 'mark:"top"'])
        # CONTROL: shadow write to any OTHER page (proves the harness is alive).
        p.rule("ctrl_store", "MMU.s_wmap_n==0 && MMU.s_la_20_10!=%s" % TOPPAGE,
               ["event"])
        # Paging-enable edge.
        p.rule("paging_on", "PON==1", ['log:"paging enabled"', "fst_on"])

        base = len(p.events())
        main_before = p.examine(0o177777)
        note("[store] MAIN[177777] before run = %s" % oct(main_before))

        # -- Drive the memory-reference test. --------------------------------
        note("\n=== sending 'RUN' and stepping up to %d ticks ===" % MAXTICKS)
        p.send("run\r")

        stepped = 0
        seen_ref = False
        while stepped < MAXTICKS:
            p.run(STEP)
            stepped += STEP
            evs = p.events(since=base)
            n_top = sum(1 for e in evs if e["trig"] == "top_store")
            n_ctl = sum(1 for e in evs if e["trig"] == "ctrl_store")
            n_pon = sum(1 for e in evs if e["trig"] == "paging_on")
            con = p.console_text()
            low = con.lower()
            if ("reference" in low or "memory ref" in low) and not seen_ref:
                seen_ref = True
                note("[progress] tick~%d: memory-reference section reached in console."
                     % (BOOT_TICKS + PROMPT_TICKS + stepped))
            note("[progress] +%dM ticks: shadow(top=%d ctrl=%d) pon=%d ref_seen=%s"
                 % (stepped // 1_000_000, n_top, n_ctl, n_pon, seen_ref))
            # Stop once we have the memory-reference section AND at least one
            # top-page shadow store captured (the event we came for), plus a
            # little slack already ran this chunk.
            if seen_ref and n_top > 0:
                note("[progress] captured top-page store + memory-ref section - stopping.")
                break
            # Also stop if the test clearly errored on the store (console proof).
            if "STA/STT" in con or "*** ERROR ***" in con:
                note("[progress] TPE printed a memory-reference ERROR - stopping.")
                # run one more chunk-free settle
                break

        main_after = p.examine(0o177777)
        note("[store] MAIN[177777] after run  = %s" % oct(main_after))

        # -- Tally + honest verdict. -----------------------------------------
        evs = p.events(since=base)
        n_top = sum(1 for e in evs if e["trig"] == "top_store")
        n_ctl = sum(1 for e in evs if e["trig"] == "ctrl_store")
        n_pon = sum(1 for e in evs if e["trig"] == "paging_on")
        note("\n=== TALLY ===")
        note("  paging_on edges                    : %d" % n_pon)
        note("  ctrl_store (non-o77 shadow writes) : %d" % n_ctl)
        note("  top_store  (o77 shadow writes)     : %d" % n_top)
        note("  MAIN[177777] before=%s after=%s" % (oct(main_before), oct(main_after)))

        note("\n=== VERDICT (Phase 1 capture) ===")
        if n_pon == 0 and n_ctl == 0 and n_top == 0:
            note("HARNESS DID NOT EXERCISE PAGING: no PON edge and no shadow writes "
                 "were captured. Cannot answer the 177777 routing question from this "
                 "run. NOT evidence of a bug.")
        elif n_top == 0 and n_ctl > 0:
            note("CONTROL ALIVE, TOP-PAGE NOT SEEN: %d non-o77 shadow writes fired but "
                 "ZERO writes to page o77. Either TPE had not reached the 177777 store "
                 "yet (increase TPE_MAXTICKS) or o77 is the wrong index (inspect the CSV "
                 "for the actual top-page index)." % n_ctl)
        elif n_top > 0:
            note("TOP-PAGE (o77) SHADOW WRITE(S) CAPTURED: %d. See tpe_paging.csv / "
                 "tpe_paging_win.fst for LA->PPN/PT format and the MMU state "
                 "(LSHADOW/EPMAP_n/EPT_n/WMAP_n). MAIN[177777] %s. This is the "
                 "ground-truth setup for the Phase 3 replay tb." %
                 (n_top, "changed %s->%s" % (oct(main_before), oct(main_after))
                  if main_before != main_after else "unchanged (%s)" % oct(main_after)))
        note("\nCSV: %s\nFST: %s\nEVENTS: %s" %
             (os.path.join(SIM_DIR, "tpe_paging.csv"),
              os.path.join(SIM_DIR, "tpe_paging_win.fst"),
              os.path.join(SIM_DIR, "tpe_paging_events.log")))
    evlog.close()


if __name__ == "__main__":
    main()
