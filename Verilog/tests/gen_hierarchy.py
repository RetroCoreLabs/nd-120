#!/usr/bin/env python3
"""
gen_hierarchy.py - draw the module tree of every build top from a real yosys
elaboration, write Verilog/HIERARCHY.md, and put a navigation block on every
generated module doc.

WHY THIS EXISTS
    MODULES.md lists every module, but a flat list does not say what sits
    inside what. The tree has to come from the tools, not from reading the
    source with a pattern: `ifdef`s, generate blocks and parameters decide
    which instances really exist, and they differ from board to board. So for
    each top this reads the EXACT file list, defines and include folders that
    top's own build uses, lets yosys elaborate it (`hierarchy -top <top>`),
    and takes the instance tree from what yosys built.

WHERE EACH TOP'S FILE LIST COMES FROM (each read from the build itself)
    Simulation     Verilog/runSim/Makefile - make is asked for its own
                   variables (VERILATOR_FLAGS, VERILATOR_DIRS, SDFAT_VFILES)
                   with the default settings. Verilator finds a module by FILE
                   NAME in the -I folders; yosys does the same with
                   `hierarchy -libdir`.
    Tang Nano 20K  Verilog/fpga/tang-nano-20k/Makefile - make is asked for
                   SRCS (the ordered list from nd120_tang20k.gprj), INCS,
                   VDEFS and TOP: the list the OSS yosys flow itself reads.
    Nexys 4 DDR, Cmod A7-35T, QMTECH XC7A35T, MEGA65 R3 and R6, Basys3, MiSTer
                   the board's build script is RUN in tclsh with the vendor
                   commands swapped for stubs (tests/hierarchy_harness.tcl),
                   which print what the script hands to synthesis. The Basys3
                   script drives a Vivado project (.xpr) kept outside the
                   repository; its file list is read from that project when
                   the file is there, and the page says so when it is not.

    Framework and vendor parts are LEAVES, never followed: the MiSTer
    framework (fpga/mister/sys), the MEGA65 framework (the m2m submodule and
    the VHDL in CORE/), Xilinx MIG, PLLs, clock buffers and Gowin/Quartus IP.
    yosys leaves them as cells of an unknown type and the page shows them as
    "vendor". For MiSTer and MEGA65 the tree starts at OUR top below the
    framework (MiSTer `emu`, MEGA65 `nd120_mega65_machine`).

WHAT IT WRITES
    Verilog/HIERARCHY.md    one tree per top, every node a link to its doc
    <folder>/doc/<M>.md     a navigation block between two marker lines,
                            replaced on every run: where the module sits,
                            which modules use it (on which tops), what it
                            contains, links back to HIERARCHY.md and MODULES.md

    ROM and RAM init files ($readmemh) are not needed to know which instances
    exist, and several of them only appear after a build has copied them in.
    yosys stops on a missing one, so each run gets EMPTY stand-in files with
    those names in a scratch folder. The page says this too.

WHERE YOSYS NEEDED HELP (each one is also written on the page)
    - Simulation: sd_card_model.v and nds_mem_model.v (SD-FAT/sim) are
      behavioural test models ($random, file I/O). yosys cannot read them
      even as a library, so they are black boxes made from their own port
      list. Checked by hand 30-SEP-2026: neither instantiates a module.
    - MiSTer: nd120.sv passes unpacked arrays to the framework's hps_io,
      which yosys' own reader rejects. That one file goes through the slang
      plugin that ships with oss-cad-suite; see run_yosys() for how the rest
      is still elaborated by yosys itself.
    - MiSTer: build_id.v is written by the framework just before synthesis;
      a one-line stand-in with the same define is used.

    HIER_KEEP=<folder> keeps each top's yosys script, log and netlist in
    <folder>/<top> for a look by hand.

USAGE
    Run in WSL/Linux (yosys and tclsh live there). Normally called by
    gen_module_docs.py, which is the ONE command that regenerates the module
    docs, MODULES.md and this:
        cd Verilog
        python3 tests/gen_module_docs.py
    On its own (after the docs exist):
        python3 tests/gen_hierarchy.py
        python3 tests/gen_hierarchy.py --only tang,nexys   # a subset (no page)
    yosys: $YOSYS, else ~/oss-cad-suite/bin/yosys, else yosys on PATH.

Last reviewed: 30-SEP-2026
Ronny Hansen
"""

import argparse
import hashlib
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
VROOT = os.path.dirname(HERE)                       # Verilog/
HARNESS = os.path.join(HERE, "hierarchy_harness.tcl")
PAGE = os.path.join(VROOT, "HIERARCHY.md")
INDEX = os.path.join(VROOT, "MODULES.md")

NAV_BEGIN = "<!-- HIERARCHY-NAV:BEGIN - written by Verilog/tests/gen_hierarchy.py, do not edit -->"
NAV_END = "<!-- HIERARCHY-NAV:END -->"
GENERATED_MARK = "Generated by `Verilog/tests/module_doc.py`"

# Paths below Verilog/ that belong to somebody else's framework. Files there
# are not read; their modules become vendor leaves.
FRAMEWORK_PREFIXES = ("fpga/mister/sys/", "fpga/mega65/m2m/")

# ---------------------------------------------------------------------------
# The tops. `short` is the word used in the "Used in" lines of the doc pages.
# Order matters: the first top a module appears in gives its "Where it sits"
# path, and the first place a sub-tree appears on the page is where it is
# drawn in full.
# ---------------------------------------------------------------------------
TOPS = [
    dict(key="sim", title="Simulation (Verilator)", short="Simulation",
         kind="make-verilator", dir="runSim",
         build="`Verilog/runSim/Makefile`, default settings "
               "(`make compile`: USE_LATCHES=0, VERILOG_TAPE=1, SD_STORAGE=1, CACHE=1)"),
    dict(key="tang", title="Tang Nano 20K", short="Tang",
         kind="make-yosys", dir="fpga/tang-nano-20k",
         build="`Verilog/fpga/tang-nano-20k/Makefile` (the OSS yosys flow, "
               "default VARIANT=slow, CACHE=0); its file list is "
               "`nd120_tang20k.gprj`, the same list the Gowin build reads"),
    dict(key="nexys", title="Nexys 4 DDR", short="Nexys",
         kind="vivado", script="fpga/nexys4ddr/build.tcl", args=[],
         build="`Verilog/fpga/nexys4ddr/build.tcl`, default arguments"),
    dict(key="mister", title="MiSTer", short="MiSTer",
         kind="quartus", script="fpga/mister/nd120.qsf", top="emu",
         # written by the framework's sys/build_id.tcl (the qsf's
         # PRE_FLOW_SCRIPT_FILE) before every Quartus run; nd120.sv
         # `includes it. The date only feeds the OSD version string.
         generated={"build_id.v": '`define BUILD_DATE "000000"'},
         # nd120.sv passes unpacked arrays (sd_lba[VDNUM]) to the
         # framework's hps_io; yosys' own reader stops on that
         # ("Insufficient number of array indices", yosys 0.66), so the
         # .sv goes through the slang plugin. The .v files do not.
         frontend="slang",
         build="`Verilog/fpga/mister/nd120.qsf` (which sources `files.qip`). "
               "The Quartus top is the framework's `sys_top`; the tree starts "
               "at the core's `emu` below it"),
    dict(key="mega65-r6", title="MEGA65 R4 R5 R6", short="MEGA65 R6",
         kind="vivado", script="fpga/mega65/build.tcl", args=["board=r6"],
         top="nd120_mega65_machine",
         build="`Verilog/fpga/mega65/build.tcl board=r6`. R4 and R5 build the "
               "same Verilog with the same defines (only the VHDL framework top "
               "differs). The Vivado top is the framework's `mega65_r6`; the "
               "tree starts at `nd120_mega65_machine`, which the VHDL "
               "`CORE/vhdl/main.vhd` instantiates as `i_machine`"),
    dict(key="mega65-r3", title="MEGA65 R3", short="MEGA65 R3",
         kind="vivado", script="fpga/mega65/build.tcl", args=["board=r3"],
         top="nd120_mega65_machine",
         build="`Verilog/fpga/mega65/build.tcl board=r3` (HyperRAM instead of "
               "SDRAM). The tree starts at `nd120_mega65_machine`, below the "
               "VHDL framework"),
    dict(key="qmtech", title="QMTECH XC7A35T", short="QMTECH",
         kind="vivado", script="fpga/qmtech-a35t/build.tcl", args=[],
         build="`Verilog/fpga/qmtech-a35t/build.tcl`, default arguments"),
    dict(key="basys3", title="Basys3", short="Basys3",
         kind="project", script="fpga/basys3/vivado_build.tcl",
         args=["full_synth", "skip_program"],
         build="`Verilog/fpga/basys3/vivado_build.tcl` with `full_synth`. Its "
               "file list is the Vivado project (.xpr) the script opens, which "
               "is kept OUTSIDE the repository, plus the files the script adds"),
    dict(key="cmod", title="Cmod A7-35T", short="Cmod",
         kind="vivado", script="fpga/cmod-a7-35t/build.tcl", args=[],
         build="`Verilog/fpga/cmod-a7-35t/build.tcl`, default arguments"),
]


