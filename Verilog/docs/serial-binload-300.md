# Serial binary loader (300$) - status and findings

PARKED by owner decision, 11-JUL-2026 (see FINAL VERDICT). Trimmed
28-SEP-2026: the blocker analysis, the sim repro recipe and the LDIRV
documentation cross-check are in git history.

10-JUL-2026. Goal: load BPUN programs fast by typing `300$` at the OPCOM
prompt and streaming the raw BPUN file bytes into the console UART - the
BPUN format IS the microcode loader's wire format, no conversion needed.
Reference: RetroTerm docs ND110-OPCOM-MICROCODE-REFERENCE.md (sections on
ETLO1, the 300$ transfer sequence, and the C appendix).

## What works

- The ND-120 microcode (DELILAH-L) HAS the full loader: ETLO1, SEEK/SIKI
  (ASCII preamble), EXFOU ('!' -> binary), BIN, STLP, INCH, DVACT, and
  the on-CPU-board console dispatch IOXG -> IOXX1 -> TERMX -> TRMVC with
  handlers TRM0 (IOX 300 data), TRM2 (IOX 302 status), TRM3 (IOX 303
  control). Confirmed in nd120uc source + L listing.
- `$` is dispatched (DOLOA/ETLOA -> LOAD1 -> ETLO1); the CPU enters the
  loader and its INCH polling loop. Confirmed by CSA trace in simulation.
- Host-side transfer tool: fpga/tools/ndcomm (-b mode) types 300$ and
  streams the file with settle delay + pad; estimated ~49 s for the full
  23001-word INSTRUCTION-B at 9600 baud (vs ~45 min via deposits).
- Feed-rate analysis: the 9600 line cannot be overfed from the host (the
  kernel blocks); once INCH polls, the microcode consumes bytes ~50x
  faster than the line delivers them, so no pacing or flow control is
  needed mid-transfer; too slow is safe (INCH polls forever). The only
  loss window is between typing '$' and ETLO1 polling (MOPC dispatch is
  RTC-tick paced and the SC2661 buffers ONE char) - covered by the
  tool's settle delay (-w ms, default 400) and leading pad spaces.

## The blocker in one paragraph

INCH polls IOX 302 (console input status), but the TERMX 4-way dispatch
(`T,JMP0-3 TRMVC` - IR0-3 drive the low control-store address bits) always
landed on TRMVC+0 (TRM0, the IOX 300 handler) instead of TRM2 at 3722, so the
data-available bit was never reported and INCH spun forever. Reproduced in
Verilator (runSim, `-DSCRIPT_CMD_BINLOAD` + the `ND120_BINLOAD_FILE` harness
in `Run120.cpp`) and identical on hardware. The cause is that nothing in the
ETLO1/INCH flow fires LDIRV, so IR is stale - see below.

## FINAL VERDICT (11-JUL-2026) - hunt closed, bug not ours to fix

Sheet-verified conclusion after full instrumentation and schematic
cross-check with the owner:

1. Our RTL is a FAITHFUL transcription of the CGA as drawn. Verified
   pin-for-pin against DELILAH.pdf: the four LDIRV product terms
   (DCD sheet 4/10: G1=COMM0N.COMM3N.COMM4.MIS0.MIS1.LCSN,
   ND5a=COMM1.COMM3N.COMM4.MIS1.LCSN, ND5b=COMM0.COMM1.COMM3N.COMM4.LCSN,
   ND4=COMM2.COMM3N.COMM4.LCSN = GATES_79/3/8/9), no fifth term, final
   NOR = {decode, MCLK} (GATES_6/10); MIC sheet 2: IRLATCH gate = bare
   LDIRV, data = CD0-CD6; the MUX34P vector legs and selects.
2. Measured in sim (window probes +-2 clocks): selects arrive exactly on
   the dispatch tick; LAA pipelining is by design; BMG=2, R1=302,
   MASKDA=A&~D all correct; IR=0 because nothing in the ETLO1/INCH flow
   fires LDIRV (LDIRV = the fetch/jump/continue COMM family, agent-
   verified against the Microprogrammer's Guide decode table).
3. Therefore the DRAWN hardware dispatches microcode-issued IOX-30x on
   stale IR - a real ND-120 per these sheets would fail 300$ exactly as
   ours does. The console-300 binary load is historically inconclusive
   (the ND110-OPCOM reference is an analysis, not silicon-verified);
   possibly it never worked on ND-120, or an ECO beyond these drawings
   changed it.
4. Experiments (kept behind +define+ND120_EXP_LDIRV_PUSH, OFF by
   default, normal builds untouched): loading IR from the internal IDB
   on T,PUSH calls fixes the poll vector (measured IR=02 -> CS 3722/TRM2,
   first correct dispatch ever) but not DVACT (tail-call, no push);
   loading on every IDBS,ALU word fixes all vectors but clobbers IR in
   macro/MOPC flows and deranges boot. No faithful-to-the-drawings rule
   exists because the drawings themselves lack the mechanism.

DECISION (owner, 11-JUL-2026): STOP hunting. 300$ is parked as
"mechanism proven, hardware-as-drawn cannot do it, disabled". BPUN
loading paths: ndcomm deposit mode (proven on silicon), and the
device-400 SD tape reader (docs/sd-bpun-device-plan.md) which uses the
general bus IOX path and needs no vector. All probes remain available:
Run120.cpp harness (-DND120_PROBE_MIC + --public-flat-rw build),
+define+ND120_EXP_LDIRV_PUSH for the vector experiments.
