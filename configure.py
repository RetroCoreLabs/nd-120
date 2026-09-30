#!/usr/bin/env python3
"""
ND-120 - set up a fresh clone for building, and remember the answers.

    python3 configure.py                     ask for what it cannot find, set up
    py configure.py                          the same, from a Windows shell
    python3 configure.py --non-interactive   take values from --set / the environment
    python3 configure.py --check             print every setting, where it came from,
                                             and what is missing (exit 1 if a
                                             required one is missing)
    python3 configure.py --set NAME=VALUE    change one setting (repeatable;
                                             NAME= with no value removes it)

What it does, in order:
  1. reads the answers it already has - local.mk at the repository root (and,
     once, the old Verilog/fpga/local.mk if that still exists) - and uses them
     as the defaults;
  2. looks for the tools: vivado, gw_sh (Gowin), quartus_sh, oss-cad-suite,
     w64devkit, netlistsvg on PATH and in the usual install folders (from WSL it also
     looks on the Windows drives), plus verilator, iverilog, yosys and python3
     on PATH (those are only reported - the Makefiles take them from PATH);
  3. asks for what it could not find, and for ND120_BUILD_DIR and ND_REPOS;
  4. writes local.mk at the repository root (make syntax, NAME := value);
  5. sets up the clone: `git submodule update --init`, the microcode preload
     images (Code/Microcode/gen_wcs_image.py for the boards, --sim for the
     simulators) and the build folder.

local.mk is machine-local and never committed (.gitignore). Every consumer
reads it: the board Makefiles through paths.mk, the PowerShell scripts through
Verilog/fpga/paths.ps1, the Vivado/Gowin Tcl scripts through
Verilog/fpga/paths.tcl, and the Python and shell helpers through this file
(import configure; configure.setting(NAME)). One rule everywhere: a value set
in the ENVIRONMENT wins over local.mk (and on a make command line,
make NAME=value wins over both).

Python 3 standard library only - the same file runs on Linux, in WSL and in a
native Windows shell. It never runs Vivado, Gowin or Quartus.
"""

import argparse
import glob
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
LOCAL_MK = os.path.join(ROOT, "local.mk")
OLD_LOCAL_MK = os.path.join(ROOT, "Verilog", "fpga", "local.mk")
EXAMPLE_MK = os.path.join(ROOT, "local.mk.example")

IS_WINDOWS = os.name == "nt"


def _is_wsl():
    if IS_WINDOWS or not sys.platform.startswith("linux"):
        return False
    try:
        with open("/proc/version") as f:
            return "microsoft" in f.read().lower()
    except OSError:
        return False


IS_WSL = _is_wsl()

# The fix lines every "missing setting" message ends with. The same words are
# printed by paths.mk (through --require), Verilog/fpga/paths.ps1 and
# Verilog/fpga/paths.tcl - change all four together.
FIX_RUN = "python3 configure.py"
FIX_RUN_WIN = "py configure.py"


# ---------------------------------------------------------------------------
# The settings. kind:
#   builddir  a folder that is created when missing
#   tool      a program file (checked to exist)
#   dir       an existing folder
#   file      an existing file
#   text      free text, not checked
# ask:
#   always    asked on every interactive run (the current value is the default)
#   missing   asked only when nothing was found (Enter skips it)
#   never     only through --set or the environment
# ---------------------------------------------------------------------------
class Setting:
    def __init__(self, name, what, kind, ask, readers, required_for,
                 placeholder, notes=""):
        self.name = name
        self.what = what                  # short, for messages: "the Vivado program"
        self.kind = kind
        self.ask = ask
        self.readers = readers            # who reads it (for --check and local.mk)
        self.required_for = required_for  # "" = never required
        self.placeholder = placeholder    # <folder> / <program> / <file>
        self.notes = notes


