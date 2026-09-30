#!/usr/bin/env python3
"""
gen_schematics.py - draw a schematic of every module from the Verilog, with
yosys and netlistsvg, and put it on the module's doc page.

WHY THIS EXISTS
    The symbol picture (module_doc.py) is a box with inputs and outputs. It
    says what a module connects to, not what is inside it. The schematic shows
    the inside: every sub-module as a box with its ports, every gate, flip-flop
    and multiplexer yosys finds in the code, and the wires between them, each
    wire named after its Verilog signal.

HOW A SCHEMATIC IS MADE
    1. The netlist comes from the SAME yosys elaboration gen_hierarchy.py makes
       for the build tops - the same file list, defines and include folders -
       so `ifdef`s and parameters are those of a real build. A module is drawn
       from the first top (in gen_hierarchy.TOPS order) that uses it, and the
       page says which one.
    2. yosys `proc` turns the always blocks into flip-flops and multiplexers,
       `opt_clean` drops the unnamed left-over wires, `write_json` writes it.
       NOTHING is flattened: a sub-module stays one box.
    3. The module is cut out of that JSON on its own and handed to netlistsvg,
       which lays it out and draws the SVG.
    4. The SVG is then edited here: every sub-module box becomes a link to
       that module's page, and every wire gets its Verilog name (a small label
       on its longest straight piece, and a tooltip on every piece).

    A module no build top uses is elaborated from its own file (no defines,
    default parameters); the modules it uses become empty boxes made from
    their own port lists. The page says so.

WHAT IT WRITES
    <folder>/doc/<Module>.svg   the schematic
    <folder>/doc/<Module>.md    a block between two marker lines, right after
                                the symbol picture, replaced on every run.
                                When no SVG could be made the block says
                                "Schematic not generated: <reason>" - a page
                                never just lacks one.

TOOLS
    yosys      $YOSYS, else ~/oss-cad-suite/bin/yosys, else yosys on PATH
    netlistsvg the ND120_NETLISTSVG setting (configure.py; environment first,
               then local.mk), else netlistsvg on PATH. Optional: without it
               this step prints why and leaves the pages as they are.
    Install netlistsvg OUTSIDE the repository, for example
        mkdir -p ~/tools/netlistsvg && cd ~/tools/netlistsvg && npm install netlistsvg
    then  python3 configure.py --set ND120_NETLISTSVG=<that folder>/node_modules/.bin/netlistsvg

USAGE
    Normally run by gen_hierarchy.py, which is run by the one command:
        cd Verilog
        python3 tests/gen_module_docs.py
    On its own (elaborates the tops again, then draws):
        python3 tests/gen_schematics.py
        python3 tests/gen_schematics.py --modules CGA_ALU,TTL_74245   # a few

Last reviewed: 30-SEP-2026
Ronny Hansen
"""

import argparse
import concurrent.futures as cf
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
VROOT = os.path.dirname(HERE)                      # Verilog/
ROOT = os.path.dirname(VROOT)                      # the repository

SCH_BEGIN = "<!-- SCHEMATIC:BEGIN - written by Verilog/tests/gen_schematics.py, do not edit -->"
SCH_END = "<!-- SCHEMATIC:END -->"

# Seconds netlistsvg gets for one module. Its layout engine (ELK) grows much
# faster than the module does; a module that does not finish in this time
# gets a page that says so, instead of holding up the other 390.
NETLISTSVG_TIMEOUT = int(os.environ.get("ND120_NETLISTSVG_TIMEOUT", "300"))
# largest schematic written to the repository - see draw()
MAX_SVG_BYTES = int(float(os.environ.get("ND120_SCHEMATIC_MAX_MB", "4")) * 1048576)
# Two at a time at most: each netlistsvg can take several GB on a big module.
JOBS = 2

SVG_NS = "http://www.w3.org/2000/svg"
S_NS = "https://github.com/nturley/netlistsvg"

