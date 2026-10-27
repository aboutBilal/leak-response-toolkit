#!/usr/bin/env bash
# Build a print-ready leadership report from a copy hunt (and optionally a secret scan).
# The investigation table, counts and secret types are filled in from the results;
# facts the tools cannot know (exposure window, owners, decisions) stay highlighted.
#
# Usage: leak report <hunt-dir> [--scan secrets-report.json] [--out report.html]
#   <hunt-dir>   a folder written by hunt-copies.sh (has meta.json and results.jsonl)
#   --scan       the JSON report written by scan-secrets.sh (secret TYPES are used, never values)
#   --out        output file (default: <hunt-dir>/executive-report.html)
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

hunt=""; scan=""; out=""
while (($#)); do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --scan) need_value "$1" "${2:-}"; scan="$2"; shift 2 ;;
    --out) need_value "$1" "${2:-}"; out="$2"; shift 2 ;;
    -*) echo "unknown option: $1" >&2; exit "$EXIT_USAGE" ;;
    *) if [[ -z "$hunt" ]]; then hunt="$1"; else echo "unexpected argument: $1" >&2; exit "$EXIT_USAGE"; fi; shift ;;
  esac
done
[[ -n "$hunt" ]] || { print_help "$0" >&2; exit "$EXIT_USAGE"; }
[[ -f "$hunt/meta.json" && -f "$hunt/results.jsonl" ]] || { echo "not a hunt folder (needs meta.json and results.jsonl): $hunt" >&2; exit 2; }
[[ -z "$scan" || -f "$scan" ]] || { echo "scan report not found: $scan" >&2; exit 2; }
command -v jq >/dev/null || { echo "missing: jq" >&2; exit 2; }
out="${out:-$hunt/executive-report.html}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

meta="$(cat "$hunt/meta.json")"
results="$(jq -s '.' "$hunt/results.jsonl")"
repos="$(jq -r '.repos | join(", ")' <<<"$meta")"
run="$(jq -r '.run | "\(.[0:4])-\(.[4:6])-\(.[6:8]) \(.[9:11]):\(.[11:13]) UTC"' <<<"$meta")"
total="$(jq 'length' <<<"$results")"
n_found="$(jq '[.[] | select(.status=="found")] | length' <<<"$results")"
n_unknown="$(jq '[.[] | select(.status=="unknown")] | length' <<<"$results")"
n_clean="$(jq '[.[] | select(.status=="clean")] | length' <<<"$results")"
tbc() { printf '<mark class="tbc">[%s]</mark>' "$1"; }

if ((n_found == 0)); then
  copies_card='<div class="card ok"><div class="k">Public copies today</div><div class="v">None found</div><p>'"$total"' checks: '"$n_clean"' clean, '"$n_unknown"' not checkable.</p></div>'
  finding="A scan of public sources found <b>no surviving public copy</b>."
else
  copies_card='<div class="card bad"><div class="k">Public copies today</div><div class="v">'"$n_found"' to act on</div><p>See Section 3; each needs removal or review.</p></div>'
  finding="A scan of public sources found <b>$n_found item(s) that need action</b> (Section 3)."
fi

secret_rows=""; secret_summary="$(tbc "credential types in the code")"; secrets_card_v="$(tbc "Rotated / In progress")"
if [[ -n "$scan" ]]; then
  # Types and counts only; the report never contains secret values.
  secret_rows="$(jq -r --arg owner "$(tbc owner)" --arg st "$(tbc status)" \
    'group_by(.RuleID)[] | "<tr><td>\(.[0].RuleID|@html)</td><td>\(length)</td><td>\([.[].File]|unique|length)</td><td>\(min_by(.Date).Date[0:10])</td><td>\($owner)</td><td>\($st)</td></tr>"' "$scan")"
  n_types="$(jq '[.[].RuleID] | unique | length' "$scan")"
  if ((n_types == 0)); then
    secret_summary="The history scan found no secrets"
    secrets_card_v="None found"
  else
    secret_summary="$n_types type(s) found by the history scan: $(jq -r '[.[].RuleID] | unique | join(", ") | @html' "$scan")"
    secrets_card_v="$n_types type(s) found"
  fi
fi

check_rows="$(jq -r '
  def pill: if .status=="clean" then "<span class=\"pill ok\">Clean</span>"
            elif .status=="found" then "<span class=\"pill bad\">Found</span>"
            elif .status=="unknown" then "<span class=\"pill warn\">Not checked</span>"
            else "<span class=\"pill na\">Review</span>" end;
  to_entries[] | "<tr><td class=\"n\">\(.key+1)</td><td>\(.value.section|@html)</td><td>\(.value.check|gsub("`";"")|@html)</td><td>\(.value|pill)</td><td>\(.value.detail|gsub("`";"")|@html)</td></tr>"' <<<"$results")"

style="$(sed -n '/<style>/,/<\/style>/p' "$here/templates/executive-report.html")"

