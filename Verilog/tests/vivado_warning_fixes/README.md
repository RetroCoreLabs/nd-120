# Vivado Warning Fixes - Testbench Suite

> **Note on testbench placement:** New testbenches should be placed in a
> `sim/` subdirectory next to the module's source code, following the
> project convention used throughout the codebase (e.g.,
> `DELILAH-CPU/CGA_MIC/sim/`). This directory (`tests/vivado_warning_fixes/`)
> contains legacy testbenches from the initial Vivado warning fix pass.
> The MASEL testbenches (`MASEL_cycle_tb.v`, `MASEL_iw_capture_tb.v`) have
> been moved to `DELILAH-CPU/CGA_MIC/sim/`.

This directory contains unit testbenches for all modules modified to fix Vivado synthesis warnings (combinatorial loops, latch inferences, and incomplete signal assignments).

## Overview

These testbenches verify that the behavioral changes made to fix synthesis warnings maintain functional correctness.

### Modules Tested

| Testbench | Module | Fix Type | Description |
|-----------|--------|----------|-------------|
| `PAL_44304E_tb.v` | `PAL_44304E.v` | Combinatorial loop | Converted BACT_reg and EBADR_n_reg to edge-triggered flip-flops |
| `PAL_45008B_tb.v` | `PAL_45008B.v` | Latch inference | Converted DISB_reg and TST_reg latches to flip-flops |
| `BusDriver16_tb.v` | `BusDriver16.v` | Latch inference | Added default assignments and blocking operators |
| `CGA_MIC_MASEL_tb.v` | `CGA_MIC_MASEL.v` | Latch + Signal assignment | Fixed regW latch and s_jmpaddr_12_0[12] assignment |
| `CPU_CS_TCV_20_tb.v` | `CPU_CS_TCV_20.v` | Latch inference | Added default initialization for regCSBITS |
| `F595_tb.v` | `F595.v` | Gated latch | Converted gated R/S latch to edge-triggered flip-flop |

## Prerequisites

### Icarus Verilog (Recommended)
```bash
# Ubuntu/Debian
sudo apt-get install iverilog

# macOS
brew install icarus-verilog

# Check installation
iverilog -v
```

### Alternative: Verilator
```bash
# Ubuntu/Debian
sudo apt-get install verilator

# macOS
brew install verilator
```

## Running the Tests

### Run All Tests
```bash
cd Verilog/tests/vivado_warning_fixes   # from the repository root
make all
```

This will compile and run all 6 testbenches sequentially, displaying results for each.

### Run Individual Tests

```bash
# Test specific module
make test-pal44304e      # PAL_44304E combinatorial loop fix
make test-pal45008b      # PAL_45008B latch fix
make test-busdriver16    # BusDriver16 latch fix
make test-masel          # CGA_MIC_MASEL latch + signal fix
make test-tcv20          # CPU_CS_TCV_20 latch fix
make test-f595           # F595 gated latch fix
```

### Clean Build Artifacts
```bash
make clean
```

## Validating Test Results

Each testbench includes:
- **PASS** messages for successful tests
- **ERROR** messages for failures
- Detailed signal monitoring at each test step

### Expected Output Format

```
========================================
[Module]_tb Testbench - Testing [fix description]
========================================

Test 1: [Description]
Time=X: [Signal values]
PASS: [What was verified]

Test 2: [Description]
...

========================================
[Module]_tb Testbench Complete
========================================
```

## Testbench Details

### 1. PAL_44304E_tb.v - Combinatorial Loop Fix

**What it tests:**
- BACT_reg and EBADR_n_reg now update on clock edges (not combinatorially)
- No self-referential feedback loops
- Proper state holding between clock edges

**Key validation:**
- ✓ BACT sets on (BGNT50 & MWRITE_n)
- ✓ BACT holds when BDAP50=1
- ✓ BACT clears when BDAP50=0
- ✓ EBADR_n sets on (GNT_n & BGNT_n)
- ✓ EBADR_n clears on (IBAPR_n=0 & GNT_n=0)
- ✓ Values stable without clock edge (no combinatorial loops)

**Run:**
```bash
make test-pal44304e
```

**Validation criteria:**
- All tests show PASS
- No ERROR messages
- Signals only change on positive clock edges

---

### 2. PAL_45008B_tb.v - Latch to Flip-Flop Conversion

**What it tests:**
- DISB_reg and TST_reg converted from latches to edge-triggered flip-flops
- Proper synchronous operation with clock input
- State captured only on rising clock edge

**Key validation:**
- ✓ DISB sets on (LBD3 & BIOXL & ECCR) at clock edge
- ✓ DISB clears on (MR_n=0 or BIOXL_n=0) at clock edge
- ✓ TST sets on (LBD0|LBD1|LBD4 & BIOXL & ECCR) at clock edge
- ✓ TST clears on (MR_n=0 or ECCR_n=1) at clock edge
- ✓ Outputs stable without clock edge (no latches)

**Run:**
```bash
make test-pal45008b
```

**Validation criteria:**
- All tests show PASS
- Values don't change between clock edges
- Edge-triggered behavior confirmed

---

### 3. BusDriver16_tb.v - Bidirectional Bus Latch Fix