GITHUB_BLOB = "https://github.com/RetroCoreLabs/nd-120/blob/main/"


# ---------------------------------------------------------------------------
# tools
# ---------------------------------------------------------------------------
def find_netlistsvg():
    """The netlistsvg program, or None. ND120_NETLISTSVG first (environment,
    then local.mk through configure.py), then PATH."""
    v = os.environ.get("ND120_NETLISTSVG", "").strip()
    if not v:
        try:
            sys.path.insert(0, ROOT)
            import configure                                     # noqa: E402
            v = configure.setting_path("ND120_NETLISTSVG") or ""
        except Exception:                                        # noqa: BLE001
            v = ""
    if v and os.path.isfile(v):
        return v
    return shutil.which("netlistsvg")


def yosys_path():
    sys.path.insert(0, HERE)
    import gen_hierarchy                                         # noqa: E402
    return gen_hierarchy.find_tool("YOSYS", ["yosys"], ["~/oss-cad-suite/bin/yosys"])


def run_yosys_json(yosys, script_lines, workdir):
    """Run a yosys script that ends in write_json; (json dict, None) or
    (None, reason)."""
    ys = os.path.join(workdir, "sch.ys")
    out = os.path.join(workdir, "sch.json")
    with open(ys, "w") as fh:
        fh.write("\n".join(script_lines + ["write_json %s" % out]) + "\n")
    log = os.path.join(workdir, "sch.log")
    r = subprocess.run([yosys, "-q", "-l", log, "-s", ys], cwd=workdir,
                       capture_output=True, text=True, timeout=1800)
    if r.returncode != 0 or not os.path.exists(out):
        text = (r.stderr or "") + (r.stdout or "")
        try:
            text += open(log, encoding="utf-8", errors="replace").read()
        except OSError:
            pass
        errs = [ln.strip() for ln in text.splitlines() if "ERROR" in ln]
        return None, (errs[0] if errs else "yosys exit %d" % r.returncode)
    with open(out, encoding="utf-8") as fh:
        return json.load(fh), None


# ---------------------------------------------------------------------------
# which netlist each page is drawn from
# ---------------------------------------------------------------------------
def first_variants(results):
    """(module, source rel. to Verilog/) -> (top dict, RTLIL module name,
    instance path), from the first top that uses it. The instance path is the
    shortest one, found the same way as the "Where it sits" line."""
    out = {}
    for t, spec, tree, err in results:
        if not tree:
            continue
        path = {tree.top: []}
        queue = [tree.top]
        order = [tree.top]
        while queue:
            v = queue.pop(0)
            for inst, ctype in tree.mods[v]["cells"]:
                if tree.is_mod(ctype) and ctype not in path:
                    path[ctype] = path[v] + [inst]
                    queue.append(ctype)
                    order.append(ctype)
        for v in order:
            key = (tree.mods[v]["base"], tree.src_rel(v))
            if key not in out and tree.spec.bbox_kind.get(tree.mods[v]["base"]) is None:
                out[key] = (t, v, path[v])
    return out


def unescape(name):
    return name[1:] if name.startswith("\\") else name


def base_of(mod):
    sys.path.insert(0, HERE)
    import gen_hierarchy                                         # noqa: E402
    return gen_hierarchy.base_of(mod)


