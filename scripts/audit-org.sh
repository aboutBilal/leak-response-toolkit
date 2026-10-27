#!/usr/bin/env bash
# Grade every repository of a GitHub organisation or user (or every Git repository
# in a local folder) and build one dashboard: HTML, markdown and JSON.
#
# Usage: leak audit-org [options] <org-or-user>
#        leak audit-org [options] --dir <folder-of-repos>
# Options:
#   --no-scan          skip full-history scans (much faster; history marked not checked)
#   --limit N          audit at most N repositories (default 50)
#   --include-forks    include forks and archived repositories (skipped by default)
#   --out DIR          output folder (default: audits/audit_<time>)
# Env:   GITHUB_TOKEN (optional) - includes private repositories you can read; higher API limits.
# Exit:  0 no repository has critical findings, 1 at least one has, 2 bad arguments
set -uo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
shopt -s dotglob nullglob   # include repositories such as .github

help() { print_help "$0"; }
scan_flag=(); limit=50; forks=0; out=""; owner=""; dir=""
while (($#)); do
  case "$1" in
    -h|--help) help; exit 0 ;;
    --no-scan) scan_flag=(--no-scan); shift ;;
    --limit) need_value "$1" "${2:-}"; limit="$2"; shift 2 ;;
    --include-forks) forks=1; shift ;;
    --out) need_value "$1" "${2:-}"; out="$2"; shift 2 ;;
    --dir) need_value "$1" "${2:-}"; dir="$2"; shift 2 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) owner="$1"; shift ;;
  esac
done
[[ "$limit" =~ ^[0-9]+$ ]] || { echo "--limit needs a number" >&2; exit 2; }
if [[ -n "$dir" ]]; then [[ -d "$dir" ]] || { echo "not a folder: $dir" >&2; exit 2; }
elif [[ ! "$owner" =~ ^[A-Za-z0-9_.-]+$ ]]; then help >&2; exit 2; fi
command -v jq >/dev/null || { echo "missing: jq" >&2; exit 2; }

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out="${out:-audits/audit_$stamp}"
mkdir -p "$out/results"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# gh <path>: print the JSON body; fail on any non-200 response (token stays out of argv).
gh() {
  local f; f="$(mktemp)"
  if [[ "$(gh_get "$1" "$f")" == 200 ]]; then cat "$f"; rm -f "$f"; else rm -f "$f"; return 1; fi
}
git_auth_env   # private repositories clone with GITHUB_TOKEN; git never prompts

