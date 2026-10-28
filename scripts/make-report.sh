#!/usr/bin/env bash
# Build a print-ready incident report for leadership from a copy hunt (and optionally a
# secret scan). Facts the tools know are filled in: the investigation, secret types and
# counts, timeline entries and evidence checksums. Facts only people know (exposure window,
# severity, owners, decisions) stay highlighted to complete. Never contains secret values.
# Structure follows NIST SP 800-61r3; handling labels follow FIRST TLP 2.0.
#
# Usage: leak report <hunt-dir> [--scan secrets-report.json] [--id INC-2026-014] [--tlp LABEL] [--out report.html]
#        leak report --blank [--tlp LABEL] [--out report.html]
#   <hunt-dir>   a folder written by leak hunt (has meta.json and results.jsonl)
#   --scan       the JSON report written by leak scan (secret TYPES are used, never values)
#   --id         incident reference shown on every page
#   --tlp        handling label: clear, green, amber, amber+strict (default) or red
#   --blank      an empty report to fill in by hand
#   --out        output file (default: <hunt-dir>/incident-report.html, or ./incident-report.html)
# The hand-fill template, templates/incident-report.html, is this script's --blank output.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

hunt=""; scan=""; out=""; id=""; tlp="amber+strict"; blank=0
while (($#)); do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --scan) need_value "$1" "${2:-}"; scan="$2"; shift 2 ;;
    --out) need_value "$1" "${2:-}"; out="$2"; shift 2 ;;
    --id) need_value "$1" "${2:-}"; id="$2"; shift 2 ;;
    --tlp) need_value "$1" "${2:-}"; tlp="${2,,}"; shift 2 ;;
    --blank) blank=1; shift ;;
    -*) echo "unknown option: $1" >&2; exit "$EXIT_USAGE" ;;
    *) if [[ -z "$hunt" ]]; then hunt="$1"; else echo "unexpected argument: $1" >&2; exit "$EXIT_USAGE"; fi; shift ;;
  esac
done
tlp_line="$(tlp_info "$tlp")" || { echo "--tlp must be clear, green, amber, amber+strict or red" >&2; exit "$EXIT_USAGE"; }
IFS='|' read -r tlp_label tlp_rule tlp_class <<<"$tlp_line"
command -v jq >/dev/null || { echo "missing: jq" >&2; exit "$EXIT_USAGE"; }
if ((blank)); then
  [[ -z "$hunt" && -z "$scan" ]] || { echo "--blank takes no hunt folder or scan report" >&2; exit "$EXIT_USAGE"; }
  out="${out:-$PWD/incident-report.html}"
else
  [[ -n "$hunt" ]] || { print_help "$0" >&2; exit "$EXIT_USAGE"; }
  [[ -f "$hunt/meta.json" && -f "$hunt/results.jsonl" ]] || { echo "not a hunt folder (needs meta.json and results.jsonl): $hunt" >&2; exit "$EXIT_USAGE"; }
  [[ -z "$scan" || -f "$scan" ]] || { echo "scan report not found: $scan" >&2; exit "$EXIT_USAGE"; }
  out="${out:-$hunt/incident-report.html}"
fi
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$here/leak")"

html() { jq -rn --arg s "$1" '$s|@html'; }
tbc() { printf '<mark class="tbc">[%s]</mark>' "$1"; }
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
mtime() { date -u -r "$1" '+%Y-%m-%d %H:%M' 2>/dev/null || echo ""; }
label() { printf '<span class="label %s">%s</span>' "$1" "$2"; }
today="$( ((blank)) && tbc date || date -u +%F)"
id_html="$( [[ -n "$id" ]] && html "$id" || tbc "incident ID")"
id_css="$( [[ -n "$id" ]] && jq -rn --arg s "Incident report · $id" '$s|@json' || echo '"Incident report"')"

