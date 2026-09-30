#!/usr/bin/env python3
"""
Generate a pre-loaded Writable Control Store (WCS) image from the two ND-120
microcode PROM hex files, so the WCS can be $readmemh'd directly and the runtime
WCS-load phase (LCS_n sequence) can be skipped.

Repo path: Code/Microcode/gen_wcs_image.py

Data mapping (verified against RTL):
  - AM27256_45132L.hex = LO byte (bits 7:0),  AM27256_45133L.hex = HI byte (15:8)
  - PROM byte index      idx = LUA*4 + RF          (s_Address = {LUA_12_0, RF_1_0})
  - 16-bit PROM read     P(LUA,RF) = (hi[idx]<<8) | lo[idx]
  - 64-bit microword     word[LUA] = { P(RF=3), P(RF=2), P(RF=1), P(RF=0) }
                         RF=0 -> bits[15:0] ... RF=3 -> bits[63:48]  (no remap)
  - WCS geometry: 2 banks x 16 nibble chips (IDT6168A, 4096x4).
      bank C (16C..31C) = lower, LUA 0..4095 ; bank D (16D..31D) = upper, 4096..8191
      chip (16+j) holds bits [63-4j : 60-4j]  (16 -> [63:60], 31 -> [3:0])

Outputs (into ./wcs/, or ./wcs-sim/ with --sim):
  - wcs_image.hex        : 8192 lines x 16 hex digits (unified, for inspection /
                           a single-BRAM WCS rewrite)
  - wcs_<16..31><C|D>.hex : 32 files x 4096 lines x 1 hex nibble (per IDT6168A chip)

Two variants, DECIDED by Ronny 02-SEP-2026 ("raw on FPGA, patched in sims"):
  - default (no flag) -> ./wcs/     : the RAW PROM microcode, byte for byte the
                                      real ND-120. This is what every BOARD
                                      preloads (Nexys, Tang, Basys3, MEGA65, and
                                      the MiSTer via Verilog/Shared/support).
  - --sim             -> ./wcs-sim/ : the run-simulator variant with the PATCHES
                                      below applied, equal to the patched
                                      AM27256_45133L.hex the Verilator harnesses
                                      (Verilog/sim, runSim, dmaSim) load at
                                      runtime. Only for SKIP_WCS=1 sim runs.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SIM  = "--sim" in sys.argv[1:]
OUT  = os.path.join(HERE, "wcs-sim" if SIM else "wcs")

def read_bytes(name):
    with open(os.path.join(HERE, name)) as f:
        toks = f.read().split()
    vals = [int(t, 16) for t in toks]
    assert len(vals) == 32768, f"{name}: expected 32768 bytes, got {len(vals)}"
    return vals

def main():
    lo = read_bytes("AM27256_45132L.hex")   # bits 7:0
    hi = read_bytes("AM27256_45133L.hex")   # bits 15:8

    words = []
    for lua in range(8192):
        w = 0
        for rf in range(4):
            idx = lua * 4 + rf
            p16 = (hi[idx] << 8) | lo[idx]
            w |= p16 << (16 * rf)            # RF=0 -> LSB group
        words.append(w)

    # SIMULATOR MICROCODE PATCH (--sim only; applied since 07-DEC-2024 to
    # every Verilator harness copy - commit 895f360 "Need pacthed hex files
    # for the run-simulator"; decoded 02-SEP-2026): microword 0o2002 (MACL+1)
    # with RF0 bits 14:13 cleared. Those bits are part of the A-OPERAND
    # field (RF0 bits 15:12): the PROM word says "A,6", the patched word
    # "A,0". The word is "A,6 B,R1 ALUF,PASSD ALUD,B IDBS,BMG" - the
    # bit-mask generator (1 << A) loads scratch register R1 with the OUTER
    # count of the master-clear wait loop (listing 001777-002003, "% WAITING
    # LOOP 0.5 - 1 SECOND": 64 passes of a 65536-step inner loop). Patched,
    # R1 = 1, so the power-on wait is 64x shorter. It is a simulation
    # speed-up, NOT a bug fix: the raw word is the real ND-120 microcode and
    # boots SINTRAN on the MiSTer and the Tang (Verilog/docs/nd120-facts.md).
    # An earlier version of this comment blamed the COND/F,JMP/F,HOLD fields
    # (bits 7:0, untouched) and a LIST-FILE-NAMES failure. The fields were
    # misread, and the LFN claim was withdrawn the same day it was made:
    # the 24-AUG 14:00 A/B matrix in
    # Verilog/fpga/nexys4ddr/HANDOFF-floppy-dma-investigation.md (retired,
    # git c4896a4) shows the
    # Nexys failing LFN with the PATCHED word too, and the rig and the Tang
    # passing with the raw one ("MICROCODE FULLY EXONERATED"). Decoded
    # against ND110Compile/ND120Tokens.cs ("A,6" = RF0 060000, "COND,F=0" =
    # RF0 000340) and BUFALU.cs BMG() = 1 << A.
    # The raw PROM dumps in this directory stay untouched. Boards get the
    # raw word (default run); the patch is applied only for --sim so a
    # SKIP_WCS preload equals what the simulators load at runtime.
    PATCHES = {
        0o2002: (0x0000000000006000, 0x0000000000000000),  # (clear-mask bits, set bits)
    }
    if SIM:
        for lua, (clear, setb) in PATCHES.items():
            before = words[lua]
            words[lua] = (words[lua] & ~clear) | setb
            print(f"  --sim patch LUA {lua:o}: {before:016x} -> {words[lua]:016x}")
    else:
        print("  raw PROM microcode (no patches) - the board variant")

    os.makedirs(OUT, exist_ok=True)

    # Unified 64-bit image
    # newline="\n": LF on every host, so a Windows run and a WSL/CI run write
    # byte-identical files (a CRLF copy fooled a cmp on 02-SEP-2026).
    with open(os.path.join(OUT, "wcs_image.hex"), "w", newline="\n") as f:
        for w in words:
            f.write(f"{w:016x}\n")

    # 32 per-chip nibble files
    for bank, (name, lo_lua, hi_lua) in enumerate(
            [("C", 0, 4096), ("D", 4096, 8192)]):
        for j in range(16):                  # chip 16+j -> bits [63-4j : 60-4j]
            shift = 60 - 4 * j
            chip = 16 + j
            with open(os.path.join(OUT, f"wcs_{chip}{name}.hex"), "w", newline="\n") as f:
                for lua in range(lo_lua, hi_lua):
                    nib = (words[lua] >> shift) & 0xF
                    f.write(f"{nib:x}\n")

    # Sanity report
    nonzero = sum(1 for w in words if w != 0)
    print(f"WCS image: 8192 words, {nonzero} non-zero")
    print(f"  word[0x0000] = {words[0]:016x}   (master-clear entry)")
    print(f"  word[0x0001] = {words[1]:016x}")
    print(f"  word[0x0401] = {words[0x0401]:016x}   (o02001, first real exec)")
    print(f"  wrote wcs_image.hex + 32 per-chip files to {OUT}")

if __name__ == "__main__":
    main()