# 1. Collect repositories as "name<TAB>path-or-clone-url"
targets="$work/targets.tsv"; : > "$targets"
if [[ -n "$dir" ]]; then
  label="$(basename "$(cd "$dir" && pwd)")"
  for d in "$dir"/*/; do
    git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1 && printf '%s\t%s\n' "$(basename "$d")" "$(cd "$d" && pwd)" >> "$targets"
  done
else
  label="$owner"
  kind=orgs; gh "/orgs/$owner" >/dev/null 2>&1 || kind=users
  page=1
  while :; do
    batch="$(gh "/$kind/$owner/repos?per_page=100&page=$page&type=all" 2>/dev/null || echo '[]')"
    [[ "$(jq 'length' <<<"$batch")" -eq 0 ]] && break
    jq -r --argjson forks "$forks" '.[] | select($forks == 1 or ((.fork | not) and (.archived | not))) | [.name, .clone_url] | @tsv' <<<"$batch" >> "$targets"
    page=$((page + 1))
  done
fi
head -n "$limit" "$targets" > "$work/t" && mv "$work/t" "$targets"
total="$(wc -l < "$targets" | tr -d ' ')"
((total > 0)) || { echo "no repositories found for: ${owner:-$dir}" >&2; exit 2; }
echo "==> Auditing $total repositories of $label"

# 2. Audit each one
i=0
while IFS=$'\t' read -r name src; do
  i=$((i + 1))
  path="$src"
  if [[ "$src" == https://* ]]; then
    path="$work/repos/$name"
    depth=(); ((${#scan_flag[@]})) && depth=(--depth 1)
    if ! git clone --quiet "${depth[@]}" "$src" "$path" 2>/dev/null; then
      jq -n --arg r "$name" '{repository: $r, grade: "not audited", score: 0, max: 0, percent: null, critical: false, error: "could not be cloned (private without a token, or unavailable)", checks: []}' > "$out/results/$name.json"
      printf '  [%d/%d] %-40s not audited (clone failed)\n' "$i" "$total" "$name"
      continue
    fi
  fi
  NO_COLOR=1 "$here/audit.sh" "${scan_flag[@]}" --json "$path" > "$out/results/$name.json" 2>/dev/null
  jq --arg r "$name" '.repository = $r' "$out/results/$name.json" > "$work/j" && mv "$work/j" "$out/results/$name.json"
  printf '  [%d/%d] %-40s grade %s\n' "$i" "$total" "$name" "$(jq -r .grade "$out/results/$name.json")"
done < "$targets"

# 3. Aggregate
jq -s --arg label "$label" --arg run "$stamp" --argjson scanned "$(( ${#scan_flag[@]} == 0 ))" '{
  label: $label, run: $run, history_scanned: ($scanned == 1),
  repositories: length,
  audited: (map(select(.error | not)) | length),
  not_audited: (map(select(.error)) | length),
  average_percent: (map(select(.error | not) | .percent) | if length > 0 then (add / length | floor) else 0 end),
  critical: (map(select(.critical)) | length),
  grades: (reduce (.[] | select(.error | not)) as $r ({A:0,B:0,C:0,D:0,F:0}; .[$r.grade] += 1)),
  results: (sort_by((.error != null), (.percent // 0), .repository))
}' "$out"/results/*.json > "$out/audit-org.json"

summary="$out/audit-org.json"
{
  echo "# Secret hygiene: $label"
  echo
  echo "- **Run:** $stamp (UTC) · **Repositories:** $(jq .repositories "$summary") ($(jq .not_audited "$summary") not audited) · **Average:** $(jq .average_percent "$summary")% · **Critical:** $(jq .critical "$summary")"
  echo "- **Grades:** $(jq -r '.grades | to_entries | map("\(.key) \(.value)") | join(" · ")' "$summary")"
  [[ "$(jq .history_scanned "$summary")" == true ]] || echo "- History was **not** scanned (--no-scan)."
  echo
  echo "| Repository | Grade | Score | Needs attention |"
  echo "|---|:-:|:-:|---|"
  jq -r '.results[] | if .error then "| \(.repository) | not audited | – | \(.error) |"
    else "| \(.repository) | \(.grade) | \(.percent)% | \([.checks[] | select(.status != "pass") | .message] | join("; ") | if . == "" then "—" else . end) |" end' "$summary"
} > "$out/README.md"

style="$(sed -n '/<style>/,/<\/style>/p' "$here/../templates/executive-report.html")"
rows="$(jq -r '
  def pill: if .grade == "A" or .grade == "B" then "ok" elif .grade == "C" or .grade == "D" then "warn" else "bad" end;
  .results[] | if .error then "<tr><td><b>\(.repository|@html)</b></td><td><span class=\"pill na\">Not audited</span></td><td>–</td><td class=\"note\">\(.error|@html)</td></tr>"
  else "<tr><td><b>\(.repository|@html)</b></td><td><span class=\"pill \(pill)\">\(.grade|@html)</span></td><td>\(.percent)%</td><td>\([.checks[] | select(.status != "pass") | "<div class=\"\(if .status == "fail" then "f" else "w" end)\">\(.message|@html)</div>"] | join("") | if . == "" then "<span class=\"note\">Nothing to fix</span>" else . end)</td></tr>" end' "$summary")"
bars="$(jq -r '.repositories as $n | .grades | to_entries[] | "<div class=\"bar\"><span class=\"g\">\(.key)</span><span class=\"track\"><span class=\"fill g\(.key)\" style=\"width:\(if $n > 0 then (.value * 100 / $n | floor) else 0 end)%\"></span></span><span class=\"c\">\(.value)</span></div>"' "$summary")"
cat > "$out/dashboard.html" <<HTML
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Secret Hygiene Dashboard</title>
$style
<style>
  .bar{display:flex;align-items:center;gap:10px;margin:6px 0}.bar .g{width:18px;font-weight:700}.bar .c{width:30px;text-align:right;color:var(--muted)}
  .track{flex:1;height:14px;background:var(--wash);border-radius:7px;overflow:hidden}.fill{display:block;height:100%}
  .gA,.gB{background:#1A7F37}.gC,.gD{background:#9A6700}.gF{background:#CF222E}
  td .f{color:var(--bad)} td .w{color:var(--warn)} td .f::before{content:"✘ "} td .w::before{content:"! "}
</style></head>
<body><main>
<div class="eyebrow">Secret hygiene dashboard</div>
<h1>$(jq -rn --arg l "$label" '$l|@html')</h1>
<p class="note">Generated by leak-response-toolkit on $(date -u +"%Y-%m-%d %H:%M UTC"). $( [[ "$(jq .history_scanned "$summary")" == true ]] && echo "Full history scanned." || echo "History not scanned (--no-scan).") Secret values are never included.</p>
<div class="cards">
  <div class="card ok"><div class="k">Repositories</div><div class="v">$(jq .audited "$summary")</div><p>graded A–F$( [[ "$(jq .not_audited "$summary")" -gt 0 ]] && echo ", $(jq .not_audited "$summary") not audited")</p></div>
  <div class="card warn"><div class="k">Average score</div><div class="v">$(jq .average_percent "$summary")%</div><p>across all repositories</p></div>
  <div class="card bad"><div class="k">Critical</div><div class="v">$(jq .critical "$summary")</div><p>tracked secret files, baked-in or historical secrets</p></div>
</div>
<h2>Grade distribution</h2>
$bars
<h2>Repositories, worst first</h2>
<table><tr><th style="width:26%">Repository</th><th style="width:9%">Grade</th><th style="width:9%">Score</th><th>Needs attention</th></tr>
$rows
</table>
<p class="note">Fix each item with the matching guide in docs/08-secrets-by-design.md and the prevention kit; re-run to track progress.</p>
</main></body></html>
HTML

echo
echo "Dashboard: $out/dashboard.html"
echo "Markdown:  $out/README.md"
echo "JSON:      $out/audit-org.json"
[[ "$(jq .critical "$summary")" -eq 0 ]]