# ---------- Facts from the tools ----------
if ((blank)); then
  repos_html="$(tbc "owner/repo")"; run="$(tbc "date hh:mm UTC")"; since="$(tbc "date")"
  total=11; n_found=0; n_unknown=0; n_clean=0
  check_rows=""; i=0
  for t in "The repository itself" "Direct forks" "Same-name forks, traced to their root" "Wayback Machine" "Software Heritage" \
           "Code search (Sourcegraph)" "GitLab projects of the same name" "Uploader's other repositories" "Uploader's public gists" \
           "Public activity (90 days)" "Original commits in other repositories"; do
    i=$((i + 1)); check_rows+="<tr><td class=\"n\">$i</td><td>$t</td><td>$(tbc result)</td><td>$(tbc detail)</td></tr>"
  done
  copies_stat="<div class=\"stat warn\"><div class=\"k\">Public copies today</div><div class=\"v\">$(tbc result)</div><p>$(tbc "N sources checked")</p></div>"
  finding="$(tbc "e.g. A search of N public sources on date found no surviving public copy.")"
else
  meta="$(cat "$hunt/meta.json")"
  results="$(jq -s '.' "$hunt/results.jsonl")"
  repos_html="$(jq -r '.repos | join(", ") | @html' <<<"$meta")"
  run="$(jq -r '.run | "\(.[0:4])-\(.[4:6])-\(.[6:8]) \(.[9:11]):\(.[11:13])"' <<<"$meta")"
  since="$(jq -r '.since' <<<"$meta")"
  total="$(jq 'length' <<<"$results")"
  n_found="$(jq '[.[] | select(.status=="found")] | length' <<<"$results")"
  n_unknown="$(jq '[.[] | select(.status=="unknown")] | length' <<<"$results")"
  n_clean="$(jq '[.[] | select(.status=="clean")] | length' <<<"$results")"
  check_rows="$(jq -r '
    def lab: if .status=="clean" then "<span class=\"label ok\">Clean</span>"
             elif .status=="found" then "<span class=\"label bad\">Found</span>"
             elif .status=="unknown" then "<span class=\"label warn\">Not checked</span>"
             elif .status=="covered" then "<span class=\"label na\">Covered below</span>"
             else "<span class=\"label na\">Review</span>" end;
    to_entries[] | "<tr><td class=\"n\">\(.key+1)</td><td>\(.value.check|gsub("`";"")|@html)<div class=\"note\">\(.value.section|@html)</div></td><td>\(.value|lab)</td><td>\(.value.detail|gsub("`";"")|@html)</td></tr>"' <<<"$results")"
  if ((n_found > 0)); then
    copies_stat="<div class=\"stat bad\"><div class=\"k\">Public copies today</div><div class=\"v\">$n_found to act on</div><p>Each needs removal or review (section 4).</p></div>"
    finding="A search of public sources found <b>$n_found item(s) that need action</b>."
  elif ((n_unknown > 0)); then
    copies_stat="<div class=\"stat warn\"><div class=\"k\">Public copies today</div><div class=\"v\">None found yet</div><p>$n_unknown of $total sources could not be checked.</p></div>"
    finding="A search of public sources found <b>no surviving public copy</b>, but $n_unknown of $total sources could not be checked and must be checked by hand."
  else
    copies_stat="<div class=\"stat ok\"><div class=\"k\">Public copies today</div><div class=\"v\">None found</div><p>All $total sources checked.</p></div>"
    finding="A search of $total public sources found <b>no surviving public copy</b>."
  fi
fi

secret_rows=""; n_types=""
if [[ -n "$scan" ]]; then
  # Types and counts only; the report never contains secret values.
  n_types="$(jq '[.[].RuleID] | unique | length' "$scan")"
  secret_rows="$(jq -r --arg o "$(tbc owner)" --arg s "$(tbc status)" \
    'group_by(.RuleID)[] | "<tr><td><code>\(.[0].RuleID|@html)</code></td><td>\(length)</td><td>\([.[].File]|unique|length)</td><td class=\"t\">\(min_by(.Date).Date[0:10])</td><td>\($o)</td><td>\($s)</td></tr>"' "$scan")"
fi
if [[ -z "$scan" ]]; then
  secrets_stat="<div class=\"stat warn\"><div class=\"k\">Credentials in the code</div><div class=\"v\">$( ((blank)) && tbc "result" || echo "Not scanned")</div><p>Run <code>leak scan</code> on the full history.</p></div>"
  secret_sentence="$( ((blank)) && tbc "Secret types found by the history scan, or none." || echo "The full history has not been scanned yet; run <code>leak scan</code> and regenerate this report.")"