**What it tests:**
- IO_reg and A_reg no longer infer latches
- Combinational logic with complete signal assignments
- Bidirectional data transfer (A↔IO)

**Key validation:**
- ✓ A→IO transfer when EN=0, TN=1
- ✓ IO→A transfer when EN=1, TN=1
- ✓ High-Z outputs when TN=0
- ✓ Immediate combinational response
- ✓ Direction change works correctly

**Run:**
```bash
make test-busdriver16
```

**Validation criteria:**
- Correct data transfer in both directions
- Proper enable/disable behavior
- Combinational (not latched) operation

---

### 4. CGA_MIC_MASEL_tb.v - Microcode Address Selector

**What it tests:**
- regW latch fix (else clause added for complete assignment)
- s_jmpaddr_12_0 incomplete signal fix (bit 12 added)
- Four operation modes: JUMP, RETURN, NEXT, REPEAT

**Key validation:**
- ✓ JUMP mode: 13-bit address with CSBIT20 as bit[12]
- ✓ RETURN mode: RET_12_0 selected
- ✓ NEXT mode: NEXT_12_0 selected
- ✓ REPEAT mode: IW feeds back
- ✓ regW follows REP when MCLKN=1, holds when MCLKN=0
- ✓ CSBIT20 correctly propagates to bit[12]

**Run:**
```bash
make test-masel
```

**Validation criteria:**
- All 13 bits of jump address correctly formed
- Bit [12] toggles with CSBIT20
- No latch warnings for regW
- All four modes work correctly

---

### 5. CPU_CS_TCV_20_tb.v - Control Store Transceivers

**What it tests:**
- regCSBITS latch fix (default pass-through assignment)
- Bidirectional CSBITS↔IDB data transfer
- 4×16-bit word selection

**Key validation:**
- ✓ Read CSBITS[15:0], [31:16], [47:32], [63:48] to IDB
- ✓ Write IDB to each 16-bit word of CSBITS
- ✓ Pass-through when no word selected
- ✓ Direction control (WCS_n)
- ✓ Enable control (ECSL_n)
- ✓ Combinational response

**Run:**
```bash
make test-tcv20
```

**Validation criteria:**
- All 4 word selections work for read and write
- Pass-through works (verifies latch fix)
- Immediate combinational updates

---

### 6. F595_tb.v - R/S Latch to Flip-Flop

**What it tests:**
- Gated R/S latch converted to edge-triggered flip-flop
- State captured on rising edge of gate (not transparent)
- S/R truth table preserved

**Key validation:**
- ✓ S=1, R=1: Q=1, Qn=1 (both high)
- ✓ S=0, R=1: Q=0, Qn=1 (reset)
- ✓ S=1, R=0: Q=1, Qn=0 (set)
- ✓ S=0, R=0: Hold previous state
- ✓ Edge-triggered (not transparent when G=1)
- ✓ Multiple pulses work correctly

**Run:**
```bash
make test-f595
```

**Validation criteria:**
- R/S truth table preserved
- Edge-triggered behavior confirmed
- Not transparent (values don't change while G=1)

---

## Troubleshooting

### Compilation Errors

**Problem:** Module not found
```
Error: Module 'PAL_44304E' not found
```

**Solution:** Check that module paths in Makefile are correct:
```bash
ls ../../PAL/PAL_44304E.v
```

### Simulation Failures

**Problem:** Test shows ERROR messages

**Solution:**
1. Check the specific test that failed
2. Look at the expected vs actual values
3. Review the module changes to verify correctness
4. Run with waveform generation for detailed analysis:
```bash
iverilog -g2012 -o test_tb test_tb.v module.v
vvp test_tb
gtkwave test.vcd  # if waveform dump enabled
```

### No Output

**Problem:** Testbench runs but shows no output

**Solution:** Ensure `$display` and `$monitor` statements are present in testbench

## Adding Waveform Viewing

To enable VCD waveform dumps, add to any testbench:

```verilog
initial begin
  $dumpfile("testbench_name.vcd");
  $dumpvars(0, module_instance_name);
end
```

Then view with:
```bash
gtkwave testbench_name.vcd
```

## Integration Testing

After unit tests pass, run full system simulation:

```bash
cd ../../runSim
make clean
make compile
make run
```

This tests all modules in their actual operating context within the ND-120 CPU.

## Success Criteria

All tests pass when:
- ✅ No ERROR messages in any testbench output
- ✅ All PASS messages appear for each test
- ✅ No Vivado synthesis warnings when synthesizing with Vivado
- ✅ Full system simulation runs without errors
- ✅ Behavior matches original design intent

## Questions or Issues?

If tests fail or show unexpected behavior:
1. Review the specific ERROR message
2. Check signal values in the test output
3. Compare with original module behavior (pre-fix)
4. Review the fix implementation in the module source
5. Open an issue with:
   - Which testbench failed
   - Full error output
   - Expected vs actual behavior

## Summary

These testbenches provide comprehensive verification that:
- Combinatorial loops are eliminated (PAL_44304E)
- Latch inferences are removed (PAL_45008B, BusDriver16, CGA_MIC_MASEL, CPU_CS_TCV_20, F595)
- Signal assignments are complete (CGA_MIC_MASEL)
- Functional behavior is preserved

Run `make all` to verify all fixes are correct.
