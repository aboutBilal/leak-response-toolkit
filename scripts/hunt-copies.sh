#!/usr/bin/env bash
# Hunt for surviving public copies of one or more leaked GitHub repositories.
# Checks GitHub (repo, forks, same-name forks, commit search, owner activity),
# public event archives, web and code archives, code search and mirror sites,
# then writes a dated markdown report plus the raw responses.
#
# Usage: leak hunt [--since YYYY-MM-DD] [--out DIR] <owner>/<repo> [<owner>/<repo> ...]
#   --since   look for same-name copies created on or after this date (default: 60 days ago)
#   --out     parent folder for the results (default: ./hunts)
# Env:   GITHUB_TOKEN (optional) - higher rate limits (60 -> 5000 requests/hour).
# Exit:  0 nothing found, 1 copies found, 2 bad arguments,
#        4 incomplete: some sources could not be checked (rate limits, outages)
#
# Read-only: every request is an anonymous (or token-authenticated) public query.
# A source that fails is reported as "not checked", never as clean.
set -uo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# GNU date (Linux), then BSD date (macOS).
since="$(date -u -d '60 days ago' +%F 2>/dev/null || date -u -v-60d +%F 2>/dev/null || date -u +%F)"
outroot="hunts"
repos=()
while (($#)); do
  case "$1" in
    --since) need_value "$1" "${2:-}"; since="$2"; shift 2 ;;
    --out) need_value "$1" "${2:-}"; outroot="$2"; shift 2 ;;
    -h|--help) print_help "$0"; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit "$EXIT_USAGE" ;;
    *) repos+=("$1"); shift ;;
  esac