SETTINGS = [
    Setting("ND120_BUILD_DIR", "where builds go", "builddir", "always",
            "every board build (Verilog/fpga/<board>/Makefile, build.tcl, the .ps1 wrappers)",
            "every board build - each board writes everything to <this>/<board>/",
            "<folder>",
            "Must be a folder the build tools can reach. A Windows program (Vivado, Gowin) "
            "started from WSL needs it on a Windows drive (/mnt/<drive>/...)."),
    Setting("ND120_VIVADO", "the Vivado program", "tool", "missing",
            "Basys3, Cmod A7, Nexys 4 DDR, QMTECH and MEGA65 builds",
            "the Vivado board builds (basys3, cmod-a7-35t, nexys4ddr, qmtech-a35t, mega65)",
            "<program>",
            "vivado.bat on Windows, vivado on Linux. A Windows Vivado is stored as a Windows "
            "path even when configure runs in WSL."),
    Setting("ND120_VIVADO_LICENSE", "the Vivado licence file list", "text", "never",
            "paths.mk, Verilog/fpga/run_tool.ps1, basys3/vivado_build.ps1, nexys4ddr/build-watch.ps1",
            "", "<licence file>;<another>",
            "Handed to Vivado as XILINXD_LICENSE_FILE when that is not already set."),
    Setting("ND120_GOWIN", "the Gowin gw_sh program", "tool", "missing",
            "tang-nano-20k: make gowin, gowin_build.ps1",
            "the Tang Nano 20K Gowin build (make gowin)", "<program>"),
    Setting("ND120_QUARTUS", "the Quartus bin folder", "dir", "missing",
            "nothing yet (the MiSTer build runs Quartus in Docker)",
            "", "<folder>"),
    Setting("ND120_OSS_CAD_SUITE", "the oss-cad-suite folder", "dir", "missing",
            "tang-nano-20k Makefile (OSS flow, its bin/ goes on PATH), "
            "Verilog/ND-120-Yosys/synh.bat, the BUS-IF gate Windows example",
            "", "<folder>",
            "The install the shell you build from uses: a Linux one for WSL/Linux, "
            "a Windows one for synh.bat."),
    Setting("ND120_NETLISTSVG", "the netlistsvg program", "tool", "missing",
            "Verilog/tests/gen_schematics.py (run by gen_module_docs.py)",
            "", "<program>",
            "Optional: draws the module schematics on the doc pages. Install it OUTSIDE "
            "the repository with npm (npm install netlistsvg in a folder of its own); "
            "the program is <that folder>/node_modules/.bin/netlistsvg."),
    Setting("ND120_W64DEVKIT", "the w64devkit folder", "dir", "never",
            "the BUS-IF gate Windows example (Verilog/ND-BUS-DEVICES/BUS-IF/gate/Makefile)",
            "", "<folder>"),
    Setting("ND_REPOS", "the folder holding the other ND repositories", "dir", "always",
            "Verilog/tests/instruction-verify, Verilog/sim/compare_boot.py",
            "the instruction-verify golden traces and compare_boot.py",
            "<folder>",
            "Optional: the sibling checkouts (ND110Compile, nd120uc, NDDeviceCore, ...)."),
    Setting("ND120_ILA_CSV", "an ILA capture exported as CSV", "file", "never",
            "Verilog/sim/analyze_ila.py, Verilog/sim/compare_boot.py",
            "", "<file>"),
    Setting("ND120_ORACLE_DIR", "where long trace captures are kept", "dir", "never",
            "Tang capture scripts, Verilog/sim/Makefile", "", "<folder>"),
    Setting("ND120_SIM_WSLDIR", "the Verilog/sim folder as WSL sees it", "text", "never",
            "Verilog/sim/nd120_probe.py", "", "<folder>",
            "Optional: by default worked out from the script's own location."),
    Setting("ND120_FRESH_DIR", "an empty folder for make fresh-build", "text", "never",
            "make fresh-build in every board folder",
            "make fresh-build", "<empty folder>",
            "The current commit is cloned into it and built there, to prove the build "
            "needs nothing outside the repository."),
    Setting("ND120_BASYS3_PROJECT", "the old Basys3 Vivado project folder", "dir", "never",
            "nothing any more - the Basys3 build is a non-project flow since 30-SEP-2026",
            "", "<folder>",
            "Kept only if you set it; no build reads it."),
]
SETTING = {s.name: s for s in SETTINGS}
NAME_RE = re.compile(r"^(ND120_[A-Za-z0-9_]+|ND_REPOS)$")


# ---------------------------------------------------------------------------
# local.mk reading and writing. Only plain "NAME := value" lines (also = and
# ?=) are read. In make syntax a '$' is written '$$' and a '#' is '\#'; the
# readers undo that, the writer does it.
# ---------------------------------------------------------------------------
_LINE_RE = re.compile(r"^\s*(ND120_[A-Za-z0-9_]+|ND_REPOS)\s*[:?]?=(.*)$")


def _mk_unescape(v):
    return v.replace("$$", "$").replace("\\#", "#")


def _mk_escape(v):
    return v.replace("$", "$$").replace("#", "\\#")


def read_local_mk(path=LOCAL_MK):
    """NAME -> value from a local.mk; {} when the file does not exist."""
    vals = {}
    if not os.path.exists(path):
        return vals
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = _LINE_RE.match(line.rstrip("\r\n"))
            if m:
                vals[m.group(1)] = _mk_unescape(m.group(2).strip())
    return vals


