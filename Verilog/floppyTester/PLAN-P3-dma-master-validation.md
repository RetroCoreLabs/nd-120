# P3 — DMA master vs the real board bus: adjudicating the 7/8 errors

**Status: DONE + MEASURED (2026-07-26).** A standalone Verilator harness was
built (its own dir + Makefile + obj_dir, NOT touching `sim/` or `runSim/`), it
drives the real `ND_DMA_MASTER` against the real arbiter (`PAL_44801A` via BIF)
and real RAM, and it **passes**. The "7/8 errors" were adjudicated: writes and
reads through the real bus are correct; the recovery gap (`MIN_GAP_TICKS`) was
proven **load-bearing** by reproducing the documented "every second read lost".
The measured outcome is in **§0 RESULTS** below. The original design and
analysis (sections 1-7: the fidelity ladder, the planned iverilog Tier-1 bench,
open decisions) was overtaken by the Verilator harness that was built instead,
and was cut on 28-SEP-2026; it is in git history. Facts are cited by path+line.

**Bus protocol reference** (what this P3 work validates the DMA master against):
`Verilog/docs/nd100-bus-dma.md` (writeup; §10.8 =
measured DMA findings) and `Verilog/docs/nd100-bus-deck.pptx`
(slide deck, all bus phases). See also `../ND-BUS-DEVICES/README.md`.

---

## 0. RESULTS (built + measured, 2026-07-26)

**Harness:** `Verilog/dmaSim/` — own `Makefile`,
own `obj_dir`, own C++ main `dma_p3_main.cpp` (+ copied `AM27256_4513{2,3}L.hex`
microcode PROMs). Verilates `ND120_TOP` (`-DVERILATOR_SIM -DFPGA_FF_MODE
-DND_SDRAM_PACK16 -DND120_VERILOG_DEVICES --timing`) and drives ONLY the DMA
test-client ports (`DMA_REQ/WR/ADDR/WDATA -> DMA_RDATA/ACK/ERR`), so the Verilog
`ND_DMA_MASTER` (instantiated at `ND120_CORE.v:622`) requests the bus from the
real arbiter and runs real memory cycles — true cycle-steal while the CPU idles.
Links against the harness alone (the RTL is pure Verilog, no DPI). Bring-up =
reset + clock to a settle count (CPU reaches its OPCOM idle loop, freeing the
bus); verification reads the Verilated RAM byte arrays directly
(`...MEM__DOT__RAM__DOT__b0_lo/hi`).

**Gates (in `dmaSim/Makefile`):**

| Target | Config | Result |
|---|---|---|
| `test-dma-p3` | shipping RTL, 32-word DMA write+read back-to-back | **PASS** (all words correct) |
| `test-dma-p3-repro` | recovery OFF: `MIN_GAP_TICKS=0` + `EARLY_REREQ=1` | **7 / 64 reads stale** — hazard reproduced |
| `test-dma-p3-recovery` | shipping: `EARLY_REREQ=0` + `MIN_GAP_TICKS=32` | **0 / 64 stale** — clean |
| `test-dma-p3-teeth` | runs both above | the gap is load-bearing |

**Findings (measured, not inferred):**

1. **Adjudication of the "7/8 errors": the device is CORRECT.** DMA writes AND
   reads through the real arbiter return the right data. An initial "reads return
   0" symptom was a **HARNESS bug** (the state machine consumed the trailing
   write `dma_ack` — high for one sysclk = two half-cycle samples, and lingering
   across the write->read phase change — as the first read's result). Gating ACK
   handling on an in-flight-request flag fixed it. So the original combined-tb
   "7/8" is consistent with a harness/ACK-sampling artifact, not a device fault.
2. **The recovery gap is load-bearing.** With `MIN_GAP_TICKS=0` and
   `EARLY_REREQ=1` (re-assert BREQ overlapping BDRY), 7 of 64 back-to-back reads
   returned stale data — the exact "every second read lost" of
   `ND_DMA_MASTER.v:55-72` / `nd100-bus-dma.md` §10.8. The shipping default
   (`EARLY_REREQ=0`, `MIN_GAP_TICKS=32`) is clean (0/64).
3. **`EARLY_REREQ=1` DEFEATS `MIN_GAP`** and must never be used (as the RTL
   comment warns): `ST_END` re-asserts `BREQ_n` (`ND_DMA_MASTER.v:265`) before
   the gap counter gates it, so `EARLY_REREQ=1 + MIN_GAP=32` still loses reads.
   `MIN_GAP` alone (`EARLY_REREQ=0`) also shows the hazard at gap 0 (thin margin,
   1/64), confirming the gap itself — not only the re-request discipline — is the
   fix.
4. **Why writes always survived:** memory captures the address on a single
   sysclk-sampled rising edge of `BCGNT50` (`MEM_ADDR_44.v:90-113`,
   `AM29C821 USE_SYSCLK=2`) and this board buffers DMA writes — so a lost grant
   round drops a READ cycle but a WRITE still lands. Reads have no such buffer.

**RTL footprint:** two inert compile-time hooks added to
`Verilog/ND-BUS-DEVICES/DMA/circuit/ND_DMA_MASTER.v`
(`` `ND_DMA_MIN_GAP_TICKS `` / `` `ND_DMA_EARLY_REREQ ``) — no normal build
defines them, so every shipping build is byte-identical. They exist only so the
teeth targets can rebuild with the recovery disabled.

**Note on the old plan:** it framed a Tier-1 iverilog stand-in and a
Verilator Tier-2 as owner-fenced. That was overtaken — a *separate* Verilator
harness (own obj_dir) was authorized and is what was built, so the authoritative
Tier-2 gate exists now without touching the fenced `sim/`/`runSim/` trees.

---

See also:
`Verilog/floppyTester/CONFORMANCE.md`,
`Verilog/ND-BUS-DEVICES/DMA/circuit/ND_DMA_MASTER.v`,
`Verilog/PAL/PAL_44801A.v`,
`Verilog/CPU-BOARD-3202/circuit/BIF_5.v`.
