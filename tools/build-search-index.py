#!/usr/bin/env python3
"""Build the documentation search index from the Markdown pages.

Each page is split at its level 2 and 3 headings, so a search result opens
the right section. Anchors follow the GitHub-style IDs that kramdown (GFM
input) generates; tools/check-site.py verifies every one after the build.

Usage: tools/build-search-index.py <output.json> <page.md> [<page.md> ...]
       Paths are relative to the repository root (the current folder).
"""
import json
import re
import sys

HEADING = re.compile(r"^(#{1,6})\s+(.+?)\s*#*\s*$")
FENCE = re.compile(r"^\s*(```|~~~)")


def plain(text):
    """Markdown inline syntax to plain text. Code spans are kept literally."""
    text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", text)     # images and links, even around code
    parts = re.split(r"(`+)(.+?)\1", text)
    out = []
    for i in range(0, len(parts), 3):
        out.append(_strip(parts[i]))
        if i + 2 < len(parts):
            out.append(parts[i + 2])
    return "".join(out)


def _strip(text):
    text = re.sub(r"!\[([^\]]*)\]\([^)]*\)", r"\1", text)        # images
    text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", text)         # links
    text = re.sub(r"\[([^\]]+)\]\[[^\]]*\]", r"\1", text)        # reference links
    text = re.sub(r"<[^>]+>", " ", text)                         # HTML tags
    text = re.sub(r"\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]", " ", text)
    text = re.sub(r"(\*\*|__)", "", text)
    text = re.sub(r"(?<![\w*])\*(?!\s)([^*]+)(?<!\s)\*", r"\1", text)
    return text


def slug(text, seen):
    """GitHub-style heading ID, as kramdown's GFM parser generates it."""
    base = re.sub(r"[^\w\- \t]", "", plain(text).strip().lower()).replace(" ", "-").replace("\t", "-")
    n = seen.get(base, 0)
    seen[base] = n + 1
    return base if n == 0 else f"{base}-{n}"


def nav_titles(path="site/_data/nav.yml"):
    """Page titles from the site navigation: {url: title}."""
    titles = {}
    try:
        with open(path, encoding="utf-8") as f:
            for m in re.finditer(r"title:\s*([^,}]+?)\s*,\s*url:\s*([^\s}]+)", f.read()):
                titles[m.group(2)] = m.group(1).strip()
    except OSError:
        pass
    return titles


NAV = nav_titles()


def url_for(path):
    return "/overview.html" if path == "README.md" else "/" + re.sub(r"\.md$", ".html", path)


def sections(path):
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    url = url_for(path)
    title, seen, out = None, {}, []
    current = {"heading": "", "anchor": "", "lines": []}
    fenced = False
    for line in lines:
        if FENCE.match(line):
            fenced = not fenced
            continue
        m = None if fenced else HEADING.match(line)
        if m and len(m.group(1)) == 1 and title is None:
            title = plain(m.group(2)).strip()
            slug(m.group(2), seen)
            continue
        if m and len(m.group(1)) in (2, 3):
            out.append(current)
            heading = m.group(2)
            current = {"heading": plain(heading).strip(), "anchor": slug(heading, seen), "lines": []}
            continue
        if m:
            slug(m.group(2), seen)  # keep the ID counter in step with kramdown
        line = re.sub(r"^\s*(>\s?)+", "", line)                  # blockquotes
        line = re.sub(r"^\s*([-*+]|\d+\.)\s+(\[[ xX]\]\s+)?", "", line)  # list markers, task boxes
        if re.match(r"^\s*\|?\s*:?-{3,}", line):                  # table separator rows
            continue
        current["lines"].append(plain(line.replace("|", " ")))
    out.append(current)
    title = NAV.get(url) or title or path
    entries = []
    for s in out:
        text = re.sub(r"\s+", " ", " ".join(s["lines"])).strip()
        if not text and not s["heading"]:
            continue
        entries.append({
            "t": title,
            "h": s["heading"],
            "u": url + ("#" + s["anchor"] if s["anchor"] else ""),
            "x": text,
        })
    return entries


def main(argv):
    if len(argv) < 3 or argv[1] in ("-h", "--help"):
        print(__doc__.strip())
        return 0 if len(argv) > 1 and argv[1] in ("-h", "--help") else 2
    index = []
    for path in argv[2:]:
        index.extend(sections(path))
    with open(argv[1], "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, separators=(",", ":"))
    print(f"search index: {argv[1]} ({len(index)} sections)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
