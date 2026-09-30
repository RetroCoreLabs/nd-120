#!/usr/bin/env python3
"""
Compare FPGA (ILA CSV) vs Verilator (VCD) boot sequences.
Extracts CSA at MCLK rising edges from both, maps to microcode listing,
and identifies divergence points.
"""

import csv
import sys
import re
import os

_HERE = os.path.dirname(os.path.abspath(__file__))


def _need_env(name, what):
    """Read a location outside this repository from the environment; stop with a clear message if unset."""
    value = os.environ.get(name)
    if not value:
        sys.exit("compare_boot.py: set %s to %s" % (name, what))
    return value


# The microcode listing lives in the sibling ND110Compile repository:
#   $ND_REPOS/ND110Compile/ND110Compile/uCode/ND-120-DELILAH-L.LISTING.TXT
LISTING_REL = os.path.join("ND110Compile", "ND110Compile", "uCode", "ND-120-DELILAH-L.LISTING.TXT")
# The ILA capture is the CSV Vivado exports (impl_1/iladata.csv in the Vivado
# project); it is named by ND120_ILA_CSV. Both are read in main().
VCD_PATH = os.path.join(_HERE, "waveform.vcd")

def load_microcode_labels(listing_path):
    """Load address->label mapping from microcode listing."""
    labels = {}
    if not os.path.exists(listing_path):
        return labels
    with open(listing_path, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            # Look for label definitions like "MOPC:" or "FTCH2" at known addresses
            parts = line.strip().split()
            if len(parts) >= 2:
                try:
                    addr_str = parts[1]
                    addr = int(addr_str, 8)
                except (ValueError, IndexError):
                    continue
                # Find labels (word ending with :)
                for p in parts[2:]:
                    if p.endswith(':') and not p.startswith('%'):
                        label = p.rstrip(':')
                        if addr not in labels:
                            labels[addr] = label
                        break
                    elif p.startswith('%'):
                        break
    return labels

def extract_ila_csa_at_mclk(csv_path):
    """Extract CSA values at MCLK rising edges from Vivado ILA CSV."""
    results = []
    with open(csv_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        radix = next(reader)  # skip radix row

        # Find columns
        csa_idx = None
        mclk_idx = None
        lcs_idx = None
        zf_idx = None
        cond_idx = None
        run_idx = None
        uarttx_idx = None

        for i, name in enumerate(header):
            name = name.strip()
            if 'CSA_12_0[12:0]' in name:
                csa_idx = i
            elif 's_debug_mclk' == name:
                mclk_idx = i
            elif 's_debug_lcs_n' == name:
                lcs_idx = i
            elif 's_zf' in name:
                zf_idx = i
            elif 's_cond' in name:
                cond_idx = i
            elif 's_run' == name:
                run_idx = i
            elif 's_debug_uartTx' in name:
                uarttx_idx = i

        prev_mclk = None
        for row in reader:
            if len(row) < 10:
                continue
            mclk = row[mclk_idx].strip()
            if prev_mclk == '0' and mclk == '1':
                csa_oct = row[csa_idx].strip()
                lcs = row[lcs_idx].strip() if lcs_idx else '?'
                zf = row[zf_idx].strip() if zf_idx else '?'
                cond = row[cond_idx].strip() if cond_idx else '?'
                run = row[run_idx].strip() if run_idx else '?'
                uarttx = row[uarttx_idx].strip() if uarttx_idx else '?'
                results.append({
                    'csa_oct': csa_oct,
                    'csa_int': int(csa_oct, 8),
                    'lcs': lcs,
                    'zf': zf,
                    'cond': cond,
                    'run': run,
                    'uarttx': uarttx,
                })
            prev_mclk = mclk
    return results

def extract_vcd_csa_sequence(vcd_path, max_transitions=2000):
    """Extract CSA transitions from VCD file (Verilator output).
    Returns list of CSA values at each change, after LCS_n goes high."""

    # Use vcd_extract.py to get CSA and LCS_n, or parse directly
    # For speed, let's parse the VCD manually looking for CSA changes

    results = []
    signal_ids = {}
    csa_id = None
    mclk_id = None
    lcs_id = None
    zf_id = None
    cond_id = None
    run_id = None
    uarttx_id = None

    current_time = 0
    current_csa = 0
    current_mclk = 0
    current_lcs = 0
    current_zf = 0
    current_cond = 0
    current_run = 0
    current_uarttx = 1
    prev_mclk = 0

    lcs_went_high = False
    transitions_after_lcs = 0

    print(f"Parsing VCD: {vcd_path} ...")
    with open(vcd_path, 'r') as f:
        in_defs = True
        scope_stack = []

        for line in f:
            line = line.strip()

            if in_defs:
                if line.startswith('$scope'):
                    parts = line.split()
                    if len(parts) >= 3:
                        scope_stack.append(parts[2])
                elif line.startswith('$upscope'):
                    if scope_stack:
                        scope_stack.pop()
                elif line.startswith('$var'):
                    parts = line.split()
                    if len(parts) >= 5:
                        var_id = parts[3]
                        var_name = parts[4]
                        full_path = '.'.join(scope_stack) + '.' + var_name

                        if var_name == 'CSA_12_0' or (var_name == 'CSA_12_0' and 'ND120_TOP' in full_path):
                            csa_id = var_id
                        elif 's_debug_mclk' in var_name or var_name == 'MCLK':
                            if mclk_id is None:
                                mclk_id = var_id
                        elif 's_debug_lcs_n' in var_name:
                            lcs_id = var_id
                        elif var_name == 's_zf' or 'debug_zf' in var_name:
                            zf_id = var_id
                        elif var_name == 's_cond' or 'debug_cond' in var_name:
                            cond_id = var_id
                        elif var_name == 's_run':
                            run_id = var_id
                        elif var_name == 's_debug_uartTx' or var_name == 'uartTx':
                            uarttx_id = var_id

                elif line.startswith('$enddefinitions'):
                    in_defs = False
                    print(f"  CSA id: {csa_id}")
                    print(f"  MCLK id: {mclk_id}")
                    print(f"  LCS_n id: {lcs_id}")
                    print(f"  s_run id: {run_id}")
                    print(f"  uartTx id: {uarttx_id}")
                continue

            # Parse value changes
            if line.startswith('#'):
                current_time = int(line[1:])
                continue

            if line.startswith('b'):
                # Multi-bit value
                parts = line.split()
                if len(parts) == 2:
                    val_str = parts[0][1:]  # remove 'b'
                    sig_id = parts[1]
                    try:
                        val = int(val_str, 2)
                    except ValueError:
                        val = 0

                    if sig_id == csa_id:
                        current_csa = val
            elif len(line) >= 2 and line[0] in '01xXzZ':
                val = 1 if line[0] == '1' else 0
                sig_id = line[1:]

                if sig_id == mclk_id:
                    if prev_mclk == 0 and val == 1:
                        # MCLK rising edge
                        if current_lcs == 1:
                            if not lcs_went_high:
                                lcs_went_high = True
                                print(f"  LCS_n went high at time {current_time}")

                            results.append({
                                'time': current_time,
                                'csa_int': current_csa,
                                'csa_oct': f"{current_csa:05o}",
                                'lcs': '1',
                                'zf': str(current_zf),
                                'cond': str(current_cond),
                                'run': str(current_run),
                                'uarttx': str(current_uarttx),
                            })
                            transitions_after_lcs += 1
                            if transitions_after_lcs >= max_transitions:
                                break
                    prev_mclk = val
                    current_mclk = val
                elif sig_id == lcs_id:
                    current_lcs = val
                elif sig_id == zf_id:
                    current_zf = val
                elif sig_id == cond_id:
                    current_cond = val
                elif sig_id == run_id:
                    current_run = val
                elif sig_id == uarttx_id:
                    current_uarttx = val

    print(f"  Extracted {len(results)} CSA values after LCS_n=1")
    return results

def identify_phases(csa_sequence):
    """Identify logical phases from CSA sequence."""
    phases = []
    i = 0
    n = len(csa_sequence)

    while i < n:
        csa = csa_sequence[i]['csa_int']
        csa_oct = csa_sequence[i]['csa_oct']

        # Check for known patterns
        # Phase: Countdown loop (o02025/o02026 or o02045/o02046)
        if csa in (0o2025, 0o2026, 0o2045, 0o2046):
            start = i
            loop_addr = csa
            while i < n and csa_sequence[i]['csa_int'] in (loop_addr, loop_addr+1, loop_addr-1):
                i += 1
            phases.append(('COUNTDOWN_LOOP', start, i-1, f"o{loop_addr:05o}/o{loop_addr+1:05o}"))
            continue

        # Phase: MACL self-test loop (o02116-o02123)
        if csa in range(0o2116, 0o2124):
            start = i
            while i < n and csa_sequence[i]['csa_int'] in range(0o2116, 0o2124):
                i += 1
            phases.append(('MACL_SELFTEST', start, i-1, "o02116-o02123"))
            continue

        # Phase: APID2 / TRA PID (o00702-o00723)
        if csa in range(0o702, 0o750):
            start = i
            while i < n and csa_sequence[i]['csa_int'] in range(0o700, 0o750):
                i += 1
            phases.append(('APID2_TRA_PID', start, i-1, "o00702-o00745"))
            continue

        # Phase: Fetch loop (o00000)
        if csa == 0:
            start = i
            # Collect until next fetch (o00000)
            fetch_block = [csa_sequence[i]]
            i += 1
            while i < n and csa_sequence[i]['csa_int'] != 0:
                fetch_block.append(csa_sequence[i])
                i += 1
            # Identify what instruction was executed
            addrs = [e['csa_int'] for e in fetch_block]
            addr_strs = [f"o{a:05o}" for a in addrs]

            # Check for MOPC pattern
            if any(a in range(0o2202, 0o2210) for a in addrs):
                phases.append(('MOPC_UART', start, i-1, ' '.join(addr_strs[:8])))
            elif any(a in range(0o2333, 0o2350) for a in addrs):
                phases.append(('FETCH_EXEC_A', start, i-1, ' '.join(addr_strs[:8])))
            else:
                phases.append(('FETCH_EXEC', start, i-1, ' '.join(addr_strs[:8])))
            continue

        # Generic sequential
        phases.append(('SEQ', i, i, csa_oct))
        i += 1

    return phases

def main():
    LISTING_PATH = os.path.join(
        _need_env("ND_REPOS", "the folder that holds the other ND checkouts (ND110Compile)"),
        LISTING_REL)
    ILA_CSV_PATH = _need_env("ND120_ILA_CSV", "the ILA CSV exported from Vivado (iladata.csv)")
    labels = load_microcode_labels(LISTING_PATH)

    # Extract ILA data
    print("=" * 80)
    print("EXTRACTING FPGA (ILA) DATA")
    print("=" * 80)
    ila_data = extract_ila_csa_at_mclk(ILA_CSV_PATH)
    print(f"ILA: {len(ila_data)} CSA values at MCLK rising edges")

    # Extract VCD data
    print()
    print("=" * 80)
    print("EXTRACTING VERILATOR (VCD) DATA")
    print("=" * 80)
    vcd_data = extract_vcd_csa_sequence(VCD_PATH, max_transitions=len(ila_data) + 100)
    print(f"VCD: {len(vcd_data)} CSA values after LCS_n=1")

    # Build CSA-only sequences for comparison
    ila_csa = [d['csa_oct'] for d in ila_data]
    vcd_csa = [d['csa_oct'] for d in vcd_data]

    # Deduplicate (keep only transitions)
    def dedup(seq):
        result = []
        prev = None
        for v in seq:
            if v != prev:
                result.append(v)
                prev = v
        return result

    ila_trans = dedup(ila_csa)
    vcd_trans = dedup(vcd_csa)

    print()
    print("=" * 80)
    print("PHASE IDENTIFICATION - FPGA")
    print("=" * 80)
    ila_phases = identify_phases(ila_data)
    for phase_type, start, end, detail in ila_phases[:30]:
        label_info = ""
        if phase_type == 'SEQ':
            addr = ila_data[start]['csa_int']
            if addr in labels:
                label_info = f" [{labels[addr]}]"
        print(f"  [{start:4d}-{end:4d}] {phase_type:20s} {detail}{label_info}")
    if len(ila_phases) > 30:
        print(f"  ... ({len(ila_phases)} phases total)")

    print()
    print("=" * 80)
    print("PHASE IDENTIFICATION - VERILATOR")
    print("=" * 80)
    vcd_phases = identify_phases(vcd_data)
    for phase_type, start, end, detail in vcd_phases[:30]:
        label_info = ""
        if phase_type == 'SEQ':
            addr = vcd_data[start]['csa_int']
            if addr in labels:
                label_info = f" [{labels[addr]}]"
        print(f"  [{start:4d}-{end:4d}] {phase_type:20s} {detail}{label_info}")
    if len(vcd_phases) > 30:
        print(f"  ... ({len(vcd_phases)} phases total)")

    # Side-by-side CSA transition comparison
    print()
    print("=" * 80)
    print("CSA TRANSITION COMPARISON (first divergence)")
    print("=" * 80)
    print(f"{'Step':>5} {'Verilator':>10} {'FPGA':>10} {'Match':>6} {'Label':>20}")
    print("-" * 60)

    max_compare = min(len(vcd_trans), len(ila_trans), 500)
    first_diff = None
    for i in range(max_compare):
        vcd_val = vcd_trans[i] if i < len(vcd_trans) else '---'
        ila_val = ila_trans[i] if i < len(ila_trans) else '---'
        match = "OK" if vcd_val == ila_val else "DIFF"

        label = ""
        try:
            addr = int(ila_val, 8)
            if addr in labels:
                label = labels[addr]
        except ValueError:
            pass

        if match == "DIFF" or i < 20 or (first_diff and i < first_diff + 20):
            print(f"{i:>5} {vcd_val:>10} {ila_val:>10} {match:>6} {label:>20}")

        if match == "DIFF" and first_diff is None:
            first_diff = i
            print(f"\n  *** FIRST DIVERGENCE at step {i} ***")
            print(f"  Verilator: o{vcd_val}")
            print(f"  FPGA:      o{ila_val}\n")

    if first_diff is None:
        print(f"\n  All {max_compare} transitions match!")

    # UART activity check
    print()
    print("=" * 80)
    print("UART TX ACTIVITY")
    print("=" * 80)
    ila_uart_changes = sum(1 for i in range(1, len(ila_data)) if ila_data[i]['uarttx'] != ila_data[i-1]['uarttx'])
    vcd_uart_changes = sum(1 for i in range(1, len(vcd_data)) if vcd_data[i]['uarttx'] != vcd_data[i-1]['uarttx'])
    print(f"  FPGA uartTx transitions: {ila_uart_changes}")
    print(f"  Verilator uartTx transitions: {vcd_uart_changes}")

    # s_run check
    print()
    print("=" * 80)
    print("s_run STATUS")
    print("=" * 80)
    ila_run_vals = set(d['run'] for d in ila_data)
    vcd_run_vals = set(d['run'] for d in vcd_data)
    print(f"  FPGA s_run values: {ila_run_vals}")
    print(f"  Verilator s_run values: {vcd_run_vals}")

if __name__ == "__main__":
    main()