def setting(name, default=None):
    """The value a script should use: the environment first, then local.mk.

    For the Python helpers in this repository:
        sys.path.insert(0, <repository root>); import configure
        path = configure.setting("ND_REPOS")
    """
    v = os.environ.get(name, "")
    if v.strip():
        return v.strip()
    v = read_local_mk().get(name, "")
    return v if v else default


def setting_path(name, default=None):
    """setting(name) as a path this host can open (see host_path)."""
    v = setting(name)
    return host_path(v) if v else default


def host_path(value):
    """Turn a stored path into one this host can open.

    local.mk holds paths in the form the shell that ran configure.py used, and
    Windows programs always as Windows paths. So in WSL a 'X:\\...' or 'X:/...'
    value becomes /mnt/x/..., and in a Windows shell a /mnt/x/... value becomes
    X:/... - the same rule paths.mk, paths.ps1 and paths.tcl apply."""
    if not value:
        return value
    if IS_WINDOWS:
        m = re.match(r"^/mnt/([a-zA-Z])(/.*)?$", value)
        if m:
            return m.group(1).upper() + ":" + (m.group(2) or "/")
        return value
    m = re.match(r"^([A-Za-z]):[\\/](.*)$", value)
    if m:
        if IS_WSL:
            out = _wslpath("-u", value)
            if out:
                return out
            return "/mnt/%s/%s" % (m.group(1).lower(), m.group(2).replace("\\", "/"))
    return value


def _wslpath(flag, value):
    if not shutil.which("wslpath"):
        return None
    try:
        r = subprocess.run(["wslpath", flag, value], stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, universal_newlines=True)
        out = r.stdout.strip()
        return out if r.returncode == 0 and out else None
    except OSError:
        return None


def windows_path(path):
    """A path as a Windows program needs it (used for tools found from WSL)."""
    if IS_WINDOWS:
        return os.path.normpath(path)
    if IS_WSL:
        out = _wslpath("-w", path)
        if out:
            return out
        m = re.match(r"^/mnt/([a-z])/(.*)$", path)
        if m:
            return m.group(1).upper() + ":\\" + m.group(2).replace("/", "\\")
    return path


def is_windows_tool(value):
    return bool(value) and bool(re.search(r"\.(bat|exe|cmd)$", value, re.I))


def windows_drive_of(path):
    """The drive letter a Windows program would see for this build folder, or
    None when a Windows program cannot reach it (a Linux-only WSL folder)."""
    if IS_WINDOWS:
        m = re.match(r"^([A-Za-z]):", os.path.abspath(path))
        return m.group(1) if m else None
    m = re.match(r"^([A-Za-z]):[\\/]", path)
    if m:
        return m.group(1)
    m = re.match(r"^/mnt/([a-z])(/|$)", path)
    return m.group(1).upper() if m else None


# ---------------------------------------------------------------------------
# Tool detection. The install folders are looked up at run time on every
# drive; nothing machine-specific is written here.
# ---------------------------------------------------------------------------
def _drive_roots():
    """Roots of the Windows drives: C:\\ ... in Windows, /mnt/c ... in WSL."""
    roots = []
    if IS_WINDOWS:
        for c in "CDEFGHIJKLMNOPQRSTUVWXYZ":
            r = c + ":\\"
            if os.path.isdir(r):
                roots.append(r)
    elif IS_WSL:
        for c in "cdefghijklmnopqrstuvwxyz":
            r = "/mnt/" + c
            try:
                if os.path.isdir(r) and os.listdir(r):
                    roots.append(r)
            except OSError:
                pass
    return roots


def _version_key(path):
    """Sort key: the highest version number in the path wins."""
    nums = re.findall(r"\d+(?:\.\d+)+", path)
    best = max((tuple(int(x) for x in n.split(".")) for n in nums), default=())
    return (best, path)


def _newest(cands):
    cands = [c for c in cands if os.path.isfile(c) or os.path.isdir(c)]
    if not cands:
        return None
    return sorted(set(cands), key=_version_key)[-1]


def _globs(bases, patterns):
    out = []
    for b in bases:
        for p in patterns:
            out.extend(glob.glob(os.path.join(b, p)))
    return out


def _home():
    return os.path.expanduser("~")


def _linux_bases():
    return [_home(), "/opt", "/tools", "/usr/local"]


def _windows_bases():
    """Folders under which Windows tools are commonly installed, on every drive
    (plus the user profile when running natively on Windows)."""
    bases = []
    for r in _drive_roots():
        bases.append(r)
        for sub in ("Utils", "Tools", "Program Files"):
            bases.append(os.path.join(r, sub))
    if IS_WINDOWS:
        bases.append(_home())
    return bases


