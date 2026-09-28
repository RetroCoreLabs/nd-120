# 48-BITS-FLOATING deep failures: not a bug - the machine is a 32-bit-float ND-120

**Verdict: N/A by configuration.** The INSTRUCTION-B `48-BITS-FLOATING` area
(NLZ48/DNZ48/FMU48/FDV48/FAD48, 4995 error lines, never reaches END OF TEST)
cannot pass on this CPU because the DELILAH microcode in our PROMs implements
the **32-bit** floating-point option, not the 48-bit one. The area to
validate on this machine is `32-BITS-FLOATING` (INSTRUCTION-B has it, and an
ND-110 golden trace exists for it:
`$ND_REPOS/ND110Compile/traces/TRACE-INSTRUCTION-VERIFY-32-BITS-FLOATING.md`).

## Evidence

1. **Failure counts are build-independent.** The sub-op mix (DNZ48=512,
   FAD48=770, FDV48=1536, FMU48=1536, NLZ48=640) is byte-identical across
   the CGA_ALU_QREG multiply fix and the CGA_CPU_ALU_CONTR SSEL fix -
   whatever fails, it is not the ALU data paths those fixes touched.

2. **Deposit ground truth** (`Verilog/runSim/shift-tests/dnzcheck.s`,
   8 NLZ/DNZ cases, results as T/A/D/STS quads): the results are wrong for
   the 48-bit format but are **valid 32-bit-format encodings**:
   - `NLZ +16` of A=1 gives A=040100 - sign 0, 9-bit exponent field 257
     (bias 256, i.e. 2^1), mantissa 0 - exactly 1.0 in the ND 32-bit float
     format. T is untouched (the 32-bit format does not use T).
   - `NLZ +16` of A=-1 gives A=140100 (same with sign bit) - consistent.
   - `NLZ +16` of A=077777 gives A:D=041777:177400 (exponent field 271 =
     2^15, mantissa 0.111...) - consistent.
   - `NLZ` then `DNZ` round-trips 012345 exactly - the implementation is
     internally consistent, just in the other format.

3. **Microcode provenance.** The nd120uc microcode reverse-engineering
   project established that the FP block (CSA 3167-3460) is bit-identical
   in both the K (OCR listing) and L (EPROM) microcode versions and
   **both implement 32-bit float**
   (the nd120uc repository, the handoff note dated 2026-07-10 in its `docs/`
   folder).

## Consequence for the instruction-verify campaign

- `48-BITS-FLOATING`: recorded as **N/A (32-bit float machine)** - do not
  chase these failures in the RTL; they are the microcode correctly
  executing the other float option.
- `32-BITS-FLOATING`: this is the float area that gates the campaign - deep
  END-OF-TEST verdict and the golden 400-window must both pass.
- The ND-110 that produced the golden traces ran both areas; its
  48-BITS-FLOATING trace is only meaningful for a 48-bit-configured machine.

If a 48-bit-float ND-120 is ever wanted, that is a microcode PROM swap
(the 48-bit FP microcode variant), not an RTL change.
