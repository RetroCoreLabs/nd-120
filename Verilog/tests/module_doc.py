#!/usr/bin/env python3
"""
module_doc.py - generate a module symbol PNG and a README.md from Verilog source.

WHY THIS EXISTS INSTEAD OF DOXYGEN
    The RTL in this tree is already annotated in Doxygen style (`//!` on ports,
    `//! @title` / `//! @author` in headers). The obvious move would be to run
    Doxygen over it - but Doxygen CANNOT DRAW A MODULE SYMBOL. Its graphviz
    output is call / include / inheritance graphs, which mean nothing for
    Verilog. There is no Doxygen feature that renders a box with inputs on the
    left and outputs on the right, which is the picture actually wanted. Its
    Verilog support also needs a third-party filter and emits HTML that is
    awkward to commit.

    So this reads the SAME comments and emits the two artifacts that are
    actually useful, with no new dependency:
        <module>.png        block symbol - inputs left, outputs right
        <module>.md         description, parameter table, port table

    Dependencies: python3 + Pillow. Both already present. Nothing is fetched.

REPO CONVENTIONS IT UNDERSTANDS
    _n / _N suffix        active low  -> drawn with an inversion bubble
    NAME_23_0 / [15:0]    bus         -> width shown on the pin
    inout                 bidirectional -> drawn on the right with a double arrow
    //! text              the port's description, taken straight from the source

USAGE
    module_doc.py FILE.v [-o OUTDIR] [--module NAME] [--png-only|--md-only]
                         [--note "TB_RESULT: PASS (n checks)"]

EXAMPLE
    python3 tests/module_doc.py Shared/support/TTL_74245.v -o Shared/support/doc \\
        --note "TB_RESULT: PASS - 524292 checks, exhaustive"

THE NAVIGATION BLOCK
    A doc written by this script has NO hierarchy navigation block (where the
    module sits, what uses it, what it contains). That block comes from
    gen_hierarchy.py. After regenerating a doc on its own, put it back with
    the one command for all docs (cd Verilog; python3 tests/gen_module_docs.py)
    or just the block: python3 tests/gen_module_docs.py --hierarchy-only

THE VERILOG SOURCE AND THE SCHEMATIC
    Every page ends with the module's Verilog in a fold-out block (the whole
    file, or only this module's part when the file holds several) and a link
    to the file on GitHub. The schematic block right after the symbol comes
    from gen_schematics.py; this script keeps the one the old page had.

Last reviewed: 30-SEP-2026
Ronny Hansen
"""
import argparse
import os
import re
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("module_doc: needs Pillow (python3 -m pip install pillow)")

BG      = (250, 250, 252)
BOX     = (255, 255, 255)
BOXLINE = (40, 46, 60)
TITLECOL= (20, 24, 34)
# Palette: Verilog/docs/COLOR-STANDARDS.md (WCAG 2.1 AA, light mode).
# Contrast against the #FAFAFC page: input 8.4:1, output 5.0:1, inout 7.1:1.
# Direction is ALSO carried by side and arrow head, so the drawing stays
# readable in greyscale - colour is reinforcement, never the carrier (1.4.1).
INCOL   = (13, 71, 161)     # #0D47A1 blue   - inputs
OUTCOL  = (46, 125, 50)     # #2E7D32 green  - outputs
BIDICOL = (154, 52, 18)     # #9A3412 orange - inouts
CLKCOL  = (106, 27, 154)    # #6A1B9A purple - clocks (9.4:1)
MUTED   = (110, 118, 132)
BUSFILL = (232, 240, 254)


def _font(sz, bold=False):
    cands = ["/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf" if bold
             else "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
             "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold
             else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]
    for p in cands:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, sz)
            except Exception:
                pass
    return ImageFont.load_default()


def strip_comments_keep_doc(src):
    """Remove /* */ blocks but keep //! doc comments attached to their line."""
    return re.sub(r"/\*.*?\*/", "", src, flags=re.S)


