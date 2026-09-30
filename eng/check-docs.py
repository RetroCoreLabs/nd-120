#!/usr/bin/env python3
"""
check-docs.py - the documentation's own test.

    python eng/check-docs.py              # from the repository root
    python eng/check-docs.py some/folder  # or any folder you name

THIS FILE IS COPIED INTO EVERY RetroCore Labs REPOSITORY, at eng/check-docs.py, and the
copies are meant to stay identical. The canonical one lives in the repo-standards
repository at tools/check-docs.py; `tools/sync-standards.ps1` there pushes it out. Each
repository carries its own so that somebody who cloned only one of them can run the
command its README gives - a single shared copy sat outside all of them and the
instruction did not work. x25emu has the same checker at tests/check_docs.py.

WHAT IT CHECKS

Group 1, every markdown file. These are about the file being correct:

  LINK          a relative link pointing at a file that is not there
  ESCAPES       a relative link that climbs out of the repository root. It resolves on
                the machine it was written on, where the other repository happens to sit
                next door, and 404s for everybody else. Those belong in the text as plain
                paths, not as links.
  ABSPATH       a machine-specific absolute path. A drive letter or a home directory is
                right on exactly one machine, and these repositories are public. This is
                the check that earns its keep: a batch of them was committed with nothing
                looking. A variable - %USERPROFILE%, ~ - is deliberately NOT flagged,
                because that is the portable way to name a per-user location.
  MERMAID       a mermaid block that is malformed or breaks MERMAID_COLOR_STANDARDS.md
  ALT-TEXT      an image with no alt text. It is all a screen reader, and a reader on a
                slow line, ever gets.
  EMOJI-HEADING an emoji in a heading. Three repositories in this organisation use them
                heavily and twenty-nine do not; the majority keeps headings greppable and
                anchor links predictable.
  HAND-TOC      a hand-written Table of Contents. GitHub builds one from the headings and
                puts it behind the outline button, so a hand-written one is duplicate work
                that goes stale. Four repositories here maintain one by hand.
  NEW-HEADING   "(NEW)" in a heading. Nothing ever removes it.

Group 2, the repository's own README.md only. These are about the README following
standards/README-TEMPLATE.md:

  H1            exactly one level-1 heading, and it is the first heading in the file
  BADGES        a badge row near the top
  NAVBAR        an anchor nav bar - three or more links to #anchors on one line
  INSTALL-ORDER "Install" or "Quick start" appears before "Building from source". Six of
                the thirteen biggest READMEs surveyed have both sections and all six order
                them that way. Nobody should read compiler instructions to find a download.
  LICENCE-LAST  the licence section is the last one. Our own repositories break this:
                nd100x runs License, Contributing, TODO; nd500x runs License,
                Acknowledgments, Support.
  ABOUT         an "About <the machine or protocol>" section, for a reader who has never
                heard of it
  STATUS        a "Status" section
  APPS-TABLE    every application folder has a row in the README

WAIVERS

Not every repository has every section, and a section that does not apply should be
absent rather than placeheld. So every check can be waived per file in the JSON file
beside this script - `eng/check-docs.json`. A waiver needs a reason written next to it;
that is the whole point of the file. See check-docs.json for the shape.

Exit status is 0 when everything passes, 1 otherwise.
"""
import io
import json
import os
import re
import sys

LINK = re.compile(r"(!?)\[([^\]]*)\]\(([^)]+)\)")

# The owner-agnostic GitHub link idiom - see the note in check_links.
GITHUB_RELATIVE = re.compile(
    r"^\.\./\.\./"
    r"(releases|issues|pulls|wiki|discussions|actions|tags|commits|blob|tree|compare|graphs|security)"
    r"(/|$)")

# Machine-specific absolute paths. %USERPROFILE% and ~ are deliberately not matched - the
# first version of this pattern wrongly condemned a correct line for using one.
ABSPATH = re.compile(
    r"[A-Za-z]:[\\/](?:Dev|Users|Utils|Tools|Program Files|Windows|ndfs)"
    r"|/home/[A-Za-z0-9_.-]+/"
    r"|/mnt/[a-z]/(?:Dev|Users)",
    re.IGNORECASE)