done
((${#repos[@]})) || { echo "usage: leak hunt [--since YYYY-MM-DD] [--out DIR] <owner>/<repo> ..." >&2; exit 2; }
[[ "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "--since must be a date like 2026-01-31" >&2; exit 2; }
for r in "${repos[@]}"; do
  [[ "$r" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "not owner/repo: $r" >&2; exit 2; }
done
for cmd in curl jq; do command -v "$cmd" >/dev/null || { echo "missing: $cmd" >&2; exit 2; }; done

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out="$outroot/hunt_$stamp"
raw="$out/raw"
mkdir -p "$raw"
report="$out/REPORT.md"
results="$out/results.jsonl" # one JSON object per check, for ./leak report
section=""

# --- helpers ---------------------------------------------------------------
gh() { gh_get "$@"; } # gh <path> <outfile> -> HTTP status (token kept out of argv)
search_pause() { [[ -n "${GITHUB_TOKEN:-}" ]] && sleep 2 || sleep 7; } # search API: 10/min anonymous
fetch() { http_get "$@"; }
is_json() { jq -e "$1" "$2" >/dev/null 2>&1; } # is_json <filter> <file>: true when the file parses and the filter holds
safe() { echo "$1" | tr '/*:?&=' '______'; }
CLEAN="clean"; FOUND="**found**"; UNKNOWN="not checked"; REVIEW="review"; COVERED="covered below"
row() {
  printf '| %s | %s | %s |\n' "$1" "$2" "$3" >> "$report"
  local status=info
  case "$2" in "$CLEAN") status=clean ;; "$FOUND") status=found ;; "$UNKNOWN") status=unknown ;; "$COVERED") status=covered ;; esac
  jq -cn --arg section "$section" --arg check "$1" --arg status "$status" --arg detail "$3" \
    '{section: $section, check: $check, status: $status, detail: $detail}' >> "$results"
}

{
  echo "# Copy hunt report"
  echo
  echo "- **Run:** $stamp (UTC)"
  echo "- **Repositories:** ${repos[*]}"
  echo "- **Same-name copies searched since:** $since"
  echo "- **Method:** read-only public queries; raw responses in \`raw/\`"
  echo
  echo "Results: **found** needs follow-up; review means a match worth a look; not checked means the source was unavailable or rate-limited (check it by hand); covered below means another check answers it."
} > "$report"

jq -cn --arg run "$stamp" --arg since "$since" --args '{run: $run, since: $since, repos: $ARGS.positional}' "${repos[@]}" > "$out/meta.json"

owners=()
for r in "${repos[@]}"; do
  o="${r%%/*}"
  [[ " ${owners[*]} " == *" $o "* ]] || owners+=("$o")
done

# --- per repository ----------------------------------------------------------
for r in "${repos[@]}"; do
  name="${r#*/}"; s="$(safe "$r")"
  echo "==> $r"
  section="$r"
  { echo; echo "## \`$r\`"; echo; echo "| Check | Result | Detail |"; echo "|---|---|---|"; } >> "$report"

  code="$(gh "/repos/$r" "$raw/repo_$s.json")"
  case "$code" in
    200) row "Repository on GitHub" "$FOUND" "Still reachable: visibility $(jq -r .visibility "$raw/repo_$s.json"), pushed $(jq -r .pushed_at "$raw/repo_$s.json")" ;;
    404) row "Repository on GitHub" "$CLEAN" "Not found (deleted or private)" ;;
    *)   row "Repository on GitHub" "$UNKNOWN" "HTTP $code" ;;
  esac

  if [[ "$code" == 200 ]]; then
    fcode="$(gh "/repos/$r/forks?per_page=100" "$raw/forks_$s.json")"
    if [[ "$fcode" == 200 ]] && is_json 'type == "array"' "$raw/forks_$s.json"; then
      n="$(jq 'length' "$raw/forks_$s.json")"
      if ((n > 0)); then row "Direct forks" "$FOUND" "$n: $(jq -r '[.[].full_name]|join(", ")' "$raw/forks_$s.json")"; else row "Direct forks" "$CLEAN" "None"; fi
    else row "Direct forks" "$UNKNOWN" "HTTP $fcode"; fi
  elif [[ "$code" == 404 ]]; then
    row "Direct forks" "$COVERED" "Cannot be listed for a removed repository; the same-name forks check below finds them"
  else
    row "Direct forks" "$UNKNOWN" "HTTP $code"
  fi

  # Same-name forks: trace each to its root. Forks of a deleted public repo survive and re-root.
  search_pause
  code="$(gh "/search/repositories?q=$(printf %s "$name" | jq -sRr @uri)+in:name+fork:only+created:%3E%3D$since&per_page=100" "$raw/samename-forks_$s.json")"
  if [[ "$code" == 200 ]] && is_json '.items | type == "array"' "$raw/samename-forks_$s.json"; then
    total="$(jq .total_count "$raw/samename-forks_$s.json")"; linked=(); untraced=0
    while read -r f; do
      [[ -z "$f" ]] && continue
      fc="$(gh "/repos/$f" "$raw/fork_$(safe "$f").json")"
      if [[ "$fc" != 200 ]]; then untraced=$((untraced + 1)); continue; fi
      src="$(jq -r '.source.full_name // "none"' "$raw/fork_$(safe "$f").json")"
      [[ "${src,,}" == "${r,,}" || "${src%%/*}" == "${r%%/*}" ]] && linked+=("$f")
    done < <(jq -r '.items[].full_name' "$raw/samename-forks_$s.json")
    if ((${#linked[@]})); then row "Same-name forks since $since" "$FOUND" "${#linked[@]} trace back to this repository: ${linked[*]}"
    elif ((untraced > 0)); then row "Same-name forks since $since" "$UNKNOWN" "$untraced of $total could not be traced (rate limit or error); set GITHUB_TOKEN and run again"
    else row "Same-name forks since $since" "$CLEAN" "$total checked (first 100 traced to their root); none trace back to this repository"; fi
  else
    row "Same-name forks since $since" "$UNKNOWN" "Search HTTP $code"
  fi

  # Web archives
  for target in "github.com/$r*" "raw.githubusercontent.com/$r/*" "codeload.github.com/$r*"; do
    f="$raw/wayback_$(safe "$target").json"
    code="$(fetch "https://web.archive.org/cdx/search/cdx?url=$target&output=json&fl=timestamp,original,statuscode" "$f")"
    if [[ "$code" == 200 ]] && n="$(jq 'if length>0 then length-1 else 0 end' "$f" 2>/dev/null)"; then
      if ((n > 0)); then row "Wayback Machine: \`$target\`" "$FOUND" "$n capture(s), first $(jq -r '.[1][0] | "\(.[0:4])-\(.[4:6])-\(.[6:8])"' "$f")"; else row "Wayback Machine: \`$target\`" "$CLEAN" "0 captures"; fi
    else row "Wayback Machine: \`$target\`" "$UNKNOWN" "HTTP $code"; fi
    sleep 2
  done

  code="$(fetch "https://archive.softwareheritage.org/api/1/origin/https://github.com/$r/get/" "$raw/swh_$s.json")"
  case "$code" in
    200) row "Software Heritage" "$FOUND" "Archived: $(jq -r .url "$raw/swh_$s.json")" ;;
    404) row "Software Heritage" "$CLEAN" "Not archived" ;;
    *)   row "Software Heritage" "$UNKNOWN" "HTTP $code" ;;
  esac

  q="$(printf '%s fork:yes archived:yes count:100' "$r" | jq -sRr @uri)"
  code="$(curl -s --max-time 90 -H 'Accept: text/event-stream' -o "$raw/sourcegraph_$s.txt" -w '%{http_code}' "https://sourcegraph.com/.api/search/stream?q=$q" || echo 000)"
  if [[ "$code" == 200 ]] && grep -q '^event: done' "$raw/sourcegraph_$s.txt"; then
    hits="$(awk '/^event: matches/{getline; sub(/^data: /,""); print}' "$raw/sourcegraph_$s.txt" | jq -r '.[].repository' 2>/dev/null | sort -u)"
    if [[ -n "$hits" ]]; then row "Sourcegraph code search" "$FOUND" "Referenced in: $(echo "$hits" | paste -sd, -)"; else row "Sourcegraph code search" "$CLEAN" "0 matches"; fi
  else row "Sourcegraph code search" "$UNKNOWN" "HTTP $code or incomplete response"; fi
  # Same-name public projects on GitLab created since the date: re-uploads often keep the name.
  code="$(fetch "https://gitlab.com/api/v4/projects?search=$(printf %s "$name" | jq -sRr @uri)&created_after=${since}T00:00:00Z&order_by=created_at&sort=desc&per_page=100&simple=true" "$raw/gitlab-projects_$s.json")"
  if [[ "$code" == 200 ]] && is_json 'type == "array"' "$raw/gitlab-projects_$s.json"; then
    exact="$(jq -r --arg n "$name" '[.[] | select((.path | ascii_downcase) == ($n | ascii_downcase)) | .web_url] | join(", ")' "$raw/gitlab-projects_$s.json")"
    if [[ -n "$exact" ]]; then row "GitLab projects named \`$name\` since $since" "$REVIEW" "$exact"
    else row "GitLab projects named \`$name\` since $since" "$CLEAN" "None with this exact name"; fi
  else row "GitLab projects named \`$name\` since $since" "$UNKNOWN" "HTTP $code"; fi