def detect_vivado():
    on_path = shutil.which("vivado.bat" if IS_WINDOWS else "vivado")
    if on_path:
        return on_path, "on PATH"
    lin = _globs(_linux_bases(), ["Xilinx/Vivado/*/bin/vivado", "Xilinx/*/Vivado/bin/vivado",
                                  "AMDDesignTools/*/Vivado/bin/vivado"])
    if not IS_WINDOWS and _newest(lin):
        return _newest(lin), "in an install folder"
    win = _globs(_windows_bases(), ["Xilinx/Vivado/*/bin/vivado.bat",
                                    "Xilinx/*/Vivado/bin/vivado.bat",
                                    "AMDDesignTools/*/Vivado/bin/vivado.bat",
                                    "AMD/*/Vivado/bin/vivado.bat"])
    if _newest(win):
        return _newest(win), "in an install folder on the Windows side"
    return None, None


def detect_gowin():
    on_path = shutil.which("gw_sh.exe" if IS_WINDOWS else "gw_sh")
    if on_path:
        return on_path, "on PATH"
    if not IS_WINDOWS:
        lin = _globs(_linux_bases(), ["gowin/IDE/bin/gw_sh", "Gowin/IDE/bin/gw_sh",
                                      "gowin/*/IDE/bin/gw_sh", "Gowin/*/IDE/bin/gw_sh"])
        if _newest(lin):
            return _newest(lin), "in an install folder"
    win = _globs(_windows_bases(), ["Gowin/IDE/bin/gw_sh.exe", "Gowin/*/IDE/bin/gw_sh.exe"])
    # An Education edition sorts below a full one of the same version.
    full = [w for w in win if "education" not in w.lower()]
    pick = _newest(full) or _newest(win)
    if pick:
        return pick, "in an install folder on the Windows side"
    return None, None


def detect_quartus():
    exe = "quartus_sh.exe" if IS_WINDOWS else "quartus_sh"
    on_path = shutil.which(exe)
    if on_path:
        return os.path.dirname(on_path), "on PATH"
    if not IS_WINDOWS:
        lin = _globs(_linux_bases(), ["intelFPGA*/*/quartus/bin/quartus_sh",
                                      "altera*/*/quartus/bin/quartus_sh"])
        if _newest(lin):
            return os.path.dirname(_newest(lin)), "in an install folder"
    win = _globs(_windows_bases(), ["intelFPGA*/*/quartus/bin64/quartus_sh.exe",
                                    "altera*/*/quartus/bin64/quartus_sh.exe"])
    if _newest(win):
        return os.path.dirname(_newest(win)), "in an install folder on the Windows side"
    return None, None


def detect_oss_cad_suite():
    # The install the shell running configure would use: Linux first in WSL.
    y = shutil.which("yosys")
    if y and os.path.basename(os.path.dirname(y)) == "bin":
        top = os.path.dirname(os.path.dirname(y))
        if os.path.exists(os.path.join(top, "environment")) or \
           os.path.exists(os.path.join(top, "environment.bat")):
            return top, "on PATH"
    if not IS_WINDOWS:
        lin = _globs(_linux_bases(), ["oss-cad-suite"])
        if _newest(lin):
            return _newest(lin), "in an install folder"
        return None, None
    win = _globs(_windows_bases(), ["oss-cad-suite"])
    if _newest(win):
        return _newest(win), "in an install folder"
    return None, None


def detect_w64devkit():
    if not IS_WINDOWS:
        return None, None
    g = shutil.which("gcc")
    if g and "w64devkit" in g.lower():
        return os.path.dirname(os.path.dirname(g)), "on PATH"
    win = _globs(_windows_bases(), ["w64devkit"])
    if _newest(win):
        return _newest(win), "in an install folder"
    return None, None


def detect_netlistsvg():
    """netlistsvg on PATH, else an npm install in the home folder (a folder
    of its own under ~/tools, or ~ itself). Only the shell that runs the doc
    generator (WSL/Linux) is searched - it runs netlistsvg directly."""
    on_path = shutil.which("netlistsvg")
    if on_path:
        return on_path, "on PATH"
    if IS_WINDOWS:
        return None, None
    cands = _globs([_home()], ["tools/netlistsvg/node_modules/.bin/netlistsvg",
                               "tools/*/node_modules/.bin/netlistsvg",
                               "node_modules/.bin/netlistsvg",
                               ".npm-global/bin/netlistsvg"])
    cands = [c for c in cands if os.path.isfile(c)]
    if cands:
        return sorted(cands)[0], "in an npm install folder"
    return None, None


