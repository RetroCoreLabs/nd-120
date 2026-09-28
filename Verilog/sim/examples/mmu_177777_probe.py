#!/usr/bin/env python3
r"""
mmu_177777_probe.py - investigate STA -> logical 177777 (top page) store routing.

QUESTION (from the probe design note, now in ../PROBE-README.md): when a PAGED store targets logical address
177777 (the very top word of the address space), does the write land in MAIN
memory or in the MMU SHADOW map? A suspected top-page routing bug would send it
to the wrong place.

METHODOLOGY (anti-assume discipline):
  - We instrument the MMU shadow-write strobe s_wmap_n. From CPU_MMU_24.v:
        assign s_wmap_n = ~(s_lshadow & s_write & s_cyd);
    so s_wmap_n==0  <=>  a SHADOW-map write is in flight this cycle.
  - The logical page is read from s_la_20_10 (LA bits 20:10). For the top page
    those upper bits are all ones (o3777 = 0x7FF).
  - We add TWO detectors so a harness that never issues a paged store can NEVER
    masquerade as a top-page bug:
        top_shadow  : s_wmap_n==0 && s_la_20_10==o3777   (the case under test)
        ctrl_shadow : s_wmap_n==0 && s_la_20_10!=o3777   (CONTROL: normal paged store)
  - The FST is gated ON only while a top-page shadow store is in flight, so the
    resulting waveform is tiny and focused.
  - Finally we backdoor-examine MAIN RAM at 177777.

HONEST LIMITATIONS stated up front:
  * The backdoor examines MAIN RAM only (the b0_* arrays). The MMU SHADOW array
    is a separate memory not exposed by the RAM backdoor, so "landed in shadow"
    is INFERRED from the shadow-write strobe firing for that address, not read
    back from the shadow array.
  * INSTRUCTION-B.BPUN is a CPU self-test, not a paging exerciser. If it never
    turns paging on (PON) or never issues a paged store, this run CANNOT answer
    the routing question - and the script says so instead of inventing a bug.

Run (WSL only for the engine; this Python may run on Windows and spawns via wsl.exe):
    python3 examples/mmu_177777_probe.py
"""

import os
import sys

# Allow importing nd120_probe.py from the parent sim/ directory.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from nd120_probe import Probe   # noqa: E402


TICKS = int(os.environ.get("MMU177_TICKS", "400000"))


def resolved(p, name):
    """Return (ok, value) for a signal - honest about VPI-unresolved names."""
    v = p.get(name)
    return (v is not None, v)