elif ((n_types == 0)); then
  secrets_stat='<div class="stat ok"><div class="k">Credentials in the code</div><div class="v">None found</div><p>No secret in any commit on any branch.</p></div>'
  secret_sentence="The history scan found no secrets in any commit."
else
  secrets_stat="<div class=\"stat bad\"><div class=\"k\">Credentials in the code</div><div class=\"v\">$n_types type(s) found</div><p>Compromised until rotated and the old value revoked.</p></div>"
  secret_sentence="The history scan found $n_types secret type(s): $(jq -r '[.[].RuleID] | unique | join(", ") | @html' "$scan"). Each is treated as compromised until it is rotated and the old value revoked."
fi

# Timeline: what the tools know, in order, plus the facts people must add.
timeline="<tr><td class=\"t\">$(tbc "date hh:mm")</td><td>Repository first pushed or made public</td><td>Account security log; snapshot <code>metadata.json</code></td></tr>
<tr><td class=\"t\">$(tbc "date hh:mm")</td><td>Exposure detected: $(tbc "how")</td><td>$(tbc "alert email, colleague, monitoring")</td></tr>
<tr><td class=\"t\">$(tbc "date hh:mm")</td><td>Copy contained (made private, deleted or taken down)</td><td>$(tbc source)</td></tr>
<tr><td class=\"t\">$(tbc "date hh:mm")</td><td>First secret revoked</td><td>$(tbc "provider console or audit log")</td></tr>
<tr><td class=\"t\">$(tbc "date hh:mm")</td><td>Last secret revoked</td><td>$(tbc "provider console or audit log")</td></tr>"
# Events the tools recorded, oldest first (each line starts with its UTC time).
auto=""
if [[ -n "$scan" ]]; then
  auto+="$(mtime "$scan")|<tr><td class=\"t\">$(mtime "$scan")</td><td>Full-history secret scan: $(jq 'length' "$scan") finding(s), $n_types type(s)</td><td><code>leak scan</code>, $(html "$(basename "$scan")")</td></tr>"$'\n'
fi
if ((blank)); then
  auto+="|<tr><td class=\"t\">$(tbc "date hh:mm")</td><td>Search for surviving copies</td><td><code>leak hunt</code></td></tr>"$'\n'
else
  auto+="$run|<tr><td class=\"t\">$run</td><td>Search for surviving copies: $total checks, $n_found found, $n_unknown not checked</td><td><code>leak hunt</code>, $(html "$(basename "$hunt")")</td></tr>"$'\n'
fi
timeline+="$(printf '%s' "$auto" | sort | cut -d'|' -f2-)"
timeline+="<tr><td class=\"t\">$(tbc "date hh:mm")</td><td>Notifications sent</td><td>$(tbc "to whom")</td></tr>"

# Evidence: bind this report to the saved results with checksums.
if ((blank)); then
  evidence="<tr><td>Copy hunt</td><td>$(tbc "folder")</td><td>$(tbc "SHA-256 of MANIFEST.sha256")</td></tr><tr><td>Secret scan</td><td>$(tbc "file")</td><td>$(tbc "SHA-256")</td></tr>"
else
  manifest="$hunt/MANIFEST.sha256"
  if [[ -f "$manifest" ]]; then
    evidence="<tr><td>Copy hunt: $(wc -l < "$manifest" | tr -d ' ') files, raw responses</td><td><code>$(html "$(basename "$hunt")")/</code></td><td><code>$(sha256 "$manifest")</code> (MANIFEST.sha256)</td></tr>"
  else
    evidence="<tr><td>Copy hunt</td><td><code>$(html "$(basename "$hunt")")/</code></td><td><span class=\"label warn\">No manifest</span></td></tr>"
  fi
  [[ -n "$scan" ]] && evidence+="<tr><td>Secret scan (redacted)</td><td><code>$(html "$(basename "$scan")")</code></td><td><code>$(sha256 "$scan")</code></td></tr>"
