# Visual language

The images, reports and dashboards in this repository share one small design system. Use it for anything new.

## Principle: calm signal

People open this toolkit during an incident. The visuals should be quiet, legible and honest, so that what matters stands out without effort.

- **Colour carries meaning.** Status colours appear only where something passed, needs attention or failed. Nothing is coloured for decoration.
- **One accent.** Ember is the only brand colour. Use it for the mark, step numbers, the command prompt and at most one call to action per image.
- **Neutrals do the work.** Roughly 60% background, 30% surfaces and text, 10% accent and status.
- **Hierarchy through type, not effects.** In images, reports and dashboards: no glows, textures, gradients (except the mark's highlight) or drop shadows beyond the single elevation below. The website has a small, documented allowance for depth; see [Website](#website).
- **Flush left, on a grid.** 8-point spacing. Text aligns to a common left edge.
- **Real content only.** Every terminal image is rendered from captured output with [`tools/render-terminal-svg.py`](../tools/render-terminal-svg.py).

## Tokens

### Colour: dark surfaces (README images)

| Token | Hex | Use |
|---|---|---|
| `ink-950` | `#0B0F1A` | Background |
| `ink-900` | `#111827` | Cards, terminal surface |
| `ink-800` | `#1C2433` | Raised elements: title bars, chips |
| `ink-700` | `#2B3445` | Hairline borders, inactive dots |
| `ink-500` | `#828D9F` | Tertiary text, arrows, hints (4.6:1 or better on every dark surface) |
| `ink-300` | `#A3ADBF` | Secondary text |
| `ink-100` | `#E6EAF2` | Primary text |
| `ember-500` | `#FF6B3D` | Brand mark |
| `ember-400` | `#FF8A5C` | Accent text on dark (prompt, step numbers) |
| `pass` | `#3FB950` | Passed check, grades A–B |
| `warn` | `#D29922` | Needs attention, grades C–D |
| `fail` | `#F85149` | Failed check, grade F, findings |

### Colour: light surfaces (reports and dashboards)

| Token | Hex | Use |
|---|---|---|
| `paper` | `#FFFFFF` | Page |
| `wash` | `#F6F7F9` | Table headers, tracks |
| `line` | `#E3E7EE` | Hairlines |
| `text` | `#111827` | Primary text and headings |
| `text-2` | `#4B5565` | Secondary text |
| `muted` | `#667183` | Notes, labels (4.6:1 on `paper` and `wash`) |
| `ember-700` | `#C2410C` | Accent text on white (4.9:1) |
| `pass` / `pass-tint` | `#1A7F37` / `#DAFBE1` | Passed |
| `warn` / `warn-tint` | `#9A6700` / `#FFF8C5` | Needs attention; fields to complete |
| `fail` / `fail-tint` | `#CF222E` / `#FFEBE9` | Failed |

All text meets WCAG AA contrast (4.5:1) on its background.

### Type

| Role | Family | Sizes |
|---|---|---|
| Text | Inter, then the system sans-serif | 13 · 16 · 20 · 25 · 32 · 40 · 52 |
| Code and commands | JetBrains Mono, then the system monospace | 13 · 14.5 · 16 |

Weights: 400 for text, 600 for labels, 700 for titles. Labels above titles ("eyebrows") use 13 px monospace, uppercase, 0.12 em tracking, in `ink-300` or `muted`.

### Shape and space

| Token | Value |
|---|---|
| Spacing | Multiples of 8 px (4 px for tight insets) |
| Radius | 8 px for chips and small elements; 12 px for cards, windows and images |
| Border | 1 px hairline in `ink-700` (dark) or `line` (light) |
| Elevation | One shadow for floating windows: `0 24 48 rgba(0,0,0,0.45)` |

## Components

| Component | Specification |
|---|---|
| Terminal window | `ink-900` surface, 12 px radius, `ink-800` title bar with three `ink-700` dots, title in 13 px mono `ink-500`. Prompt `$` in `ember-400`. |
| Command chip | `ink-800` fill, `ink-700` border, 8 px radius, 16 px mono `ink-100`. Never colour-coded. |
| Step card | `ink-900` fill, `ink-700` border, 12 px radius; step number in `ember-400`, title `ink-100`, body `ink-300`. |
| Status pill | Tint background with matching status text, 8 px radius. Only for status. |
| Feature image | `ink-950` background; copy on the left (eyebrow, title, body, one command chip); product window on the right. |

## Website

The documentation site and home page (`site/`) use the same tokens, with a few additions for an interactive surface. Source: [`site/assets/tokens.css`](../site/assets/tokens.css), [`docs.css`](../site/assets/docs.css) and [`landing.css`](../site/assets/landing.css).

### Idea: an incident field manual

The home page reads like the first pages of a well-made operations manual, not a marketing template. It leads with the one thing a reader under pressure needs, the first 15 minutes of a response, and everything after it is reference: the commands set like a manual page, output shown as captioned figures, the guides as a table of contents. Specific content does the persuading; decoration does not.

Avoid the patterns of generated landing pages: glow blobs, background grids, gradient text, a version pill above a centred hero, an uppercase label over every section, bento tiles, pointer spotlights, slogan headings ("X, not Y"), pulsing dots and scroll-in animations.

### Themes and type

| Surface | Rule |
|---|---|
| Every page | Follows the reader's system setting; the header switch overrides it and is remembered. |
| Code, terminals, install and verify blocks | Always dark, in both themes, so commands look the same as in a terminal. |
| Text | IBM Plex Sans (variable, 100–700), an engineering typeface that reads as documentation. Headings 600, body 400. |
| Code | JetBrains Mono, as in the README images. |

### Colour on the web

- **Ink does the work.** Primary buttons are ink on paper (`#111827` on white; inverted in dark mode).
- **Red means urgency.** The incident card's top rule, its label and the header's "Leaked a secret?" dot. Nowhere else.
- **Ember marks links and the current page**, never large surfaces.
- **Depth comes from hairlines** (`#E3E7EE` light, `rgba(230, 234, 242, 0.09)` dark), paper surfaces and one soft shadow on the incident card. The header is solid.

### Code colours

Two hues on the dark code surface, so syntax never competes with status colours.

| Role | Colour | Contrast on `#0E131F` |
|---|---|---|
| Text | `#E6EAF2` | 15.4:1 |
| Keywords, commands, prompt | `#FF8A5C` | 8.0:1 |
| Keys, attributes, names | `#FFB59A` | 10.9:1 |
| Strings, numbers | `#9CC3F5` | 10.2:1 |
| Variables | `#C9B8F5` | 10.3:1 |
| Comments (italic) | `#8B95A7` | 6.1:1 |

### Motion

Hover and focus changes only: 150 ms, `cubic-bezier(0.2, 0.7, 0.2, 1)`. Nothing moves on scroll or on load, and nothing loops. Reduced-motion settings are respected.

### Components

| Component | Specification |
|---|---|
| Header | Solid, hairline below. Brand, four links, search (`Ctrl K`, `⌘K` or `/`), theme switch, GitHub, and "Leaked a secret?" with a static `fail` dot that opens the cheat sheet. |
| Incident card | Paper surface, 3 px `fail` top rule, label in `fail`. Rows: time in 13 px mono, the action in 15 px with the verb phrase in 600, an optional command chip. Footer links to the cheat sheet and the runbook. Content mirrors `CHEATSHEET.md`. |
| Manual page | `dl` grid: command synopsis in mono (arguments in `muted`), description beside it; groups match `leak help` (Prevent, Respond, Setup). |
| Figure | Hairline frame, 10 px radius, caption below starting with **Figure n.** Screenshots are cropped from the top at 16:9; terminals show in full. |
| Table of contents | Four columns under a 2 px ink rule; each entry is a guide title in 600 with a one-line summary. |
| Search | Modal dialog over a dimmed backdrop. Results are page sections, keyboard-driven (arrow keys, Enter, Esc). The index is built from the Markdown by `tools/build-search-index.py`. |
| Callout | Tint background, 30% status-colour border, 18 px line icon, sentence-case label. Note uses `info`, Tip `pass`, Important `ember`, Warning `warn`, Caution `fail`. |
| Code block | Dark surface, 40 px header with the language and a copy button, 13.5 px mono on a 1.7 line height. |
| Logo strip | Monochrome marks in `text-2` from [Simple Icons](https://simpleicons.org) 16.36.0 (CC0), 19 px, each followed by the product name. Brands whose owners do not permit logo use without a licence (AWS, Microsoft Azure, Azure DevOps) and tools without a mark appear as names only. |
| Sidebar | Group titles in 13 px semibold; pages on a 1 px guide line; the current page in ember with an ember guide segment. |

### Checks

`tools/check-site.py` runs on every pull request and blocks a deploy if an internal link, anchor, page title, description, `h1`, image alt text or search entry is missing. Keep every new colour pairing at 4.5:1 or better; `muted` text is for `bg` and `bg-2` only.
