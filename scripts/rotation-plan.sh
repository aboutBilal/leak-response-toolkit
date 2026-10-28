#!/usr/bin/env bash
# Turn a secret scan into an ordered rotation plan: one item per secret (its type and
# file), most dangerous first, each with where to revoke it, the guide section and, where
# one exists, the `leak rotate` recipe that automates it. Written as Markdown with
# checkboxes (paste it into the incident issue), as print-ready HTML and as JSON for
# automation. Never contains secret values: it reads the redacted report written by leak scan.
#
# Usage: leak plan <secrets-report.json> [--out DIR] [--id INC-2026-014] [--tlp LABEL]
#   <secrets-report.json>  the JSON report written by leak scan
#   --out DIR              where to write rotation-plan.md, .html and .json
#                          (default: the folder of the report)
#   --id                   incident reference shown on the plan
#   --tlp                  handling label: clear, green, amber, amber+strict (default) or red
# Order: 1 can create resources or read data, 2 has billing attached, 3 grants further
#        access, 4 the rest; oldest first within each (docs/02-rotate-secrets.md).
# Exit:  0 nothing to rotate, 1 secrets to rotate, 2 bad arguments
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

report=""; out=""; id=""; tlp="amber+strict"
while (($#)); do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --out) need_value "$1" "${2:-}"; out="$2"; shift 2 ;;
    --id) need_value "$1" "${2:-}"; id="$2"; shift 2 ;;
    --tlp) need_value "$1" "${2:-}"; tlp="${2,,}"; shift 2 ;;
    -*) echo "unknown option: $1" >&2; exit "$EXIT_USAGE" ;;
    *) if [[ -z "$report" ]]; then report="$1"; else echo "unexpected argument: $1" >&2; exit "$EXIT_USAGE"; fi; shift ;;
  esac
done
[[ -n "$report" ]] || { echo "usage: leak plan <secrets-report.json> [--out DIR] [--id ID] [--tlp LABEL]" >&2; exit "$EXIT_USAGE"; }
command -v jq >/dev/null || { echo "missing: jq" >&2; exit "$EXIT_USAGE"; }
[[ -f "$report" ]] || { echo "scan report not found: $report" >&2; exit "$EXIT_USAGE"; }
jq -e 'type == "array" and all(.[]; has("RuleID") and has("File"))' "$report" >/dev/null 2>&1 \
  || { echo "not a leak scan report (a JSON array of gitleaks findings): $report" >&2; exit "$EXIT_USAGE"; }
tlp_line="$(tlp_info "$tlp")" || { echo "--tlp must be clear, green, amber, amber+strict or red" >&2; exit "$EXIT_USAGE"; }
IFS='|' read -r tlp_label tlp_rule tlp_class <<<"$tlp_line"
out="${out:-$(dirname "$report")}"
mkdir -p "$out"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$here/leak")"
guide="https://aboutbilal.github.io/spillkit/docs/02-rotate-secrets.html"
generated="$(date -u '+%Y-%m-%d %H:%M')"

# The catalog: one JSON object per line of scripts/secret-types.txt.
catalog="$(grep -vE '^[[:space:]]*(#|$)' "$here/scripts/secret-types.txt" | jq -R '
  split(" | ") | map(gsub("^\\s+|\\s+$"; ""))
  | {rules: (.[0] | split(" ")), file: .[1], tier: (.[2] | tonumber), type: .[3], guide: .[4], revoke: .[5], recipe: .[6]}' | jq -s '.')"

# One item per secret type and file, classified by the first matching catalog line, ordered by tier then age.
items="$(jq --argjson cat "$catalog" '
  def glob: "^" + (gsub("(?<c>[.+?^$(){}|\\[\\]\\\\])"; "\\\(.c)") | gsub("\\*"; ".*")) + "$";
  def classify:
    . as $i
    | first($cat[] | . as $c
        | select(any($c.rules[]; . as $g | $i.rule | test($g | glob)))
        | select($c.file == "-" or ($i.file | test($c.file | glob)))) // {};
  group_by([.RuleID, .File])
  | map(sort_by(.Date // "") as $g | {
      rule: $g[0].RuleID, file: $g[0].File, line: ($g[0].StartLine // 1),
      commit: (($g[0].Commit // "")[0:10]), since: (($g[0].Date // "")[0:10]),
      commits: ([$g[].Commit] | unique | length) })
  | map(. + (classify | {tier, type, guide, revoke, recipe}) + {note: ""})
  # An unidentified secret right next to a known one (AWS_SECRET_ACCESS_KEY under the key ID) is
  # usually its other half: keep it as its own item, but rotate it with that one.
  | . as $all
  | map(if .rule == "generic-api-key" then
        . as $g
        | ([$all[] | select(.rule != "generic-api-key" and .file == $g.file and .commit == $g.commit
                            and (.line - $g.line | if . < 0 then -. else . end) <= 2)][0]) as $pair
        | if $pair then . + ($pair | {tier, guide, revoke, recipe}) + {type: "Secret next to the \($pair.type)",
            note: "Probably the other half of the \($pair.type) on line \($pair.line): rotate them together."} else . end
      else . end)
  | sort_by(.tier, .since, .file, .line)
  | to_entries | map(.value + {n: (.key + 1)})' "$report")"
count="$(jq 'length' <<<"$items")"

tier_name() {
  case "$1" in
    1) echo "Can create resources or read data" ;;
    2) echo "Billing attached" ;;
    3) echo "Grants further access" ;;
    *) echo "Everything else" ;;
  esac
}

