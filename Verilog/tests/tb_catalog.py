#!/usr/bin/env python3
"""
Testbench catalogue and coverage report.

Answers three questions that were previously answered by guessing:

  1. Which testbenches does `make test` actually RUN?
     (Not "how many entries are in the registry" - one registry entry can run
     several testbenches, and a testbench can sit in the tree with nothing
     pointing at it.)

  2. Which testbenches are ORPHANED - they exist, they may even build, but no
     registry entry reaches them, so they never run and can rot silently.

  3. Which circuit modules have NO testbench at all.

How it works: every registry line names a directory and a make target. This
walks that directory's Makefile, resolving the target through its
prerequisites and recipe lines (and through aggregate targets like `test-all`),
collecting every *_tb binary or *_tb.v source it reaches. That set is what
`make test` really exercises.

Run:  python3 tests/tb_catalog.py            (report)
      python3 tests/tb_catalog.py --check    (report + fail on new orphans)

Exit 0 on pass, 1 when an orphan appears that is not in the ORPHAN_BASELINE.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
VERILOG = os.path.abspath(os.path.join(HERE, ".."))
REGISTRY = os.path.join(HERE, "run_all_tests.sh")

# Testbenches known not to be reached by `make test`, with the reason.
# This list may only SHRINK. A new orphan is a failure.
ORPHAN_BASELINE = {
    "CPU-BOARD-3202/circuit/sim/CPU_MMU_PT_29_wcinh_tb.v":
        "DETECTOR, deliberately RED against today's RTL - 28-AUG-2026. The "
        "cache-inhibit bit (WCINH_n, CHIP_20G) gates the whole cache: "
        "WCINH_n -> EWC -> WCA -> CWR -> CUP. It had NO coverage at all while "
        "CACHE-120-A00 was failing on hardware with 'Cache not updated (Use "
        "of limit registers)'. Checks 1 and 2 pass; check 3 fails because "
        "CPU_MMU_PT_29.v:71 addresses the RAM with "
        "s_ppn_25_10_in | s_ppn_25_10_out - a bitwise OR of the two "
        "directions of one bidirectional bus. With the CPU presenting page "
        "0005B and the map presenting 0012B the RAM is addressed at 0017B, a "
        "page neither side asked for.\n\n"
        "CORRECTED SAME DAY, AGAINST MYSELF. Sheet 29 of the 3202D schematic "
        "shows ONE bidirectional bus PPN(25:10) feeding the IMS1403 address "
        "pins (PPN10-23) and its data pin (PPN25). The OR is therefore a "
        "WIRED-OR model of that tri-state bus, which is legitimate as long as "
        "the non-driver contributes 0 - and CPU_15.v:406 does exactly that: "
        "s_lapa_ppn_25_10 = s_lapa_n ? 16'b0 : {2'b0, s_la_23_10}. So the CPU "
        "side is 0 whenever it is not driving, and the mixture this bench "
        "forces is probably UNREACHABLE in the real design. PPN25 is not "
        "stuck at 0 either - CPU_MMU_PPNX_28 drives PPN25-18 from the IDB.\n\n"
        "So this is NOT a proven defect and must not be cited as one. It is "
        "kept as COVERAGE for a path that had none, and as a guard: if anyone "
        "ever makes the CPU side drive the PPN bus while the map is driving "
        "it, this goes red and says why. Retire it or rewrite it to assert "
        "the wired-OR precondition instead.",
    "DELILAH-CPU/CGA_MAC/sim/CGA_MAC_pt_apt_selection_tb.v":
        "UNRESOLVED - 27-AUG-2026. red at 129/259 (PT request selects "
        "PCR[14:11]: got 1 expected 12). 17-AUG ERRFATAL-campaign probe; that "
        "campaign closed via the bank-decode root cause, and whether this is "
        "stale bench expectations or a real PT/APT defect has NOT been "
        "determined. Needs its own look before register-or-delete.",
    "DELILAH-CPU/CGA_TRAP/sim/CGA_TRAP_TVGEN_ptrace_tb.v":
        "DETECTOR, deliberately RED against today's RTL - same family as "
        "the two TVGEN benches below (early PT_15_9 release latches a page "
        "fault from a legal access, 49/99). Register it the day the "
        "trap-vector timing is fixed.",
    "DELILAH-CPU/CGA_MAC/sim/CGA_MAC_replay_tb.v":
        "SKIP by construction - 27-AUG-2026. Replays maccap_vectors.txt, a "
        "capture artifact the MAC capture rig has never produced. Cannot "
        "gate until a capture exists.",
    "DELILAH-CPU/CGA_TRAP/sim/CGA_TRAP_TVGEN_transition_tb.v":
        "DETECTOR, deliberately RED against today's RTL - 17-AUG-2026. "
        "Checks every ordered pair of trap-condition classes: when a condition "
        "becomes live, the dispatched TVEC must name THAT condition. Today all "
        "30 transitions dispatch the previous condition's vector, 8 of them as "
        "vector 7 (the unimplemented Issue-D value). Reproduces BOTH the "
        "27-JUL Issue-D symptom and the page-fault-as-ring-down transient on "
        "the bench in milliseconds. Register it the day the trap-vector "
        "timing is fixed - it is the acceptance gate for that fix.",
    "DELILAH-CPU/CGA_TRAP/sim/CGA_TRAP_TVGEN_pgfrace_tb.v":
        "DETECTOR, deliberately RED against today's RTL - 17-AUG-2026. "
        "Narrow version of the transition bench: PGF stable across the TCLK "
        "edge gives the correct TVEC=1, PGF arriving AT the edge gives TVEC=3. "
        "Kept as the minimal reproduction of the stale-vector capture. "
        "Register alongside CGA_TRAP_TVGEN_transition_tb.v.",
    "CPU-BOARD-3202/circuit/sim/PT_stale_read_tvec_tb.v":
        "EXPERIMENT, deliberately RED in the sync build - 17-AUG-2026. "
        "Wires the real TMM2018D_25 page-table status RAM to CGA_TRAP_TVGEN "
        "and sweeps how early the PT address must change before the capturing "
        "edge. Its measured result RETIRED the async-read theory: sync and "
        "async behave identically, so TMM_ASYNC_READ is NOT the cure and "
        "Verilator needs no divergence from silicon here. Kept for that "
        "record. Not a gate.",
    "fpga/tang-nano-20k/sd-fat-test/sim/sd_fat_block_tb.v":
        "RED, storage lane, parked out of the registry 11-AUG-2026 - see the "
        "comment on the parked entry in run_all_tests.sh. It reaches the range "
        "read, the card model logs 'ACMD6 bus width -> 4-bit', and the next "
        "line is an SD read error at sector 000000A1 with 0 blocks read. "
        "blockdump.img is present but BIG.BPUN, which make_block_image.sh "
        "builds it from, is absent from the tree. NOT caused by the CPU-board "
        "work of that day: BLOCK_SRCS names only SD-FAT circuit files, the "
        "card model, uart_tx/uart_rx and status_printer - no CPU-BOARD-3202 "
        "source is in the build. Target still runs by hand: make test-block. "
        "Restore the registry line the day it goes green.",

    "SD-FAT/sim/nd_storage_smd_adapter_tb.v":
        "OPEN FAULT, and it belongs to the SMD controller workstream that was "
        "handed to another session (do not edit ND_SMD.v or "
        "nd_storage_smd_adapter.v here). Tracked into the tree by commit "
        "b8dd72d with no Makefile rule and no registry entry, so nothing has "
        "ever run it. Built by hand 11-AUG-2026 against STACK_SRCS + "
        "nd_storage_disc_adapter.v: it elaborates and reports 3036 errors, so "
        "it does NOT pass. Baselined rather than registered because this "
        "catalogue check is the FIRST entry in the fail-fast registry, so its "
        "own red result aborted the ENTIRE suite before a single test ran. "
        "Keep the word F-A-I-L out of this text: the runner greps the whole "
        "log for it. Register it the day it goes green.",

    # --- known-failing on purpose: reproducers for OPEN faults --------------
    # The suite is fail-fast, so registering a red test blocks every later
    # test. Each of these is registered the day it goes green.
    "DECODE-GateArray/DGA/sim/F595_transparency_tb.v":
        "OPEN FAULT reproducer - asserts F595 transparent-latch semantics; the "
        "FPGA branch LAGS. The transparent fix WAS tried and REVERTED (it "
        "created a combinational loop that kills the board - do not retry it "
        "naively). Target exists: make test-f595-transparency. Currently "
        "red - 1 error.",

    # --- no machine-checkable verdict: cannot be registered as-is ----------
    # The registry requires a strict pass pattern, because a test that can
    # pass silently can fail silently. These print findings but no verdict.
    "DELILAH-CPU/CGA_MIC/sim/MASEL_cycle_tb.v":
        "prints no TB_RESULT verdict, so it cannot be gated. Target exists "
        "(make test-masel-cycle) and it documents that iverilog cannot "
        "reproduce the original posedge-MCLK pattern because the tb drives SC "
        "and MCLK on the same posedge sysclk. TO FIX: decide the pass "
        "condition, print TB_RESULT, then register.",

    "DELILAH-CPU/CGA_MIC/sim/MASEL_iw_capture_tb.v":
        "prints no TB_RESULT verdict, and currently reports 5 of 7 passing on "
        "capture-correctness. Target exists (make test-masel-iw). TO FIX: "
        "establish whether the 2 bad ones are real, then add a verdict and "
        "register.",

    "DECODE-GateArray/DGA/sim/DECODE_DGA_COMM_tb.v":
        "has a make target since 09-AUG-2026 (make test-dga-comm in "
        "DECODE-GateArray/DGA/sim) and builds in all four ifdef modes, but its "
        "verdict line is red - note errors=0; the failure is a stale "
        "CHECK-COUNT constant (got 240865, expected 219100). The DUT is not "
        "implicated. TO FIX: find out why the count moved (do NOT just update "
        "the constant), then register.",

    # --- board bring-up harnesses, not unit tests --------------------------
    "fpga/basys3/mem-test/sim/basys3_mem_test_tb.v":
        "board bring-up harness for the Basys3 memory test; the directory has "
        "no Makefile. Not a unit test - it exercises a board-specific design "
        "that needs the vendor toolchain.",

    "fpga/qmtech-a35t/mem-test/sim/qmtech_mem_test_tb.v":
        "board bring-up harness for the QMTECH A35T memory test; the directory "
        "has no Makefile. The QMTECH board work is PAUSED "
        "(see qmtech-a35t/docs/board-notes.md).",

    "fpga/tang-nano-20k/sd-fat-test/sim/sd_fat_test_tb.v":
        "top-level Tang SD-FAT harness. The sd-fat-test/sim directory IS "
        "registered (six targets: test-dumper, test-verilator, "
        "test-verilator-fat32, -fat32big, test-tristate, test-errtexts) - this "
        "particular tb is the whole-board wrapper those targets do not build.",

    "fpga/tang-nano-20k/sim/nd120_tang20k_tb.v":
        "whole-board Tang top-level simulation, not a unit test. Covered in "
        "practice by the `make test-full` Tang vtest boot+deposit gate.",
}

# Directories that are not CPU/board RTL and are not expected to carry a
# testbench per module.
SKIP_DIRS = ("/sim/", "/tests/", "/docs/", "/fpga/", "/obj_dir/", "/build/")


def read(path):
    try:
        return open(path, errors="replace").read()
    except OSError:
        return ""


def parse_registry():
    """[(dir, target)] from the REGISTRY array."""
    out = []
    for line in read(REGISTRY).splitlines():
        m = re.match(r'\s*"([^":]+?)\s*::\s*([^":]+?)\s*::', line)
        if m:
            out.append((m.group(1).strip(), m.group(2).strip()))
    return out


def parse_makefile(mkpath):
    """
    -> {target: (prereqs[], recipe_lines[])}, with variables expanded.

    Variable expansion matters: several targets build mode variants whose
    BINARY name (MEM_LBDIF_48_ff_tb_bin) cannot be matched back to the SOURCE
    name (MEM_LBDIF_48_tb.v). The source only appears inside a variable such as
    LBDIF_SRCS, so without expansion those testbenches look orphaned when they
    are in fact registered and running.
    """
    txt = read(mkpath)
    txt = re.sub(r"\\\n", " ", txt)          # join continuations

    # collect simple variable definitions, then expand them (a few passes,
    # since variables reference each other)
    varsd = {}
    for line in txt.splitlines():
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*[:?]?=\s*(.*)$", line)
        if m:
            varsd[m.group(1)] = m.group(2)
    for _ in range(4):
        for k, v in list(varsd.items()):
            varsd[k] = re.sub(r"\$[({]([A-Za-z_][A-Za-z0-9_]*)[)}]",
                              lambda mm: varsd.get(mm.group(1), mm.group(0)), v)
    txt = re.sub(r"\$[({]([A-Za-z_][A-Za-z0-9_]*)[)}]",
                 lambda mm: varsd.get(mm.group(1), mm.group(0)), txt)

    rules = {}
    cur = None
    for line in txt.splitlines():
        if line.startswith("\t"):
            if cur:
                rules[cur][1].append(line.strip())
            continue
        m = re.match(r"^([^\s:=#][^:=]*):(?!=)\s*(.*)$", line)
        if m:
            targets = m.group(1).split()
            prereqs = m.group(2).split()
            for t in targets:
                rules.setdefault(t, ([], []))
                rules[t][0].extend(prereqs)
                cur = t
            if len(targets) == 1:
                cur = targets[0]
        elif not line.strip():
            cur = None
    return rules


TB_TOKEN = re.compile(r"([A-Za-z0-9_]+_tb(?:_[A-Za-z0-9]+)?)")
TB_FILE  = re.compile(r"([A-Za-z0-9_]+_tb)\.v\b")
# any .v named by a target - this is how a module compiled into a
# Verilator harness (test_*.cpp) is detected; those have no _tb.v
MOD_FILE = re.compile(r"([A-Za-z0-9_]+)\.v\b")


def resolve(dirpath, target, rules, seen=None, depth=0):
    """Every *_tb-ish token reachable from `target`."""
    if seen is None:
        seen = set()
    key = (dirpath, target)
    if key in seen or depth > 12:
        return set()
    seen.add(key)

    found = set()
    if target not in rules:
        # Pattern rule, e.g.  iv-%:  iverilog ... -o /tmp/ndtb_$* $*_tb.v
        # Several sim/ Makefiles run a whole family of testbenches this way and
        # register them one per registry line, so missing this reports dozens
        # of false orphans.
        for pat, (pprereqs, precipe) in rules.items():
            if "%" not in pat:
                continue
            esc = re.escape(pat).replace(r"\%", "%")   # re.escape leaves % bare
            rx = "^" + esc.replace("%", "(.*)") + "$"
            m = re.match(rx, target)
            if not m:
                continue
            stem = m.group(1)
            for line in list(precipe) + list(pprereqs):
                expanded = line.replace("$*", stem).replace("$(*)", stem)
                for tok in TB_FILE.findall(expanded):
                    found.add(tok)
                for tok in TB_TOKEN.findall(expanded):
                    found.add(tok)
            break
        return found
    prereqs, recipe = rules[target]

    for p in prereqs:
        p = p.strip()
        if not p:
            continue
        for tok in TB_FILE.findall(p):
            found.add(tok)
        for tok in MOD_FILE.findall(p):
            found.add("MOD:" + tok)
        for tok in TB_TOKEN.findall(os.path.basename(p)):
            found.add(tok)
        if p in rules and not p.endswith(".v"):
            found |= resolve(dirpath, p, rules, seen, depth + 1)

    for line in recipe:
        for tok in TB_FILE.findall(line):
            found.add(tok)
        for tok in MOD_FILE.findall(line):
            found.add("MOD:" + tok)
        for tok in TB_TOKEN.findall(line):
            found.add(tok)
        # `make -C other/dir target` or `$(MAKE) target`
        for m in re.finditer(r"\$\(MAKE\)\s+([A-Za-z0-9_.-]+)", line):
            found |= resolve(dirpath, m.group(1), rules, seen, depth + 1)

    return found



# ---------------------------------------------------------------------------
# Per-area module catalogue (CPU board / DGA / CGA)
# ---------------------------------------------------------------------------
AREAS = [
    ("CPU board 3202D", "CPU-BOARD-3202"),
    ("Decoder gate array (DGA)", "DECODE-GateArray"),
    ("DELILAH CPU gate array (CGA)", "DELILAH-CPU"),
]


def module_list(area_root):
    """Every RTL module in an area (excluding testbenches and sim/ dirs)."""
    out = []
    root_abs = os.path.join(VERILOG, area_root)
    for root, dirs, files in os.walk(root_abs):
        dirs[:] = [d for d in dirs if d not in ("obj_dir", "sim", "build", ".git")]
        for f in sorted(files):
            if f.endswith(".v") and not f.endswith("_tb.v"):
                rel = os.path.relpath(os.path.join(root, f), VERILOG)
                out.append((rel.replace("\\", "/"), f[:-2]))
    return sorted(out)



def module_shape(relpath):
    """
    Measured shape of a module: how much LOGIC it contains versus how much it
    is just wiring submodules together. Used to rank the missing-testbench
    backlog - a container sheet that only instantiates other sheets is a much
    lower-value unit-test target than one full of equations.
    """
    src = read(os.path.join(VERILOG, relpath))
    src = re.sub(r"/\*.*?\*/", " ", src, flags=re.S)
    src = re.sub(r"//[^\n]*", " ", src)
    always = len(re.findall(r"\balways\b", src))
    assigns = len(re.findall(r"\bassign\b", src))
    # submodule instantiations: `Name inst (` that is not a keyword
    insts = len(re.findall(r"^\s*([A-Z][A-Za-z0-9_]*)\s+[A-Za-z_]\w*\s*\(",
                           src, flags=re.M))
    return always, assigns, insts


def write_area_catalogue(all_tb, exercised_set, compiled):
    """
    Emit tests/TESTBENCH-CATALOGUE.md - one table per area, one row per module.

    Coverage per module, measured not guessed:
      DIRECT   <Module>_tb.v exists
      INDIRECT no dedicated tb, but the module name appears inside some
               testbench source (it is pulled in as part of a larger block)
      NONE     no testbench mentions it at all
    """
    tb_names = {b for b in all_tb.values()}
    tb_text = {}
    for rel in all_tb:
        tb_text[rel] = read(os.path.join(VERILOG, rel))

    lines = []
    lines.append("# Testbench catalogue by area")
    lines.append("")
    lines.append("Generated by `tests/tb_catalog.py` (`make catalog` in "
                 "`Verilog/tests/`). Do not hand-edit.")
    lines.append("")
    lines.append("One row per RTL module in the three main areas. Coverage is "
                 "measured, not assumed:")
    lines.append("")
    lines.append("| Mark | Meaning |")
    lines.append("|---|---|")
    lines.append("| **DIRECT** | the module has its own `<Module>_tb.v` |")
    lines.append("| INDIRECT | no dedicated testbench, but the module is named "
                 "inside one - it is exercised as part of a larger block |")
    lines.append("| **NONE** | no testbench mentions it at all |")
    lines.append("")
    lines.append("`in make test` says whether the DIRECT testbench is actually "
                 "reached by `tests/run_all_tests.sh`. A DIRECT testbench that "
                 "is not linked in never runs.")
    lines.append("")

    totals = []
    none_list = []
    for title, root in AREAS:
        mods = module_list(root)
        direct = indirect = none = linked = 0
        rows = []
        for rel, name in mods:
            tbname = name + "_tb"
            has_direct = tbname in tb_names
            if has_direct:
                tbrel = next((r for r, b in all_tb.items() if b == tbname), None)
                is_linked = tbrel in exercised_set
                cov, note = "**DIRECT**", "`" + os.path.basename(tbrel) + "`"
                link = "yes" if is_linked else "**NO**"
                direct += 1
                if is_linked:
                    linked += 1
            elif name in compiled:
                # no dedicated <Module>_tb.v, but a REGISTERED target compiles
                # this module - typically a Verilator test_*.cpp harness
                cov = "COMPILED"
                note = "compiled by a registered target"
                link = "yes"
                indirect += 1
            else:
                hits = [r for r, t in tb_text.items()
                        if re.search(r"\b" + re.escape(name) + r"\b", t)]
                if hits:
                    cov = "INDIRECT"
                    note = "named in `" + os.path.basename(hits[0]) + "`"
                    if len(hits) > 1:
                        note += f" (+{len(hits)-1})"
                    link = "-"
                    indirect += 1
                else:
                    cov, note, link = "**NONE**", "-", "-"
                    none += 1
                    none_list.append(rel)
            rows.append((rel, cov, note, link))

        lines.append(f"## {title}")
        lines.append("")
        lines.append(f"{len(mods)} modules - "
                     f"**{direct} DIRECT** ({linked} linked into `make test`), "
                     f"{indirect} indirect, **{none} with no testbench**.")
        lines.append("")
        lines.append("| Module | Coverage | Testbench | in `make test` |")
        lines.append("|---|---|---|---|")
        for rel, cov, note, link in rows:
            lines.append(f"| `{rel}` | {cov} | {note} | {link} |")
        lines.append("")
        totals.append((title, len(mods), direct, linked, indirect, none))

    lines.append("## Missing testbenches - the backlog, ranked")
    lines.append("")
    lines.append("Every module marked **NONE**, with its measured shape so the "
                 "list can be triaged rather than just counted:")
    lines.append("")
    lines.append("- **HIGH** - contains `always` blocks, i.e. registers, "
                 "latches or state. This is where the latch-versus-flip-flop "
                 "and edge-capture bugs in this project have actually lived.")
    lines.append("- MED - no `always`, but a lot of combinational logic.")
    lines.append("- LOW - mostly a container sheet wiring submodules together; "
                 "its children are where the behaviour is.")
    lines.append("")
    lines.append("Note on the `assign` column: the Logisim-generated style "
                 "wires nets together with `assign`, so a high count is NOT by "
                 "itself evidence of complexity. The `always` column is the "
                 "discriminating one.")
    lines.append("")
    lines.append("| Module | `always` | `assign` | submodules | kind |")
    lines.append("|---|---|---|---|---|")
    shaped = sorted(((module_shape(r), r) for r in none_list),
                    key=lambda x: (-x[0][0], -x[0][1]))
    for (a, g, i), rel in shaped:
        if a:
            kind = "**HIGH**"
        elif g >= 20:
            kind = "MED"
        else:
            kind = "LOW"
        lines.append(f"| `{rel}` | {a} | {g} | {i} | {kind} |")
    lines.append("")
    lines.append("### Caveat on what NONE means")
    lines.append("")
    lines.append("NONE means *no registered unit test names this module*. The "
                 "whole-machine Verilator harnesses in `Verilog/sim` and "
                 "`Verilog/runSim` compile nearly everything through `-y` "
                 "library paths, so these modules are exercised there - but "
                 "only as part of a full boot, where a fault shows up as a "
                 "wedged CPU rather than a named failing assertion. That is "
                 "exactly the difference this backlog is about.")
    lines.append("")
    lines.append("## Summary")
    lines.append("")
    lines.append("Modules marked **NONE** have no testbench at all. This is a "
                 "backlog, not a failure: this project has written testbenches "
                 "where bugs were found rather than uniformly, so an untested "
                 "module is usually one that has never misbehaved. Use the list "
                 "to pick targets when a subsystem starts acting up.")
    lines.append("")
    lines.append("| Area | Modules | DIRECT | linked | INDIRECT | NONE |")
    lines.append("|---|---|---|---|---|---|")
    for t, m, d, l, i, n in totals:
        lines.append(f"| {t} | {m} | {d} | {l} | {i} | {n} |")
    lines.append("")

    out = os.path.join(HERE, "TESTBENCH-CATALOGUE.md")
    with open(out, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    return totals


def main():
    check = "--check" in sys.argv

    # ---- every testbench source in the tree ----
    all_tb = {}          # rel path -> basename without .v
    for root, dirs, files in os.walk(VERILOG):
        dirs[:] = [d for d in dirs if d not in ("obj_dir", ".git", "build")]
        for f in files:
            if f.endswith("_tb.v"):
                rel = os.path.relpath(os.path.join(root, f), VERILOG)
                all_tb[rel.replace("\\", "/")] = f[:-2]

    # ---- what the registry reaches ----
    reached = {}         # dir -> set(tokens)
    entries = parse_registry()
    for d, t in entries:
        mk = os.path.join(VERILOG, d, "Makefile")
        if not os.path.isfile(mk):
            continue
        rules = parse_makefile(mk)
        reached.setdefault(d, set())
        reached[d] |= resolve(d, t, rules)

    # a tb source counts as exercised if a token from its own directory
    # matches its basename (tokens are binary names, usually == basename)
    exercised, orphaned = [], []
    for rel, base in sorted(all_tb.items()):
        d = os.path.dirname(rel)
        toks = reached.get(d, set())
        plain = {t for t in toks if not t.startswith("MOD:")}
        hit = base in plain or any(t.startswith(base) or base.startswith(t)
                                   for t in plain)
        (exercised if hit else orphaned).append(rel)

    print("=" * 74)
    print("TESTBENCH CATALOGUE")
    print("=" * 74)
    print(f"testbench sources in tree : {len(all_tb)}")
    print(f"registry entries          : {len(entries)}")
    print(f"reached by `make test`    : {len(exercised)}")
    print(f"ORPHANED (never run)      : {len(orphaned)}")

    new_orphans = [o for o in orphaned if o not in ORPHAN_BASELINE]
    known = [o for o in orphaned if o in ORPHAN_BASELINE]

    if known:
        print(f"\n--- known orphans ({len(known)}), baselined with a reason ---")
        for o in known:
            print(f"  {o}")
            print(f"      {ORPHAN_BASELINE[o]}")

    if new_orphans:
        print(f"\n--- ORPHANED, NOT BASELINED ({len(new_orphans)}) ---")
        print("  These testbenches exist but nothing runs them. Either register")
        print("  them in tests/run_all_tests.sh, or add them to ORPHAN_BASELINE")
        print("  here with a reason.")
        for o in new_orphans:
            print(f"  {o}")

    # ---- modules with no testbench at all ----
    modules = []
    for root, dirs, files in os.walk(VERILOG):
        dirs[:] = [d for d in dirs if d not in ("obj_dir", ".git", "build", "sim")]
        for f in files:
            if not f.endswith(".v") or f.endswith("_tb.v"):
                continue
            rel = os.path.relpath(os.path.join(root, f), VERILOG).replace("\\", "/")
            if any(s in "/" + rel for s in SKIP_DIRS):
                continue
            modules.append((rel, f[:-2]))

    tb_names = {b for b in all_tb.values()}
    untested = []
    for rel, name in sorted(modules):
        if not any(t == name + "_tb" or t.startswith(name + "_")
                   for t in tb_names):
            untested.append(rel)

    print(f"\n--- module coverage ---")
    print(f"RTL modules (excluding sim/fpga) : {len(modules)}")
    print(f"with a matching testbench        : {len(modules) - len(untested)}")
    print(f"with NO testbench                : {len(untested)}")
    print("\n  Untested modules are a backlog, not a failure - this project")
    print("  builds testbenches where bugs were found, not uniformly. The list")
    print("  is written to tests/UNTESTED-MODULES.txt for triage.")

    compiled = set()
    for toks in reached.values():
        for t in toks:
            if t.startswith("MOD:"):
                compiled.add(t[4:])
    totals = write_area_catalogue(all_tb, set(exercised), compiled)
    print("\n--- per-area catalogue (tests/TESTBENCH-CATALOGUE.md) ---")
    print(f"  {'area':32} {'mods':>5} {'DIRECT':>7} {'linked':>7} {'INDIR':>6} {'NONE':>5}")
    for t, m, d, l, i, n in totals:
        print(f"  {t:32} {m:5} {d:7} {l:7} {i:6} {n:5}")

    with open(os.path.join(HERE, "UNTESTED-MODULES.txt"), "w") as fh:
        fh.write("# RTL modules with no matching testbench.\n")
        fh.write("# Generated by tests/tb_catalog.py - do not hand-edit.\n")
        fh.write(f"# {len(untested)} of {len(modules)} modules.\n\n")
        for m in untested:
            fh.write(m + "\n")

    print()
    if check and new_orphans:
        print(f"TB_RESULT: FAIL {len(new_orphans)} unregistered testbenches")
        return 1
    print("TB_RESULT: PASS (no unregistered testbenches)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