cat > "$out" <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Exposure Report</title>
$style
</head>
<body>
<main>
<div class="draft"><b>Generated draft.</b> Sections 3 and 4 were filled in from the tool results. Complete every <mark class="tbc">[highlighted field]</mark>, then delete this box and print to PDF.</div>

<div class="eyebrow">Incident report · Confidential</div>
<h1>Exposure of source code on a public repository</h1>
<p style="color:var(--ink-2);margin:0">$(jq -rn --arg r "$repos" '$r|@html')</p>

<div class="meta">
  <div><b>Report date</b><span>$(date -u +%F)</span></div>
  <div><b>Affected party</b><span>$(tbc "team / client")</span></div>
  <div><b>Status</b><span>$(tbc "Contained / Open / Closed")</span></div>
  <div><b>Prepared by</b><span>$(tbc "name, role")</span></div>
</div>

<h2>1. Executive summary</h2>
<div class="summary">
  <p><b>What happened.</b> $(tbc "Whose code, pushed where, public for how long.")</p>
  <p><b>What the investigation found.</b> $finding $total checks were run on $run.</p>
  <p><b>Secrets.</b> $secret_summary.$( [[ "$secrets_card_v" == "None found" ]] || echo " Every one is treated as compromised until rotated and the old value revoked.")</p>
  <p><b>What remains.</b> Copies cloned while the code was public cannot be detected by anyone, so the code is treated as disclosed.</p>
</div>
<div class="cards">
  $copies_card
  <div class="card $( [[ "$secrets_card_v" == "None found" ]] && echo ok || echo bad)"><div class="k">Credentials in the code</div><div class="v">$secrets_card_v</div><p>Safe only once each is rotated and revoked.</p></div>
  <div class="card warn"><div class="k">Source code</div><div class="v">Disclosed</div><p>May have been cloned while public.</p></div>
</div>

<h2>2. Key facts</h2>
<table>
  <tr><th style="width:32%">Item</th><th>Detail</th></tr>
  <tr><td>Repositories</td><td>$(jq -rn --arg r "$repos" '$r|@html')</td></tr>
  <tr><td>Exposure window</td><td>$(tbc "start – end UTC; source: account security log")</td></tr>
  <tr><td>How it was noticed</td><td>$(tbc "alert email, colleague, monitoring")</td></tr>
  <tr><td>Copies searched since</td><td>$(jq -r '.since' <<<"$meta")</td></tr>
  <tr><td>Personal or customer data</td><td>$(tbc "yes / no")</td></tr>
</table>

<h2>3. Investigation: where copies could survive</h2>
<p>$total checks · <span class="pill ok">$n_clean clean</span> <span class="pill bad">$n_found found</span> <span class="pill warn">$n_unknown not checked</span>. Raw responses and a checksum manifest are kept with the hunt results.</p>
<table>
  <tr><th class="n">#</th><th style="width:18%">Target</th><th style="width:26%">Check</th><th style="width:12%">Result</th><th>Detail</th></tr>
  $check_rows
</table>
<h3>What no one can check</h3>
<ul>
  <li><b>Private clones</b> made while the code was public.</li>
  <li><b>Pages in archives that block automated queries</b> (archive.today, grep.app): check them by hand.</li>
</ul>

<h2>4. Secrets to rotate</h2>
$(if [[ -n "$secret_rows" ]]; then echo '<table><tr><th>Type</th><th>Findings</th><th>Files</th><th>First seen</th><th>Owner</th><th>Status</th></tr>'"$secret_rows"'</table><p class="note">Types and counts only. Values are never included in this report.</p>'; elif [[ -n "$scan" ]]; then echo "<p>No secrets were found in any commit. Keep the scan report with the evidence.</p>"; else echo "<p>$(tbc "Run leak scan and pass --scan to fill this section")</p>"; fi)

<h2>5. Next actions</h2>
<table>
  <tr><th style="width:50%">Action</th><th>Owner</th><th>Status</th></tr>
  <tr><td>Rotate every credential above, revoking the old values</td><td>$(tbc owner)</td><td>$(tbc status)</td></tr>
  <tr><td>Review logs from first push to rotation</td><td>$(tbc owner)</td><td>$(tbc status)</td></tr>
  <tr><td>Remove every copy marked Found; check the Not checked sources by hand</td><td>$(tbc owner)</td><td>$(tbc status)</td></tr>
  <tr><td>Repeat this hunt after 7 days</td><td>$(tbc owner)</td><td>$(tbc date)</td></tr>
  <tr><td>Notify affected parties where required</td><td>$(tbc owner)</td><td>$(tbc status)</td></tr>
</table>

<footer>
  <span>Generated by leak-response-toolkit from hunt $(jq -r '.run' <<<"$meta")</span>
  <span>Confidential</span>
</footer>
</main>
</body>
</html>
HTML
echo "Report: $out"
