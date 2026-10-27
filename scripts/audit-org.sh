#!/usr/bin/env bash
# Grade every repository of a GitHub organisation or user, a Bitbucket Cloud workspace,
# an Azure DevOps organisation (or one of its projects), or every Git repository in a
# local folder, and build one report: HTML, Markdown and JSON.
#
# Usage: leak audit-org [options] <org-or-user>                  GitHub
#        leak audit-org [options] --bitbucket <workspace>        Bitbucket Cloud
#        leak audit-org [options] --azure-devops <org>[/<project>]  Azure DevOps
#        leak audit-org [options] --dir <folder-of-repos>
# Options:
#   --no-scan          skip full-history scans (much faster; history marked not checked)
#   --limit N          audit at most N repositories (default 50)
#   --include-forks    include forks and archived repositories (skipped by default)
#   --out DIR          output folder (default: audits/audit_<time>)
#   --tlp LABEL        handling label on the report: clear, green, amber, amber+strict (default) or red
# Env:   GITHUB_TOKEN, BITBUCKET_TOKEN (an access token) or AZURE_DEVOPS_PAT (Code: Read), all
#        optional: include private repositories you can read. Tokens never appear in command lines.
# Exit:  0 no repository has critical findings, 1 at least one has, 2 bad arguments,
#        4 the repositories could not be listed (API error or missing permission)
set -uo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
shopt -s dotglob nullglob   # include repositories such as .github

help() { print_help "$0"; }
scan_flag=(); limit=50; forks=0; out=""; owner=""; dir=""; bitbucket=""; ado=""; tlp="amber+strict"
while (($#)); do
  case "$1" in
    -h|--help) help; exit 0 ;;
    --no-scan) scan_flag=(--no-scan); shift ;;
    --limit) need_value "$1" "${2:-}"; limit="$2"; shift 2 ;;
    --include-forks) forks=1; shift ;;
    --out) need_value "$1" "${2:-}"; out="$2"; shift 2 ;;
    --dir) need_value "$1" "${2:-}"; dir="$2"; shift 2 ;;
    --bitbucket) need_value "$1" "${2:-}"; bitbucket="$2"; shift 2 ;;
    --azure-devops) need_value "$1" "${2:-}"; ado="$2"; shift 2 ;;
    --tlp) need_value "$1" "${2:-}"; tlp="$2"; shift 2 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) owner="$1"; shift ;;
  esac