# ---------------------------------------------------------------------------
# one module -> netlistsvg -> SVG
# ---------------------------------------------------------------------------
def module_json(mod, name):
    """A JSON netlist holding only this module, with each sub-module cell's
    type cut down to the module's plain name ($paramod\\X\\W=4 -> X)."""
    m = json.loads(json.dumps(mod))            # a deep copy
    m.setdefault("attributes", {})["top"] = "00000000000000000000000000000001"
    # yosys names the cells it makes after the source line, with the FULL
    # path of the file in it ($not$/<checkout>/Verilog/X.v:216$9933). That
    # name ends up as an id in the SVG, and the SVG is committed: keep only
    # the file name ($not$X.v:216$9933). No machine path in a committed file.
    m["cells"] = {short_name(k): v for k, v in m.get("cells", {}).items()}
    for cell in m.get("cells", {}).values():
        t = cell.get("type", "")
        if not t.startswith("$") or t.startswith("$paramod"):
            cell["type"] = base_of(t)
        # netlistsvg only draws ports whose direction it knows; an inout is
        # drawn as an input so the wire is not lost
        pd = cell.get("port_directions")
        if pd:
            for p, d in list(pd.items()):
                if d == "inout":
                    pd[p] = "input"
        else:
            # a cell of a type yosys never saw (a vendor primitive left as a
            # black box) has no directions: call them all inputs, so the box
            # and its wires are still drawn
            cell["port_directions"] = {p: "input" for p in cell.get("connections", {})}
    for p in m.get("ports", {}).values():
        if p.get("direction") == "inout":
            p["direction"] = "output"
    # netlistsvg accepts the constants 0, 1 and x, but not z (high
    # impedance), and refuses the whole module when it meets one. Each z bit
    # becomes a wire of its own named "z", so the drawing shows where the
    # code drives z instead of pretending it is 0, 1 or x.
    top_bit = [1]

    def scan(bits):
        for b in bits:
            if isinstance(b, int) and b > top_bit[0]:
                top_bit[0] = b
    for p in m.get("ports", {}).values():
        scan(p.get("bits", []))
    for c in m.get("cells", {}).values():
        for bits in c.get("connections", {}).values():
            scan(bits)
    for nn in m.get("netnames", {}).values():
        scan(nn.get("bits", []))
    zbits = []

    def unz(bits):
        out = []
        for b in bits:
            if b == "z":
                top_bit[0] += 1
                zbits.append(top_bit[0])
                out.append(top_bit[0])
            else:
                out.append(b)
        return out
    for p in m.get("ports", {}).values():
        p["bits"] = unz(p.get("bits", []))
    for c in m.get("cells", {}).values():
        for k in list(c.get("connections", {})):
            c["connections"][k] = unz(c["connections"][k])
    n_z_wires = len(zbits)
    # A port left open in the code (`.QCN()`) comes out of yosys with NO
    # bits. netlistsvg names a wire after its bit numbers, so every empty
    # port in a module got the same name and was drawn as ONE wire joining
    # all the unused outputs to each other - a connection the code does not
    # have (seen on CGA_ALU_STS: R41P_EN QCN "wired" to SCAN_FF_EN Q, and on
    # 48 more pages, 30-SEP-2026). Each open port gets a bit of its own that
    # nothing else uses: the pin is drawn, with no wire to anywhere.
    for c in m.get("cells", {}).values():
        for k in list(c.get("connections", {})):
            if not c["connections"][k]:
                top_bit[0] += 1
                c["connections"][k] = [top_bit[0]]
    # a named wire tied to z: its bits must be numbers too, or netlistsvg
    # refuses the module (a new number joins it to nothing)
    for nn in m.get("netnames", {}).values():
        nn["bits"] = unz(nn.get("bits", []))
    zbits = zbits[:n_z_wires]
    for i, b in enumerate(zbits):
        m.setdefault("netnames", {})["z#%d" % (i + 1)] = {
            "hide_name": 0, "bits": [b], "attributes": {}}
    return {"creator": "nd-120 gen_schematics.py", "modules": {name: m}}


def short_name(name):
    """$not$/any/path/X.v:216$9933 -> $not$X.v:216$9933"""
    return re.sub(r"\$[^$]*/([^/$]+)", r"$\1", name)


def no_machine_paths(text):
    """Last guard before an SVG is written: any absolute path left in it is
    cut down to its file name."""
    # (?<![\w/]): a drive letter or a /mnt/... must start a path, not sit
    # inside a word - "http://www.w3.org/2000/svg" has "p:/" in it, and an
    # earlier version of this line cut the SVG namespace down to "httsvg"
    return re.sub(r"(?<![\w/.])(?:/(?:mnt|home|tmp|Users)/|[A-Za-z]:[\\/])[^\s\"'<>:$]*[\\/]"
                  r"([^\\/\s\"'<>:$]+)", r"\1", text)