# Block keywords a matching `end` closes. subgraph is the flowchart one; the rest belong
# to sequenceDiagram. Counting `end` against `subgraph` alone condemns a perfectly good
# sequence diagram, which this checker did once.
OPENERS = r"^\s*(subgraph|loop|alt|opt|par|critical|rect|box)\b"

# Emoji and pictograph ranges. Python's `re` has no \p{Emoji}, so the ranges are spelled
# out. Deliberately NOT included: the arrows block (U+2190-U+21FF) and the plain
# dingbats that read as punctuation, because a heading containing an arrow is text, not
# decoration.
EMOJI = re.compile(
    "["
    "\U0001F300-\U0001FAFF"   # pictographs, emoticons, symbols, supplemental
    "\U0001F000-\U0001F2FF"   # mahjong through enclosed alphanumeric supplement
    "☀-➿"           # miscellaneous symbols and dingbats
    "️"                  # variation selector 16, the "render as emoji" marker
    "⬀-⯿"           # miscellaneous symbols and arrows (stars, etc.)
    "]")

# Directories holding generated or third-party material rather than our documentation.
SKIP = ("/bin/", "/obj/", "/.git/", "/node_modules/", "/packages/", "/TestResults/")

# Files that are scaffolds, not documents. README.template.md is the skeleton
# apply-standards.ps1 drops into a repository to be worked from; it is FULL of
# placeholders such as src/<APP>/README.md on purpose, so checking its links reports a
# finding for every one of them. Checking a scaffold is checking the wrong thing.
SKIP_NAMES = ("README.template.md",)

DEFAULT_CONFIG = {
    "app_folders": ["src"],
    "waivers": [],
}


# --------------------------------------------------------------------------- config

def load_config(script_dir, report):
    """Read check-docs.json from beside this script. A missing file is fine."""
    path = os.path.join(script_dir, "check-docs.json")
    config = dict(DEFAULT_CONFIG)
    if not os.path.exists(path):
        return config
    try:
        raw = json.load(io.open(path, encoding="utf-8"))
    except ValueError as exc:
        # A broken waiver file must NOT silently disable every waiver - that would turn a
        # typo into a wall of failures and teach everybody to ignore the output.
        report.append("CONFIG  check-docs.json is not valid JSON: " + str(exc))
        return config
    for key in ("app_folders", "waivers"):
        if key in raw:
            config[key] = raw[key]
    for w in config["waivers"]:
        if not w.get("reason"):
            report.append("CONFIG  a waiver for " + repr(w.get("files")) +
                          " has no reason. Every waiver needs one.")
    return config


def waived(config, rel, code):
    """Is this check waived for this file?

    `files` entries are matched three ways:
      - a plain path:              "docs/GLASS.md"
      - a suffix:                  "README.md" waives the root README, and
                                   "Desktop/README.md" one particular application's
      - a folder, trailing slash:  "docs/" waives everything under docs/

    The folder form exists because nd100x has 118 markdown files and 767 emoji-heading
    findings in docs/ alone; a waiver that had to list each file would never be written,
    and a waiver that is never written is a check that gets ignored.
    """
    rel = rel.replace(os.sep, "/")
    for w in config["waivers"]:
        if code not in w.get("checks", []):
            continue
        for f in w.get("files", []):
            f = f.replace(os.sep, "/")
            if f.endswith("/"):
                if rel.startswith(f):
                    return True
            elif rel == f or rel.endswith("/" + f):
                return True
    return False


def add(report, config, rel, code, message):
    """Record a finding unless it is waived."""
    if waived(config, rel, code):
        return
    report.append(code.ljust(14) + rel + "  " + message)


# ---------------------------------------------------------------- file gathering