def parse_header(src):
    """The leading banner comment: title/author/description lines."""
    m = re.match(r"\s*/\*+(.*?)\*+/", src, flags=re.S)
    title = author = ""
    desc = []
    if m:
        for raw in m.group(1).splitlines():
            line = raw.strip().strip("*").strip()
            line = re.sub(r"^\*+", "", line).strip()
            if line.startswith("**") and line.endswith("**"):
                line = line.strip("*").strip()
            line = line.rstrip("*").strip()
            if not line:
                continue
            t = re.match(r"//!\s*@title\s+(.*)", line)
            a = re.match(r"//!\s*@author\s+(.*)", line)
            if t:
                title = t.group(1).strip(); continue
            if a:
                author = a.group(1).strip(); continue
            desc.append(line)
    # also catch //! @title outside the banner
    for tag, dest in (("title", "t"), ("author", "a")):
        mm = re.search(r"//!\s*@%s\s+(.+)" % tag, src)
        if mm:
            if tag == "title" and not title:
                title = mm.group(1).strip()
            if tag == "author" and not author:
                author = mm.group(1).strip()
    return title, author, desc


def expand_port_includes(src, srcdir):
    """Replace an `include line that sits INSIDE a module's port list with the
    text of that file. The MiSTer core top (fpga/mister/nd120.sv, module emu)
    takes its whole port list from the framework's sys/emu_ports.vh, so
    without this the doc would show a module with no ports at all - or, as
    first measured 30-SEP-2026, "no module found". Includes anywhere else are
    left alone, so every other doc comes out exactly as before. A file that
    cannot be found is left as it is."""
    inc_re = re.compile(r'^[ \t]*`include\s+"([^"]+)"[^\n]*', re.M)

    def repl(im):
        p = os.path.join(srcdir, im.group(1))
        try:
            with open(p, encoding="utf-8", errors="replace") as fh:
                return fh.read()
        except OSError:
            return im.group(0)
    out = []
    pos = 0
    for m in re.finditer(r"\bmodule\s+[A-Za-z_]\w*", src):
        # the word "module" also turns up in comments and inside a port
        # list already passed; only a match past the last one counts
        if m.start() < pos:
            continue
        end = src.find(");", m.end())
        if end < 0:
            continue
        head = src[m.end():end]
        if not inc_re.search(head):
            continue                     # nothing to expand: leave it alone
        out.append(src[pos:m.end()])
        out.append(inc_re.sub(repl, head))
        pos = end
    out.append(src[pos:])
    return "".join(out)