def net_names(mod):
    """bit string ("3,4,5") -> Verilog name, and every named net's bits.
    Names yosys made up itself ($...) are not used."""
    exact = {}
    named = []
    for n, info in mod.get("netnames", {}).items():
        if n.startswith("$") or info.get("hide_name"):
            continue
        bits = info.get("bits", [])
        if not bits or any(not isinstance(b, int) for b in bits):
            continue
        key = ",".join(str(b) for b in bits)
        # a port name wins over an internal alias of the same wire
        if key not in exact or n in mod.get("ports", {}):
            exact[key] = n
        named.append((n, bits))
    return exact, named


def name_for(bitstr, exact, named):
    if bitstr in exact:
        return exact[bitstr]
    try:
        bits = [int(b) for b in bitstr.split(",")]
    except ValueError:
        return None
    # a slice of a named bus (netlistsvg splits and joins buses)
    for n, nb in named:
        if len(nb) > len(bits) and bits[0] in nb:
            i = nb.index(bits[0])
            if nb[i:i + len(bits)] == bits:
                lo, hi = i, i + len(bits) - 1
                return "%s[%d]" % (n, lo) if lo == hi else "%s[%d:%d]" % (n, hi, lo)
    return None


def post_process(svg_text, mod, links):
    """Name the wires and make the sub-module boxes links.
    links: instance name -> (href, module name)."""
    ET.register_namespace("", SVG_NS)
    ET.register_namespace("s", S_NS)
    root = ET.fromstring(svg_text)
    q = lambda t: "{%s}%s" % (SVG_NS, t)                       # noqa: E731
    exact, named = net_names(mod)

    # ---- wires: a tooltip on every piece, one label per net ---------------
    best = {}
    for el in list(root):
        if el.tag != q("line"):
            continue
        cls = el.get("class", "")
        if not cls.startswith("net_"):
            continue
        nm = name_for(cls[4:], exact, named)
        if not nm:
            continue
        t = ET.SubElement(el, q("title"))
        t.text = nm
        x1, x2 = float(el.get("x1")), float(el.get("x2"))
        y1, y2 = float(el.get("y1")), float(el.get("y2"))
        if y1 == y2:                         # label horizontal pieces only
            ln = abs(x2 - x1)
            if cls not in best or ln > best[cls][0]:
                best[cls] = (ln, min(x1, x2), y1, nm)
    for cls, (ln, x, y, nm) in sorted(best.items()):
        if ln < 20:
            continue
        tx = ET.SubElement(root, q("text"), {"x": "%.1f" % (x + 3), "y": "%.1f" % (y - 3),
                                               "class": "netlabel"})
        tx.text = nm

    # ---- sub-module boxes become links ---------------------------------------
    for i, el in enumerate(list(root)):
        cid = el.get("id", "")
        if el.tag != q("g") or not cid.startswith("cell_"):
            continue
        inst = cid[len("cell_"):]
        if inst not in links:
            continue
        href, mname = links[inst]
        a = ET.Element(q("a"), {"href": href})
        t = ET.SubElement(a, q("title"))
        t.text = "%s (%s) - open its page" % (inst, mname)
        idx = list(root).index(el)
        root.remove(el)
        a.append(el)
        root.insert(idx, a)

    # ---- smaller files ---------------------------------------------------------
    # netlistsvg copies its layout hints into the picture: an <s:alias> list
    # and s:* attributes on every cell, and indentation. A browser draws none
    # of it. Dropping it roughly halves a big schematic (they are committed,
    # and a ROM turned into gates by `proc` runs to megabytes).
    def strip(el):
        for child in list(el):
            if child.tag == "{%s}alias" % S_NS:
                el.remove(child)
                continue
            strip(child)
        for k in [k for k in el.attrib if k.startswith("{%s}" % S_NS)]:
            del el.attrib[k]
        if el.text is not None and not el.text.strip():
            el.text = None
        if el.tail is not None and not el.tail.strip():
            el.tail = None
    strip(root)
    for child in root:
        child.tail = "\n"          # one drawing element per line

    # ---- style for the labels and the links ----------------------------------
    style = root.find(q("style"))
    extra = ("\n.netlabel { font-family: sans-serif; font-size: 8px; fill: #1565c0; }"
             "\na:hover rect { fill: #e3f2fd; }"
             "\na { cursor: pointer; }\n")
    if style is not None:
        style.text = (style.text or "") + extra
    # a white page behind the drawing, so it reads the same on a dark theme
    w, h = root.get("width", "0"), root.get("height", "0")
    bg = ET.Element(q("rect"), {"x": "0", "y": "0", "width": w, "height": h,
                                "fill": "#ffffff"})
    root.insert(1 if style is not None else 0, bg)
    # netlistsvg puts some labels (long port names on the left) partly
    # outside its own width; a margin all round keeps them on the picture
    pad = 80.0
    fw, fh = float(w) + 2 * pad, float(h) + 2 * pad
    root.set("viewBox", "%.1f %.1f %.1f %.1f" % (-pad, -pad, fw, fh))
    root.set("width", "%.1f" % fw)
    root.set("height", "%.1f" % fh)
    bg.set("x", "%.1f" % -pad)
    bg.set("y", "%.1f" % -pad)
    bg.set("width", "%.1f" % fw)
    bg.set("height", "%.1f" % fh)
    return no_machine_paths(ET.tostring(root, encoding="unicode"))