done

# --- per owner ---------------------------------------------------------------
for o in "${owners[@]}"; do
  s="$(safe "$o")"
  echo "==> owner $o"
  section="owner:$o"
  { echo; echo "## Owner account \`$o\`"; echo; echo "| Check | Result | Detail |"; echo "|---|---|---|"; } >> "$report"

  code="$(gh "/users/$o" "$raw/user_$s.json")"
  if [[ "$code" == 200 ]]; then
    rc_repos="$(gh "/users/$o/repos?per_page=100&type=all" "$raw/user-repos_$s.json")"
    if [[ "$rc_repos" == 200 ]] && is_json 'type == "array"' "$raw/user-repos_$s.json"; then
      # The leaked repositories themselves are checked above; list only the others.
      others="$(printf '%s\n' "${repos[@]}" | jq -R 'ascii_downcase' | jq -s -c . | jq -r --slurpfile r "$raw/user-repos_$s.json" '. as $leaked
        | [$r[0][] | select((.full_name | ascii_downcase) as $n | $leaked | index($n) | not) | "\(.name) (pushed \(.pushed_at[:10]))"]
        | if length > 0 then "\(length): \(join(", "))" else "" end')"
      if [[ -n "$others" ]]; then row "Other public repositories" "$REVIEW" "$others"
      else row "Other public repositories" "$CLEAN" "None besides the leaked repositories"; fi
    else row "Other public repositories" "$UNKNOWN" "HTTP $rc_repos"; fi
    rc_gists="$(gh "/users/$o/gists?per_page=100" "$raw/user-gists_$s.json")"
    if [[ "$rc_gists" == 200 ]] && is_json 'type == "array"' "$raw/user-gists_$s.json"; then
      g="$(jq 'length' "$raw/user-gists_$s.json")"
      if ((g > 0)); then row "Public gists" "$FOUND" "$g gist(s); review for pasted code"; else row "Public gists" "$CLEAN" "None"; fi
    else row "Public gists" "$UNKNOWN" "HTTP $rc_gists"; fi
  elif [[ "$code" == 404 ]]; then
    row "Account" "$CLEAN" "No GitHub account of this name (deleted or renamed)"
  else
    row "Account" "$UNKNOWN" "HTTP $code"
  fi

  ecode="$(gh "/users/$o/events/public?per_page=100" "$raw/events_$s.json")"
  if [[ "$ecode" == 200 ]] && is_json 'type == "array"' "$raw/events_$s.json"; then
    pattern="$(printf '%s\n' "${repos[@]}" | grep -i "^$o/" | paste -sd'|' -)"
    n="$(jq --arg p "$pattern" '[.[] | select(.repo.name|test($p;"i"))] | length' "$raw/events_$s.json")"
    if ((n > 0)); then row "GitHub public activity (90 days)" "$FOUND" "$n event(s) for the leaked repositories"; else row "GitHub public activity (90 days)" "$CLEAN" "No events for the leaked repositories"; fi
  else row "GitHub public activity (90 days)" "$UNKNOWN" "HTTP $ecode"; fi

  for kind in author committer; do
    search_pause
    code="$(gh "/search/commits?q=$kind:$o&per_page=100" "$raw/commits-${kind}_${s}.json")"
    if [[ "$code" == 200 ]]; then
      elsewhere="$(jq -r --arg o "$o" '[.items[].repository.full_name | select((split("/")[0]|ascii_downcase) != ($o|ascii_downcase))] | unique | join(", ")' "$raw/commits-${kind}_${s}.json")"
      if [[ -n "$elsewhere" ]]; then row "Commits by $o ($kind) in others' repos" "$FOUND" "$elsewhere"; else row "Commits by $o ($kind) in others' repos" "$CLEAN" "None (default branches indexed by GitHub)"; fi
    else row "Commits by $o ($kind) in others' repos" "$UNKNOWN" "Search HTTP $code"; fi
  done

  sql="SELECT created_at, event_type, actor_login, repo_name FROM github_events WHERE lower(actor_login)=lower('$o') AND created_at >= '$since' ORDER BY created_at FORMAT TSVWithNames"
  ccode="$(curl -s --max-time 120 -o "$raw/clickhouse_$s.tsv" -w '%{http_code}' "https://play.clickhouse.com/?user=play" --data-binary "$sql" || echo 000)"
  if [[ "$ccode" == 200 ]] && head -1 "$raw/clickhouse_$s.tsv" | grep -q '^created_at'; then
    n=$(( $(wc -l < "$raw/clickhouse_$s.tsv") - 1 )); ((n < 0)) && n=0
    if ((n > 0)); then row "Public event archive (ClickHouse, since $since)" "$REVIEW" "$n event(s); see raw file. Dataset has gaps."
    else row "Public event archive (ClickHouse, since $since)" "$CLEAN" "No events (dataset has gaps: supporting evidence only)"; fi
  else row "Public event archive (ClickHouse)" "$UNKNOWN" "HTTP $ccode or unexpected response"; fi

  code="$(fetch "https://gitlab.com/api/v4/users?username=$o" "$raw/gitlab_$s.json")"
  if [[ "$code" == 200 ]] && ! is_json 'type == "array"' "$raw/gitlab_$s.json"; then row "GitLab account of the same name" "$UNKNOWN" "Unexpected response"
  elif [[ "$code" == 200 && "$(jq 'length' "$raw/gitlab_$s.json")" -gt 0 ]]; then row "GitLab account of the same name" "$REVIEW" "$(jq -r '.[0].web_url' "$raw/gitlab_$s.json")"
  elif [[ "$code" == 200 ]]; then row "GitLab account of the same name" "$CLEAN" "None"
  else row "GitLab account of the same name" "$UNKNOWN" "HTTP $code"; fi

  code="$(fetch "https://codeberg.org/api/v1/users/$o" "$raw/codeberg_$s.json")"
  case "$code" in
    200) row "Codeberg account of the same name" "$REVIEW" "https://codeberg.org/$o" ;;
    404) row "Codeberg account of the same name" "$CLEAN" "None" ;;
    *)   row "Codeberg account of the same name" "$UNKNOWN" "HTTP $code" ;;
  esac
done

cat >> "$report" <<'EOF'

## Not covered by this script

- **Private clones** made while the repository was public. Nobody can see these: rotate every secret.
- **archive.today** and **grep.app** block automated queries: search them by hand in a browser.
- **Copies re-uploaded without history** under a new name: use `leak commits` with commit IDs, or compare distinctive strings from the code.
- **GH Archive** (permanent push log: commit IDs, messages, author emails, not code): query it for the exposure hours once they are known.
EOF

(cd "$out" && sha256_files)
found="$(grep -c '^| .*| \*\*found\*\* |' "$report")"
unchecked="$(grep -c '^| .*| not checked |' "$report")"
echo
echo "Report: $report"
echo "Findings needing follow-up: $found"
echo "Sources not checked: $unchecked$( ((unchecked)) && echo " (check them by hand, or set GITHUB_TOKEN and run again)")"
if ((found > 0)); then exit "$EXIT_FOUND"; fi
if ((unchecked > 0)); then exit "$EXIT_FAILED"; fi
exit "$EXIT_OK"