# ---------------------------------------------------------------------------
# small helpers
# ---------------------------------------------------------------------------
def rel_v(path):
    """Path relative to Verilog/ with forward slashes, or None when the file
    is outside Verilog/. Everything written to a committed file goes through
    here: no machine path ever reaches the page."""
    ap = os.path.abspath(path)
    r = os.path.relpath(ap, VROOT).replace(os.sep, "/")
    if r.startswith("../"):
        return None
    return r


def host_to_local(p):
    """A path a build script wrote for Windows (E:/Dev/.../Verilog/X) is mapped
    onto THIS checkout by the part after /Verilog/. Other paths come back as
    they are."""
    if re.match(r"^[A-Za-z]:[/\\]", p):
        q = p.replace("\\", "/")
        i = q.rfind("/Verilog/")
        if i >= 0:
            return os.path.join(VROOT, q[i + len("/Verilog/"):])
        m = re.match(r"^([A-Za-z]):/(.*)$", q)
        return "/mnt/%s/%s" % (m.group(1).lower(), m.group(2))
    return p


def is_vendor_file(rel):
    """A file the vendor tools generated (Gowin PLL, Xilinx MIG, a Quartus
    wizard file with its .qip beside it). gen_module_docs.py gives these no
    doc page for the same reason."""
    if not rel:
        return False
    fn = os.path.basename(rel)
    if fn.startswith(("gowin_", "mig_7series_")):
        return True
    return os.path.exists(os.path.join(VROOT, os.path.splitext(rel)[0] + ".qip"))


def is_framework(path):
    r = rel_v(path)
    return r is not None and r.startswith(FRAMEWORK_PREFIXES)


def find_tool(env, names, extra):
    p = os.environ.get(env)
    if p:
        return p
    for x in extra:
        x = os.path.expanduser(x)
        if os.path.exists(x):
            return x
    for n in names:
        w = shutil.which(n)
        if w:
            return w
    return None


def yosys_version(yosys):
    out = subprocess.run([yosys, "-V"], capture_output=True, text=True).stdout
    m = re.search(r"Yosys (\S+)", out)
    return m.group(1) if m else out.strip()


# ---------------------------------------------------------------------------
# reading each top's build
# ---------------------------------------------------------------------------
class Spec:
    """What one top's build hands to synthesis."""
    def __init__(self):
        self.files = []       # (absolute path, is_systemverilog), in order
        self.defines = []     # "NAME" or "NAME=VALUE"
        self.incdirs = []     # absolute
        self.libdirs = []     # absolute; modules found by file name (Verilator -I)
        self.top = None
        self.notes = []       # plain sentences for the page
        self.skipped = []     # framework files not read
        self.error = None     # the build could not be read at all
        self.frontend = "verilog"   # or "slang" for the .sv files
        self.board_dir = None       # folder of the build, for vendor headers
        self.bbox_src = {}          # black-boxed module -> its real file
        self.bbox_kind = {}         # black-boxed module -> "sim" or "vendor"


def make_vars(mdir, names):
    """Ask make itself for the value of some variables in a Makefile, so the
    lists are exactly what that Makefile computes (defaults included)."""
    # $(info) prints the value as make holds it. A shell printf would not:
    # the runSim defines carry quotes ('"...img"') the shell would eat.
    cmd = ["make", "-s", "--no-print-directory", "-C", mdir,
           "--eval", "hier-print-%: ; @: $(info $($*))"]
    cmd += ["hier-print-" + n for n in names]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("make failed in %s: %s" % (rel_v(mdir), r.stderr.strip()[-300:]))
    lines = r.stdout.split("\n")
    return dict(zip(names, lines))


def spec_make_verilator(t):
    s = Spec()
    mdir = os.path.join(VROOT, t["dir"])
    v = make_vars(mdir, ["VERILATOR_FLAGS", "VERILATOR_DIRS", "SDFAT_VFILES"])
    toks = shlex.split(v["VERILATOR_FLAGS"])
    i = 0
    while i < len(toks):
        a = toks[i]
        if a.startswith("-D"):
            s.defines.append(a[2:])
        elif a == "--top-module":
            i += 1
            s.top = toks[i]
        elif a.endswith((".v", ".sv")):
            s.files.append((os.path.normpath(os.path.join(mdir, a)), a.endswith(".sv")))
        i += 1
    for a in shlex.split(v["VERILATOR_DIRS"]):
        if a.startswith("-I"):
            d = os.path.normpath(os.path.join(mdir, a[2:]))
            s.incdirs.append(d)
            s.libdirs.append(d)
    vt = shlex.split(v["SDFAT_VFILES"])
    for i, a in enumerate(vt):
        if a == "-v" and i + 1 < len(vt):
            s.files.append((os.path.normpath(os.path.join(mdir, vt[i + 1])), False))
    if s.top is None and s.files:
        # Verilator's top is the one module of the file on its command line
        with open(s.files[0][0], encoding="utf-8", errors="replace") as fh:
            m = re.search(r"^\s*module\s+(\w+)", fh.read(), re.M)
        s.top = m.group(1) if m else None
    return s


