#!/usr/bin/env python3
"""
gen_site_nav.py - write the left-hand page tree of the docs site
(docs-site/nav.yml) from the files that are really in the repository.

WHY THIS EXISTS
    A hand-kept navigation list goes stale the day a page is added, moved or
    renamed. This one is made from the tree: the board READMEs that exist, the
    notes in Verilog/docs/, and every module page grouped by area exactly as
    Verilog/MODULES.md groups them. gen_module_docs.py runs it every time it
    rebuilds MODULES.md, so the two cannot disagree.

WHAT IT WRITES
    docs-site/nav.yml    only the `nav:` key. docs-site/mkdocs.yml reads it
                         with INHERIT, so the hand-written settings (theme,
                         extensions) and the generated tree stay in separate
                         files. Pages that are not in the tree are still built
                         and can be reached by links and by search.

    The page titles are the first "# " heading of each file.

USAGE
    cd Verilog
    python3 tests/gen_module_docs.py --index-only     # MODULES.md + nav.yml
    python3 tests/gen_site_nav.py                     # nav.yml on its own

Last reviewed: 30-SEP-2026
Ronny Hansen
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
VROOT = os.path.dirname(HERE)                       # Verilog/
ROOT = os.path.dirname(VROOT)                       # the repository
NAV = os.path.join(ROOT, "docs-site", "nav.yml")

# board folders under Verilog/fpga, in the order the README lists them
# (boards that boot first). A board folder not named here still shows up,
# after these, so a new board cannot be left out.
BOARD_ORDER = ["tang-nano-20k", "nexys4ddr", "mister", "mega65", "qmtech-a35t",
               "cmod-a7-35t", "basys3"]


def rel(path):
    return os.path.relpath(path, ROOT).replace(os.sep, "/")


_TRACKED = None


def tracked(path):
    """True when git tracks the file. The menu may only name files a clean
    clone has: the site is built from a fresh checkout, and one untracked
    note in a working tree (a handoff from another session) made the
    strict build stop on the first try (30-SEP-2026)."""
    global _TRACKED
    if _TRACKED is None:
        import subprocess
        r = subprocess.run(["git", "-C", ROOT, "ls-files", "-z"], capture_output=True)
        if r.returncode != 0:
            sys.exit("gen_site_nav: git ls-files failed - run from inside the checkout")
        _TRACKED = set(p for p in r.stdout.decode("utf-8", "replace").split("\0") if p)
    return rel(path) in _TRACKED


def title_of(path, fallback=None):
    """The first '# ' heading of a Markdown file, without Markdown marks.
    Front matter (--- ... ---) with a title: is used when there is one."""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read(20000)
    except OSError:
        return fallback or os.path.basename(path)
    fm = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if fm:
        m = re.search(r"^title:\s*(.+)$", fm.group(1), re.M)
        if m:
            return m.group(1).strip().strip("\"'")
    in_code = False
    for ln in text.split("\n"):
        if ln.startswith("```"):
            in_code = not in_code
        if not in_code and ln.startswith("# "):
            t = ln[2:].strip()
            t = re.sub(r"!\[[^\]]*\]\([^)]*\)", "", t)          # images
            t = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", t)      # links
            t = re.sub(r"<[^>]+>", "", t)                        # HTML
            t = t.replace("`", "").replace("**", "").strip()
            if t:
                return t
    return fallback or os.path.splitext(os.path.basename(path))[0]


def md_files(folder):
    """The .md files directly in a folder, sorted by name, README first."""
    try:
        names = sorted(f for f in os.listdir(folder)
                       if f.endswith(".md") and tracked(os.path.join(folder, f)))
    except OSError:
        return []
    names.sort(key=lambda f: (f.lower() != "readme.md", f.lower()))
    return [os.path.join(folder, f) for f in names]


def item(title, path):
    return {title: rel(path)}


def exists(*parts):
    p = os.path.join(ROOT, *parts)
    return p if os.path.exists(p) and tracked(p) else None


def boards_section():
    fpga = os.path.join(VROOT, "fpga")
    out = []
    if exists("Verilog", "fpga", "README.md"):
        out.append(item("Boards overview", os.path.join(fpga, "README.md")))
    quick = [os.path.join(fpga, f) for f in sorted(os.listdir(fpga))
             if f.startswith("QUICKSTART-") and f.endswith(".md")
             and tracked(os.path.join(fpga, f))]
    if quick:
        out.append({"Quick starts": [item(title_of(q), q) for q in quick]})
    boards = [d for d in os.listdir(fpga)
              if os.path.isdir(os.path.join(fpga, d)) and md_files(os.path.join(fpga, d))]
    boards.sort(key=lambda d: (BOARD_ORDER.index(d) if d in BOARD_ORDER else 99, d))
    for d in boards:
        files = md_files(os.path.join(fpga, d))
        if len(files) == 1:
            out.append(item(title_of(files[0], d), files[0]))
        else:
            out.append({title_of(files[0], d):
                        [item("Overview" if os.path.basename(f).lower() == "readme.md"
                              else title_of(f), f) for f in files]})
    rel_notes = [os.path.join(fpga, f) for f in sorted(os.listdir(fpga))
                 if f.startswith("RELEASE") and f.endswith(".md")
                 and tracked(os.path.join(fpga, f))]
    if rel_notes:
        out.append({"Releases": [item(title_of(r), r) for r in rel_notes]})
    return out


def design_notes_section():
    docs = os.path.join(VROOT, "docs")
    out = []
    files = md_files(docs)
    for f in files:
        if os.path.basename(f).lower() == "readme.md":
            out.append(item("Overview", f))
    rest = [f for f in files if os.path.basename(f).lower() != "readme.md"]
    rest.sort(key=lambda f: title_of(f).lower())
    out += [item(title_of(f), f) for f in rest]
    # the older notes that sit directly in Verilog/
    top = [os.path.join(VROOT, n) for n in
           ("nd120-plan.md", "boot-sequence.md", "cycle_clock.md", "mic-calculation.md",
            "SignalReport.md", "OWNERSHIP.md")]
    top = [t for t in top if os.path.exists(t) and tracked(t)]
    if top:
        out.append({"Older notes in Verilog/": [item(title_of(t), t) for t in top]})
    return out


def modules_section(rows, area_title, area_sort_key):
    """rows: area key -> [(module, doc path rel. to Verilog/, source, desc)]"""
    out = [item("All modules", os.path.join(VROOT, "MODULES.md"))]
    for key in sorted(rows, key=area_sort_key):
        pages = []
        for module, doc, source, desc in sorted(rows[key], key=lambda r: r[0].lower()):
            pages.append({module: "Verilog/" + doc})
        out.append({"%s (%d)" % (area_title(key), len(pages)): pages})
    return out


def build_nav(rows, area_title, area_sort_key):
    nav = [{"Home": "README.md"}]
    start = []
    for n, f in (("Contributing and local settings", "CONTRIBUTING.md"),
                 ("Building", "BUILDING.md"),
                 ("Development", "DEVELOPMENT.md"),
                 ("Verilog overview", "Verilog/readme.md"),
                 ("Prerequisites", "Verilog/docs/PREREQUISITES.md"),
                 ("Build options", "Verilog/docs/build-defines.md"),
                 ("Security", "SECURITY.md")):
        if exists(*f.split("/")):
            start.append({n: f})
    nav.append({"Getting started": start})
    nav.append({"Boards": boards_section()})
    nav.append({"Module hierarchy": "Verilog/HIERARCHY.md"})
    nav.append({"Modules by area": modules_section(rows, area_title, area_sort_key)})
    nav.append({"Design notes": design_notes_section()})
    if exists("Verilog", "TODO.md"):
        nav.append({"Open work": "Verilog/TODO.md"})
    if exists("HISTORY.md"):
        nav.append({"History": "HISTORY.md"})
    if exists("HARDWARE.md"):
        nav.append({"Hardware": "HARDWARE.md"})
    return nav


def to_yaml(node, indent=0):
    """A small YAML writer for the nav: lists of one-key maps. Every string
    is written JSON-quoted, which is valid YAML and needs no escaping rules
    of its own."""
    pad = "  " * indent
    out = []
    for entry in node:
        (k, v), = entry.items()
        if isinstance(v, list):
            out.append("%s- %s:" % (pad, json.dumps(k)))
            out += to_yaml(v, indent + 2)
        else:
            out.append("%s- %s: %s" % (pad, json.dumps(k), json.dumps(v)))
    return out


def write_nav(rows, area_title, area_sort_key):
    nav = build_nav(rows, area_title, area_sort_key)
    lines = ["# docs-site/nav.yml - GENERATED by Verilog/tests/gen_site_nav.py",
             "# (run by Verilog/tests/gen_module_docs.py). Do not edit by hand:",
             "# the left-hand page tree of the docs site, made from the files in the",
             "# repository. docs-site/mkdocs.yml reads it with INHERIT.",
             "nav:"]
    lines += to_yaml(nav, 1)
    os.makedirs(os.path.dirname(NAV), exist_ok=True)
    with open(NAV, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    n = sum(1 for ln in lines if re.search(r'": "', ln))
    return n


def main():
    sys.path.insert(0, HERE)
    import gen_module_docs                                   # noqa: E402
    gen_module_docs.write_index()
    print("wrote %s" % rel(NAV))
    return 0


if __name__ == "__main__":
    sys.exit(main())
