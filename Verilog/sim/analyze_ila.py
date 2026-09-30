#!/usr/bin/env python3
"""
Analyze Vivado ILA CSV capture and compare with Verilator boot sequence.
Extracts CSA values at MCLK rising edges and compares with expected sequence.
"""

import csv
import os
import sys

def parse_ila_csv(filepath):
    """Parse Vivado ILA CSV, return list of dicts with key signals."""
    rows = []
    with open(filepath, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)  # Column names
        radix_row = next(reader)  # Radix row

        # Find column indices for key signals
        col_map = {}
        for i, name in enumerate(header):
            col_map[name.strip()] = i

        for row in reader:
            if len(row) < 10:
                continue
            rows.append(row)

    return header, rows, col_map

def find_col(col_map, *patterns):
    """Find column index matching any of the patterns."""
    for pat in patterns:
        for name, idx in col_map.items():
            if pat in name:
                return idx, name
    return None, None

def main():
    # The capture is the CSV Vivado exports from the ILA (impl_1/iladata.csv in
    # the Vivado project). Give it as the first argument, or name it with the
    # environment variable ND120_ILA_CSV.
    filepath = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("ND120_ILA_CSV")
    if not filepath:
        sys.exit("analyze_ila.py: give the ILA CSV as the first argument, or set ND120_ILA_CSV")

    header, rows, col_map = parse_ila_csv(filepath)

    # Find key columns
    csa_idx, csa_name = find_col(col_map, "CSA_12_0[12:0]")
    mclk_idx, mclk_name = find_col(col_map, "s_debug_mclk")
    lcs_idx, lcs_name = find_col(col_map, "s_debug_lcs_n")
    mr_idx, mr_name = find_col(col_map, "s_debug_mr_n")
    fetch_idx, fetch_name = find_col(col_map, "s_debug_fetch")
    zf_idx, zf_name = find_col(col_map, "s_zf")
    cry_idx, cry_name = find_col(col_map, "s_cry")
    cond_idx, cond_name = find_col(col_map, "s_cond")
    run_idx, run_name = find_col(col_map, "s_run")
    fidbo_idx, fidbo_name = find_col(col_map, "FIDBO[15:0]")
    prom_idx, _ = find_col(col_map, "regData_1")
    prom2_idx, _ = find_col(col_map, "regData_2")
    prom3_idx, _ = find_col(col_map, "regData[9:1]")
    aluf_idx, aluf_name = find_col(col_map, "ALU_F[15:0]")
    aluq_idx, aluq_name = find_col(col_map, "ALU_Q[15:0]")

    print(f"=== ILA Data Analysis ===")
    print(f"Total samples: {len(rows)}")
    print(f"CSA column: {csa_idx} ({csa_name})")
    print(f"MCLK column: {mclk_idx} ({mclk_name})")
    print()

    # Extract CSA at MCLK rising edges (0->1)
    print("=== CSA at MCLK Rising Edges ===")
    print(f"{'Sample':>6} {'CSA(oct)':>10} {'LCS_n':>5} {'MR_n':>5} {'FETCH':>5} {'ZF':>3} {'CRY':>3} {'COND':>4} {'ALU_F':>8} {'ALU_Q':>8} {'FIDBO':>8}")
    print("-" * 90)

    prev_mclk = None
    csa_sequence = []

    for i, row in enumerate(rows):
        mclk = row[mclk_idx].strip()

        if prev_mclk == '0' and mclk == '1':
            csa = row[csa_idx].strip()
            lcs = row[lcs_idx].strip() if lcs_idx else '?'
            mr = row[mr_idx].strip() if mr_idx else '?'
            fetch = row[fetch_idx].strip() if fetch_idx else '?'
            zf = row[zf_idx].strip() if zf_idx else '?'
            cry = row[cry_idx].strip() if cry_idx else '?'
            cond = row[cond_idx].strip() if cond_idx else '?'
            aluf = row[aluf_idx].strip() if aluf_idx else '?'
            aluq = row[aluq_idx].strip() if aluq_idx else '?'
            fidbo = row[fidbo_idx].strip() if fidbo_idx else '?'

            print(f"{i:>6} {csa:>10} {lcs:>5} {mr:>5} {fetch:>5} {zf:>3} {cry:>3} {cond:>4} {aluf:>8} {aluq:>8} {fidbo:>8}")
            csa_sequence.append((i, csa))

        prev_mclk = mclk

    print()
    print(f"Total MCLK rising edges: {len(csa_sequence)}")

    # Show unique CSA transitions
    print()
    print("=== CSA Transitions (address changes only) ===")
    prev_csa = None
    transitions = []
    for sample, csa in csa_sequence:
        if csa != prev_csa:
            transitions.append((sample, csa))
            prev_csa = csa

    for sample, csa in transitions:
        print(f"  Sample {sample:>5}: CSA = {csa}")

    # Expected sequence from boot_analysis.md (after LCS_n=1)
    expected = [
        "02001", "02002", "02003", "02004", "02005", "02006", "02007",
        "02010", "02011", "02012", "02013", "02014", "02015", "02016", "02017",
        "05660",  # jump
    ]

    print()
    print("=== Comparison with Expected Boot Sequence ===")
    print(f"{'Step':>4} {'Expected':>10} {'FPGA':>10} {'Match':>6}")
    print("-" * 40)

    # Find where LCS_n goes to 1 in the capture
    lcs_high_idx = None
    for i, row in enumerate(rows):
        if lcs_idx and row[lcs_idx].strip() == '1':
            lcs_high_idx = i
            break

    if lcs_high_idx is not None:
        print(f"LCS_n goes HIGH at sample {lcs_high_idx}")

    # Compare CSA transitions after LCS_n=1 with expected
    post_lcs_transitions = [(s, c) for s, c in transitions if lcs_high_idx is None or s >= (lcs_high_idx - 5)]

    for i, (expected_csa) in enumerate(expected):
        if i < len(post_lcs_transitions):
            sample, fpga_csa = post_lcs_transitions[i]
            match = "OK" if fpga_csa.strip() == expected_csa else "DIFF"
            print(f"{i:>4} {expected_csa:>10} {fpga_csa:>10} {match:>6}")
        else:
            print(f"{i:>4} {expected_csa:>10} {'---':>10} {'N/A':>6}")

    # Check PROM data
    print()
    print("=== PROM Data Check ===")
    non_zero_prom = 0
    for row in rows[:100]:  # Check first 100 samples
        if prom_idx:
            val = row[prom_idx].strip()
            if val != '0':
                non_zero_prom += 1
    print(f"Non-zero PROM values in first 100 samples: {non_zero_prom}")
    if non_zero_prom > 0:
        print("PROM has data - microcode ROM is populated")
    else:
        print("WARNING: PROM appears empty!")

    # Check FIDBO
    print()
    print("=== FIDBO Data Check ===")
    non_zero_fidbo = 0
    for row in rows[:100]:
        if fidbo_idx:
            val = row[fidbo_idx].strip()
            if val != '0000' and val != '0':
                non_zero_fidbo += 1
    print(f"Non-zero FIDBO values in first 100 samples: {non_zero_fidbo}")
    if non_zero_fidbo > 0:
        print("FIDBO has data - internal data bus is alive")
    else:
        print("WARNING: FIDBO appears dead!")

if __name__ == "__main__":
    main()