def detect_nd_repos():
    """The folder above this checkout, if it holds another ND repository."""
    parent = os.path.dirname(ROOT)
    for sib in ("ND110Compile", "nd120uc", "NDDeviceCore", "RetroTerm", "NDInsight"):
        if os.path.isdir(os.path.join(parent, sib)):
            return parent, "next to this checkout"
    return None, None


DETECT = {
    "ND120_VIVADO": detect_vivado,
    "ND120_GOWIN": detect_gowin,
    "ND120_QUARTUS": detect_quartus,
    "ND120_OSS_CAD_SUITE": detect_oss_cad_suite,
    "ND120_W64DEVKIT": detect_w64devkit,
    "ND_REPOS": detect_nd_repos,
    "ND120_NETLISTSVG": detect_netlistsvg,
}

# Tools the Makefiles take from PATH - reported, never stored.
PATH_TOOLS = ["verilator", "iverilog", "yosys", "python3", "make", "git"]


def store_form(name, value):
    """The form a value is written to local.mk in: tools that are Windows
    programs as Windows paths (they are started through powershell.exe/cmd.exe
    from WSL), everything else as this shell sees it."""
    if not value:
        return value
    s = SETTING.get(name)
    if re.match(r"^[A-Za-z]:[\\/]", value):
        # Already a Windows path: keep it exactly (wslpath -w would mangle it;
        # measured 30-SEP-2026 - make fresh-build passed F:\...\vivado.bat on
        # and the clone stored "FAMDDesignTools...").
        return value
    if s and s.kind == "tool" and is_windows_tool(value):
        return windows_path(value)
    if s and s.kind == "dir" and name == "ND120_QUARTUS" and IS_WSL and value.startswith("/mnt/"):
        return windows_path(value)
    if s and s.kind in ("dir", "builddir", "file", "tool") and not re.match(r"^[A-Za-z]:[\\/]", value):
        return os.path.abspath(os.path.expanduser(value))
    return value


# ---------------------------------------------------------------------------
# Checking values
# ---------------------------------------------------------------------------
def value_problem(name, value):
    """None when the value is usable, else a short reason."""
    s = SETTING.get(name)
    if not s or not value:
        return None
    p = host_path(value)
    if s.kind == "tool":
        return None if os.path.isfile(p) else "does not exist"
    if s.kind == "dir":
        return None if os.path.isdir(p) else "does not exist"
    if s.kind == "file":
        return None if os.path.isfile(p) else "does not exist"
    if s.kind == "builddir":
        if not (os.path.isabs(p) or re.match(r"^[A-Za-z]:[\\/]", value)):
            return "is not an absolute path"
        if os.path.exists(p) and not os.path.isdir(p):
            return "is a file, not a folder"
    return None


def _what(name):
    s = SETTING.get(name)
    return s.what if s else "a local setting"


def _placeholder(name):
    s = SETTING.get(name)
    return s.placeholder if s else "<value>"


def require_message(names, problems, local_mk_exists, target=None):
    """The one "missing setting" block. problems: list of (kind, name, value)
    with kind 'missing', 'bad' (path does not exist), 'unreachable'."""
    parts = ["%s (%s)" % (n, _what(n)) for n in names]
    needs = parts[0] if len(parts) == 1 else ", ".join(parts[:-1]) + " and " + parts[-1]
    who = "this target" if not target else "'%s'" % target
    lines = ["nd-120: %s needs %s." % (who, needs)]
    missing = [n for k, n, v in problems if k == "missing"]
    if missing:
        if not local_mk_exists:
            lines.append("  local.mk not found at %s." % LOCAL_MK)
        else:
            lines.append("  %s does not set %s." % (LOCAL_MK, ", ".join(missing)))
    for k, n, v in problems:
        if k == "bad":
            lines.append("  %s points at %s, which %s - run configure.py again." %
                         (n, v, value_problem(n, v) or "cannot be used"))
        elif k == "unreachable":
            lines.append("  %s is %s, which a Windows program started from WSL cannot reach -"
                         % (n, v))
            lines.append("  pick a folder on a Windows drive (/mnt/<drive>/...).")
    first = (missing or [n for k, n, v in problems] or names)[0]
    lines.append("  Fix: from the repository root run   %-24s(Windows: %s)" % (FIX_RUN, FIX_RUN_WIN))
    lines.append("       or set one value:              %s --set %s=%s" %
                 (FIX_RUN, first, _placeholder(first)))
    lines.append("  See CONTRIBUTING.md \"Local settings\".")
    return "\n".join(lines)


