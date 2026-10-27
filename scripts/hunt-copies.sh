#!/usr/bin/env bash
# Hunt for surviving public copies of one or more leaked GitHub repositories.
# Checks GitHub (repo, forks, same-name forks, commit search, owner activity),
# public event archives, web and code archives, code search and mirror sites,
# then writes a dated markdown report plus the raw responses.
#
# Usage: ./scripts/hunt-copies.sh [--since YYYY-MM-DD] [--out DIR] <owner>/<repo> [<owner>/<repo> ...]
# Env:   GITHUB_TOKEN (optional) - higher rate limits (60 -> 5000 requests/hour).
#
# Read-only: every request is an anonymous (or token-authenticated) public query.
set -uo pipefail

since="$(date -u -d '60 days ago' +%F 2>/dev/null || date -u +%F)"
outroot="hunts"
repos=()
while (($#)); do
  case "$1" in
    --since) since="$2"; shift 2 ;;
    --out) outroot="$2"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) repos+=("$1"); shift ;;
  esac
done
((${#repos[@]})) || { echo "usage: $0 [--since YYYY-MM-DD] [--out DIR] <owner>/<repo> ..." >&2; exit 2; }
for r in "${repos[@]}"; do
  [[ "$r" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "not owner/repo: $r" >&2; exit 2; }
done
for cmd in curl jq; do command -v "$cmd" >/dev/null || { echo "missing: $cmd" >&2; exit 2; }; done

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out="$outroot/hunt_$stamp"
raw="$out/raw"
mkdir -p "$raw"
report="$out/REPORT.md"

# --- helpers ---------------------------------------------------------------
gh() { # gh <path> <outfile> -> http code
  local auth=()
  [[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  curl -s --max-time 60 -o "$2" -w '%{http_code}' -H "Accept: application/vnd.github+json" "${auth[@]}" "https://api.github.com$1"
}
search_pause() { [[ -n "${GITHUB_TOKEN:-}" ]] && sleep 2 || sleep 7; } # search API: 10/min anonymous
fetch() { curl -s --max-time 90 -o "$2" -w '%{http_code}' -A "leak-response-toolkit" "$1"; }
safe() { echo "$1" | tr '/*:?&=' '______'; }
row() { printf '| %s | %s | %s |\n' "$1" "$2" "$3" >> "$report"; }
CLEAN="✅ clean"; FOUND="⚠️ **found**"; UNKNOWN="❔ not checked"

{
  echo "# Copy hunt report"
  echo
  echo "- **Run:** $stamp (UTC)"
  echo "- **Repositories:** ${repos[*]}"
  echo "- **Same-name copies searched since:** $since"
  echo "- **Method:** read-only public queries; raw responses in \`raw/\`"
  echo
  echo "Legend: $CLEAN nothing found · $FOUND needs follow-up · $UNKNOWN source unavailable or rate-limited (check by hand)"
} > "$report"

owners=()
for r in "${repos[@]}"; do
  o="${r%%/*}"
  [[ " ${owners[*]} " == *" $o "* ]] || owners+=("$o")
done

# --- per repository ----------------------------------------------------------
for r in "${repos[@]}"; do
  name="${r#*/}"; s="$(safe "$r")"
  echo "==> $r"
  { echo; echo "## \`$r\`"; echo; echo "| Check | Result | Detail |"; echo "|---|---|---|"; } >> "$report"

  code="$(gh "/repos/$r" "$raw/repo_$s.json")"
  case "$code" in
    200) row "Repository on GitHub" "$FOUND" "Still reachable: visibility $(jq -r .visibility "$raw/repo_$s.json"), pushed $(jq -r .pushed_at "$raw/repo_$s.json")" ;;
    404) row "Repository on GitHub" "$CLEAN" "Not found (deleted or private)" ;;
    *)   row "Repository on GitHub" "$UNKNOWN" "HTTP $code" ;;
  esac

  if [[ "$code" == 200 ]]; then
    gh "/repos/$r/forks?per_page=100" "$raw/forks_$s.json" >/dev/null
    n="$(jq 'length' "$raw/forks_$s.json" 2>/dev/null || echo 0)"
    if ((n > 0)); then row "Direct forks" "$FOUND" "$n: $(jq -r '[.[].full_name]|join(", ")' "$raw/forks_$s.json")"; else row "Direct forks" "$CLEAN" "None"; fi
  else
    row "Direct forks" "$UNKNOWN" "Cannot be listed for a removed repository; see same-name forks below"
  fi

  # Same-name forks: trace each to its root. Forks of a deleted public repo survive and re-root.
  search_pause
  code="$(gh "/search/repositories?q=$(printf %s "$name" | jq -sRr @uri)+in:name+fork:only+created:%3E%3D$since&per_page=100" "$raw/samename-forks_$s.json")"
  if [[ "$code" == 200 ]]; then
    total="$(jq .total_count "$raw/samename-forks_$s.json")"; linked=()
    while read -r f; do
      [[ -z "$f" ]] && continue
      gh "/repos/$f" "$raw/fork_$(safe "$f").json" >/dev/null
      src="$(jq -r '.source.full_name // "none"' "$raw/fork_$(safe "$f").json")"
      [[ "${src,,}" == "${r,,}" || "${src%%/*}" == "${r%%/*}" ]] && linked+=("$f")
    done < <(jq -r '.items[].full_name' "$raw/samename-forks_$s.json")
    if ((${#linked[@]})); then row "Same-name forks since $since" "$FOUND" "${#linked[@]} trace back to this repository: ${linked[*]}"
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
  if curl -s --max-time 90 -H 'Accept: text/event-stream' "https://sourcegraph.com/.api/search/stream?q=$q" > "$raw/sourcegraph_$s.txt"; then
    hits="$(awk '/^event: matches/{getline; sub(/^data: /,""); print}' "$raw/sourcegraph_$s.txt" | jq -r '.[].repository' 2>/dev/null | sort -u)"
    if [[ -n "$hits" ]]; then row "Sourcegraph code search" "$FOUND" "Referenced in: $(echo "$hits" | paste -sd, -)"; else row "Sourcegraph code search" "$CLEAN" "0 matches"; fi
  else row "Sourcegraph code search" "$UNKNOWN" "Request failed"; fi
done

# --- per owner ---------------------------------------------------------------
for o in "${owners[@]}"; do
  s="$(safe "$o")"
  echo "==> owner $o"
  { echo; echo "## Owner account \`$o\`"; echo; echo "| Check | Result | Detail |"; echo "|---|---|---|"; } >> "$report"

  code="$(gh "/users/$o" "$raw/user_$s.json")"
  if [[ "$code" == 200 ]]; then
    gh "/users/$o/repos?per_page=100&type=all" "$raw/user-repos_$s.json" >/dev/null
    gh "/users/$o/gists?per_page=100" "$raw/user-gists_$s.json" >/dev/null
    row "Other public repositories" "ℹ️ review" "$(jq -r 'length' "$raw/user-repos_$s.json"): $(jq -r '[.[] | "\(.name) (pushed \(.pushed_at[:10]))"] | join(", ")' "$raw/user-repos_$s.json")"
    g="$(jq 'length' "$raw/user-gists_$s.json" 2>/dev/null || echo 0)"
    if ((g > 0)); then row "Public gists" "$FOUND" "$g gist(s); review for pasted code"; else row "Public gists" "$CLEAN" "None"; fi
  else
    row "Account" "$UNKNOWN" "HTTP $code"
  fi

  gh "/users/$o/events/public?per_page=100" "$raw/events_$s.json" >/dev/null
  pattern="$(printf '%s\n' "${repos[@]}" | grep -i "^$o/" | paste -sd'|' -)"
  n="$(jq --arg p "$pattern" '[.[]? | select(.repo.name|test($p;"i"))] | length' "$raw/events_$s.json" 2>/dev/null || echo 0)"
  if ((n > 0)); then row "GitHub public activity (90 days)" "$FOUND" "$n event(s) for the leaked repositories"; else row "GitHub public activity (90 days)" "$CLEAN" "No events for the leaked repositories"; fi

  for kind in author committer; do
    search_pause
    code="$(gh "/search/commits?q=$kind:$o&per_page=100" "$raw/commits-${kind}_${s}.json")"
    if [[ "$code" == 200 ]]; then
      elsewhere="$(jq -r --arg o "$o" '[.items[].repository.full_name | select((split("/")[0]|ascii_downcase) != ($o|ascii_downcase))] | unique | join(", ")' "$raw/commits-${kind}_${s}.json")"
      if [[ -n "$elsewhere" ]]; then row "Commits by $o ($kind) in others' repos" "$FOUND" "$elsewhere"; else row "Commits by $o ($kind) in others' repos" "$CLEAN" "None (default branches indexed by GitHub)"; fi
    else row "Commits by $o ($kind) in others' repos" "$UNKNOWN" "Search HTTP $code"; fi
  done

  sql="SELECT created_at, event_type, actor_login, repo_name FROM github_events WHERE lower(actor_login)=lower('$o') AND created_at >= '$since' ORDER BY created_at FORMAT TSVWithNames"
  if curl -s --max-time 120 "https://play.clickhouse.com/?user=play" --data-binary "$sql" > "$raw/clickhouse_$s.tsv"; then
    n=$(( $(wc -l < "$raw/clickhouse_$s.tsv") - 1 )); ((n < 0)) && n=0
    if ((n > 0)); then row "Public event archive (ClickHouse, since $since)" "ℹ️ review" "$n event(s); see raw file. Dataset has gaps."
    else row "Public event archive (ClickHouse, since $since)" "$CLEAN" "No events (dataset has gaps: supporting evidence only)"; fi
  else row "Public event archive (ClickHouse)" "$UNKNOWN" "Request failed"; fi

  code="$(fetch "https://gitlab.com/api/v4/users?username=$o" "$raw/gitlab_$s.json")"
  if [[ "$code" == 200 && "$(jq 'length' "$raw/gitlab_$s.json")" -gt 0 ]]; then row "GitLab account of the same name" "ℹ️ review" "$(jq -r '.[0].web_url' "$raw/gitlab_$s.json")"
  elif [[ "$code" == 200 ]]; then row "GitLab account of the same name" "$CLEAN" "None"
  else row "GitLab account of the same name" "$UNKNOWN" "HTTP $code"; fi

  code="$(fetch "https://codeberg.org/api/v1/users/$o" "$raw/codeberg_$s.json")"
  case "$code" in
    200) row "Codeberg account of the same name" "ℹ️ review" "https://codeberg.org/$o" ;;
    404) row "Codeberg account of the same name" "$CLEAN" "None" ;;
    *)   row "Codeberg account of the same name" "$UNKNOWN" "HTTP $code" ;;
  esac
done

cat >> "$report" <<'EOF'

## Not covered by this script

- **Private clones** made while the repository was public. Nobody can see these: rotate every secret.
- **archive.today** and **grep.app** block automated queries: search them by hand in a browser.
- **Copies re-uploaded without history** under a new name: use `find-commit-copies.sh` with commit IDs, or compare distinctive strings from the code.
- **GH Archive** (permanent push log: commit IDs, messages, author emails, not code): query it for the exposure hours once they are known.
EOF

(cd "$out" && find . -type f ! -name MANIFEST.sha256 -print0 | sort -z | xargs -0 sha256sum > MANIFEST.sha256)
echo
echo "Report: $report"
echo "Findings needing follow-up: $(grep -c '^| .*| ⚠️ \*\*found\*\* |' "$report")"