def submodule_paths(root):
    """The `path =` entries of .gitmodules, as repo-relative paths with a trailing slash.

    A file inside a submodule belongs to ANOTHER repository. Reporting it here would invite
    somebody to edit it here, which commits the change to the wrong place - or to nowhere,
    since a submodule's working tree is not this repository's history. nd100x carries six
    submodules and nine of its absolute-path findings were in two of them.
    """
    out = []
    path = os.path.join(root, ".gitmodules")
    if not os.path.exists(path):
        return out
    for line in io.open(path, encoding="utf-8", errors="replace"):
        m = re.match(r"^\s*path\s*=\s*(.+?)\s*$", line)
        if m:
            out.append("/" + m.group(1).strip().replace("\\", "/").strip("/") + "/")
    return out


def markdown_files(root):
    out = []
    skip_dirs = tuple(SKIP) + tuple(submodule_paths(root))
    for base, dirs, files in os.walk(root):
        for name in files:
            if not name.endswith(".md"):
                continue
            if name in SKIP_NAMES:
                continue
            path = os.path.join(base, name)
            rel = "/" + os.path.relpath(path, root).replace(os.sep, "/")
            # SKIP entries match anywhere in the path; submodule entries are anchored
            # at the repository root, because "/external/libdap/" should not also skip a
            # docs folder that happens to contain that string.
            if any(s in rel for s in SKIP):
                continue
            if any(rel.startswith(s) for s in skip_dirs if s not in SKIP):
                continue
            out.append(path)
    return sorted(out)


def headings(lines):
    """Every ATX heading as (level, text, line number), skipping fenced code.

    Fenced code matters: a shell example containing `# comment` is not a heading, and
    counting it as one made an earlier version report two H1s in a correct file.
    """
    out = []
    fence = None
    for n, line in enumerate(lines, 1):
        stripped = line.strip()
        if fence is None and (stripped.startswith("```") or stripped.startswith("~~~")):
            fence = stripped[:3]
            continue
        if fence is not None:
            if stripped.startswith(fence):
                fence = None
            continue
        m = re.match(r"^(#{1,6})\s+(.*?)\s*$", line)
        if m:
            out.append((len(m.group(1)), m.group(2), n))
    return out


# ------------------------------------------------------------- group 1: every file

def check_abspaths(root, path, report, config):
    rel = os.path.relpath(path, root)
    lines = io.open(path, encoding="utf-8", errors="replace").read().split(chr(10))
    for n, line in enumerate(lines, 1):
        if ABSPATH.search(line):
            add(report, config, rel, "ABSPATH",
                ":" + str(n) + "  " + line.strip()[:100])


def check_links(root, path, report, config):
    s = io.open(path, encoding="utf-8", errors="replace").read()

    # An HTML comment is not rendered, so a link inside one is not a link. This matters
    # because README-TEMPLATE.md tells you to park the image block in a comment until the
    # capture exists - and the first version of this check reported that parked block as a
    # broken link in every repository, which is the opposite of helpful.
    #
    # Only the LINK, ESCAPES and ALT-TEXT checks skip comments. ABSPATH deliberately does
    # not: a drive letter sitting in a comment is still in a published file, and will be
    # uncommented by somebody one day.
    s = re.sub(r"<!--.*?-->", "", s, flags=re.S)

    base = os.path.dirname(path)
    rel = os.path.relpath(path, root)
    checked = 0

    for m in LINK.finditer(s):
        is_image = m.group(1) == "!"
        alt = m.group(2)
        target = m.group(3).strip()

        # Alt text: an image link whose label is empty tells a screen reader nothing.
        if is_image and not alt.strip():
            add(report, config, rel, "ALT-TEXT",
                "image has no alt text  ->  " + target)

        if target.startswith(("http://", "https://", "#", "mailto:")):
            continue
        filepart = target.split("#", 1)[0]
        if not filepart:
            continue

        # "../../releases" is a deliberate GitHub idiom, not a broken link. A relative link
        # in a README resolves against https://github.com/<owner>/<repo>/blob/<branch>/, so
        # climbing two levels lands on https://github.com/<owner>/<repo>/ and the rest names
        # a GitHub page. It is how you link your own releases without writing the
        # organisation name, which is exactly what the organisation rename made valuable.
        #
        # yt-dlp and nd100x both use it, and so do the skeletons in this repository - the
        # first version of this check reported our own templates as broken.
        if GITHUB_RELATIVE.match(filepart):
            continue
        # A Windows absolute path in a link is a path, not a relative link. ABSPATH
        # already has an opinion about it.
        if re.match(r"^[A-Za-z]:[\\/]", filepart):
            continue
        filepart = filepart.replace("%20", " ")
        resolved = os.path.normpath(os.path.join(base, filepart))
        checked += 1
        if not os.path.exists(resolved):
            add(report, config, rel, "LINK", "->  " + target)
            continue
        if not os.path.abspath(resolved).startswith(os.path.abspath(root) + os.sep):
            add(report, config, rel, "ESCAPES", "->  " + target +
                "  (resolves here, 404s on GitHub - use a plain path)")
    return checked