def draw(job):
    """Run netlistsvg for one module. Returns (job, None) or (job, reason)."""
    nsvg = job["netlistsvg"]
    with tempfile.TemporaryDirectory(prefix="nd120-sch-") as wd:
        jf = os.path.join(wd, "m.json")
        sf = os.path.join(wd, "m.svg")
        with open(jf, "w") as fh:
            json.dump(module_json(job["mod"], job["name"]), fh)
        env = dict(os.environ)
        env["NODE_OPTIONS"] = "--max-old-space-size=6144"
        t0 = time.time()
        try:
            r = subprocess.run([nsvg, jf, "-o", sf], capture_output=True, text=True,
                               timeout=NETLISTSVG_TIMEOUT, env=env)
        except subprocess.TimeoutExpired:
            return job, "netlistsvg did not finish in %d s (%d cells, %d wires)" % (
                NETLISTSVG_TIMEOUT, len(job["mod"].get("cells", {})),
                len(job["mod"].get("netnames", {})))
        job["seconds"] = time.time() - t0
        if r.returncode != 0 or not os.path.exists(sf):
            err = (r.stderr or r.stdout or "").strip().splitlines()
            # node prints the stack after the message; the message is the
            # line that names the error
            msg = next((ln.strip() for ln in err if "Error" in ln), None) or \
                (err[0].strip() if err else "exit %d" % r.returncode)
            return job, "netlistsvg failed: %s" % msg[:200]
        with open(sf, encoding="utf-8") as fh:
            svg = fh.read()
    try:
        svg = post_process(svg, job["mod"], job["links"])
    except ET.ParseError as exc:
        return job, "the SVG netlistsvg wrote could not be read: %s" % exc
    # read back what is about to be committed: it must still be an SVG
    # (a bad edit here once broke the namespace of all 387 pictures and
    # nothing complained - a browser just shows nothing)
    try:
        chk = ET.fromstring(svg)
    except ET.ParseError as exc:
        return job, "the edited SVG is not valid XML: %s" % exc
    if chk.tag != "{%s}svg" % SVG_NS:
        return job, "the edited SVG has the wrong root element %s" % chk.tag
    # A picture this big is a memory's contents drawn as gates (font_rom,
    # the microcode PROM, char_ram: 4.5 to 17 MB each, measured 30-SEP-2026)
    # - nobody can read it, and every regenerate adds it to git history
    # again. All real logic measured under 4 MB (the largest,
    # nd_storage_engine, 3.6 MB). Such a module gets no picture; its page
    # says why, and the source below it is the thing to read.
    if len(svg.encode("utf-8")) > MAX_SVG_BYTES:
        if os.path.exists(job["svg"]):
            os.remove(job["svg"])
        return job, ("too large to show as one picture: %d cells make a %.1f MB "
                     "drawing (limit %.0f MB) - for a memory that is its stored "
                     "contents drawn as gates; read the Verilog source below"
                     % (len(job["mod"].get("cells", {})),
                        len(svg.encode("utf-8")) / 1048576.0,
                        MAX_SVG_BYTES / 1048576.0))
    with open(job["svg"], "w", encoding="utf-8", newline="\n") as fh:
        fh.write(svg + "\n")
    return job, None


