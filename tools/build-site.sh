#!/usr/bin/env bash
# Assemble the documentation site source in _site_src/ for GitHub Pages (Jekyll).
# Markdown is copied unchanged and wrapped in {% raw %} so Liquid never touches
# examples such as ${{ secrets.X }}. Build it with the jekyll-build-pages action.
#
# Usage: ./tools/build-site.sh [output-dir]   (default: _site_src)
set -euo pipefail

case "${1:-}" in -h|--help) sed -n '2,/^set -/{/^#/s/^# \{0,1\}//p;}' "$0"; exit 0 ;; esac

root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$root/_site_src}"
rm -rf "$out"
mkdir -p "$out"

cp -R "$root/site/." "$out/"
# The version shown on the site comes from the CLI, so it cannot drift from the release.
version="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$root/leak")"
[[ -n "$version" ]] || { echo "could not read VERSION from ./leak" >&2; exit 1; }
printf '\nversion: "%s"\n' "$version" >> "$out/_config.yml"
mkdir -p "$out/assets"
cp "$root"/assets/*.svg "$root"/assets/*.png "$out/assets/"

pages=(README.md CHEATSHEET.md SECURITY.md CONTRIBUTING.md CHANGELOG.md ROADMAP.md CODE_OF_CONDUCT.md
       assets/DESIGN.md prevention/README.md docs/*.md templates/*.md)
cd "$root"
for page in "${pages[@]}"; do
  mkdir -p "$out/$(dirname "$page")"
  # Explicit front matter makes every file a page (GitHub Pages skips CONTRIBUTING and
  # CODE_OF_CONDUCT otherwise). README becomes the Overview page; site/index.html is the home page.
  front="---"$'\n'; [[ "$page" == README.md ]] && front+="permalink: /overview.html"$'\n'"title: Overview"$'\n'; front+="---"$'\n'
  # jekyll-relative-links converts Markdown links only; HTML links to .md files are converted here.
  { printf '%s' "$front"; printf '{%% raw %%}\n'; sed -E 's/(href="[^":]+)\.md(#[^"]*)?"/\1.html\2"/g' "$page"; printf '\n{%% endraw %%}\n'; } > "$out/$page"
done
# Templates that are not Markdown are published as-is (for example the executive report).
cp templates/*.html "$out/templates/"
# Full-text search index, one entry per section (served as a static file).
python3 "$root/tools/build-search-index.py" "$out/search.json" "${pages[@]}"

echo "site source: $out ($(find "$out" -name '*.md' | wc -l | tr -d ' ') pages)"