def check_headings(root, path, report, config):
    """Emoji, a hand-written contents list, and "(NEW)" - all in headings."""
    rel = os.path.relpath(path, root)
    lines = io.open(path, encoding="utf-8", errors="replace").read().split(chr(10))
    for level, text, n in headings(lines):
        if EMOJI.search(text):
            add(report, config, rel, "EMOJI-HEADING",
                ":" + str(n) + "  " + text[:60])
        if is_hand_written_toc(lines, text, n):
            add(report, config, rel, "HAND-TOC", ":" + str(n) +
                "  GitHub builds one from the headings; this one will go stale")
        if "(NEW)" in text.upper():
            add(report, config, rel, "NEW-HEADING", ":" + str(n) +
                "  a heading marked NEW is never un-marked; date it in the text instead")


def is_hand_written_toc(lines, text, n):
    """A contents heading FOLLOWED BY links to anchors in this same document.

    The heading alone is not enough, and this is not a hypothetical: the first version of
    this check matched the word "Contents" and reported 35 correct RetroIO package READMEs,
    every one of which uses `## Contents` to mean "the types this package holds" - a table
    of the package's contents, which is not a table of contents at all. Matching the word
    instead of the construct would have turned a passing checker into 35 edits to correct
    files.

    So: the heading must look like a contents heading AND the lines under it, up to the
    next heading, must actually carry links to `#anchors`. That is the construct.
    """
    if not re.match(r"^\(?(table of contents|contents|toc)\)?$", text.strip(), re.I):
        return False
    anchors = 0
    for line in lines[n:]:
        if re.match(r"^#{1,6}\s", line):
            break
        anchors += len(re.findall(r"\]\(#[^)]+\)", line))
    return anchors >= 3


def check_mermaid(root, path, report, config):
    lines = io.open(path, encoding="utf-8", errors="replace").read().split(chr(10))
    rel = os.path.relpath(path, root)
    inside = False
    block = []
    start = 0
    blocks = 0

    for n, line in enumerate(lines, 1):
        if not inside and line.strip() == "```mermaid":
            inside, block, start = True, [], n
            continue
        if inside and line.strip() == "```":
            inside = False
            blocks += 1
            body = chr(10).join(block)
            where = ":" + str(start) + "  "

            subs = len(re.findall(OPENERS, body, re.M))
            ends = len(re.findall(r"^\s*end\s*$", body, re.M))
            if subs != ends:
                add(report, config, rel, "MERMAID", where + "block openers=" +
                    str(subs) + " end=" + str(ends) + " MISMATCH")

            # Mermaid allows a trailing semicolon on a `class` line, and some documents
            # use them. A regex anchored at end-of-line reports four dead classDefs in a
            # diagram that uses all four. Read the diagram before believing this.
            defined = set(re.findall(r"classDef\s+(\w+)", body))
            used = set()
            for m in re.finditer(r"^\s*class\s+([\w,\s]+?)\s+(\w+)\s*;?\s*$", body, re.M):
                used.add(m.group(2))
            for role in sorted(used - defined):
                add(report, config, rel, "MERMAID",
                    where + "class uses undefined role '" + role + "'")
            for role in sorted(defined - used):
                add(report, config, rel, "MERMAID",
                    where + "classDef '" + role + "' is never used")

            for m in re.finditer(r"(classDef\s+\w+|style\s+\w+)\s+(.+)", body):
                for want in ("fill:", "stroke:", "color:"):
                    if want not in m.group(2):
                        add(report, config, rel, "MERMAID",
                            where + m.group(1) + " is missing " + want)

            if "theme" in body:
                add(report, config, rel, "MERMAID", where + "forces a mermaid theme")
            continue
        if inside:
            block.append(line)

    if inside:
        add(report, config, rel, "MERMAID",
            ":" + str(start) + "  UNCLOSED mermaid fence")
    return blocks