# ---------------------------------------------------------------------------
# a module no build top uses: elaborate it from its own file
# ---------------------------------------------------------------------------
def include_dirs():
    """Every folder under Verilog/ that holds a Verilog header (.vh/.svh).
    A module read on its own does not get its build's include list, and
    several of them `include a header from another folder
    (sd_fat_features.vh, nd_storage_*.vh)."""
    out = []
    for dirpath, dirnames, filenames in os.walk(VROOT):
        dirnames[:] = [d for d in dirnames if d not in (".git", "obj_dir", "build", "m2m")
                       and not d.startswith("obj_dir")]
        if any(f.endswith((".vh", ".svh")) for f in filenames):
            out.append(dirpath)
    return sorted(out)


_INCDIRS = None


def standalone_json(yosys, name, src_rel, sources_by_name):
    """(module json, None) or (None, reason). The module's own file is read
    with no defines. Every module it uses is read from its own file as a
    library module (yosys `read_verilog -lib`: ports and directions only, the
    inside ignored), so it is drawn as a box; a vendor primitive with no
    source anywhere becomes a box made from the way it is used."""
    global _INCDIRS
    sys.path.insert(0, HERE)
    import gen_hierarchy as gh                                   # noqa: E402
    if _INCDIRS is None:
        _INCDIRS = include_dirs()
    incs = " ".join("-I%s" % d for d in [os.path.dirname(os.path.join(VROOT, src_rel))]
                    + _INCDIRS)
    path = os.path.join(VROOT, src_rel)
    own = set(gh.modules_in_file(path))
    lines = []
    with tempfile.TemporaryDirectory(prefix="nd120-sch1-") as wd:
        # empty stand-ins for ROM/RAM init files, as for the tops
        for n in set(gh.MEMFILE_RE.findall(open(path, encoding="utf-8",
                                                errors="replace").read())):
            open(os.path.join(wd, n), "w").close()
        lib_files = []
        for used in gh.instantiated(path):
            if used in own:
                continue
            if used in sources_by_name:
                f = os.path.join(VROOT, sources_by_name[used])
                if f != path and f not in lib_files:
                    lib_files.append(f)
                continue
            got = gh.usage_stub(path, used)
            if got is None:
                continue
            stub = os.path.join(wd, "bbox_%s.v" % used)
            with open(stub, "w") as fh:
                fh.write("(* blackbox *)\n%s\nendmodule\n" % got[1])
            lib_files.append(stub)
        for f in lib_files:
            fsv = " -sv" if f.endswith(".sv") else ""
            lines.append("read_verilog -lib%s %s %s" % (fsv, incs, f))
        sv = " -sv" if path.endswith(".sv") else ""
        lines.append("read_verilog -defer%s %s %s" % (sv, incs, path))
        lines.append("hierarchy -top %s" % name)
        lines.append("proc")
        lines.append("opt_clean")
        data, err = run_yosys_json(yosys, lines, wd)
    if data is None:
        return None, "yosys could not elaborate it from its own file: %s" % gh.clean_msg(err)
    for mname, mod in data.get("modules", {}).items():
        # an empty module (PAL/template: ports only, no logic) comes back
        # marked as a black box; it is still this module, drawn as its ports
        if base_of(mname) == name:
            return mod, None
    return None, "yosys did not produce the module"