# ---------- Markdown: a checklist to paste into the incident issue ----------
md="$out/rotation-plan.md"
{
  echo "# Rotation plan"
  echo
  echo "${id:+Incident $id · }$tlp_label · Generated $generated UTC by Spillkit $version from \`$(basename "$report")\`"
  echo
  if ((count == 0)); then
    echo "**Nothing to rotate.** The scan found no secrets in any commit. Keep the scan report with the evidence."
  else
    echo "**$count secret$( ((count > 1)) && echo s) to rotate**, most dangerous first. For each one: create the replacement, deploy it everywhere it is used, revoke the old one, then check the provider's usage or audit log for the exposure window. If a secret is being abused right now, revoke it first and accept the downtime."
    echo
    echo "Secret values were never read. *Since* is when the secret first entered the history; the exposure began when the repository became public."
    for t in 1 2 3 4; do
      jq -e --argjson t "$t" 'any(.[]; .tier == $t)' <<<"$items" >/dev/null || continue
      echo
      echo "## $t · $(tier_name "$t")"
      echo
      jq -r --argjson t "$t" --arg guide "$guide" '
        def code: "`" + gsub("`"; "ʼ") + "`";
        .[] | select(.tier == $t) |
        "- [ ] **\(.n). \(.type)** in \(.file | code) line \(.line), since \(.since) (\(.commit | code)\(if .commits > 1 then ", in \(.commits) commits" else "" end))",
        (if .note != "" then "  - \(.note)" else empty end),
        "  - Revoke at: \(.revoke)",
        "  - Guide: <\($guide)#\(.guide)>\(if .recipe != "-" then " · Automate: `leak rotate \(.recipe)` (a dry run unless you add --apply)" else "" end)",
        "  - Owner: ____ · Rotated (UTC): ____ · Old one revoked (UTC): ____ · Usage log checked: ____"' <<<"$items"
    done
  fi
  echo
  echo "---"
  echo "Detection rule IDs, for reference: $(jq -r '[.[].rule] | unique | map("`" + . + "`") | join(", ") | if . == "" then "none" else . end' <<<"$items")"
} > "$md"

# ---------- JSON: the same items for automation (the GitHub Action builds its summary from it) ----------
jq --arg v "$version" --arg at "$generated" --arg id "$id" --arg tlp "$tlp_label" --arg report "$(basename "$report")" --arg guide "$guide" '
  {generator: "Spillkit \($v)", generated_utc: $at, incident: (if $id == "" then null else $id end), tlp: $tlp,
   report: $report, count: length,
   items: map(. + {guide_url: "\($guide)#\(.guide)", recipe: (if .recipe == "-" then null else .recipe end),
                   note: (if .note == "" then null else .note end)})}' <<<"$items" > "$out/rotation-plan.json"

# ---------- HTML: the same plan, print-ready, in the style of the incident report ----------
html() { jq -rn --arg s "$1" '$s|@html'; }
tbc() { printf '<mark class="tbc">[%s]</mark>' "$1"; }
sections=""
for t in 1 2 3 4; do
  jq -e --argjson t "$t" 'any(.[]; .tier == $t)' <<<"$items" >/dev/null || continue
  rows="$(jq -r --argjson t "$t" --arg guide "$guide" --arg tbc "$(tbc "owner")" --arg time "$(tbc "UTC")" '
    .[] | select(.tier == $t) |
    "<tr><td class=\"n\">\(.n)</td>"
    + "<td><b>\(.type | @html)</b><br><code>\(.rule | @html)</code></td>"
    + "<td><code>\(.file | @html)</code> line \(.line)<br>since \(.since | @html) · <code>\(.commit | @html)</code>\(if .commits > 1 then " · \(.commits) commits" else "" end)</td>"
    + "<td>\(if .note != "" then "<i>\(.note | @html)</i><br>" else "" end)\(.revoke | @html)<br><a href=\"\($guide)#\(.guide | @uri)\">Guide</a>\(if .recipe != "-" then " · <code>leak rotate \(.recipe | @html)</code>" else "" end)</td>"
    + "<td>\($tbc)<br>Rotated \($time)<br>Revoked \($time)</td></tr>"' <<<"$items")"
  sections+="<h2><span class=\"no\">$t</span>$(tier_name "$t")</h2>