# ------------------------------------------------- group 2: the root README only

def check_readme_structure(root, path, report, config):
    """The README follows standards/README-TEMPLATE.md.

    Only the repository's own README.md is judged on this. A per-application README
    follows the shortened spine and has no badge row or nav bar of its own, so holding it
    to this would report a finding on a correct file.
    """
    rel = os.path.relpath(path, root)
    text = io.open(path, encoding="utf-8", errors="replace").read()
    lines = text.split(chr(10))
    heads = headings(lines)

    # --- H1: exactly one, and first --------------------------------------------
    h1 = [h for h in heads if h[0] == 1]
    if len(h1) != 1:
        add(report, config, rel, "H1",
            "found " + str(len(h1)) + " level-1 headings, expected exactly 1")
    elif heads and heads[0][0] != 1:
        add(report, config, rel, "H1",
            "the first heading is level " + str(heads[0][0]) + ", not the title")

    # --- badge row -------------------------------------------------------------
    # Two or more badge images anywhere in the first 40 lines - NOT two on the same line.
    # The first version required them on one line and then failed this repository's own
    # README, because README-TEMPLATE.md prescribes one badge per line and so do 86Box,
    # dosbox-staging and Avalonia. A check that fails the format the standard prescribes is
    # a bug in the check.
    #
    # Looking for the images rather than for the word "badge" is what makes this survive a
    # centred HTML block, which four of the surveyed repositories use.
    badges = 0
    for line in lines[:40]:
        badges += len(re.findall(r"img\.shields\.io|badge\.svg|badges\.", line))
    if badges < 2:
        add(report, config, rel, "BADGES",
            "found " + str(badges) + " badge image(s) in the first 40 lines, expected at "
            "least 2 (build, release, licence, downloads)")

    # --- anchor nav bar --------------------------------------------------------
    nav = False
    for line in lines[:60]:
        if len(re.findall(r"\]\(#[^)]+\)", line)) >= 3:
            nav = True
            break
    if not nav:
        add(report, config, rel, "NAVBAR",
            "no anchor nav bar in the first 60 lines (3 or more #links on one line)")

    # --- install before build --------------------------------------------------
    h2 = [(t, n) for lvl, t, n in heads if lvl == 2]
    first_install = None
    first_build = None
    for t, n in h2:
        low = t.lower()
        if first_install is None and re.search(r"\b(install|download|quick start)\b", low):
            first_install = n
        if first_build is None and re.search(r"build(ing)?\s+from\s+source|^building\b", low):
            first_build = n
    if first_install is not None and first_build is not None and first_build < first_install:
        add(report, config, rel, "INSTALL-ORDER",
            "building from source (line " + str(first_build) + ") comes before install (line " +
            str(first_install) + ")")

    # --- licence last ----------------------------------------------------------
    if h2:
        lic = [n for t, n in h2 if re.search(r"licen[cs]e", t, re.I)]
        if not lic:
            add(report, config, rel, "LICENCE-LAST", "no licence section")
        elif lic[-1] != h2[-1][1]:
            add(report, config, rel, "LICENCE-LAST",
                "the licence section is at line " + str(lic[-1]) + " but '" +
                h2[-1][0] + "' at line " + str(h2[-1][1]) + " comes after it")

    # --- the two required sections --------------------------------------------
    if not any(re.match(r"about\b", t.strip(), re.I) for t, _ in h2):
        add(report, config, rel, "ABOUT",
            "no 'About <the machine or protocol>' section - a reader may never have "
            "heard of it")
    if not any(re.match(r"status\b", t.strip(), re.I) for t, _ in h2):
        add(report, config, rel, "STATUS",
            "no 'Status' section - a version and a measured fact or two")

    # --- every application has a row ------------------------------------------
    for app in application_folders(root, config):
        # The name has to appear as link text or in a link target; a bare mention in a
        # paragraph is not a row in a table, but matching the folder name anywhere in the
        # file is the check that does not need to parse a table.
        if app not in text:
            add(report, config, rel, "APPS-TABLE",
                "the application '" + app + "' is not mentioned - every application "
                "needs a row linking its own README")