def parse_module(src, want=None):
    """Return (name, params, ports). ports = [(dir, width, name, comment)]."""
    s = strip_comments_keep_doc(src)
    for m in re.finditer(r"\bmodule\s+([A-Za-z_]\w*)", s):
        name = m.group(1)
        if want and name != want:
            continue
        # body from module name to the ');' that closes the port list
        rest = s[m.end():]
        end = rest.find(");")
        if end < 0:
            continue
        head = rest[:end]

        params = []
        for pm in re.finditer(
                r"parameter\s+(?:\[[^\]]*\]\s*)?(?:integer\s+|real\s+)?"
                r"([A-Za-z_]\w*)\s*=\s*([^,\n)]+)", head):
            params.append((pm.group(1), pm.group(2).strip()))

        ports = []
        for line in head.splitlines():
            pm = re.match(
                # \s* not \s+ after the direction: this tree contains
                # "output[7:0] A_OUT" with NO space (Shared/support/TTL_74646.v),
                # and requiring whitespace silently dropped BOTH outputs and both
                # wide inputs - the symbol drew "7 in / 0 out" for a transceiver.
                # Also allow "signed" and multiple type words.
                r"\s*(input|output|inout)\b\s*"
                r"(?:(?:wire|reg|logic|signed)\s+)*"
                r"(\[[^\]]*\]\s*)?([A-Za-z_]\w*)", line)
            if not pm:
                continue
            direction = pm.group(1)
            width = (pm.group(2) or "").strip()
            pname = pm.group(3)
            cm = re.search(r"//!?\s*(.+?)\s*$", line)
            comment = ""
            if cm:
                comment = cm.group(1).strip()
                comment = re.sub(r"^!\s*", "", comment).rstrip(",")
            ports.append((direction, width, pname, comment))

        # ---- Verilog-1995 (non-ANSI) header ---------------------------------
        # Logisim-evolution emits "module T_FLIPFLOP( clock, preset, q, ... );"
        # with the DIRECTIONS declared further down the body, not in the header.
        # 35 modules in Shared/logisim are written this way, and treating an
        # empty port list as "no module found" silently dropped every one of
        # them from the documentation sweep. Fall back to reading the names
        # from the header and the directions from the body.
        if not ports:
            # strip the opening paren, or the FIRST port stays glued to it
            # ("( clock" fails the name match and the clock vanishes from the
            # drawing - which is exactly what happened to T_FLIPFLOP).
            hdr = head.lstrip().lstrip("(")
            names = [n.strip() for n in re.split(r"[,\n]", hdr) if n.strip()]
            names = [n for n in names
                     if re.fullmatch(r"[A-Za-z_]\w*", n) and n != name]
            body = rest[end + 2:]
            # stop at the matching endmodule so a following module's
            # declarations are not attributed to this one
            em = re.search(r"\bendmodule\b", body)
            if em:
                body = body[:em.start()]
            decl = {}
            # one declaration may name several ports: "input A, B, D0, D1;"
            # (Shared/ndlib/MUX41P.v). Taking only the first name made the
            # rest look undeclared - a bug here, not in the Verilog.
            for dm in re.finditer(
                    r"^\s*(input|output|inout)\b\s*"
                    r"(?:(?:wire|reg|logic|signed)\s+)*"
                    r"(\[[^\]]*\]\s*)?"
                    r"([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*;?(.*)$",
                    body, re.M):
                cm2 = re.search(r"//!?\s*(.+?)\s*$", dm.group(4) or "")
                for pn in re.split(r"\s*,\s*", dm.group(3).strip()):
                    decl[pn] = (dm.group(1),
                                (dm.group(2) or "").strip(),
                                cm2.group(1).strip() if cm2 else "")
            for n in names:
                if n in decl:
                    d, w, c = decl[n]
                    ports.append((d, w, n, c))
            # a port named in the header but never declared is a REAL defect in
            # the source. Say so where the person running the generator sees
            # it; the page itself leaves the description empty rather than
            # printing a word that means nothing to a reader.
            for n in names:
                if n not in decl:
                    sys.stderr.write("module_doc: %s: port %s is in the header but "
                                     "never declared input/output/inout\n" % (name, n))
                    ports.append(("input", "", n, ""))

        if ports or params:
            return name, params, ports
    return None, [], []


def bus_label(width, name):
    if width:
        return width.replace(" ", "")
    m = re.search(r"_(\d+)_(\d+)$", name)
    if m:
        return "[%s:%s]" % (m.group(1), m.group(2))
    return ""


CLOCK_NAMES = ("clk", "sysclk", "clock", "sys_clk", "ui_clk", "clk_cpu",
               "clk_stor", "clk2x", "mclk", "aluclk", "maclk", "uclk", "osc")


def is_clock(pname):
    """A clock gets its own colour because it is the thing every other signal
    is read RELATIVE TO - burying it in the input blue makes a timing diagram
    much harder to read. Matched on name: the RTL has no other marker.
    Deliberately NOT matching resets or strobes - over-colouring is as bad as
    under-colouring, and those stay input-blue unless a case is made."""
    n = pname.lower().rstrip("_n")
    return (n in CLOCK_NAMES or n.endswith("clk") or n.endswith("clock")
            or n.startswith("clk"))


def port_colour(direction, pname):
    if is_clock(pname):
        return CLKCOL
    if direction == "inout":
        return BIDICOL
    return INCOL if direction == "input" else OUTCOL