def require(items, target=None, stream=sys.stderr):
    """Check the settings a target needs BEFORE it does any work. Prints the
    block and returns 2 when something is wrong; creates the build folder.

    items are NAMEs (value from the environment, then local.mk) or NAME=VALUE
    (the value the caller already worked out - paths.mk passes make's own
    value this way, and an empty VALUE means the setting is missing)."""
    lm_exists = os.path.exists(LOCAL_MK)
    lm = read_local_mk() if lm_exists else {}
    problems = []
    values = {}
    names = []
    for it in items:
        if "=" in it:
            n, v = it.split("=", 1)
            n, v = n.strip(), v.strip()
        else:
            n = it.strip()
            v = os.environ.get(n, "").strip() or lm.get(n, "")
        names.append(n)
        values[n] = v
        if not v:
            problems.append(("missing", n, ""))
            continue
        if value_problem(n, v):
            problems.append(("bad", n, v))
    bd = values.get("ND120_BUILD_DIR")
    if bd and not any(n == "ND120_BUILD_DIR" for k, n, v in problems):
        wintool = any(is_windows_tool(values.get(n, "")) for n in names)
        if IS_WSL and wintool and not windows_drive_of(bd):
            problems.append(("unreachable", "ND120_BUILD_DIR", bd))
        else:
            try:
                os.makedirs(host_path(bd), exist_ok=True)
            except OSError:
                problems.append(("bad", "ND120_BUILD_DIR", bd))
    if problems:
        print(require_message(names, problems, lm_exists, target), file=stream)
        return 2
    return 0


# ---------------------------------------------------------------------------
# Writing local.mk
# ---------------------------------------------------------------------------
def write_local_mk(values):
    lines = [
        "# local.mk - GENERATED by configure.py. Machine-local: never commit it",
        "# (.gitignore). Change a value with",
        "#     python3 configure.py --set NAME=VALUE        (Windows: py configure.py ...)",
        "# or run python3 configure.py again - it keeps these answers as defaults.",
        "# Hand edits are kept too, as long as they stay plain NAME := value lines.",
        "# A value in the environment wins over this file; make NAME=value wins over both.",
        "# Every variable is described in local.mk.example and CONTRIBUTING.md.",
        "",
    ]
    known = [s.name for s in SETTINGS]
    extra = sorted(n for n in values if n not in known)
    for n in known + extra:
        v = values.get(n, "")
        if not v:
            continue
        s = SETTING.get(n)
        if s:
            lines.append("# %s - %s" % (n, s.what))
        lines.append("%s := %s" % (n, _mk_escape(v)))
    tmp = LOCAL_MK + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    os.replace(tmp, LOCAL_MK)


# ---------------------------------------------------------------------------
# Interactive questions
# ---------------------------------------------------------------------------
def ask(prompt, default):
    shown = " [%s]" % default if default else " [Enter to skip]"
    try:
        sys.stdout.write("%s%s: " % (prompt, shown))
        sys.stdout.flush()
        line = sys.stdin.readline()
    except (EOFError, KeyboardInterrupt):
        print()
        return default
    if line == "":            # end of input (answers piped in and used up)
        print()
        return default
    if not sys.stdin.isatty():
        print()               # piped answers are not echoed; end the prompt line
    ans = line.strip()
    if ans == "-":            # a single dash clears the value
        return ""
    return ans or default


# ---------------------------------------------------------------------------
# Setup steps
# ---------------------------------------------------------------------------
def run_step(title, cmd, cwd):
    print("  %s: %s" % (title, " ".join(cmd)))
    try:
        r = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           universal_newlines=True)
    except OSError as e:
        print("    FAILED: %s" % e)
        return False
    if r.returncode != 0:
        print("    FAILED (exit %d):" % r.returncode)
        for line in r.stdout.strip().splitlines()[-15:]:
            print("    " + line)
        return False
    return True


def microcode_state():
    uc = os.path.join(ROOT, "Code", "Microcode")
    board = len(glob.glob(os.path.join(uc, "wcs", "wcs_*.hex")))
    sim = len(glob.glob(os.path.join(uc, "wcs-sim", "wcs_*.hex")))
    return board, sim


def submodule_state():
    """[(path, state)] from `git submodule status`; state 'ok', 'missing' or '?'."""
    try:
        r = subprocess.run(["git", "submodule", "status"], cwd=ROOT, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, universal_newlines=True)
    except OSError:
        return []
    out = []
    for line in r.stdout.splitlines():
        if not line.strip():
            continue
        flag = line[0]
        path = line[1:].split()[1] if len(line[1:].split()) > 1 else "?"
        out.append((path, "missing" if flag == "-" else ("changed" if flag == "+" else "ok")))
    return out