def application_folders(root, config):
    """Immediate subdirectories of each app folder that build an EXECUTABLE.

    An application is a project that declares <OutputType>Exe</OutputType> or WinExe. A
    project file alone is not enough, and this is not a hypothetical: the first version of
    this check counted RetroCommander.Core - a class library sitting beside the desktop
    application - and demanded a row for it in the README. A library is not an application
    and does not belong in that table.

    Configurable because not every repository puts its applications under src/. A
    repository with no executable projects yields nothing, which is why this is safe to
    run on a C repository, and on a library repository such as RetroIO whose src/ holds
    packages rather than programs.
    """
    out = []
    for parent in config.get("app_folders", []):
        base = os.path.join(root, parent.replace("/", os.sep))
        if not os.path.isdir(base):
            continue
        for name in sorted(os.listdir(base)):
            d = os.path.join(base, name)
            if not os.path.isdir(d):
                continue
            for f in sorted(os.listdir(d)):
                if not f.endswith((".csproj", ".fsproj", ".vbproj")):
                    continue
                try:
                    text = io.open(os.path.join(d, f), encoding="utf-8",
                                   errors="replace").read()
                except IOError:
                    continue
                if re.search(r"<OutputType>\s*(Win)?Exe\s*</OutputType>", text, re.I):
                    out.append(name)
                    break
    return out


# ---------------------------------------------------------------------------- main

def main():
    # A finding quotes the offending line, and an EMOJI-HEADING finding quotes an emoji. On a
    # Windows console the default output encoding is cp1252, which cannot write one, so the
    # checker died with UnicodeEncodeError while PRINTING its own report - after doing all the
    # work, and before the summary line. Measured 28 September 2026 on RetroTerm. Write UTF-8
    # and replace what the console still cannot show, rather than crash.
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass  # a stream without reconfigure (older Python, or redirected oddly): leave it

    root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
    if not os.path.isdir(root):
        print("not a directory: " + root)
        return 1

    script_dir = os.path.dirname(os.path.abspath(__file__))
    report = []
    config = load_config(script_dir, report)

    links = 0
    blocks = 0
    files = markdown_files(root)
    root_readme = os.path.join(root, "README.md")

    for path in files:
        check_abspaths(root, path, report, config)
        check_headings(root, path, report, config)
        links += check_links(root, path, report, config)
        blocks += check_mermaid(root, path, report, config)
        if os.path.abspath(path) == os.path.abspath(root_readme):
            check_readme_structure(root, path, report, config)

    for line in report:
        print(line)

    apps = application_folders(root, config)
    print("")
    print(os.path.basename(root) + ": " + str(len(files)) + " markdown file(s), " +
          str(links) + " relative link(s), " + str(blocks) + " mermaid block(s), " +
          str(len(apps)) + " application(s)")
    if report:
        print(str(len(report)) + " problem(s)")
        print("A section that genuinely does not apply is waived in check-docs.json, "
              "with a reason.")
        return 1
    print("no problems")
    return 0


if __name__ == "__main__":
    sys.exit(main())
