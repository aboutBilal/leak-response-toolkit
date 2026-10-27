# Visual language

The images, reports and dashboards in this repository share one small design system. Use it for anything new.

## Principle: calm signal

People open this toolkit during an incident. The visuals should be quiet, legible and honest, so that what matters stands out without effort.

- **Colour carries meaning.** Status colours appear only where something passed, needs attention or failed. Nothing is coloured for decoration.
- **One accent.** Ember is the only brand colour. Use it for the mark, step numbers, the command prompt and at most one call to action per image.
- **Neutrals do the work.** Roughly 60% background, 30% surfaces and text, 10% accent and status.
- **Hierarchy through type, not effects.** No glows, textures, gradients (except the mark's highlight) or drop shadows beyond the single elevation below.
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
| `ink-500` | `#6B7689` | Tertiary text, arrows, hints |
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
| `muted` | `#6B7689` | Notes, labels |
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