def setup(values, skip_submodules):
    ok = True
    print("\nSetting up the clone:")
    if skip_submodules:
        print("  submodules: skipped (--skip-submodules)")
    elif not shutil.which("git"):
        print("  submodules: git not found - skipped")
        ok = False
    else:
        ok &= run_step("submodules", ["git", "submodule", "update", "--init"], ROOT)
    uc = os.path.join(ROOT, "Code", "Microcode")
    py = sys.executable or "python3"
    ok &= run_step("microcode for the boards (Code/Microcode/wcs)",
                   [py, "gen_wcs_image.py"], uc)
    ok &= run_step("microcode for the simulators (Code/Microcode/wcs-sim)",
                   [py, "gen_wcs_image.py", "--sim"], uc)
    bd = values.get("ND120_BUILD_DIR")
    if bd:
        try:
            os.makedirs(host_path(bd), exist_ok=True)
            print("  build folder: %s" % bd)
        except OSError as e:
            print("  build folder: cannot create %s: %s" % (bd, e))
            ok = False
    return ok


# ---------------------------------------------------------------------------
# --check
# ---------------------------------------------------------------------------
def check(stream=sys.stdout):
    lm_exists = os.path.exists(LOCAL_MK)
    lm = read_local_mk()
    print("nd-120 settings (%s)" % ("local.mk: " + LOCAL_MK if lm_exists
                                    else "local.mk NOT FOUND at " + LOCAL_MK), file=stream)
    print("  rule: a value in the environment wins over local.mk\n", file=stream)
    bad_required = 0
    for s in SETTINGS:
        env = os.environ.get(s.name, "").strip()
        filev = lm.get(s.name, "")
        v = env or filev
        src = "environment" if env else ("local.mk" if filev else "")
        if not v:
            state = "MISSING (required)" if s.name == "ND120_BUILD_DIR" else "not set"
            if s.name == "ND120_BUILD_DIR":
                bad_required += 1
            print("  %-22s %s" % (s.name, state), file=stream)
        else:
            prob = value_problem(s.name, v)
            state = "PROBLEM: %s" % prob if prob else "ok"
            if prob and s.name == "ND120_BUILD_DIR":
                bad_required += 1
            print("  %-22s %s  (%s, %s)" % (s.name, v, src, state), file=stream)
        print("  %-22s   %s; needed for: %s" % ("", s.what,
                                                s.required_for or "nothing (optional)"),
              file=stream)
    extra = sorted(n for n in lm if n not in SETTING)
    for n in extra:
        print("  %-22s %s  (local.mk, not a known name)" % (n, lm[n]), file=stream)
    print("\nTools the Makefiles take from PATH:", file=stream)
    for t in PATH_TOOLS:
        w = shutil.which(t) or (shutil.which("py") if t == "python3" and IS_WINDOWS else None)
        print("  %-10s %s" % (t, w or "not found"), file=stream)
    board, sim = microcode_state()
    print("\nMicrocode preload images: Code/Microcode/wcs %d of 33, wcs-sim %d of 33%s" %
          (board, sim, "" if board == 33 and sim == 33 else
           "  - run configure.py (without --check) to make them"), file=stream)
    subs = submodule_state()
    if subs:
        print("Submodules: " + ", ".join("%s %s" % (p, st) for p, st in subs), file=stream)
    if bad_required:
        print("\nMISSING: ND120_BUILD_DIR - run %s (Windows: %s)" % (FIX_RUN, FIX_RUN_WIN),
              file=stream)
        return 1
    return 0


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
def parse_sets(items):
    out = {}
    for it in items or []:
        if "=" not in it:
            sys.exit("configure.py: --set wants NAME=VALUE, got '%s'" % it)
        n, v = it.split("=", 1)
        n = n.strip()
        if not NAME_RE.match(n):
            sys.exit("configure.py: '%s' is not a setting name (ND120_* or ND_REPOS)" % n)
        out[n] = v.strip()
    return out


