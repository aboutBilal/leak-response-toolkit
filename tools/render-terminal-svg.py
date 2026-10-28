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

# Design tokens: assets/DESIGN.md. Status colours only for status; everything else neutral.
INK_900, INK_800, INK_700, INK_500, INK_300, INK_100 = "#111827", "#1C2433", "#2B3445", "#828D9F", "#A3ADBF", "#E6EAF2"
EMBER_400, PASS, WARN, FAIL = "#FF8A5C", "#3FB950", "#D29922", "#F85149"

COLOURS = [
    (r"^\s*✔", PASS, "400"),
    (r"^\s*✘", FAIL, "600"),
    (r"^\s*!", WARN, "400"),
    (r"^\s*~", WARN, "400"),
    (r"^\s*→", INK_500, "400"),
    (r"^WRN", WARN, "400"),
    (r"^RULE", INK_500, "600"),
    (r"^#\s+TIER", INK_500, "600"),
    (r"^Score.*Grade [AB]\b", PASS, "700"),
    (r"^Score", FAIL, "700"),
    (r"^(==>|Next:|Secret hygiene audit|Incident |\d\. )", INK_100, "600"),
    (r"^\s*(aws|slack|generic|private|github|gcp|stripe)-", FAIL, "400"),
]


def colour(line):
    for pattern, fill, weight in COLOURS:
        if re.search(pattern, line):
            return fill, weight
    return INK_300, "400"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--command", required=True, help="the command shown on the first line")
    ap.add_argument("--title", default="real output")
    ap.add_argument("--width", type=int, default=1000)
    ap.add_argument("--animate", action="store_true", help="reveal lines one by one, like a live session (respects prefers-reduced-motion)")
    ap.add_argument("--step", type=float, default=0.22, help="seconds between lines when animating")
    args = ap.parse_args()

    lines = [l.rstrip("\n") for l in open(args.input, encoding="utf-8")]
    lines = [re.sub(r"\x1b\[[0-9;]*m", "", l) for l in lines]
    lines = [f"$ {args.command}"] + lines
    width, line_height, top = args.width, 24, 72
    height = top + line_height * len(lines) + 16
    mono = "'JetBrains Mono',ui-monospace,SFMono-Regular,Menlo,Consolas,'Liberation Mono',monospace"
    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-label="Terminal: {html.escape(args.command)}">',
        f'<rect x="0.5" y="0.5" width="{width - 1}" height="{height - 1}" rx="12" fill="{INK_900}" stroke="{INK_700}"/>',
        f'<path d="M12.5 0.5 H{width - 12.5} A12 12 0 0 1 {width - 0.5} 12.5 V40 H0.5 V12.5 A12 12 0 0 1 12.5 0.5 Z" fill="{INK_800}"/>',
        f'<circle cx="24" cy="20" r="5" fill="{INK_700}"/><circle cx="42" cy="20" r="5" fill="{INK_700}"/><circle cx="60" cy="20" r="5" fill="{INK_700}"/>',
        f'<text x="{width / 2}" y="25" fill="{INK_500}" font-family="{mono}" font-size="13" text-anchor="middle">{html.escape(args.title)}</text>',
    ]
    if args.animate:
        out.append(
            "<style>"
            ".ln{opacity:0;animation:reveal .25s ease-out forwards}"
            "@keyframes reveal{from{opacity:0;transform:translateY(4px)}to{opacity:1;transform:none}}"
            ".cur{opacity:0}@keyframes show{to{opacity:1}}@keyframes blink{50%{opacity:0}}"
            "@media (prefers-reduced-motion: reduce){.ln{opacity:1;animation:none}.cur{opacity:1;animation:none}}"
            "</style>"
        )
    out.append(f'<g font-family="{mono}" font-size="14.5" style="font-variant-ligatures:none">')
    for i, line in enumerate(lines):
        fill, weight = colour(line)
        # The command line types first; output follows after a short pause.
        delay = 0 if i == 0 else 0.6 + i * args.step
        anim = f' class="ln" style="white-space:pre;animation-delay:{delay:.2f}s"' if args.animate else ' style="white-space:pre"'
        x, y = 24, top + i * line_height
        if i == 0:  # prompt in ember, command in primary text
            out.append(f'<text{anim} x="{x}" y="{y}" font-weight="600"><tspan fill="{EMBER_400}">$</tspan><tspan fill="{INK_100}">{html.escape(line[1:])}</tspan></text>')
        elif m := re.match(r"^(\s*)([✔✘])(.*)$", line):
            # Fonts draw these marks wider than one column; pin the mark and what follows to
            # the character grid so the columns after it line up with the other lines.
            indent, mark, rest = m.groups()
            cw = 14.5 * 0.6  # one column of a monospace font at this size
            mx = x + len(indent) * cw
            out.append(f'<text{anim} x="{x}" y="{y}" fill="{fill}" font-weight="{weight}">'
                       f'<tspan x="{mx:.1f}" font-size="12">{mark}</tspan><tspan x="{mx + cw:.1f}">{html.escape(rest)}</tspan></text>')
        else:
            out.append(f'<text{anim} x="{x}" y="{y}" fill="{fill}" font-weight="{weight}">{html.escape(line)}</text>')
    if args.animate:
        y = top + (len(lines) - 1) * line_height
        end = 0.6 + len(lines) * args.step
        out.append(f'<rect class="cur" x="24" y="{y + 8}" width="9" height="3" fill="{PASS}" style="animation:show 0s {end:.2f}s forwards,blink 1s steps(1) {end:.2f}s infinite"/>')
    out.append("</g></svg>")
    with open(args.output, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