done
[[ "$limit" =~ ^[0-9]+$ ]] || { echo "--limit needs a number" >&2; exit 2; }
sources=0; for v in "$owner" "$dir" "$bitbucket" "$ado"; do [[ -n "$v" ]] && sources=$((sources + 1)); done
((sources == 1)) || { help >&2; exit 2; }
if [[ -n "$dir" ]]; then [[ -d "$dir" ]] || { echo "not a folder: $dir" >&2; exit 2; }
elif [[ -n "$bitbucket" ]]; then [[ "$bitbucket" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "not a Bitbucket workspace name: $bitbucket" >&2; exit 2; }
elif [[ -n "$ado" ]]; then [[ "$ado" =~ ^[A-Za-z0-9_.-]+(/[^/]+)?$ ]] || { echo "use --azure-devops <org> or <org>/<project>" >&2; exit 2; }
elif [[ ! "$owner" =~ ^[A-Za-z0-9_.-]+$ ]]; then help >&2; exit 2; fi
command -v jq >/dev/null || { echo "missing: jq" >&2; exit 2; }
tlp_line="$(tlp_info "$tlp")" || { echo "--tlp must be clear, green, amber, amber+strict or red" >&2; exit 2; }
IFS='|' read -r tlp_label tlp_rule tlp_class <<<"$tlp_line"

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
elif [[ -n "$bitbucket" ]]; then
  label="$bitbucket"
  next="https://api.bitbucket.org/2.0/repositories/$bitbucket?pagelen=100"
  while [[ -n "$next" && "$(wc -l < "$targets")" -lt "$limit" ]]; do
    code="$(bb_get "$next" "$work/page.json")"
    if [[ "$code" != 200 ]] || ! jq -e '.values | type == "array"' "$work/page.json" >/dev/null 2>&1; then
      echo "Bitbucket API error (HTTP $code) listing $bitbucket. For private repositories set BITBUCKET_TOKEN." >&2
      exit "$EXIT_FAILED"
    fi
    # Clone URLs may carry a user name (https://user@bitbucket.org/...); credentials come from git_auth_env.
    jq -r --argjson forks "$forks" '.values[] | select($forks == 1 or (.parent == null))
      | [.slug, ([.links.clone[]? | select(.name == "https") | .href][0] // "" | sub("^https://[^@/]*@"; "https://"))]
      | select(.[1] != "") | @tsv' "$work/page.json" >> "$targets"
    next="$(jq -r '.next // empty' "$work/page.json")"
  done
elif [[ -n "$ado" ]]; then
  label="$ado"
  ado_org="${ado%%/*}"; ado_path=""
  [[ "$ado" == */* ]] && ado_path="$(jq -rn --arg p "${ado#*/}" '$p|@uri')/"
  code="$(ado_get "https://dev.azure.com/$ado_org/${ado_path}_apis/git/repositories?api-version=7.1" "$work/page.json")"
  if [[ "$code" != 200 ]] || ! jq -e '.value | type == "array"' "$work/page.json" >/dev/null 2>&1; then
    echo "Azure DevOps API error (HTTP $code) listing $ado. Set AZURE_DEVOPS_PAT with Code: Read." >&2
    exit "$EXIT_FAILED"
  fi
  jq -r --argjson forks "$forks" '.value[] | select((.isDisabled // false) | not) | select($forks == 1 or ((.isFork // false) | not))
    | ["\(.project.name)/\(.name)", (.remoteUrl | sub("^https://[^@/]*@"; "https://"))] | @tsv' "$work/page.json" >> "$targets"
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
  file="${name//\//__}"   # Azure DevOps names are project/repo
  if [[ "$src" == https://* ]]; then
    path="$work/repos/$file"
    depth=(); ((${#scan_flag[@]})) && depth=(--depth 1)
    if ! git clone --quiet "${depth[@]}" "$src" "$path" 2>/dev/null; then
      jq -n --arg r "$name" '{repository: $r, grade: "not audited", score: 0, max: 0, percent: null, critical: false, error: "could not be cloned (private without a token, or unavailable)", checks: []}' > "$out/results/$file.json"
      printf '  [%d/%d] %-40s not audited (clone failed)\n' "$i" "$total" "$name"
      continue
    fi
  fi
  NO_COLOR=1 "$here/audit.sh" "${scan_flag[@]}" --json "$path" > "$out/results/$file.json" 2>/dev/null
  jq --arg r "$name" '.repository = $r' "$out/results/$file.json" > "$work/j" && mv "$work/j" "$out/results/$file.json"
  printf '  [%d/%d] %-40s grade %s\n' "$i" "$total" "$name" "$(jq -r .grade "$out/results/$file.json")"
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

# 4. HTML report: a self-contained document styled like the incident report.
version="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$here/../leak")"
css="$(cat "$here/../templates/report.css")"
html() { jq -rn --arg s "$1" '$s|@html'; }
n_audited="$(jq .audited "$summary")"; n_not="$(jq .not_audited "$summary")"; n_crit="$(jq .critical "$summary")"; avg="$(jq .average_percent "$summary")"
avg_class="$( ((avg >= 75)) && echo ok || { ((avg >= 40)) && echo warn || echo bad; })"
run_h="${stamp:0:4}-${stamp:4:2}-${stamp:6:2} ${stamp:9:2}:${stamp:11:2}"
history_note="$( [[ "$(jq .history_scanned "$summary")" == true ]] && echo "Full Git history scanned" || echo "History not scanned (--no-scan): grades exclude section 6")"
rows="$(jq -r '
  def lab: if .grade == "A" or .grade == "B" then "ok" elif .grade == "C" or .grade == "D" then "warn" else "bad" end;
  .results[] | if .error then "<tr><td><b>\(.repository|@html)</b></td><td><span class=\"label na\">Not audited</span></td><td>–</td><td class=\"note\">\(.error|@html)</td></tr>"
  else "<tr><td><b>\(.repository|@html)</b></td><td><span class=\"label \(lab)\">\(.grade|@html)</span></td><td>\(.percent)%</td><td>\([.checks[] | select(.status != "pass") | "<div class=\"finding\"><span class=\"label \(if .status == "fail" then "bad\">Critical" else "warn\">Fix" end)</span> \(.message|@html)\(if (.fix // "") != "" then "<div class=\"note\">\(.fix|@html)</div>" else "" end)</div>"] | join("") | if . == "" then "<span class=\"note\">Nothing to fix</span>" else . end)</td></tr>" end' "$summary")"
bars="$(jq -r '.audited as $n | .grades | to_entries[] | "<div class=\"bar\"><span class=\"g\">\(.key)</span><span class=\"track\"><span class=\"fill g\(.key)\" style=\"width:\(if $n > 0 then (.value * 100 / $n | floor) else 0 end)%\"></span></span><span class=\"c\">\(.value)</span></div>"' "$summary")"
label_html="$(html "$label")"
cat > "$out/dashboard.html" <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="generator" content="Spillkit $version">
<title>Secret hygiene report: $label_html</title>
<style>
$css
  .bar { display: flex; align-items: center; gap: 10px; margin: 5px 0; font-size: 12.5px; }
  .bar .g { width: 16px; font-weight: 700; } .bar .c { width: 28px; text-align: right; color: var(--muted); }
  .track { flex: 1; height: 12px; background: var(--wash); border: 1px solid var(--line); }
  .fill { display: block; height: 100%; }
  .gA, .gB { background: var(--ok); } .gC, .gD { background: #B7791F; } .gF { background: var(--bad); }
  .finding { margin: 0 0 6px; } .finding:last-child { margin: 0; }
  .finding .note { margin: 2px 0 0 0; }
  @page {
    @top-left { content: "$tlp_label"; font: 700 8.5pt monospace; }
    @top-right { content: "Secret hygiene report"; font: 8.5pt sans-serif; color: #625A7C; }
    @bottom-left { content: "Prepared with Spillkit $version"; font: 8.5pt sans-serif; color: #625A7C; }
    @bottom-right { content: "Page " counter(page) " of " counter(pages); font: 8.5pt sans-serif; color: #625A7C; }
  }
</style>
</head>
<body>
<main class="page">
<div class="doc-head">
  <div>
    <p class="doc-type">Secret hygiene report</p>
    <h1>$label_html</h1>
    <p class="subtitle">$history_note. Secret values are never included.</p>
  </div>
  <span class="tlp $tlp_class">$tlp_label</span>
</div>
<div class="control">
  <div><b>Run (UTC)</b><span>$run_h</span></div>
  <div><b>Repositories audited</b><span>$n_audited</span></div>
  <div><b>Not audited</b><span>$n_not</span></div>
  <div><b>Tool</b><span>Spillkit $version</span></div>
</div>
<p class="note">$tlp_label: $tlp_rule</p>

<h2><span class="no">1</span>Summary</h2>
<div class="status">
  <div class="stat $avg_class"><div class="k">Average score</div><div class="v">$avg%</div><p>Across $n_audited audited repositories.</p></div>
  <div class="stat $( ((n_crit)) && echo bad || echo ok)"><div class="k">Critical findings</div><div class="v">$n_crit $( ((n_crit == 1)) && echo repository || echo repositories)</div><p>Tracked secret files, secrets in images or in history.</p></div>
  <div class="stat $( ((n_not)) && echo warn || echo ok)"><div class="k">Not audited</div><div class="v">$n_not</div><p>$( ((n_not)) && echo "Could not be read; listed below." || echo "Every repository was read.")</p></div>
</div>
<h3>Grade distribution</h3>
$bars

<h2><span class="no">2</span>Repositories, worst first</h2>
<table>
  <thead><tr><th style="width:24%">Repository</th><th style="width:9%">Grade</th><th style="width:9%">Score</th><th>Findings and fixes</th></tr></thead><tbody>
  $rows
</tbody></table>

<h2><span class="no">3</span>Method</h2>
<p>Each repository is checked by <code>leak audit</code>. Points are weighted to 100; a critical finding caps the grade at F.</p>
<table>
  <thead><tr><th style="width:40%">Check</th><th style="width:12%">Points</th><th>Critical when</th></tr></thead><tbody>
  <tr><td>1. Files that usually hold secrets</td><td>20</td><td>A <code>.env</code>, key or state file is tracked by Git</td></tr>
  <tr><td>2. Ignore rules and <code>.env.example</code></td><td>20</td><td>Never</td></tr>
  <tr><td>3. Commit-time blocking (scanner and hook)</td><td>15</td><td>Never</td></tr>
  <tr><td>4. Secret scanning in CI</td><td>15</td><td>Never</td></tr>
  <tr><td>5. Container hygiene</td><td>10</td><td>A secret-looking value is baked into an image</td></tr>
  <tr><td>6. Full Git history</td><td>20</td><td>Any secret is found in any commit</td></tr>
</tbody></table>
<p class="note">Grades: A 90 or more, B 75 or more, C 60 or more, D 40 or more, F below 40 or any critical finding. Re-run after fixes to track progress.</p>

<div class="doc-foot"><span>$tlp_label</span><span>Prepared with Spillkit $version · Contains no secret values</span></div>
</main>
</body>
</html>
HTML

echo
echo "Dashboard: $out/dashboard.html"
echo "Markdown:  $out/README.md"
echo "JSON:      $out/audit-org.json"
[[ "$(jq .critical "$summary")" -eq 0 ]]