fi

if [[ -n "$secret_rows" ]]; then
  secrets_section="<table><thead><tr><th>Type</th><th>Findings</th><th>Files</th><th>First committed</th><th>Owner</th><th>Status</th></tr></thead><tbody>$secret_rows</tbody></table><p class=\"note\">Types and counts only. This report never contains secret values. Rotate the most powerful first: cloud keys, service accounts, database passwords.</p>"
elif [[ -n "$scan" ]]; then
  secrets_section="<p>No secrets were found in any commit. Keep the scan report with the evidence.</p>"
elif ((blank)); then
  secrets_section="<table><thead><tr><th>Type</th><th>Findings</th><th>Files</th><th>First committed</th><th>Owner</th><th>Status</th></tr></thead><tbody><tr><td>$(tbc type)</td><td>$(tbc n)</td><td>$(tbc n)</td><td>$(tbc date)</td><td>$(tbc owner)</td><td>$(tbc status)</td></tr></tbody></table><p class=\"note\">Types and counts only. Never write secret values in this report.</p>"
else
  secrets_section="<p>$(tbc "Run leak scan on the full history and pass --scan to fill this section")</p>"
fi

css="$(cat "$here/templates/report.css")"

cat > "$out" <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="generator" content="Spillkit $version">
<title>Incident report$( [[ -n "$id" ]] && echo " $(html "$id")"): exposure of source code</title>
<style>
$css
  @page {
    @top-left { content: "$tlp_label"; font: 700 8.5pt monospace; }
    @top-right { content: $id_css; font: 8.5pt sans-serif; color: #625A7C; }
    @bottom-left { content: "Prepared with Spillkit $version"; font: 8.5pt sans-serif; color: #625A7C; }
    @bottom-right { content: "Page " counter(page) " of " counter(pages); font: 8.5pt sans-serif; color: #625A7C; }
  }
</style>
</head>
<body>
<aside class="howto" aria-label="How to complete this report"><b>Draft generated by Spillkit.</b> $( ((blank)) && echo "Fill in" || echo "Sections 3 to 5 and appendix A were filled in from the tool results. Complete") every <mark class="tbc">[highlighted field]</mark>, then print to PDF (A4 is set up; this box does not print).</aside>
<main class="page">

<div class="doc-head">
  <div>
    <p class="doc-type">Incident report</p>
    <h1>Exposure of source code on a public repository</h1>
    <p class="subtitle">$repos_html</p>
  </div>
  <span class="tlp $tlp_class">$tlp_label</span>
</div>

<div class="control">
  <div><b>Incident ID</b><span>$id_html</span></div>
  <div><b>Severity</b><span>$(tbc "SEV-1 to SEV-4")</span></div>
  <div><b>Status</b><span>$(tbc "Open / Contained / Closed")</span></div>
  <div><b>Version</b><span>0.1 draft</span></div>
  <div><b>Report date</b><span>$today</span></div>
  <div><b>Prepared by</b><span>$(tbc "name, role")</span></div>
  <div><b>Approved by</b><span>$(tbc "name, role")</span></div>
  <div><b>Distribution</b><span>$(tbc "names or groups")</span></div>
</div>
<p class="note">$tlp_label: $tlp_rule All times are UTC (ISO 8601).</p>

<h2><span class="no">1</span>Summary</h2>
<div class="bluf">
  <p><b>What happened.</b> $(tbc "Whose code, pushed where, by which role (not who to blame), public for how long.")</p>
  <p><b>What we found.</b> $finding</p>
  <p><b>Secrets.</b> $secret_sentence</p>
  <p><b>What remains.</b> Copies cloned while the code was public cannot be detected by anyone, so the code is treated as disclosed.</p>
</div>
<div class="status">
  $copies_stat
  $secrets_stat
  <div class="stat warn"><div class="k">Source code</div><div class="v">Disclosed</div><p>May have been cloned while it was public.</p></div>
</div>
<h3>Decisions needed</h3>
<ol>
  <li><b>Confirm</b> that every credential in section 5 has been rotated and the old value revoked.</li>
  <li><b>Decide</b> on notifications (section 7), with legal advice where personal data may be involved.</li>
  <li><b>Approve</b> the actions in section 8, each with an owner and a due date.</li>
</ol>

<h2><span class="no">2</span>Incident details</h2>
<table>
  <thead><tr><th style="width:32%">Item</th><th>Detail</th></tr></thead><tbody>
  <tr><td>Repositories</td><td>$repos_html</td></tr>
  <tr><td>Exposure window</td><td>$(tbc "start to end, UTC; source: account security log")</td></tr>
  <tr><td>How the code was exposed</td><td>$(tbc "e.g. company repository pushed to a personal public account")</td></tr>
  <tr><td>How it was detected</td><td>$(tbc "alert email, colleague, monitoring")</td></tr>
  <tr><td>Personal or customer data</td><td>$(tbc "none / yes: which categories")</td></tr>
  <tr><td>Copies searched since</td><td>$since</td></tr>
</tbody></table>

<h2><span class="no">3</span>Timeline</h2>
<table>
  <thead><tr><th style="width:20%">Time (UTC)</th><th>Event</th><th style="width:32%">Source</th></tr></thead><tbody>
  $timeline
</tbody></table>

<h2><span class="no">4</span>Investigation: where copies could survive</h2>
<p>$( ((blank)) && echo "$(tbc "N") checks" || echo "$total checks on $run UTC: $(label ok "$n_clean clean") $(label "$( ((n_found)) && echo bad || echo na)" "$n_found found") $(label "$( ((n_unknown)) && echo warn || echo na)" "$n_unknown not checked")"). Each answer is saved as evidence (appendix A).</p>
<table>
  <thead><tr><th class="n">#</th><th style="width:36%">Check</th><th style="width:13%">Result</th><th>Detail</th></tr></thead><tbody>
  $check_rows
</tbody></table>

<h2><span class="no">5</span>Secrets to rotate</h2>
$secrets_section

<h2><span class="no">6</span>Impact and risk</h2>
<table>
  <thead><tr><th style="width:26%">Risk</th><th style="width:14%">Before actions</th><th style="width:14%">After actions</th><th>Why</th></tr></thead><tbody>
  <tr><td>Use of exposed credentials</td><td>$(label bad High)</td><td>$(tbc level)</td><td>Exposed keys are harvested within minutes. Rotation removes the risk; logs show whether anything was used.</td></tr>
  <tr><td>Disclosure of code and design</td><td>$(label warn Medium)</td><td>$(label warn Medium)</td><td>Cannot be undone: exposes logic, endpoints and architecture.</td></tr>
  <tr><td>Personal or customer data</td><td>$(tbc level)</td><td>$(tbc level)</td><td>Notification duties may apply (section 7).</td></tr>
  <tr><td>Reputation and contracts</td><td>$(tbc level)</td><td>$(tbc level)</td><td>Reduced by prompt, factual communication and evidence of new controls.</td></tr>
</tbody></table>

<h2><span class="no">7</span>Notification assessment</h2>
<table>
  <thead><tr><th style="width:42%">Who may need to be told</th><th style="width:12%">Required?</th><th style="width:16%">Deadline</th><th>Owner and status</th></tr></thead><tbody>
  <tr><td>Data protection authority, if personal data is at risk (for example GDPR Article 33)</td><td>$(tbc "yes / no")</td><td>72 hours from awareness</td><td>$(tbc "owner, status")</td></tr>
  <tr><td>Affected individuals, if the risk to them is high (for example GDPR Article 34)</td><td>$(tbc "yes / no")</td><td>Without undue delay</td><td>$(tbc "owner, status")</td></tr>
  <tr><td>Customers and partners under contract</td><td>$(tbc "yes / no")</td><td>$(tbc "per contract")</td><td>$(tbc "owner, status")</td></tr>
  <tr><td>Providers of the exposed credentials</td><td>$(tbc "yes / no")</td><td>$(tbc deadline)</td><td>$(tbc "owner, status")</td></tr>
</tbody></table>
<p class="note">Engineering guidance, not legal advice. Confirm obligations with your legal or data protection team.</p>

<h2><span class="no">8</span>Actions</h2>
<table>
  <thead><tr><th style="width:46%">Action</th><th>Owner</th><th>Due</th><th>Status</th></tr></thead><tbody>
  <tr><td>Rotate every credential in section 5, revoking the old values</td><td>$(tbc owner)</td><td>$(tbc date)</td><td>$(tbc status)</td></tr>
  <tr><td>Review access and billing logs from first push to the last revocation</td><td>$(tbc owner)</td><td>$(tbc date)</td><td>$(tbc status)</td></tr>
  <tr><td>Remove every copy marked Found; check every Not checked source by hand</td><td>$(tbc owner)</td><td>$(tbc date)</td><td>$(tbc status)</td></tr>
  <tr><td>Repeat the search for copies after 7 days</td><td>$(tbc owner)</td><td>$(tbc date)</td><td>$(tbc status)</td></tr>
  <tr><td>Send the notifications decided in section 7</td><td>$(tbc owner)</td><td>$(tbc date)</td><td>$(tbc status)</td></tr>
  <tr><td>Hold a blameless post-incident review</td><td>$(tbc owner)</td><td>$(tbc date)</td><td>$(tbc status)</td></tr>
</tbody></table>

<h2><span class="no">9</span>Root cause and lessons learned</h2>
<p><b>Root cause.</b> $(tbc "The condition that allowed the exposure, e.g. no control prevented company code from being pushed to a personal account.")</p>
<p><b>Contributing factors.</b> $(tbc "e.g. long-lived credentials stored in the code; no secret scanning before commit.")</p>
<p><b>What went well.</b> $(tbc "e.g. rotation started within 15 minutes of detection.")</p>
<p class="note">Describe conditions and controls, not individuals. The full review uses the post-incident review template.</p>

<div class="pagebreak"></div>
<h2><span class="no">A</span>Evidence and chain of custody</h2>
<table>
  <thead><tr><th style="width:30%">Evidence</th><th style="width:26%">Location</th><th>SHA-256</th></tr></thead><tbody>
  $evidence
</tbody></table>
<p><b>Held by.</b> $(tbc "name, storage location, access restricted to")</p>

<h2><span class="no">B</span>Method and limitations</h2>
<div class="two">
  <div class="box"><h3>Method</h3><ul><li>Read-only queries to public services. No credential was used or tested.</li><li>Secret scanning of every commit on every branch with gitleaks; values redacted.</li><li>Each answer saved with its raw response and a checksum manifest.</li></ul></div>
  <div class="box"><h3>Limitations</h3><ul><li>Private clones made while the code was public cannot be detected.</li><li>Results are a point in time; repeat the search after 7 days.</li><li>Some archives (archive.today, grep.app) must be checked by hand.</li></ul></div>
</div>

<h2><span class="no">C</span>Severity scale</h2>
<table>
  <thead><tr><th style="width:12%">Level</th><th>Meaning (example scale; use your organisation's own if it has one)</th></tr></thead><tbody>
  <tr><td>$(label bad SEV-1)</td><td>Working production credentials or personal data publicly exposed, and not yet contained.</td></tr>
  <tr><td>$(label bad SEV-2)</td><td>Credentials exposed but all revoked, or proprietary code publicly exposed.</td></tr>
  <tr><td>$(label warn SEV-3)</td><td>Internal code exposed with no secrets and limited sensitivity.</td></tr>
  <tr><td>$(label na SEV-4)</td><td>Non-sensitive material exposed and already contained.</td></tr>
</tbody></table>

<h2><span class="no">D</span>Document history</h2>
<table>
  <thead><tr><th style="width:12%">Version</th><th style="width:16%">Date</th><th style="width:24%">Author</th><th>Change</th></tr></thead><tbody>
  <tr><td>0.1</td><td>$today</td><td>$(tbc "name")</td><td>Draft generated by Spillkit $version$( ((blank)) || echo " from hunt $(jq -r '.run' <<<"$meta")")</td></tr>
</tbody></table>

<div class="doc-foot"><span>$tlp_label</span><span>Prepared with Spillkit $version · Contains no secret values</span></div>
</main>
</body>
</html>
HTML
echo "Report: $out"
