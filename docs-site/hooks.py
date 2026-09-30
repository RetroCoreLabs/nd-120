"""
MkDocs hooks for the ND-120 docs site (docs-site/mkdocs.yml).

WHY THIS EXISTS
    MkDocs turns a Markdown link to a page (foo.md) into the page's address on
    the site (foo/). It does NOT look inside raw HTML, and it does not look
    inside SVG pictures. Two kinds of generated content use such links on
    purpose, because they must also work on github.com:

    - Verilog/HIERARCHY.md: the module tree is nested HTML lists with
      <details> so it can be folded, and every node is <a href="...md">.
    - <folder>/doc/<Module>.svg: in each schematic, every sub-module box is
      <a href="...md"> to that module's page.

    Without this hook every one of those links would be a dead link on the
    site. With it they are rewritten to the real page address, and a link to
    a page that does not exist is reported as a WARNING - so a
    `mkdocs build --strict` fails on it, exactly like a broken Markdown link.

    Only relative links ending in .md (with an optional #anchor) are touched.

    FOLDER LINKS. On github.com a link to a folder ([mem-test](mem-test/))
    opens the folder listing. The site has no folder listings, so before
    MkDocs reads a page such a link is pointed at the folder's README.md when
    it has one, and otherwise at the folder on GitHub. The same is done for a
    link to a file that is in the repository but not part of the site
    (a workflow under .github/, say): it goes to the file on GitHub.

Last reviewed: 30-SEP-2026
Ronny Hansen
"""

import logging
import os
import posixpath
import re

log = logging.getLogger("mkdocs.hooks.nd120")

HREF_RE = re.compile(r'(href|xlink:href)="([^"#:]+\.md)(#[^"]*)?"')

_files = None

GITHUB = "https://github.com/RetroCoreLabs/nd-120/"
MD_LINK_RE = re.compile(r"(\]\()([^)\s#]+)(#[^)\s]*)?(\s+\"[^\"]*\")?\)")
FENCE_RE = re.compile(r"^(```+|~~~+)")


def _target(files, from_src_uri, link):
    """The File a relative .md link points at, or None."""
    src = posixpath.normpath(posixpath.join(posixpath.dirname(from_src_uri), link))
    return files.get_file_from_path(src)


def _rel_url(target_url, from_url):
    """Address of target_url relative to the page/file at from_url."""
    base = from_url if from_url.endswith("/") else posixpath.dirname(from_url) + "/"
    if base == "/":
        base = ""
    rel = posixpath.relpath("/" + target_url, "/" + base) if base else target_url
    if target_url.endswith("/") and not rel.endswith("/"):
        rel += "/"
    if rel == "./" or rel == ".":
        rel = "./"
    return rel


def _rewrite(text, files, src_uri, from_url, what):
    def repl(m):
        attr, link, anchor = m.group(1), m.group(2), m.group(3) or ""
        f = _target(files, src_uri, link)
        if f is None or f.inclusion.is_excluded():
            log.warning("%s: raw HTML link to '%s', which is not a page of the site",
                        what, link)
            return m.group(0)
        return '%s="%s%s"' % (attr, _rel_url(f.url, from_url), anchor)
    return HREF_RE.sub(repl, text)


def _repo_root(config):
    return os.path.abspath(config["docs_dir"])


def on_page_markdown(markdown, page, config, files):
    """Folder links and links to repository files that are not on the site
    (see FOLDER LINKS above). Code blocks are left alone."""
    root = _repo_root(config)
    here = os.path.dirname(page.file.abs_src_path)
    out = []
    fence = None
    for line in markdown.split("\n"):
        m = FENCE_RE.match(line.lstrip())
        if m:
            if fence is None:
                fence = m.group(1)[0] * len(m.group(1))
            elif line.lstrip().startswith(fence):
                fence = None
            out.append(line)
            continue
        if fence is not None or "](" not in line:
            out.append(line)
            continue

        def repl(m):
            link = m.group(2)
            if re.match(r"^[a-z][a-z0-9+.-]*:", link, re.I) or link.startswith("/"):
                return m.group(0)
            target = os.path.normpath(os.path.join(here, link))
            relp = os.path.relpath(target, root).replace(os.sep, "/")
            if relp.startswith(".."):
                return m.group(0)
            anchor = m.group(3) or ""
            title = m.group(4) or ""
            if os.path.isdir(target):
                for readme in ("README.md", "readme.md", "Readme.md", "index.md"):
                    rp = os.path.join(target, readme)
                    if os.path.exists(rp) and files.get_file_from_path(
                            relp.rstrip("/") + "/" + readme if relp != "." else readme):
                        new = posixpath.join(link.rstrip("/"), readme)
                        return "%s%s%s%s)" % (m.group(1), new, anchor, title)
                return "%s%stree/main/%s%s)" % (m.group(1), GITHUB, relp, title)
            if os.path.isfile(target) and files.get_file_from_path(relp) is None:
                return "%s%sblob/main/%s%s%s)" % (m.group(1), GITHUB, relp, anchor, title)
            return m.group(0)
        out.append(MD_LINK_RE.sub(repl, line))
    return "\n".join(out)


def on_files(files, config):
    global _files
    _files = files
    return files


def on_page_content(html, page, config, files):
    # MkDocs has already rewritten every Markdown link; what is left ending
    # in .md is in raw HTML
    return _rewrite(html, files, page.file.src_uri, page.url, page.file.src_uri)


def on_post_build(config):
    """The schematics are copied as they are; rewrite the page links in
    them in the built site."""
    if _files is None:
        return
    n = 0
    for f in _files:
        if not f.src_uri.endswith(".svg") or "/doc/" not in "/" + f.src_uri:
            continue
        path = os.path.join(config["site_dir"], f.dest_uri)
        try:
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
        except (OSError, UnicodeDecodeError):
            continue
        if ".md" not in text:
            continue
        new = _rewrite(text, _files, f.src_uri, f.url, f.src_uri)
        if new != text:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(new)
            n += 1
    log.info("schematic page links rewritten in %d SVG files", n)
