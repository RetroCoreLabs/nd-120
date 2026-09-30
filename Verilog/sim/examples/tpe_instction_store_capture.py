#!/usr/bin/env python3
r"""
tpe_instction_store_capture.py - capture the FAILING paged STA -> logical 177777.

Boots the REAL TPE Monitor B01 (ND-100 series) via the PORTABLE C floppy core
(probe-floppycore == run-tpe's backend), sends `instr` then `run` to drive the
INSTCTION memory-reference test, and captures the paged DATA STORE to logical
177777 (VPN 63 = page o77) - the store the RTL is reported to read back as 0.

KEY vs tpe_paging_capture.py: that script captured the page-table SETUP writes
(s_wmap_n==0). THIS script rules on the FAILING DATA STORE - a NORMAL paged
memory write (s_write==1 && s_cyd==1 && s_la_20_10==o77 && PON==1) with
s_wmap_n==1 (NOT a shadow-map write). It also keeps a CONTROL store to a
non-top page (o76) so a harness that never issues the top-page store cannot
masquerade as a bug.

Requires the send-gap fix in nd120_probe.cpp (ND120_SEND_GAP) so `1560&` is not
mangled - without it MOPC drops the digits and autoloads INSTRUCTION-B instead.

Run under WSL:
    cd Verilog/sim          # from the repository root
    python3 examples/tpe_instction_store_capture.py
Outputs (sim/): tpe_store.csv, tpe_store_events.log
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from nd120_probe import Probe   # noqa: E402

# sim/ is this file's parent folder; runSim/ sits next to it.
SIM_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENGINE  = os.path.join(SIM_DIR, "obj_dir_probe_floppycore", "VND120_TOP")
FLOPPY  = os.path.join(os.path.dirname(SIM_DIR), "runSim", "FLOPPY1.IMG")

MMU     = "ND120_TOP.CORE.CPU_BOARD.CPU.MMU"
WRITE   = MMU + ".s_write"                 # store-cycle write enable
PPN_IN  = MMU + ".s_pt_ppn_25_10_in"       # PPN presented (physical page) this cycle

BOOT_TICKS = int(os.environ.get("TPE_BOOT_TICKS", "2000000"))
STEP       = int(os.environ.get("TPE_STEP", "10000000"))
PROMPT_MAX = int(os.environ.get("TPE_PROMPT_MAX", "90000000"))   # to TPE>
RUN_MAX    = int(os.environ.get("TPE_RUN_MAX", "250000000"))     # after run
TOPPAGE    = os.environ.get("TPE_TOPPAGE", "o77")                # VPN 63


def main():
    os.environ["ND120_FLOPPYCORE_IMG"] = FLOPPY
    evlog = open(os.path.join(SIM_DIR, "tpe_store_events.log"), "w")

    def note(m):
        print(m); evlog.write(m + "\n"); evlog.flush()

    with Probe(engine=ENGINE, wsl=False, bpun=None, echo_console=True, timeout=180) as p:
        note("=== boot TPE Monitor via C floppy core ===")
        p.run(BOOT_TICKS)
        p.send("1560&")

        # Chunk to the TPE> prompt (TPE is slow: panel-clock probe ~tens of M ticks).
        stepped = 0
        at_tpe = False
        while stepped < PROMPT_MAX:
            p.run(STEP); stepped += STEP
            con = p.console_text()
            if "TPE>" in con:
                at_tpe = True; break
            if "INSTRUCTION-B" in con or "INSTRUCTION  VERIFY" in con:
                note("VERDICT: booted INSTRUCTION-B (send-gap fix NOT effective). "
                     "Console tail:\n" + repr(con[-300:]))
                note("STOP - wrong program; try larger ND120_SEND_GAP.")
                return
        if not at_tpe:
            note("VERDICT: TPE> not reached in %d ticks. Console tail:\n%s"
                 % (PROMPT_MAX, repr(p.console_text()[-400:])))
            note("STOP - boot did not reach the TPE monitor.")
            return
        note("[boot] reached TPE>. Banner:\n" + repr(p.console_text()[-260:]))

        # -- Instrument for the FAILING paged data store. --------------------
        note("\n=== install data-store rules ===")
        p.watch_group("MMU")
        p.watch(WRITE)
        p.watch(PPN_IN)
        p.set(pre=16, post=32)
        p.open(os.path.join(SIM_DIR, "tpe_store.csv"))
        # Paged data store to the TOP page (o77): normal write (wmap_n==1), paged.
        p.rule("top_store",
               "MMU.s_wmap_n==1 && %s==1 && MMU.s_cyd==1 && MMU.s_la_20_10==%s && PON==1"
               % (WRITE, TOPPAGE),
               ['log:"TOP-PAGE paged data store"', "csv", 'mark:"topstore"'])
        # CONTROL: same shape but a non-top page (o76).
        p.rule("ctrl_store",
               "MMU.s_wmap_n==1 && %s==1 && MMU.s_cyd==1 && MMU.s_la_20_10==o76 && PON==1"
               % WRITE,
               ["csv"])
        p.rule("paging_on", "PON==1", ['log:"paging enabled"'])
        base = len(p.events())

        main_before = p.examine(0o177777)
        note("[store] MAIN[177777] before = %s" % oct(main_before))

        # -- Drive the memory-reference test: `config` then `run`. -----------
        # PROVEN sequence from runSim/Run120.cpp:174 SCRIPT_CMD "1560&config\rrun\r"
        # (the TPE-MON configure tool, then run the configured tests).
        note("\n=== send 'config' then 'run' ===")
        # NOTE: the engine strips a trailing real CR/LF from each stdin line and
        # its `send` handler turns the LITERAL two chars backslash-r into CR. So
        # we must pass a raw '\r' (backslash + r), NOT a real CR byte.
        p.send(r"config\r")
        p.run(15000000)                    # let the configure tool settle
        note("[config] console tail:\n" + repr(p.console_text()[-240:]))
        p.send(r"run\r")

        stepped = 0
        seen_ref = False; seen_err = False
        while stepped < RUN_MAX:
            p.run(STEP); stepped += STEP
            evs = p.events(since=base)
            n_top = sum(1 for e in evs if e["trig"] == "top_store")
            n_ctl = sum(1 for e in evs if e["trig"] == "ctrl_store")
            con = p.console_text(); low = con.lower()
            if "reference" in low and not seen_ref:
                seen_ref = True; note("[progress] memory-reference section reached (console).")
            if ("*** error ***" in low or "sta/stt" in low) and not seen_err:
                seen_err = True; note("[progress] TPE printed a memory-reference ERROR.")
            note("[progress] +%dM: top_store=%d ctrl=%d ref=%s err=%s"
                 % (stepped // 1_000_000, n_top, n_ctl, seen_ref, seen_err))
            if n_top > 0 and (seen_ref or seen_err):
                note("[progress] captured top-page paged store - stopping."); break
            if seen_err and stepped >= 2 * STEP:
                break

        main_after = p.examine(0o177777)
        note("[store] MAIN[177777] after  = %s" % oct(main_after))

        evs = p.events(since=base)
        n_top = sum(1 for e in evs if e["trig"] == "top_store")
        n_ctl = sum(1 for e in evs if e["trig"] == "ctrl_store")
        n_pon = sum(1 for e in evs if e["trig"] == "paging_on")
        note("\n=== TALLY ===")
        note("  paging_on edges                 : %d" % n_pon)
        note("  ctrl_store (paged store to o76) : %d" % n_ctl)
        note("  top_store  (paged store to o77) : %d" % n_top)
        note("  MAIN[177777] before=%s after=%s console_err=%s"
             % (oct(main_before), oct(main_after), seen_err))

        note("\n=== VERDICT ===")
        if n_top == 0 and n_ctl == 0:
            note("NO PAGED DATA STORES captured (top=0 ctrl=0). Either the test did not "
                 "reach the 177777 store (raise TPE_RUN_MAX) or it stalled at init "
                 "(TPE42 clock). NOT a bug conclusion. Console tail:\n"
                 + repr(p.console_text()[-300:]))
        elif n_top == 0 and n_ctl > 0:
            note("CONTROL ALIVE, TOP-PAGE NOT SEEN: %d paged stores to o76 but ZERO to "
                 "o77. The test reached paged stores but not (yet) the 177777 store." % n_ctl)
        elif n_top > 0 and main_before == main_after and int(main_after) == 0:
            note("BUG REPRODUCED (candidate): %d paged store(s) to o77 fired but "
                 "MAIN[177777] stayed %s (0). The paged top-page store did NOT land in "
                 "main memory - consistent with the reported 177777->0 fault. Inspect "
                 "tpe_store.csv for PPN/EPMAP_n/EPT_n/WMAP_n/LSHADOW on those cycles."
                 % (n_top, oct(main_after)))
        elif n_top > 0 and main_before != main_after:
            note("TOP-PAGE STORE LANDED IN MAIN: %d store(s), MAIN[177777] %s->%s. "
                 "The paged store reached main memory (correct routing)."
                 % (n_top, oct(main_before), oct(main_after)))
        else:
            note("Top-page store(s)=%d, MAIN[177777] before=%s after=%s. See CSV."
                 % (n_top, oct(main_before), oct(main_after)))
        note("\nCSV: %s\nEVENTS: %s"
             % (os.path.join(SIM_DIR, "tpe_store.csv"),
                os.path.join(SIM_DIR, "tpe_store_events.log")))
    evlog.close()


if __name__ == "__main__":
    main()