def spec_make_yosys(t):
    s = Spec()
    mdir = os.path.join(VROOT, t["dir"])
    v = make_vars(mdir, ["TOP", "INCS", "VDEFS", "SRCS"])
    s.top = v["TOP"].strip()
    for a in shlex.split(v["INCS"]):
        if a.startswith("-I"):
            s.incdirs.append(os.path.normpath(os.path.join(mdir, a[2:])))
    for a in shlex.split(v["VDEFS"]):
        if a.startswith("-D"):
            s.defines.append(a[2:])
    for a in shlex.split(v["SRCS"]):
        s.files.append((os.path.normpath(os.path.join(mdir, a)), a.endswith(".sv")))
    return s


def run_harness(tclsh, mode, script, args):
    cmd = [tclsh, HARNESS, mode, script] + list(args)
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    items = []
    for ln in r.stdout.splitlines():
        if ln.startswith("HIER|"):
            items.append(ln.split("|", 2)[1:])
    return items


def read_xpr_sources(xpr):
    """Design sources of a Vivado project: every <File> in fileset sources_1
    that Vivado has not disabled (AutoDisabled / IsEnabled=0 are left out,
    as Vivado leaves them out of the compile)."""
    out = []
    root = ET.parse(xpr).getroot()
    for fs in root.iter("FileSet"):
        if fs.get("Name") != "sources_1":
            continue
        for f in fs.findall("File"):
            path = f.get("Path", "")
            disabled = False
            for a in f.iter("Attr"):
                if a.get("Name") == "AutoDisabled" and a.get("Val") == "1":
                    disabled = True
                if a.get("Name") == "IsEnabled" and a.get("Val") == "0":
                    disabled = True
            if disabled or not path.endswith((".v", ".sv")):
                continue
            out.append((path, path.endswith(".sv")))
    return out


def spec_tcl(t, tclsh):
    s = Spec()
    script = os.path.join(VROOT, t["script"])
    mode = {"vivado": "vivado", "project": "project", "quartus": "quartus"}[t["kind"]]
    items = run_harness(tclsh, mode, script, t.get("args", []))
    stopped = False
    for kind, rest in items:
        if kind == "FILE":
            sv, p = rest.split("|", 1)
            s.files.append((host_to_local(p), sv == "1"))
        elif kind == "DEFINE":
            s.defines.append(rest)
        elif kind == "INCDIR":
            s.incdirs.append(host_to_local(rest))
        elif kind == "TOP":
            s.top = rest
        elif kind == "PROJECT":
            if os.path.exists(rest):
                # the project's own list goes first, then what the script added
                s.files = [(host_to_local(p), sv) for p, sv in read_xpr_sources(rest)] + s.files
                s.notes.append("File list read from the Vivado project the script opens "
                               "(kept outside the repository), plus the files the script adds.")
            else:
                s.error = ("the file list lives in a Vivado project (.xpr) outside the "
                           "repository, at the path set in `vivado_build.tcl`, and that "
                           "file is not on this machine")
        elif kind == "SKIP":
            s.skipped.append(rest)
        elif kind == "STOP":
            stopped = True
        elif kind == "NOTE" and rest.startswith("build script failed"):
            if not stopped:
                s.error = "the build script stopped before synthesis: " + clean_msg(rest)
    if not stopped and s.error is None:
        s.error = "the build script never reached synthesis"
    if t.get("top"):
        s.top = t["top"]
    return s


def clean_msg(msg):
    """Turn machine paths in a message into Verilog/-relative ones."""
    def repl(m):
        r = rel_v(m.group(0))
        return r if r is not None else os.path.basename(m.group(0))
    return re.sub(r"/(?:mnt|home|tmp)/[^\s:'\"`]+", repl, msg)


def finish_spec(s):
    """Common clean-up: drop repeats, map the generated banner ROM onto the
    committed one, set framework files aside, note missing files."""
    seen = set()
    files = []
    for p, sv in s.files:
        p = os.path.normpath(p)
        if p in seen:
            continue
        seen.add(p)
        if is_framework(p):
            s.skipped.append(rel_v(p))
            continue
        if not os.path.exists(p):
            # term_banner_rom.v is regenerated per build into a build/ folder
            # with the git hash in it; every build falls back to the committed
            # copy when it cannot generate one, and the module is the same.
            fb = os.path.join(VROOT, "Terminals", "rtl", os.path.basename(p))
            if os.path.basename(p) == "term_banner_rom.v" and os.path.exists(fb):
                s.notes.append("`term_banner_rom.v` is generated per build into a "
                               "`build/` folder; the committed copy in "
                               "`Terminals/rtl/` was read in its place (same module).")
                if fb not in seen:
                    seen.add(fb)
                    files.append((fb, sv))
                continue
            r = rel_v(p)
            s.notes.append("Listed by the build but missing on disk, not read: `%s`."
                           % (r if r else os.path.basename(p)))
            continue
        files.append((p, sv))
    s.files = files
    s.incdirs = [d for i, d in enumerate(s.incdirs) if d not in s.incdirs[:i]]
    s.defines = [d for i, d in enumerate(s.defines) if d not in s.defines[:i]]
    return s


# ---------------------------------------------------------------------------
# yosys
# ---------------------------------------------------------------------------
MEMFILE_RE = re.compile(r'"([A-Za-z0-9_.-]+\.(?:hex|mem))"')


def stand_ins(spec, workdir):
    """Empty files for every ROM/RAM init file name the sources mention (see
    the header: the tree does not depend on their contents)."""
    names = set()
    paths = [p for p, _ in spec.files]
    for d in spec.libdirs:
        try:
            paths += [os.path.join(d, f) for f in os.listdir(d) if f.endswith((".v", ".sv"))]
        except OSError:
            pass
    for p in paths:
        try:
            with open(p, encoding="utf-8", errors="replace") as fh:
                names.update(MEMFILE_RE.findall(fh.read()))
        except OSError:
            pass
    for n in names:
        open(os.path.join(workdir, n), "w").close()
    return len(names)


def define_arg(d):
    # yosys splits a script line on blanks and keeps quotes inside a word as
    # they are, so -DNAME="text" reaches the preprocessor as a string
    # (measured with yosys 0.66). A value with a blank in it cannot be passed
    # this way; no build here has one, and one would fail loudly.
    if " " in d:
        raise RuntimeError("define with a blank in it: %s" % d)
    return "-D" + d


MODULE_DECL_RE = re.compile(r"^\s*module\s+([A-Za-z_]\w*)", re.M)
# an instance statement: "<type> [#(...)] <name> (" at the start of a line
INST_RE = re.compile(r"^\s*([A-Za-z_]\w*)\s*(?:#\s*\(|[A-Za-z_]\w*\s*\()", re.M)
NOT_TYPES = {"module", "task", "function", "if", "for", "while", "case", "assign",
             "always", "initial", "begin", "end", "else", "wire", "reg", "logic",
             "input", "output", "inout", "genvar", "generate", "localparam",
             "parameter", "return", "repeat", "forever", "integer", "assert",
             "endcase", "endfunction", "endtask", "endgenerate", "endmodule",
             "default", "casez", "casex", "posedge", "negedge", "fork", "join",
             "disable", "wait", "force", "release", "deassign", "real", "time",
             "tri", "supply0", "supply1", "wand", "wor", "signed", "unsigned",
             "always_ff", "always_comb", "always_latch", "unique", "priority",
             "typedef", "struct", "enum", "bit", "byte", "int", "import",
             # Verilog's built-in gate primitives - not modules
             "and", "or", "not", "nand", "nor", "xor", "xnor", "buf",
             "bufif0", "bufif1", "notif0", "notif1", "pullup", "pulldown"}