# ---------------------------------------------------------------------------
# the page block
# ---------------------------------------------------------------------------
def block(name, svg_rel, reason, how):
    L = [SCH_BEGIN, "", "## Schematic", ""]
    if svg_rel:
        L.append("Drawn from the Verilog: %s Sub-modules are boxes (click the picture "
                 "to open it full size; there every sub-module box links to its page, "
                 "and every wire shows its Verilog name)." % how)
        L.append("")
        L.append("[![%s schematic](%s)](%s)" % (name, svg_rel, svg_rel))
    else:
        L.append("Schematic not generated: %s." % reason)
    L.append("")
    L.append(SCH_END)
    return L


def put_block(doc, lines_block):
    """Replace the old block, or put it right after the symbol picture."""
    with open(doc, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().split("\n")
    if SCH_BEGIN in lines:
        b = lines.index(SCH_BEGIN)
        e = lines.index(SCH_END, b) if SCH_END in lines[b:] else b
        del lines[b:e + 1]
        if b < len(lines) and lines[b] == "":
            del lines[b]
        at = b
    else:
        at = None
        for i, ln in enumerate(lines):
            if re.match(r"^!\[.* symbol\]\(.*\.png\)$", ln):
                at = i + 1
                if at < len(lines) and lines[at] == "":
                    at += 1
                break
        if at is None:
            # no symbol picture: before the first ## heading
            at = next((i for i, ln in enumerate(lines) if ln.startswith("## ")), len(lines))
    lines[at:at] = lines_block + [""]
    with open(doc, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines))