def draw_symbol(name, params, ports, note, out_png):
    ins  = [p for p in ports if p[0] == "input"]
    outs = [p for p in ports if p[0] == "output"]
    bidi = [p for p in ports if p[0] == "inout"]
    right = outs + bidi

    f_pin  = _font(13)
    f_w    = _font(10)
    f_name = _font(20, bold=True)
    f_note = _font(12)
    f_par  = _font(11)

    PIN_DY   = 26
    rows     = max(len(ins), len(right), 1)
    box_h    = max(110, rows * PIN_DY + 46)
    stub     = 62
    lbl_w    = 230
    box_w    = 300
    W        = lbl_w + stub + box_w + stub + lbl_w
    par_h    = (len(params) + 1) * 16 + 10 if params else 0
    H        = 74 + box_h + par_h + (34 if note else 12)

    img = Image.new("RGB", (W, H), BG)
    d   = ImageDraw.Draw(img)

    d.text((16, 14), name, font=f_name, fill=TITLECOL)
    d.text((16, 42), f"{len(ins)} in / {len(outs)} out"
                     + (f" / {len(bidi)} inout" if bidi else ""),
           font=f_par, fill=MUTED)

    bx0, by0 = lbl_w + stub, 70
    bx1, by1 = bx0 + box_w, by0 + box_h
    d.rounded_rectangle([bx0, by0, bx1, by1], radius=8, fill=BOX,
                        outline=BOXLINE, width=2)
    tw = d.textlength(name, font=f_pin)
    d.text((bx0 + (box_w - tw) / 2, by0 + box_h / 2 - 8), name,
           font=f_pin, fill=TITLECOL)

    def pin(idx, total, side, port, colour):
        direction, width, pname, comment = port
        y = by0 + 30 + idx * PIN_DY
        active_low = pname.endswith(("_n", "_N")) or pname.endswith("_n_IN")
        wl = bus_label(width, pname)
        if side == "L":
            xa, xb = bx0 - stub, bx0
            d.line([(xa, y), (xb - (7 if active_low else 0), y)],
                   fill=colour, width=2)
            d.polygon([(xb - 9, y - 4), (xb, y), (xb - 9, y + 4)], fill=colour)
            tx = xa - 8 - d.textlength(pname, font=f_pin)
            d.text((tx, y - 8), pname, font=f_pin, fill=colour)
            if wl:
                d.text((xa + 4, y - 15), wl, font=f_w, fill=MUTED)
            if comment:
                # RIGHT-ALIGN the description so it ENDS at the pin and grows
                # leftwards. Drawing it left-aligned from the name's x (which
                # is what this did until 20-AUG-2026) sends a long description
                # straight under the box and destroys readability - the name
                # is short, the description is not.
                c = comment
                avail = (xa - 8) - 12          # 12 px page margin on the left
                while c and d.textlength(c, font=f_w) > avail:
                    c = c[:-1]
                if c != comment and len(c) > 1:
                    c = c[:-1] + "\u2026"      # ellipsis: say it was truncated
                d.text((xa - 8 - d.textlength(c, font=f_w), y + 4),
                       c, font=f_w, fill=MUTED)
        else:
            xa, xb = bx1, bx1 + stub
            d.line([(xa + (7 if active_low else 0), y), (xb, y)],
                   fill=colour, width=2)
            if direction == "inout":
                d.polygon([(xb - 9, y - 4), (xb, y), (xb - 9, y + 4)], fill=colour)
                d.polygon([(xa + 9, y - 4), (xa, y), (xa + 9, y + 4)], fill=colour)
            else:
                d.polygon([(xb - 9, y - 4), (xb, y), (xb - 9, y + 4)], fill=colour)
            d.text((xb + 8, y - 8), pname, font=f_pin, fill=colour)
            if wl:
                d.text((xa + 6, y - 15), wl, font=f_w, fill=MUTED)
            if comment:
                c = comment
                avail = (W - 12) - (xb + 8)    # to the right page margin
                while c and d.textlength(c, font=f_w) > avail:
                    c = c[:-1]
                if c != comment and len(c) > 1:
                    c = c[:-1] + "\u2026"
                d.text((xb + 8, y + 4), c, font=f_w, fill=MUTED)
        if active_low:      # inversion bubble, repo convention _n = active low
            cx = bx0 - 4 if side == "L" else bx1 + 4
            d.ellipse([cx - 4, y - 4, cx + 4, y + 4], fill=BG, outline=colour)

    for i, p in enumerate(ins):
        pin(i, len(ins), "L", p, port_colour(p[0], p[2]))
    for i, p in enumerate(right):
        pin(i, len(right), "R", p,
            port_colour(p[0], p[2]))

    y = by1 + 14
    if params:
        d.text((16, y), "parameters", font=f_par, fill=TITLECOL)
        y += 16
        for pn, pv in params:
            d.text((28, y), f"{pn} = {pv}"[:96], font=f_par, fill=MUTED)
            y += 16
    if note:
        col = (198, 40, 40) if "FAIL" in note.upper() else (46, 125, 50)
        d.text((16, H - 26), note, font=f_note, fill=col)

    os.makedirs(os.path.dirname(os.path.abspath(out_png)), exist_ok=True)
    img.save(out_png)
    return out_png


