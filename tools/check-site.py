#!/usr/bin/env python3
"""Check the built documentation site before it is deployed.

  - every internal link and image resolves to a file in the site;
  - every #anchor on an internal link exists on the target page;
  - every page built from a layout has a title, a description, a language
    and exactly one h1, and every image has alt text;
  - every entry in search.json points at a section that exists.

Links to scripts and config files are rewritten to GitHub by site.js at run
time, so they are skipped here (lychee checks them in the Markdown sources).

Usage: tools/check-site.py <built-site-dir> [--base /leak-response-toolkit]
Exit:  0 all checks passed, 1 problems found, 2 bad arguments
"""
import json
import os
import re
import sys
from html.parser import HTMLParser
from urllib.parse import unquote, urlsplit

# Keep in step with sourceExt in site/assets/site.js.
SOURCE = re.compile(r"\.(sh|ya?ml|py|toml|bats|cff|example|json|css|js)$|/(leak|Makefile|Dockerfile|LICENSE|gitignore-secrets|dockerignore|pre-commit)$|/(ci|oidc|docker|env|hooks)/?$")


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids, self.links, self.imgs = set(), [], []
        self.lang = self.title = self.desc = None
        self.h1 = 0
        self.layout = False
        self._in_title = False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if "id" in a:
            self.ids.add(a["id"])
        if tag == "a" and "name" in a:
            self.ids.add(a["name"])
        if tag == "html":
            self.lang = a.get("lang")
        elif tag == "title":
            self._in_title = True
        elif tag == "meta" and a.get("name") == "description":
            self.desc = a.get("content")
        elif tag == "h1":
            self.h1 += 1
        elif tag == "body" and "data-base" in a:
            self.layout = True
        elif tag == "img":
            self.imgs.append(a)
            self.links.append((tag, a.get("src", "")))
        elif tag in ("a", "link") and a.get("href"):
            if tag == "link" and a.get("rel") not in ("stylesheet", "icon", "preload"):
                return
            self.links.append((tag, a["href"]))
        elif tag == "script" and a.get("src"):
            self.links.append((tag, a["src"]))

    def handle_endtag(self, tag):
        if tag == "title":
            self._in_title = False

    def handle_data(self, data):
        if self._in_title:
            self.title = (self.title or "") + data


def main(argv):
    args = [a for a in argv[1:]]
    base = "/leak-response-toolkit"
    if "--base" in args:
        i = args.index("--base")
        if i + 1 >= len(args):
            print("--base needs a value", file=sys.stderr)
            return 2
        base = args[i + 1].rstrip("/")
        del args[i:i + 2]
    if len(args) != 1 or args[0] in ("-h", "--help") or not os.path.isdir(args[0]):
        print(__doc__.strip(), file=sys.stderr)
        return 0 if args and args[0] in ("-h", "--help") else 2
    root = os.path.abspath(args[0])

    pages = {}
    for d, _, files in os.walk(root):
        for f in files:
            if f.endswith(".html"):
                path = os.path.join(d, f)
                p = Page()
                with open(path, encoding="utf-8", errors="replace") as fh:
                    p.feed(fh.read())
                pages["/" + os.path.relpath(path, root).replace(os.sep, "/")] = p

    def resolve(site_path):
        """Site path (without base) to (page key, exists)."""
        if site_path.endswith("/"):
            site_path += "index.html"
        full = os.path.join(root, site_path.lstrip("/"))
        return site_path, os.path.exists(full)

    problems = []
    for key, p in sorted(pages.items()):
        if p.layout:
            if not p.lang:
                problems.append(f"{key}: <html> has no lang")
            if not (p.title or "").strip():
                problems.append(f"{key}: no <title>")
            if not (p.desc or "").strip():
                problems.append(f"{key}: no meta description")
            if p.h1 != 1:
                problems.append(f"{key}: {p.h1} h1 elements (expected 1)")
            for img in p.imgs:
                if "alt" not in img:
                    problems.append(f"{key}: image without alt: {img.get('src')}")
        for tag, link in p.links:
            u = urlsplit(link)
            if u.scheme or link.startswith("//") or link.startswith(("mailto:", "data:")):
                continue
            if u.path == "" and u.fragment:
                if p.layout and u.fragment not in p.ids:
                    problems.append(f"{key}: missing anchor #{u.fragment}")
                continue
            if u.path.startswith("/"):
                if not u.path.startswith(base + "/") and u.path != base:
                    problems.append(f"{key}: link outside the site base: {link}")
                    continue
                target = u.path[len(base):] or "/"
            else:
                target = os.path.normpath(os.path.join(os.path.dirname(key), unquote(u.path))).replace(os.sep, "/")
            if tag == "a" and SOURCE.search(target):
                continue
            target, ok = resolve(unquote(target))
            if not ok:
                problems.append(f"{key}: broken link: {link}")
            elif u.fragment and target in pages and u.fragment not in pages[target].ids:
                problems.append(f"{key}: missing anchor: {link}")

    index = os.path.join(root, "search.json")
    if os.path.exists(index):
        with open(index, encoding="utf-8") as fh:
            entries = json.load(fh)
        for e in entries:
            path, _, frag = e["u"].partition("#")
            if path not in pages:
                problems.append(f"search.json: page not built: {e['u']}")
            elif frag and frag not in pages[path].ids:
                problems.append(f"search.json: missing anchor: {e['u']}")
    else:
        problems.append("search.json is missing")

    for line in problems:
        print(line)
    print(f"checked {len(pages)} pages: {'no problems' if not problems else f'{len(problems)} problem(s)'}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