# ---------------------------------------------------------------------------
def run(results, docs, only=None, log=print):
    """Draw every module doc's schematic. Returns 0 (failures are written on
    the pages and listed, they do not stop the sweep)."""
    t_start = time.time()
    nsvg = find_netlistsvg()
    if not nsvg:
        log("\nschematics: SKIPPED - netlistsvg not found. Set ND120_NETLISTSVG "
            "(python3 configure.py --set ND120_NETLISTSVG=<program>) or put it on "
            "PATH; see the header of tests/gen_schematics.py. The pages keep the "
            "schematics they have.")
        return 0
    yosys = yosys_path()
    log("\nschematics: netlistsvg + yosys, %d at a time, %d s per module at most"
        % (JOBS, NETLISTSVG_TIMEOUT))

    first = first_variants(results)
    sources_by_name = {}
    for (name, src) in docs.by_key:
        sources_by_name.setdefault(name, src)

    # the JSON netlist of every top that some page is drawn from
    wanted = []
    for (name, src), doc in sorted(docs.by_key.items()):
        if only and name not in only:
            continue
        wanted.append((name, src, doc))
    need_tops = []
    for name, src, doc in wanted:
        f = first.get((name, src))
        if f and f[0]["key"] not in need_tops:
            need_tops.append(f[0]["key"])
    top_json = {}
    for t, spec, tree, err in results:
        if t["key"] not in need_tops or not tree:
            continue
        t0 = time.time()
        with tempfile.TemporaryDirectory(prefix="nd120-schtop-") as wd:
            il = os.path.join(wd, "design.il")
            with open(il, "w") as fh:
                fh.write(spec.rtlil)
            data, e = run_yosys_json(yosys, ["read_rtlil %s" % il, "proc", "opt_clean"], wd)
        if data is None:
            log("  %-10s netlist FAILED: %s" % (t["key"], e))
            continue
        top_json[t["key"]] = data["modules"]
        log("  %-10s netlist for drawing: %d modules, %.0f s"
            % (t["key"], len(data["modules"]), time.time() - t0))

    jobs, results_out = [], []
    for name, src, doc in wanted:
        docdir = os.path.dirname(doc)
        svg = os.path.join(docdir, name + ".svg")
        f = first.get((name, src))
        mod, why, how = None, None, ""
        if f:
            t, variant, ipath = f
            mods = top_json.get(t["key"])
            if mods is None:
                why = "the %s netlist could not be written by yosys" % t["title"]
            else:
                mod = mods.get(unescape(variant))
                if mod is None:
                    why = "the module is missing from the %s netlist" % t["title"]
                how = ("the yosys netlist of the %s build%s." %
                       (t["title"], (", instance `%s`" % ".".join(ipath)) if ipath else
                        ", where it is the top"))
        else:
            mod, why = standalone_json(yosys, name, src, sources_by_name)
            how = ("no build top uses this module, so it was elaborated from its own "
                   "file with no defines and default parameters.")
        if mod is None:
            results_out.append((name, src, doc, None, why))
            continue
        links = {}
        for inst, cell in mod.get("cells", {}).items():
            ct = cell.get("type", "")
            if ct.startswith("$") and not ct.startswith("$paramod"):
                continue
            cb = base_of(ct)
            target = docs.doc_for(cb, None)
            # the doc of the same source the elaboration used, when known
            if f:
                t, variant, ipath = f
                tree = next(tr for tt, sp, tr, er in results if tt is t)
                for iname, ctype in tree.mods[variant]["cells"]:
                    if iname == inst and tree.is_mod(ctype):
                        target = docs.doc_for(cb, tree.src_rel(ctype)) or target
                        break
            elif cb in sources_by_name:
                target = docs.doc_for(cb, sources_by_name[cb]) or target
            if target:
                links[inst] = (os.path.relpath(target, docdir).replace(os.sep, "/"), cb)
        jobs.append({"name": name, "src": src, "doc": doc, "svg": svg, "mod": mod,
                     "links": links, "netlistsvg": nsvg, "how": how})

    log("  drawing %d modules (%d could not be read, see below)"
        % (len(jobs), len(results_out)))
    done = 0
    with cf.ThreadPoolExecutor(max_workers=JOBS) as ex:
        futs = [ex.submit(draw, j) for j in jobs]
        for fut in cf.as_completed(futs):
            job, why = fut.result()
            results_out.append((job["name"], job["src"], job["doc"],
                                job if why is None else None, why))
            done += 1
            if done % 25 == 0 or done == len(jobs):
                log("  %d/%d drawn" % (done, len(jobs)))

    ok = fail = 0
    reasons = {}
    for name, src, doc, job, why in sorted(results_out):
        if job is not None:
            ok += 1
            put_block(doc, block(name, name + ".svg", None, job["how"]))
        else:
            fail += 1
            put_block(doc, block(name, None, why, ""))
            # an SVG from an earlier run no longer matches the page
            old = os.path.join(os.path.dirname(doc), name + ".svg")
            if os.path.exists(old):
                os.remove(old)
            reasons.setdefault(re.sub(r"\d+", "N", why)[:90], []).append(name)
    log("schematics: %d drawn, %d not generated, %.0f s" % (ok, fail, time.time() - t_start))
    for r, names in sorted(reasons.items(), key=lambda x: -len(x[1])):
        log("  %3d  %s: %s" % (len(names), r, ", ".join(sorted(names)[:8])
                                + (" ..." if len(names) > 8 else "")))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--modules", help="comma list of module names to draw (default: all)")
    args = ap.parse_args(argv)
    sys.path.insert(0, HERE)
    import gen_hierarchy                                         # noqa: E402
    results, yver = gen_hierarchy.build_all()
    docs = gen_hierarchy.Docs()
    only = set(args.modules.split(",")) if args.modules else None
    return run(results, docs, only)


if __name__ == "__main__":
    sys.exit(main())