def repo_relative(path):
    """The source path as it should appear in a doc: relative to the top of
    the git checkout, with forward slashes (Verilog/Shared/support/TTL_74245.v).

    RULE: a generated doc must never hold a machine path. These docs are
    committed to a public repo, and a path like /mnt/<drive>/... or <drive>:\\... is only
    right on one machine. The sweep (gen_module_docs.py) passes absolute
    paths, and until 28-SEP-2026 this script wrote them as given, so every
    doc carried the path of the machine that made it. Now the path is worked
    out here, whatever form the caller used.

    The top of the checkout is the nearest folder above the file that holds a
    .git entry (a folder in a normal clone, a file in a worktree or
    submodule). No git call is needed. If the file is not inside a checkout at
    all, only the file name is written - never the full path."""
    ap = os.path.abspath(path)
    d = os.path.dirname(ap)
    while True:
        if os.path.exists(os.path.join(d, ".git")):
            return os.path.relpath(ap, d).replace(os.sep, "/")
        parent = os.path.dirname(d)
        if parent == d:
            return os.path.basename(ap)
        d = parent


def write_md(name, title, author, desc, params, ports, note, src_rel,
             png_rel, out_md, source_text=None):
    L = []
    L.append(f"# {name}")
    L.append("")
    if title:
        L.append(f"**{title}**")
        L.append("")
    L.append(f"Source: `{src_rel}`")
    if author:
        L.append(f"  ·  Author: {author}")
    L.append("")
    # An HTML comment, not visible text: readers of the page (GitHub, the
    # docs site) do not need it, but the index and hierarchy generators use
    # this line to tell a generated page from a hand-written note.
    L.append("<!-- Generated by Verilog/tests/module_doc.py from the //! comments"
             " in the source. Do not edit by hand - edit the RTL comments and"
             " regenerate. -->")
    L.append("")
    if png_rel:
        L.append(f"![{name} symbol]({png_rel})")
        L.append("")
    if desc:
        L.append("## Description")
        L.append("")
        for line in desc:
            L.append(line)
        L.append("")
    if params:
        L.append("## Parameters")
        L.append("")
        L.append("| Parameter | Default |")
        L.append("|---|---|")
        for pn, pv in params:
            L.append(f"| `{pn}` | `{pv}` |")
        L.append("")
    if ports:
        L.append("## Ports")
        L.append("")
        L.append("| Direction | Width | Name | Description |")
        L.append("|---|---|---|---|")
        for direction, width, pname, comment in ports:
            wl = bus_label(width, pname) or "1"
            al = " *(active low)*" if pname.endswith(("_n", "_N")) else ""
            # a "|" in the comment would split the table row
            # (emu_ports.vh: "= ~(VBlank | HBlank)")
            comment = comment.replace("|", "\\|")
            L.append(f"| {direction} | `{wl}` | `{pname}`{al} | {comment} |")
        L.append("")
    if note:
        L.append("## Validation")
        L.append("")
        L.append(f"`{note}`")
        L.append("")
    if source_text is not None:
        L.extend(source_section(name, src_rel, source_text))
    # The schematic block (tests/gen_schematics.py) sits right after the
    # symbol. It is kept from the old page, so regenerating a doc on a machine
    # without netlistsvg does not throw the drawing away.
    old_block = schematic_block_of(out_md)
    if old_block and png_rel:
        at = L.index(f"![{name} symbol]({png_rel})") + 2
        L[at:at] = old_block + [""]
    os.makedirs(os.path.dirname(os.path.abspath(out_md)), exist_ok=True)
    with open(out_md, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(L))
    return out_md


