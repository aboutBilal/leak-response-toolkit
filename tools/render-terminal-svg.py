#!/usr/bin/env python3
"""Render captured terminal output as an SVG image for the README.

The images in assets/ are made from REAL command output, never typed by hand:

    NO_COLOR=1 ./leak audit some-repo > out.txt
    python3 tools/render-terminal-svg.py out.txt assets/demo-audit.svg \
        --command './leak audit legacy-api' --title 'real output'

Lines are coloured by their first characters (✔ ✘ ! → ==> $ ...).
"""
import argparse
import html
import re

COLOURS = [
    (r"^\$ ", "#e6edf3", "700"),
    (r"^==>", "#79c0ff", "700"),
    (r"^\s*✔", "#56d364", "400"),
    (r"^\s*✘", "#ff7b72", "700"),
    (r"^\s*!", "#f0b72f", "400"),
    (r"^\s*→", "#8b949e", "400"),
    (r"^WRN", "#f0b72f", "400"),
    (r"^RULE", "#8b949e", "700"),
    (r"^Score:.*Grade [AB]", "#56d364", "700"),
    (r"^Score:", "#ff7b72", "700"),
    (r"^Next:", "#56d364", "700"),
    (r"^(Secret hygiene audit|\d\. )", "#e6edf3", "700"),
    (r"^\s+(aws|slack|generic|private|github|gcp|stripe)-", "#ffa657", "400"),
    (r"^(aws|slack|generic|private|github|gcp|stripe)-", "#ffa657", "400"),
]


def colour(line):
    for pattern, fill, weight in COLOURS:
        if re.search(pattern, line):
            return fill, weight
    return "#c9d1d9", "400"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--command", required=True, help="the command shown on the first line")
    ap.add_argument("--title", default="real output")
    ap.add_argument("--width", type=int, default=1000)
    args = ap.parse_args()

    lines = [l.rstrip("\n") for l in open(args.input, encoding="utf-8")]
    lines = [re.sub(r"\x1b\[[0-9;]*m", "", l) for l in lines]
    lines = [f"$ {args.command}"] + lines
    width, line_height, top = args.width, 22, 58
    height = top + line_height * len(lines) + 24
    mono = "ui-monospace,SFMono-Regular,Menlo,Consolas,'Liberation Mono',monospace"
    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-label="Terminal: {html.escape(args.command)}">',
        '<rect width="100%" height="100%" rx="12" fill="#0d1117"/>',
        '<rect width="100%" height="38" rx="12" fill="#161b22"/><rect y="26" width="100%" height="12" fill="#161b22"/>',
        '<circle cx="22" cy="19" r="6" fill="#ff5f56"/><circle cx="42" cy="19" r="6" fill="#ffbd2e"/><circle cx="62" cy="19" r="6" fill="#27c93f"/>',
        f'<text x="{width / 2}" y="24" fill="#8b949e" font-family="{mono}" font-size="13" text-anchor="middle">leak-response-toolkit · {html.escape(args.title)}</text>',
        f'<g font-family="{mono}" font-size="14.5">',
    ]
    for i, line in enumerate(lines):
        fill, weight = colour(line)
        out.append(f'<text style="white-space:pre" x="24" y="{top + i * line_height}" fill="{fill}" font-weight="{weight}">{html.escape(line)}</text>')
    out.append("</g></svg>")
    with open(args.output, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