<table><thead><tr><th class=\"n\">#</th><th style=\"width:24%\">Secret</th><th style=\"width:26%\">Where it was committed</th><th>Revoke at</th><th style=\"width:17%\">Done</th></tr></thead><tbody>$rows</tbody></table>"
done
if ((count == 0)); then
  sections="<p>The scan found no secrets in any commit. Keep the scan report with the evidence.</p>"
fi
by_tier="$(jq -r '[group_by(.tier)[] | "\(length) in tier \(.[0].tier)"] | join(" · ")' <<<"$items")"
css="$(cat "$here/templates/report.css")"
title="Rotation plan${id:+ · $id}"
cat > "$out/rotation-plan.html" <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="generator" content="Spillkit $version">
<title>$(html "$title")</title>
<style>
$css
  @page {
    @top-left { content: "$tlp_label"; font: 700 8.5pt monospace; }
    @top-right { content: $(jq -rn --arg s "$title" '$s|@json'); font: 8.5pt sans-serif; color: #625A7C; }
    @bottom-left { content: "Prepared with Spillkit $version"; font: 8.5pt sans-serif; color: #625A7C; }
    @bottom-right { content: "Page " counter(page) " of " counter(pages); font: 8.5pt sans-serif; color: #625A7C; }
  }
</style>
</head>
<body>
<div class="howto"><b>Generated by Spillkit.</b> Work down the list in order. Fill in every <mark class="tbc">[highlighted field]</mark> as you go; the finished plan is part of the incident timeline. This box does not print.</div>
<main class="page">

<div class="doc-head">
  <div>
    <p class="doc-type">Rotation plan</p>
    <h1>Secrets to rotate, most dangerous first</h1>
    <p class="subtitle">From $(html "$(basename "$report")") · generated $generated UTC</p>
  </div>
  <span class="tlp $tlp_class">$tlp_label</span>
</div>
<p class="note">$tlp_label: $tlp_rule All times are UTC.</p>

<div class="status">
  <div class="stat $( ((count)) && echo bad || echo ok)"><div class="k">Secrets to rotate</div><div class="v">$count</div><p>$( ((count)) && html "$by_tier" || echo "Nothing found in any commit.")</p></div>
  <div class="stat warn"><div class="k">For each one</div><div class="v">4 steps</div><p>Replace, deploy, revoke the old one, check its usage log.</p></div>
  <div class="stat ok"><div class="k">Secret values</div><div class="v">None</div><p>Read from a redacted scan. Never printed or stored.</p></div>
</div>
<p style="margin-top:14px">If a secret is being abused right now, revoke it first and accept the downtime. <i>Since</i> is when the secret entered the history; the exposure began when the repository became public.</p>

$sections

<div class="doc-foot"><span>$tlp_label</span><span>Prepared with Spillkit $version · Contains no secret values</span></div>
</main>
</body>
</html>
HTML

if ((count == 0)); then
  echo "Nothing to rotate: the scan found no secrets. Plan: $md"
  exit "$EXIT_OK"
fi
echo "==> Rotation plan: $count secret(s), most dangerous first (values were never read)"
jq -r 'def section: {aws: "AWS", "google-cloud": "Google Cloud", github: "GitHub", databases: "Databases",
    "service-principal--app-registration-secret": "Azure", "azure-devops-personal-access-token": "Azure DevOps",
    "ssh-keys-and-certificates": "SSH and TLS keys", "application-secrets": "Application secrets",
    "keys-that-are-meant-to-be-public": "Public keys", "more-secret-types-where-to-revoke": "More secret types"}[.] // .;
  (["#","TIER","TYPE","WHERE","SINCE","HOW"] | @tsv),
  (.[] | [(.n|tostring), (.tier|tostring), .type, "\(.file):\(.line)", .since,
          (if .recipe != "-" then "leak rotate \(.recipe)" else "by hand, guide: \(.guide | section)" end)] | @tsv)' <<<"$items" | table
echo
echo "Checklist for the incident issue: $md"
echo "Print or share:                   $out/rotation-plan.html"
echo "For automation:                   $out/rotation-plan.json"
exit "$EXIT_FOUND"