def modules_in_file(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return MODULE_DECL_RE.findall(fh.read())
    except OSError:
        return []


def instantiated(path):
    """Module type names a file instantiates (a pattern match, used ONLY to
    find which vendor headers slang needs; the tree itself comes from yosys)."""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            s = fh.read()
    except OSError:
        return []
    s = re.sub(r"/\*.*?\*/", " ", s, flags=re.S)
    s = re.sub(r"//[^\n]*", "", s)
    out = []
    for n in INST_RE.findall(s):
        if n not in NOT_TYPES and n not in out:
            out.append(n)
    return out


def board_module_files(board_dir):
    """module name -> file, for every .v/.sv under a board folder (framework
    included - this is where the vendor headers come from)."""
    out = {}
    if not board_dir or not os.path.isdir(board_dir):
        return out
    for dirpath, dirnames, filenames in os.walk(board_dir):
        dirnames[:] = [d for d in dirnames if d not in ("build", "sim", ".git")]
        for f in sorted(filenames):
            if f.endswith((".v", ".sv")) and not f.endswith("_tb.v"):
                p = os.path.join(dirpath, f)
                for n in modules_in_file(p):
                    out.setdefault(n, p)
    return out


def _strip_comments(s):
    s = re.sub(r"/\*.*?\*/", " ", s, flags=re.S)
    return re.sub(r"//[^\n]*", "", s)


def _balanced(s, i):
    """Index just past the bracket that closes the '(' at s[i], or None.
    Strings are skipped, so a '(' inside "..." does not count."""
    depth = 0
    while i < len(s):
        c = s[i]
        if c == '"':
            i = s.index('"', i + 1)
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return None


def _top_level_dots(text):
    """.name( at bracket depth 1 of a (...) list: the names in it."""
    out, depth = [], 0
    for m in re.finditer(r'"[^"]*"|\(|\)|\.([A-Za-z_]\w*)\s*\(', text):
        tok = m.group(0)
        if tok.startswith('"'):
            continue
        if m.group(1):
            if depth == 1:
                out.append(m.group(1))
            depth += 1
        elif tok == "(":
            depth += 1
        else:
            depth -= 1
    return out


def includes_of(path):
    """The `include lines of a file, so a header copied out of it still finds
    the macros its parameter defaults use."""
    if not path:
        return ""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            s = _strip_comments(fh.read())
    except OSError:
        return ""
    return "\n".join(re.findall(r'^\s*`include\s+"[^"]+"', s, re.M))


def usage_stub(path, name):
    """(name, header) for a module that has no source: every parameter and
    port the first instance of it names, ports all as wide inputs. Only for
    vendor primitives, which are leaves - nothing inside them is drawn."""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            s = _strip_comments(fh.read())
    except OSError:
        return None
    m = re.search(r"\b%s\s*(#\s*\()?" % re.escape(name), s)
    if not m:
        return None
    params = []
    i = m.end()
    if m.group(1):
        j = _balanced(s, m.end() - 1)
        params = _top_level_dots(s[m.end() - 1:j])
        i = j
    k = s.index("(", i)
    ports = _top_level_dots(s[k:_balanced(s, k)])
    ptxt = ""
    if params:
        ptxt = " #(%s)" % ", ".join("parameter %s = 0" % p for p in params)
    return name, "module %s%s (%s);" % (name, ptxt,
                                        ", ".join("input [1023:0] %s" % p for p in ports))


def module_header(path, want=None):
    """(name, 'module name #(...) (...);') of the first module in a file
    (or of the module called `want`),
    comments removed, or None. Parameter and port lists are found by
    counting brackets, so a default like "fat16.img" or a width [31:0] does
    not end them early."""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            s = fh.read()
    except OSError:
        return None
    s = re.sub(r"/\*.*?\*/", " ", s, flags=re.S)
    s = re.sub(r"//[^\n]*", "", s)
    m = None
    for mm in re.finditer(r"\bmodule\s+([A-Za-z_]\w*)", s):
        if want is None or mm.group(1) == want:
            m = mm
            break
    if not m:
        return None
    i = m.end()

    def skip_parens(i):
        depth = 0
        while i < len(s):
            c = s[i]
            if c == '"':
                i = s.index('"', i + 1)
            elif c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    return i + 1
            i += 1
        return None
    j = i
    while s[j].isspace():
        j += 1
    if s[j] == "#":
        j = skip_parens(s.index("(", j))
    j = skip_parens(s.index("(", j))
    if j is None:
        return None
    # SystemVerilog lets the port list use a localparam declared further
    # down (MiSTer hps_io: [VD:0] with "localparam VD = VDNUM-1;" in the
    # body), so the body's localparams come along with the header
    end = s.find("endmodule", j)
    body = s[j:end if end >= 0 else len(s)]
    # Only the localparams the header itself names, and each name once: a
    # body can declare one twice in two `ifdef branches (ND120_CORE's
    # DEV_CLK_HZ), and the header never needs those.
    header = s[m.start():j]
    lps, seen = [], set()
    for lp in re.findall(r"\blocalparam\b[^;]*;", body):
        nm = re.match(r"localparam\b(?:\s+(?:integer|real|bit|logic|int))?"
                      r"(?:\s*\[[^\]]*\])?\s*([A-Za-z_]\w*)", lp)
        if nm and nm.group(1) not in seen and re.search(r"\b%s\b" % nm.group(1), header):
            seen.add(nm.group(1))
            lps.append(lp)
    return m.group(1), header + ";\n" + "\n".join(lps)


def run_yosys(yosys, spec, workdir):
    """Elaborate one top. Returns (rtlil text, None) or (None, error)."""
    lines = []
    for d in spec.incdirs:
        lines.append("verilog_defaults -add -I%s" % d)
    for d in spec.defines:
        lines.append("verilog_defaults -add %s" % define_arg(d))
    # -defer: nothing is elaborated at read time; hierarchy then elaborates
    # only what the top really instantiates, with the real parameters.
    plain = [p for p, sv in spec.files if not sv]
    sv = [p for p, sv in spec.files if sv]
    # Simulation models in a sim/ folder that the build finds by file name
    # (runSim: sd_card_model.v, nds_mem_model.v) are behavioural test models
    # with $random, file I/O and delays - not something a synthesis tool can
    # elaborate. They contain no module instances, so reading them as black
    # boxes (ports only) loses nothing from the tree; the page marks them.
    # yosys cannot even read them with -lib (it still walks the functions and
    # stops on $random), so the black box is the module's own header - its
    # parameter and port list, copied from the file - with an empty body.
    bbox_src = {}
    for d in spec.libdirs:
        if os.path.basename(d) != "sim":
            continue
        for f in sorted(os.listdir(d)):
            if not f.endswith(".v") or f.endswith("_tb.v"):
                continue
            got = module_header(os.path.join(d, f))
            if got is None:
                continue
            name, header = got
            stub = os.path.join(workdir, "bbox_" + f)
            with open(stub, "w") as fh:
                fh.write("(* blackbox *)\n%s\nendmodule\n" % header)
            lines.append("read_verilog -lib %s" % stub)
            bbox_src[name] = os.path.join(d, f)
            spec.bbox_kind[name] = "sim"
            note = ("The simulation models in `%s/` are behavioural test models "
                    "yosys cannot elaborate ($random, file I/O); they contain no "
                    "module instances and were read as black boxes (their own "
                    "port list, empty body)." % rel_v(d))
            if note not in spec.notes:
                spec.notes.append(note)
    spec.bbox_src = bbox_src
    if spec.frontend == "slang":
        # The .sv top goes through the slang plugin (see TOPS for why). slang
        # elaborates only that one file: every module it instantiates is
        # handed to it as an EMPTY black box made from that module's own
        # header (parameters and ports, copied from its file), so slang
        # leaves each one as an instance with its real parameter values.
        # Measured with yosys 0.66 + slang: letting slang elaborate the
        # whole CPU instead stops on the F714 flip-flop ("multiple
        # asynchronous loads unsupported"), and modules read by yosys first
        # are not visible to slang with their parameters.
        #   Then the black boxes of OUR modules are deleted, the real files
        # are read by yosys as for every other top, and `hierarchy`
        # elaborates everything below the slang-built top. Framework and
        # vendor modules (MiSTer: hps_io from sys/, the Quartus pll and
        # altera_pll) stay black boxes: they are leaves.
        opts = " ".join(["-I%s" % d for d in spec.incdirs]
                        + [define_arg(d) for d in spec.defines])
        lines.insert(0, "plugin -i slang")
        ours = {}
        for p, _ in spec.files:
            for n in modules_in_file(p):
                ours.setdefault(n, p)
        defs = board_module_files(spec.board_dir)
        stubs, delete = [], []
        for p in sv:
            for name in instantiated(p):
                if name in ours and not ours[name].endswith(".sv"):
                    got = module_header(ours[name], name)
                    delete.append(name)
                elif name in defs and name not in ours:
                    got = module_header(defs[name], name)
                    bbox_src[name] = defs[name]
                    spec.bbox_kind[name] = "vendor"
                elif name not in ours:
                    # a vendor primitive with no source anywhere in the tree
                    # (Quartus altera_pll): a port-only stand-in made from
                    # the way it is instantiated
                    got = usage_stub(p, name)
                    spec.bbox_kind[name] = "vendor"
                else:
                    continue
                if got is None:
                    continue
                stub = os.path.join(workdir, "stub_%s.sv" % name)
                with open(stub, "w") as fh:
                    fh.write("%s\n%s\nendmodule\n"
                             % (includes_of(ours.get(name) or defs.get(name)), got[1]))
                stubs.append(stub)
        spec.notes.append(
            "The SystemVerilog top was read by the yosys slang plugin (yosys' own "
            "reader cannot pass the unpacked arrays in it to `hps_io`). The modules "
            "it instantiates were given to slang as black boxes made from their "
            "own headers, then replaced by the real files, which yosys elaborated "
            "as for every other top. Framework and vendor parts stay black boxes.")
        # --allow-use-before-declare: nd120.sv uses `status` above its
        # declaration, which Quartus accepts and slang by default does not
        lines.append("read_slang --empty-blackboxes --allow-use-before-declare "
                     "--top %s %s %s" % (spec.top, opts, " ".join(sv + stubs)))
        if delete:
            # "=" makes the selection include black boxes, which a plain
            # name does not match
            lines.append("delete %s" % " ".join("=" + d for d in delete))
        if plain:
            lines.append("read_verilog -defer " + " ".join(plain))
    else:
        if plain:
            lines.append("read_verilog -defer " + " ".join(plain))
        if sv:
            lines.append("read_verilog -defer -sv " + " ".join(sv))
    lib = " ".join("-libdir %s" % d for d in spec.libdirs)
    lines.append("hierarchy %s -top %s" % (lib, spec.top))
    il = os.path.join(workdir, "design.il")
    lines.append("write_rtlil %s" % il)
    ys = os.path.join(workdir, "run.ys")
    with open(ys, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    log = os.path.join(workdir, "yosys.log")
    r = subprocess.run([yosys, "-q", "-l", log, "-s", ys], cwd=workdir,
                       capture_output=True, text=True, timeout=1800)
    if r.returncode != 0 or not os.path.exists(il):
        text = (r.stderr or "") + (r.stdout or "")
        try:
            text += open(log, encoding="utf-8", errors="replace").read()
        except OSError:
            pass
        # slang reports "file:line:col: error: ..." before yosys' own
        # one-line "ERROR: Compilation failed"; the first is the useful one
        errs = [ln.strip() for ln in text.splitlines() if ": error: " in ln]
        errs += [ln.strip() for ln in text.splitlines() if "ERROR" in ln]
        msg = errs[0] if errs else "yosys exit %d" % r.returncode
        # slang writes paths relative to the folder yosys ran in
        msg = re.sub(r"(?:\.\./)+[^\s:]*",
                     lambda m: os.path.normpath(os.path.join(workdir, m.group(0))), msg)
        return None, clean_msg(msg)
    with open(il, encoding="utf-8", errors="replace") as fh:
        return fh.read(), None


def unescape(name):
    return name[1:] if name.startswith("\\") else name


def base_of(mod):
    """$paramod\\CGA_ALU\\P=1 or $paramod$<hash>\\CGA_ALU -> CGA_ALU."""
    if mod.startswith("$paramod"):
        return mod[len("$paramod"):].split("\\")[1]
    # slang names a specialised module <name>$<instance path>
    # (hps_io$emu.hps_io); no module of ours has a $ in its name
    return unescape(mod).split("$", 1)[0]


def parse_rtlil(text, workdir):
    """{module: {"base", "src", "cells": [(instance, type)]}} - module
    instances only; yosys' own internal cells ($and, $dff, ...) are left out."""
    mods = {}
    cur = None
    pending_src = None
    pending_bbox = False
    for ln in text.splitlines():
        s = ln.strip()
        if s.startswith("attribute \\src "):
            pending_src = s[len("attribute \\src "):].strip().strip('"')
            continue
        if s.startswith("attribute \\blackbox "):
            pending_bbox = True
            continue
        if s.startswith("module "):
            name = s.split(None, 1)[1]
            src = (pending_src or "").rsplit(":", 1)[0] if pending_src else ""
            if src and not os.path.isabs(src):
                # slang writes the path relative to the folder yosys ran in
                src = os.path.normpath(os.path.join(workdir, src))
            cur = mods[name] = {"base": base_of(name), "src": src, "cells": [],
                                "bbox": pending_bbox}
        elif s.startswith("cell ") and cur is not None:
            parts = s.split()
            ctype, inst = parts[1], parts[2]
            if ctype.startswith("$") and not ctype.startswith("$paramod"):
                pass                     # a yosys-internal cell, not a module
            else:
                cur["cells"].append((unescape(inst), ctype))
        elif s == "end" and cur is not None and ln.startswith("end"):
            cur = None
        if not s.startswith("attribute"):
            pending_src = None
            pending_bbox = False
    return mods


# ---------------------------------------------------------------------------
# the graph of one top
# ---------------------------------------------------------------------------
class Tree:
    def __init__(self, t, spec, mods):
        self.t = t
        self.spec = spec
        self.mods = mods                 # variant name -> info
        self.top = None
        for name, m in mods.items():
            if m["base"] == spec.top and name.lstrip("\\") == spec.top:
                self.top = name
        if self.top is None:
            for name, m in mods.items():
                if m["base"] == spec.top:
                    self.top = name
        self.sig = {}
        self._depth = {}

    def src_rel(self, variant):
        s = self.mods[variant]["src"]
        return rel_v(s) if s else None

    def is_mod(self, ctype):
        return ctype in self.mods

    def signature(self, v):
        if v in self.sig:
            return self.sig[v]
        h = hashlib.sha1()
        h.update(self.mods[v]["base"].encode())
        h.update(("@" + (self.src_rel(v) or "")).encode())
        for inst, ctype in self.mods[v]["cells"]:
            child = self.signature(ctype) if self.is_mod(ctype) else "vendor:" + base_of(ctype)
            h.update(("|%s=%s" % (inst, child)).encode())
        self.sig[v] = h.hexdigest()[:16]
        return self.sig[v]

    def depth(self, v):
        if v in self._depth:
            return self._depth[v]
        d = 1
        for _, ctype in self.mods[v]["cells"]:
            if self.is_mod(ctype):
                d = max(d, 1 + self.depth(ctype))
        self._depth[v] = d
        return d

    def reachable(self):
        seen = set()
        stack = [self.top]
        while stack:
            v = stack.pop()
            if v in seen:
                continue
            seen.add(v)
            for _, ctype in self.mods[v]["cells"]:
                if self.is_mod(ctype):
                    stack.append(ctype)
        return seen

    def counts(self):
        """(our distinct modules, vendor distinct parts, module instances)"""
        ours, vendor = set(), set()
        inst_count = {}

        def n_inst(v):
            if v in inst_count:
                return inst_count[v]
            n = 0
            for _, ctype in self.mods[v]["cells"]:
                n += 1
                if self.is_mod(ctype):
                    n += n_inst(ctype)
            inst_count[v] = n
            return n
        for v in self.reachable():
            ours.add((self.mods[v]["base"], self.src_rel(v)))
            for _, ctype in self.mods[v]["cells"]:
                if not self.is_mod(ctype):
                    vendor.add(base_of(ctype))
        return len(ours), len(vendor), 1 + n_inst(self.top), sorted(vendor)


# ---------------------------------------------------------------------------
# doc lookup
# ---------------------------------------------------------------------------
def all_docs():
    """(module, source relative to Verilog/) -> doc path, for every doc that
    module_doc.py wrote. Also module -> [doc paths] for the fallback."""
    by_key, by_name = {}, {}
    for dirpath, dirnames, filenames in os.walk(VROOT):
        if dirpath != VROOT and os.path.exists(os.path.join(dirpath, ".git")):
            dirnames[:] = []
            continue
        dirnames[:] = [d for d in dirnames if d not in (".git", "obj_dir", "build")]
        if os.path.basename(dirpath) != "doc":
            continue
        for fn in filenames:
            if not fn.endswith(".md"):
                continue
            p = os.path.join(dirpath, fn)
            try:
                with open(p, encoding="utf-8", errors="replace") as fh:
                    head = fh.read(4000)
            except OSError:
                continue
            if GENERATED_MARK not in head or not head.startswith("# "):
                continue
            name = head.split("\n", 1)[0][2:].strip()
            m = re.search(r"^Source: `Verilog/([^`]+)`", head, re.M)
            src = m.group(1) if m else ""
            by_key[(name, src)] = p
            by_name.setdefault(name, []).append(p)
    return by_key, by_name


class Docs:
    def __init__(self):
        self.by_key, self.by_name = all_docs()

    def doc_for(self, base, src_rel):
        p = self.by_key.get((base, src_rel or ""))
        if p:
            return p
        # the doc sits next to the source: <folder>/doc/<module>.md
        if src_rel:
            cand = os.path.join(VROOT, os.path.dirname(src_rel), "doc", base + ".md")
            if os.path.exists(cand):
                return cand
        c = self.by_name.get(base, [])
        return c[0] if len(c) == 1 else None


def link_from(src_file, target):
    return os.path.relpath(target, os.path.dirname(src_file)).replace(os.sep, "/")


def anchor(title):
    # GitHub and Jekyll (kramdown) agree on this for headings made only of
    # letters, digits, spaces and hyphens: lower case, spaces to hyphens.
    a = title.lower().strip()
    a = re.sub(r"[^a-z0-9 -]", "", a)
    return a.replace(" ", "-")


# ---------------------------------------------------------------------------
# the page
# ---------------------------------------------------------------------------
LEAF_NAMES_SHOWN = 12


class PageWriter:
    def __init__(self, docs):
        self.docs = docs
        self.first = {}          # signature -> anchor id of its full drawing
        self.used = set()        # anchor ids something links back to
        self.lines = []          # text, or ("anchor", id) placeholders
        self.n_anchor = 0

    def mlink(self, tree, variant):
        base = tree.mods[variant]["base"]
        kind = tree.spec.bbox_kind.get(base)
        if kind == "vendor":
            return "%s (vendor)" % base
        src = tree.src_rel(variant) or ""
        if kind == "sim":
            # sim/ folders hold test models and get no doc pages
            return "%s (simulation model in `%s/`, read as a black box)" % (
                base, os.path.dirname(src))
        doc = self.docs.doc_for(base, src)
        if doc:
            return "[%s](%s)" % (base, link_from(PAGE, doc))
        if is_vendor_file(src):
            return "%s (vendor IP)" % base
        return "**%s** (no doc page)" % base

    def node(self, tree, variant, inst, indent, path):
        pad = "  " * indent
        sig = tree.signature(variant)
        has_kids = bool(tree.mods[variant]["cells"])
        label = self.mlink(tree, variant)
        itxt = " `%s`" % inst if inst else ""
        if has_kids and sig in self.first:
            aid = self.first[sig]
            self.used.add(aid)
            self.lines.append("%s- %s%s - same as [above](#%s)" % (pad, label, itxt, aid))
            return
        if has_kids:
            self.n_anchor += 1
            aid = "h%d" % self.n_anchor
            self.first[sig] = aid
            self.lines.append((pad, label, itxt, aid))
        else:
            self.lines.append("%s- %s%s" % (pad, label, itxt))
            return
        self.children(tree, variant, indent + 1, path)

    def children(self, tree, variant, indent, path):
        pad = "  " * indent
        cells = tree.mods[variant]["cells"]
        # leaves of one type and one shape go on one line, where the first
        # of them sits; everything else is drawn in source order
        groups = {}
        order = []
        for inst, ctype in cells:
            if tree.is_mod(ctype) and tree.mods[ctype]["cells"]:
                order.append(("node", inst, ctype))
                continue
            key = tree.signature(ctype) if tree.is_mod(ctype) else "vendor:" + base_of(ctype)
            if key not in groups:
                groups[key] = (ctype, [])
                order.append(("group", key, None))
            groups[key][1].append(inst)
        for kind, a, b in order:
            if kind == "node":
                self.node(tree, b, a, indent, path + [a])
                continue
            ctype, insts = groups[a]
            if tree.is_mod(ctype):
                label = self.mlink(tree, ctype)
            else:
                label = "%s (vendor)" % base_of(ctype)
            shown = ", ".join("`%s`" % i for i in insts[:LEAF_NAMES_SHOWN])
            if len(insts) > LEAF_NAMES_SHOWN:
                shown += " and %d more" % (len(insts) - LEAF_NAMES_SHOWN)
            if len(insts) == 1:
                self.lines.append("%s- %s %s" % (pad, label, shown))
            else:
                self.lines.append("%s- %s x%d: %s" % (pad, label, len(insts), shown))

    def text(self):
        out = []
        for ln in self.lines:
            if isinstance(ln, tuple):
                pad, label, itxt, aid = ln
                if aid in self.used:
                    out.append('%s- <a name="%s"></a>%s%s' % (pad, aid, label, itxt))
                else:
                    out.append("%s- %s%s" % (pad, label, itxt))
            else:
                out.append(ln)
        return out


def write_page(results, yver, docs):
    pw = PageWriter(docs)
    out = []
    out.append("# Module hierarchy")
    out.append("")
    out.append("> Generated by `Verilog/tests/gen_hierarchy.py` from a real elaboration "
               "by yosys %s (`hierarchy -top`)." % yver)
    out.append("> Do not edit by hand - run `python3 tests/gen_module_docs.py` from "
               "`Verilog/` (in WSL) to regenerate the module docs, MODULES.md and this page.")
    out.append("")
    out.append("What sits inside what, for every build top. Each top was elaborated "
               "with the file list, defines and include folders its own build uses, so "
               "`ifdef`s, generate blocks and parameters are already applied. Every "
               "module links to its page; the full list is in [MODULES.md](MODULES.md).")
    out.append("")
    out.append("How to read the trees:")
    out.append("")
    out.append("- `name` after a module is the instance name in its parent.")
    out.append("- Modules with nothing inside them that are used several times by one "
               "parent go on one line: `x4` and the instance names.")
    out.append("- A sub-tree is drawn in full the first time it appears on this page. "
               "Later copies that are exactly the same (same modules, same instance "
               "names, all the way down) say \"same as above\" and link to it, also "
               "across boards.")
    out.append("- \"vendor\" marks a part that is not ours and is not followed: FPGA "
               "primitives, PLLs, vendor IP, and the MiSTer and MEGA65 frameworks. "
               "For MiSTer and MEGA65 the tree starts at our top below the framework.")
    out.append("- ROM/RAM init files do not change which instances exist, so yosys was "
               "given empty stand-ins for them.")
    out.append("")
    out.append("| Top | Module | Elaborated | Our modules | Instances | Depth |")
    out.append("|---|---|---|---|---|---|")
    for t, spec, tree, err in results:
        if tree:
            ours, nvend, ninst, _ = tree.counts()
            out.append("| [%s](#%s) | `%s` | yes | %d | %d | %d |"
                       % (t["title"], anchor(t["title"]), spec.top, ours, ninst,
                          tree.depth(tree.top)))
        else:
            out.append("| [%s](#%s) | `%s` | **no** - see below | - | - | - |"
                       % (t["title"], anchor(t["title"]), spec.top or "?"))
    out.append("")
    body = []
    for t, spec, tree, err in results:
        body.append("## %s" % t["title"])
        body.append("")
        body.append("Build: %s." % t["build"])
        body.append("")
        if spec.defines:
            body.append("Defines: " + ", ".join("`%s`" % d for d in spec.defines) + ".")
            body.append("")
        for n in spec.notes:
            body.append(n)
            body.append("")
        if spec.skipped:
            body.append("Not followed (framework): %d file(s)." % len(spec.skipped))
            body.append("")
        if not tree:
            body.append("**Not elaborated:** %s." % err)
            body.append("")
            continue
        ours, nvend, ninst, vend = tree.counts()
        body.append("%d of our modules, %d module instances, %d levels deep. "
                    "Vendor parts: %s."
                    % (ours, ninst, tree.depth(tree.top),
                       ", ".join("`%s`" % v for v in vend) if vend else "none"))
        body.append("")
        # the tree lines go straight into pw.lines; a marker in the body says
        # where they belong, because the "same as above" anchors can only be
        # written once every tree is drawn
        body.append(("tree", len(pw.lines)))
        pw.node(tree, tree.top, None, 0, [])
        body.append(("end", len(pw.lines)))
        body.append("")
    tree_text = pw.text()
    start = 0
    for ln in body:
        if isinstance(ln, tuple):
            if ln[0] == "tree":
                start = ln[1]
            else:
                out.extend(tree_text[start:ln[1]])
            continue
        out.append(ln)
    while out and out[-1] == "":
        out.pop()
    with open(PAGE, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(out) + "\n")


# ---------------------------------------------------------------------------
# the navigation block on each doc
# ---------------------------------------------------------------------------
def nav_data(results):
    """Per (module, source): where it sits (first top), who uses it, what it
    contains - merged over every top that elaborated."""
    info = {}
    for t, spec, tree, err in results:
        if not tree:
            continue
        reach = tree.reachable()
        # shortest instance path from the top to each variant
        path = {tree.top: [(tree.top, None)]}
        queue = [tree.top]
        while queue:
            v = queue.pop(0)
            for inst, ctype in tree.mods[v]["cells"]:
                if tree.is_mod(ctype) and ctype not in path:
                    path[ctype] = path[v] + [(ctype, inst)]
                    queue.append(ctype)
        for v in reach:
            key = (tree.mods[v]["base"], tree.src_rel(v))
            d = info.setdefault(key, {"path": None, "parents": {}, "children": {}, "tops": []})
            if t["short"] not in d["tops"]:
                d["tops"].append(t["short"])
            if d["path"] is None:
                d["path"] = (t["short"], [((tree.mods[x]["base"], tree.src_rel(x)), i)
                                          for x, i in path[v]])
            counts = {}
            for inst, ctype in tree.mods[v]["cells"]:
                ours = tree.is_mod(ctype)
                if ours:
                    cb = tree.mods[ctype]["base"]
                    # framework/vendor black boxes and vendor-generated IP
                    # are listed as "(vendor)", like the unknown cells
                    if (tree.spec.bbox_kind.get(cb) == "vendor"
                            or is_vendor_file(tree.src_rel(ctype))):
                        ours = False
                if ours:
                    ck = (tree.mods[ctype]["base"], tree.src_rel(ctype))
                else:
                    ck = (base_of(ctype), None)
                counts[ck] = counts.get(ck, 0) + 1
                if ours:
                    ckd = info.setdefault(ck, {"path": None, "parents": {}, "children": {}, "tops": []})
                    ckd["parents"].setdefault(key, [])
                    if t["short"] not in ckd["parents"][key]:
                        ckd["parents"][key].append(t["short"])
            for ck, n in counts.items():
                c = d["children"].setdefault(ck, {"n": n, "tops": []})
                if t["short"] not in c["tops"]:
                    c["tops"].append(t["short"])
    return info


def tops_text(tops, all_tops):
    if set(all_tops) <= set(tops):
        return "all tops"
    return ", ".join(tops)


def nav_block(doc, key, d, docs, all_tops):
    def ml(k):
        p = docs.doc_for(k[0], k[1]) if k[1] is not None else None
        if p:
            return "[%s](%s)" % (k[0], link_from(doc, p))
        return "`%s`" % k[0]
    L = [NAV_BEGIN, ""]
    hier = link_from(doc, PAGE)
    idx = link_from(doc, INDEX)
    if d is None:
        L.append("**Hierarchy:** not instantiated by any of the %d build tops "
                 "(elaborated by yosys)." % len(all_tops))
    else:
        top_short, chain = d["path"]
        parts = []
        for k, inst in chain[:-1]:
            parts.append(ml(k))
        parts.append("**%s**" % key[0])
        insts = [i for _, i in chain if i]
        L.append("**Where it sits** (%s): %s" % (top_short, " > ".join(parts)))
        if insts:
            L.append("- instance path: `%s`" % ".".join(insts))
        L.append("")
        if d["parents"]:
            L.append("**Used in:** " + ", ".join(
                "%s (%s)" % (ml(k), tops_text(v, all_tops))
                for k, v in sorted(d["parents"].items(), key=lambda x: x[0][0].lower())))
        else:
            L.append("**Used in:** nothing - this is a top (%s)." % tops_text(d["tops"], all_tops))
        L.append("")
        if d["children"]:
            items = []
            for k, c in sorted(d["children"].items(), key=lambda x: x[0][0].lower()):
                txt = ml(k) if k[1] is not None else "`%s` (vendor)" % k[0]
                if c["n"] > 1:
                    txt += " x%d" % c["n"]
                if not set(d["tops"]) <= set(c["tops"]):
                    txt += " (only on %s)" % ", ".join(c["tops"])
                items.append(txt)
            L.append("**Contains:** " + ", ".join(items))
        else:
            L.append("**Contains:** no other modules.")
    L.append("")
    L.append("[Module hierarchy](%s) - [All modules](%s)" % (hier, idx))
    L.append("")
    L.append(NAV_END)
    return L


def apply_nav(results, docs):
    info = nav_data(results)
    all_tops = [t["short"] for t, spec, tree, err in results if tree]
    n = 0
    for (name, src), doc in sorted(docs.by_key.items()):
        with open(doc, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().split("\n")
        # drop an old block
        if NAV_BEGIN in lines:
            b = lines.index(NAV_BEGIN)
            e = lines.index(NAV_END, b) if NAV_END in lines[b:] else b
            del lines[b:e + 1]
            if b < len(lines) and lines[b] == "":
                del lines[b]
        block = nav_block(doc, (name, src), info.get((name, src)), docs, all_tops)
        # under the title and the "Generated by" note: after the first blank
        # line that follows the note
        at = None
        for i, ln in enumerate(lines):
            if GENERATED_MARK in ln:
                j = i
                while j < len(lines) and lines[j].startswith(">"):
                    j += 1
                at = j + 1 if j < len(lines) and lines[j] == "" else j
                break
        if at is None:
            at = 2
        lines[at:at] = block + [""]
        with open(doc, "w", encoding="utf-8", newline="\n") as fh:
            fh.write("\n".join(lines))
        n += 1
    return n


# ---------------------------------------------------------------------------
class _KeptDir:
    """A work folder that is NOT removed afterwards (HIER_KEEP)."""
    def __init__(self, path):
        self.path = path

    def __enter__(self):
        shutil.rmtree(self.path, ignore_errors=True)
        os.makedirs(self.path)
        return self.path

    def __exit__(self, *exc):
        return False


def build_all(only=None, log=print):
    yosys = find_tool("YOSYS", ["yosys"], ["~/oss-cad-suite/bin/yosys"])
    tclsh = find_tool("TCLSH", ["tclsh", "tclsh8.6"], [])
    if not yosys or not tclsh:
        raise SystemExit("gen_hierarchy: needs yosys and tclsh (run in WSL; "
                         "yosys from ~/oss-cad-suite or $YOSYS)")
    yver = yosys_version(yosys)
    log("yosys %s" % yver)
    results = []
    for t in TOPS:
        if only and t["key"] not in only:
            continue
        t0 = time.time()
        try:
            if t["kind"] == "make-verilator":
                spec = spec_make_verilator(t)
            elif t["kind"] == "make-yosys":
                spec = spec_make_yosys(t)
            else:
                spec = spec_tcl(t, tclsh)
        except Exception as exc:                            # noqa: BLE001
            spec = Spec()
            spec.error = "the build could not be read: %s" % clean_msg(str(exc))
        spec = finish_spec(spec)
        spec.frontend = t.get("frontend", "verilog")
        spec.board_dir = os.path.join(VROOT, os.path.dirname(t.get("script", t.get("dir", "") + "/x")))
        tree, err = None, spec.error
        if err is None and not spec.top:
            err = "the build names no top module"
        if err is None:
            # HIER_KEEP=<folder>: keep each top's yosys script, log and
            # netlist in <folder>/<key> to look at by hand
            keep = os.environ.get("HIER_KEEP")
            if keep:
                wd_ctx = _KeptDir(os.path.join(keep, t["key"]))
            else:
                wd_ctx = tempfile.TemporaryDirectory(prefix="nd120-hier-")
            with wd_ctx as wd:
                stand_ins(spec, wd)
                for name, text in t.get("generated", {}).items():
                    with open(os.path.join(wd, name), "w") as fh:
                        fh.write(text + "\n")
                    spec.notes.append("`%s` is written by the build just before "
                                      "synthesis; a stand-in with the same kind of "
                                      "content was used." % name)
                if t.get("generated"):
                    spec.incdirs.append(wd)
                text, err = run_yosys(yosys, spec, wd)
            if text is not None:
                mods = parse_rtlil(text, wd)
                # a black-boxed simulation model points at its stub in the
                # scratch folder; point it back at the real file
                for m in mods.values():
                    if m["base"] in getattr(spec, "bbox_src", {}):
                        m["src"] = spec.bbox_src[m["base"]]
                tree = Tree(t, spec, mods)
                if tree.top is None:
                    tree, err = None, "yosys did not produce the top `%s`" % spec.top
        results.append((t, spec, tree, err))
        if tree:
            ours, nv, ninst, _ = tree.counts()
            log("  %-10s %-24s OK   %3d modules, %5d instances, depth %d, %d files, %.0f s"
                % (t["key"], spec.top, ours, ninst, tree.depth(tree.top),
                   len(spec.files), time.time() - t0))
        else:
            log("  %-10s %-24s FAIL %s" % (t["key"], spec.top, err))
    return results, yver


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", help="comma list of top keys; prints results only, "
                    "writes nothing (a page with some tops missing would be wrong)")
    args = ap.parse_args(argv)
    only = set(args.only.split(",")) if args.only else None
    results, yver = build_all(only)
    if only:
        return 0
    docs = Docs()
    write_page(results, yver, docs)
    print("wrote %s" % rel_v(PAGE))
    n = apply_nav(results, docs)
    print("navigation block written on %d module docs" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
