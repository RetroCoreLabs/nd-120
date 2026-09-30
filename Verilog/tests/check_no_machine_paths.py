#!/usr/bin/env python3
"""Machine-path gate - a test-suite gate.

Fails when any git-tracked text file holds a path that is right on one
machine only: a drive-letter path into a real folder (<drive>:/Dev/...,
<drive>:\\Xilinx\\...), a WSL mount path (/mnt/<drive>/<folder>...), a
Git-Bash drive path (/<drive>/Dev/...), or a home directory
(/home/<user>/..., /Users/<user>/...).

Why (30-SEP-2026): this repository is public, and the owner's rule is "no
hardcoded directories directly - must be configurable". About 140 tracked
files outside Verilog/fpga carried such paths - scripts that only ran on one
machine, GTKWave save files, and header comments. The convention that
replaced them:
  - a path INSIDE the repository is derived from the script's own location
    at run time, and written repo-relative in comments and docs;
  - a path OUTSIDE it is a named environment variable: $ND_REPOS for the
    folder holding the sibling ND checkouts, ND120_<WHAT> for anything else
    (listed in CONTRIBUTING.md).

The patterns need a REAL folder after the prefix, so text that only
describes the shape of such a path ("/mnt/<drive>/...", "<drive>:\\...",
"/mnt/%s") does not trip the gate. There is no per-file ignore list: a
file is either clean or it is reported.

Not scanned: binary files (a NUL byte, or a known binary extension),
submodules (they are other repositories; git lists them as folders), and
the third-party trees in SKIP_TREES, each with its reason.

Usage:    python3 check_no_machine_paths.py            # every tracked file
          python3 check_no_machine_paths.py FILE...    # just these files
Verdict:  TB_RESULT: PASS, or every hit as path:line: text and
          TB_RESULT: FAIL <n> machine paths
Exit:     0 on pass, 1 otherwise.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# Third-party trees copied into this repository. They are not ours to edit,
# so a path in them is not a finding against this repository.
SKIP_TREES = (
    # MiSTer framework files, taken as they are from the MiSTer template.
    "Verilog/fpga/mister/sys/",
    # MiSTer2MEGA65 framework (a git submodule; listed in case it is ever
    # checked in as plain files).
    "Verilog/fpga/mega65/m2m/",
)

BINARY_EXT = {
    ".pdf", ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".ico", ".zip", ".gz",
    ".tgz", ".7z", ".bin", ".bit", ".fs", ".img", ".imd", ".exe", ".dll",
    ".so", ".o", ".a", ".xlsx", ".docx", ".pptx", ".vsd",
}

# Top-level folders that only exist on a particular machine's drive.
DRIVE_FOLDERS = (r"Xilinx|Dev|Gowin|intelFPGA|intelFPGA_lite|altera|"
                 r"AMDDesignTools|Data|Users|Program Files|Program Files \(x86\)|"
                 r"Utils|ND|OCR|Repos|tmp|temp|Temp")

PATTERNS = [
    # <drive>:\Folder or <drive>:/Folder, folder from the list above.
    ("drive path", re.compile(
        r"(?<![A-Za-z0-9])[A-Za-z]:[/\\]{1,2}(?:%s)(?=[/\\\"'\s,;:)\]]|$)"
        % DRIVE_FOLDERS)),
    # WSL mount of a Windows drive, followed by a real folder name.
    ("WSL mount path", re.compile(r"/mnt/[a-z]/[A-Za-z0-9_]")),
    # Git-Bash / MSYS drive form: /<drive>/Users/..., /<drive>/Dev/...
    ("Git-Bash drive path", re.compile(
        r"(?<![\w.~/-])/[a-z]/(?:%s)(?=/)" % DRIVE_FOLDERS)),
    # A user's home directory on Linux or macOS.
    ("home directory", re.compile(r"(?<![\w.])/(?:home|Users)/[a-z][\w.-]*/")),
]


def tracked_files(root):
    out = subprocess.run(["git", "ls-files", "-z"], cwd=root,
                         capture_output=True, check=True).stdout
    return [p.decode("utf-8", "surrogateescape") for p in out.split(b"\0") if p]


def scan(path, shown):
    """Return the hits in one file as (shown, line_no, kind, line)."""
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        return []                      # e.g. a submodule folder
    if b"\0" in data:
        return []                      # binary
    text = data.decode("utf-8", "replace")
    hits = []
    for no, line in enumerate(text.splitlines(), 1):
        for kind, rx in PATTERNS:
            if rx.search(line):
                hits.append((shown, no, kind, line.strip()))
                break
    return hits


def main(argv):
    if argv:
        files = [(p, p) for p in argv]
        root = None
    else:
        root = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=HERE,
                              capture_output=True, text=True,
                              check=True).stdout.strip()
        files = []
        for rel in tracked_files(root):
            if rel.startswith(SKIP_TREES):
                continue
            if os.path.splitext(rel)[1].lower() in BINARY_EXT:
                continue
            files.append((os.path.join(root, rel), rel))

    hits = []
    scanned = 0
    for path, shown in files:
        if not os.path.isfile(path):
            continue                   # submodule gitlink or missing file
        scanned += 1
        hits.extend(scan(path, shown))

    if hits:
        for shown, no, kind, line in hits:
            if len(line) > 160:
                line = line[:157] + "..."
            print("%s:%d: [%s] %s" % (shown, no, kind, line))
        print("TB_RESULT: FAIL %d machine paths in %d files (of %d scanned)"
              % (len(hits), len({h[0] for h in hits}), scanned))
        return 1
    print("TB_RESULT: PASS (%d files scanned, no machine paths)" % scanned)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