def gather(existing, sets, interactive):
    """Work out every value: --set, then the environment, then local.mk, then
    detection; ask where the rules say so."""
    values = dict(existing)
    for s in SETTINGS:
        n = s.name
        if n in sets:
            values[n] = store_form(n, sets[n]) if sets[n] else ""
            continue
        env = os.environ.get(n, "").strip()
        cur = env or existing.get(n, "")
        src = "environment" if env else ("local.mk" if cur else "")
        if cur and value_problem(n, cur) and s.kind != "builddir":
            print("  %s: %s %s - looking again" % (n, cur, value_problem(n, cur)))
            cur, src = "", ""
        if not cur and n in DETECT:
            found, how = DETECT[n]()
            if found:
                cur, src = store_form(n, found), "found " + how
        if interactive and (s.ask == "always" or (s.ask == "missing" and not cur)):
            if s.name == "ND120_BUILD_DIR" and not cur:
                cur = os.path.join(ROOT, "build")
                src = "suggested"
            note = (" - " + s.notes) if s.notes and s.ask == "always" else ""
            print("\n%s: %s%s" % (n, s.what, note))
            if src:
                print("  (%s)" % src)
            ans = ask("  " + n, cur)
            values[n] = store_form(n, ans) if ans else ""
        else:
            values[n] = cur
            if cur and src and src != "local.mk":
                print("  %s := %s  (%s)" % (n, cur, src))
    return values


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Set up this ND-120 clone and remember the local settings in local.mk.")
    ap.add_argument("--check", action="store_true",
                    help="print every setting, where it came from, and what is missing")
    ap.add_argument("--set", action="append", metavar="NAME=VALUE",
                    help="change one setting (repeatable); NAME= removes it")
    ap.add_argument("--non-interactive", action="store_true",
                    help="ask nothing: take values from --set, the environment, "
                         "local.mk and the tool search")
    ap.add_argument("--skip-submodules", action="store_true",
                    help="do not run git submodule update --init")
    ap.add_argument("--no-setup", action="store_true",
                    help="only write local.mk; skip submodules, microcode and build folder")
    ap.add_argument("--get", metavar="NAME",
                    help="print one setting as this shell opens it (environment first, "
                         "then local.mk); prints nothing and exits 1 when it is not set")
    ap.add_argument("--require", nargs="+", metavar="NAME",
                    help=argparse.SUPPRESS)   # used by paths.mk before a target runs
    ap.add_argument("--for", dest="target", help=argparse.SUPPRESS)
    a = ap.parse_args(argv)

    if a.require:
        return require(a.require, a.target)
    if a.get:
        v = setting(a.get)
        if not v:
            return 1
        # A Windows program stays a Windows path: from WSL it is started
        # through powershell.exe/cmd.exe, which need that form.
        print(v if is_windows_tool(v) else host_path(v))
        return 0
    if a.check:
        return check()

    sets = parse_sets(a.set)
    existing = read_local_mk()
    if not existing and os.path.exists(OLD_LOCAL_MK):
        existing = read_local_mk(OLD_LOCAL_MK)
        if existing:
            print("Taking the old answers from Verilog/fpga/local.mk as defaults "
                  "(that file is no longer read; delete it when done).")
    # Old name: synh.bat read ND120_OSS_CAD before 30-SEP-2026.
    if "ND120_OSS_CAD" in existing and "ND120_OSS_CAD_SUITE" not in existing:
        existing["ND120_OSS_CAD_SUITE"] = existing.pop("ND120_OSS_CAD")

    if a.set and not a.non_interactive:
        # --set on its own: change those values and stop - no questions, no
        # setup. (With --non-interactive the values feed a full setup run.)
        values = dict(existing)
        for n, v in sets.items():
            values[n] = store_form(n, v) if v else ""
            prob = value_problem(n, values[n]) if values[n] else None
            print("%s := %s%s" % (n, values[n] or "(removed)",
                                  "   WARNING: %s" % prob if prob else ""))
        write_local_mk(values)
        print("wrote %s" % LOCAL_MK)
        return 0

    interactive = not a.non_interactive
    if interactive:
        print("nd-120 configure - Enter keeps the value in [brackets], '-' clears it.")
    else:
        print("nd-120 configure (non-interactive)")
    values = gather(existing, sets, interactive)
    bd = values.get("ND120_BUILD_DIR", "")
    if IS_WSL and bd and not windows_drive_of(bd) and \
            any(is_windows_tool(values.get(n, "")) for n in ("ND120_VIVADO", "ND120_GOWIN")):
        print("\nWARNING: ND120_BUILD_DIR %s is not on a Windows drive, so the Windows" % bd)
        print("         programs (Vivado, Gowin) started from WSL cannot write there.")
    write_local_mk(values)
    print("\nwrote %s" % LOCAL_MK)
    ok = True
    if not a.no_setup:
        ok = setup(values, a.skip_submodules)
    print()
    rc = check()
    if not ok:
        print("\nSome setup steps failed - see above.")
        return 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