SCH_BEGIN = "<!-- SCHEMATIC:BEGIN"
SCH_END = "<!-- SCHEMATIC:END -->"
GITHUB_BLOB = "https://github.com/RetroCoreLabs/nd-120/blob/main/"


def schematic_block_of(md):
    """The SCHEMATIC block of an existing page, as lines, or None."""
    try:
        with open(md, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().split("\n")
    except OSError:
        return None
    for i, ln in enumerate(lines):
        if ln.startswith(SCH_BEGIN):
            for j in range(i, len(lines)):
                if lines[j] == SCH_END:
                    return lines[i:j + 1]
    return None


def module_text(src, name):
    """The part of a file that is this module: the whole file when it holds
    only this module, otherwise from the end of the module before it (so its
    header comment comes along) to its own endmodule."""
    starts = [(m.start(), m.group(1)) for m in
              re.finditer(r"^[ \t]*module\s+([A-Za-z_]\w*)", src, re.M)]
    if len(starts) <= 1:
        return src
    for i, (pos, n) in enumerate(starts):
        if n != name:
            continue
        prev_end = 0
        if i > 0:
            pe = src.rfind("endmodule", 0, pos)
            prev_end = src.find("\n", pe) + 1 if pe >= 0 else 0
        e = src.find("endmodule", pos)
        end = len(src) if e < 0 else e + len("endmodule")
        return src[prev_end:end].strip("\n") + "\n"
    return src


def source_section(name, src_rel, text):
    """A fold-out block with the Verilog. <details markdown="1"> is what the
    docs site (MkDocs, md_in_html) needs to read Markdown inside it; GitHub
    drops the attribute and shows the same thing."""
    text = text.replace("\r\n", "\n").replace("\t", "    ")
    # a fence longer than any run of backticks in the code
    runs = [len(r) for r in re.findall(r"`+", text)]
    fence = "`" * max(3, max(runs, default=0) + 1)
    n = text.count("\n") + (0 if text.endswith("\n") else 1)
    L = ["## Verilog source", ""]
    L.append(f"[`{src_rel}`]({GITHUB_BLOB}{src_rel}) on GitHub.")
    L.append("")
    L.append('<details markdown="1">')
    L.append(f"<summary>Show the Verilog of {name} ({n} lines)</summary>")
    L.append("")
    L.append(fence + "verilog")
    L.extend(text.rstrip("\n").split("\n"))
    L.append(fence)
    L.append("")
    L.append("</details>")
    L.append("")
    return L


def main():
    ap = argparse.ArgumentParser(
        description="Verilog module -> symbol PNG + README.md (no Doxygen)")
    ap.add_argument("source")
    ap.add_argument("-o", "--outdir", default=".")
    ap.add_argument("--module")
    ap.add_argument("--note", default="")
    ap.add_argument("--png-only", action="store_true")
    ap.add_argument("--md-only", action="store_true")
    args = ap.parse_args()

    src = open(args.source, encoding="utf-8", errors="replace").read()
    title, author, desc = parse_header(src)
    name, params, ports = parse_module(
        expand_port_includes(src, os.path.dirname(os.path.abspath(args.source))),
        args.module)
    if not name:
        sys.exit(f"module_doc: no module found in {args.source}")

    made = []
    png = os.path.join(args.outdir, f"{name}.png")
    md  = os.path.join(args.outdir, f"{name}.md")
    if not args.md_only:
        made.append(draw_symbol(name, params, ports, args.note, png))
    if not args.png_only:
        made.append(write_md(name, title, author, desc, params, ports,
                             # repo-relative, never the path as given -
                             # see repo_relative() for the rule
                             args.note, repo_relative(args.source),
                             os.path.basename(png) if not args.md_only else "",
                             md, module_text(src, name)))
    for f in made:
        print("module_doc:", f)


if __name__ == "__main__":
    main()