def main():
    csv_path = "mmu_177777.csv"
    fst_path = "mmu_177777_win.fst"

    with Probe(bpun="INSTRUCTION-B.BPUN") as p:
        # -- Report which of the signals we depend on actually resolve. ----------
        print("=== signal resolution (registry floor + VPI) ===")
        deps = ["MMU.s_wmap_n", "MMU.s_la_20_10", "MMU.s_cyd",
                "MMU.s_lshadow", "MMU.s_epmap_n", "MMU.s_ept_n", "PON"]
        avail = {}
        # A read only works after at least one eval; step a few ticks first.
        p.run(200)
        for d in deps:
            ok, v = resolved(p, d)
            avail[d] = ok
            print("  %-16s %s" % (d, ("ok (=%s)" % oct(v) if ok else "UNRESOLVED")))

        have_wmap = avail.get("MMU.s_wmap_n", False)
        have_la = avail.get("MMU.s_la_20_10", False)
        have_pon = avail.get("PON", False)

        if not have_wmap:
            print("\nVERDICT: cannot proceed - MMU.s_wmap_n (shadow-write strobe) did "
                  "not resolve. This is a harness/build problem, NOT a top-page bug.")
            return

        # -- Instrument. --------------------------------------------------------
        p.watch_group("MMU")
        p.watch_group("STORE")
        p.set(pre=64, post=64)
        p.open(csv_path)
        p.capture(fst=fst_path)

        # Detector rules. Gate the FST on the top-page store window.
        la_clause_top = " && MMU.s_la_20_10==o3777" if have_la else ""
        la_clause_ctl = " && MMU.s_la_20_10!=o3777" if have_la else ""
        pon_clause = " && PON==1" if have_pon else ""

        p.rule("top_shadow", "MMU.s_wmap_n==0" + la_clause_top + pon_clause,
               ["log:\"TOP-PAGE shadow store\"", "csv", "fst_on"])
        p.rule("ctrl_shadow", "MMU.s_wmap_n==0" + la_clause_ctl,
               ["event"])
        if have_pon:
            p.rule("paging_on", "PON==1", ["log:\"paging enabled\""])

        base = len(p.events())

        # -- Run. ---------------------------------------------------------------
        print("\n=== running %d ticks ===" % TICKS)
        main_before = p.examine(0o177777)
        p.run(TICKS)
        main_after = p.examine(0o177777)

        # -- Tally. -------------------------------------------------------------
        evs = p.events(since=base)
        n_top = sum(1 for e in evs if e["trig"] == "top_shadow")
        n_ctl = sum(1 for e in evs if e["trig"] == "ctrl_shadow")
        n_pon = sum(1 for e in evs if e["trig"] == "paging_on")

        print("\n=== TALLY ===")
        print("  paging_on   edges : %d" % n_pon)
        print("  ctrl_shadow (normal paged store) hits : %d" % n_ctl)
        print("  top_shadow  (store to 177777)    hits : %d" % n_top)
        print("  MAIN[177777] before=%s after=%s" %
              (oct(main_before), oct(main_after)))

        # -- Honest verdict. ----------------------------------------------------
        print("\n=== VERDICT ===")
        if have_pon and n_pon == 0 and n_ctl == 0 and n_top == 0:
            print("HARNESS DID NOT COME UP: over %d ticks INSTRUCTION-B.BPUN never "
                  "enabled paging and never issued a paged store. The 177777 routing "
                  "question CANNOT be answered from this run. This is NOT evidence of "
                  "a top-page bug." % TICKS)
        elif n_ctl == 0 and n_top == 0:
            print("NO PAGED SHADOW STORES OBSERVED (control=0, top-page=0) in %d ticks. "
                  "The workload never exercised the shadow-write path, so nothing can "
                  "be concluded about 177777. NOT a top-page bug." % TICKS)
        elif n_ctl > 0 and n_top == 0:
            print("CONTROL WORKS, TOP-PAGE NOT SEEN: %d normal paged shadow stores "
                  "fired but ZERO stores to logical 177777 occurred in this workload. "
                  "The harness is healthy; this run simply never targeted the top page. "
                  "No bug demonstrated - a workload that stores to 177777 is needed." % n_ctl)
        elif n_top > 0 and main_before == main_after:
            print("TOP-PAGE SHADOW STORE OBSERVED (%d) and MAIN[177777] did NOT change "
                  "(%s). Consistent with the store routing to SHADOW (not main). Inspect "
                  "%s / %s to confirm the shadow vs main decode for that cycle." %
                  (n_top, oct(main_after), csv_path, fst_path))
        elif n_top > 0 and main_before != main_after:
            print("TOP-PAGE STORE OBSERVED (%d) and MAIN[177777] CHANGED %s->%s. The "
                  "store reached MAIN memory. Whether shadow ALSO asserted (double-write) "
                  "needs the %s window inspected." %
                  (n_top, oct(main_before), oct(main_after), csv_path))
        else:
            print("Inconclusive: top=%d ctrl=%d pon=%d. See %s." %
                  (n_top, n_ctl, n_pon, csv_path))

        print("\nCSV window : %s\nFST window : %s (read with fst.py / vcd_extract.py)"
              % (csv_path, fst_path))


if __name__ == "__main__":
    main()
