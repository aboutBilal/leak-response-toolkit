#!/usr/bin/env bash
# Find public GitHub repositories that contain specific commits.
# A copy pushed with its history carries the original commit IDs, whatever
# the repository is called, so this finds renamed re-uploads too.
#
# Usage: leak commits [--exclude <owner>/<repo>] <commit-sha> [<commit-sha> ...]
#   --exclude   leave out the original repository from the results
# Tip:   take 2-3 IDs from the original repository: the first commit, and a recent one.
#        git log --reverse --format=%H | head -1 ; git log -1 --format=%H
# Note:  GitHub's commit search indexes default branches of public repositories.
# Exit:  0 no copies, 1 copies found, 2 bad arguments, 4 a search failed (results incomplete)
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

exclude=""
shas=()
while (($#)); do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --exclude) need_value "$1" "${2:-}"; exclude="${2,,}"; shift 2 ;;
    -*) echo "unknown option: $1" >&2; exit "$EXIT_USAGE" ;;
    *) shas+=("$1"); shift ;;
  esac
done
((${#shas[@]})) || { echo "usage: leak commits [--exclude <owner>/<repo>] <commit-sha> ..." >&2; exit "$EXIT_USAGE"; }
command -v jq >/dev/null || { echo "missing: jq" >&2; exit "$EXIT_USAGE"; }

tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
found=0; failed=0; first=1
for sha in "${shas[@]}"; do
  [[ "$sha" =~ ^[0-9a-fA-F]{7,40}$ ]] || { echo "skip, not a commit ID: $sha" >&2; continue; }
  if ((first == 0)); then [[ -n "${GITHUB_TOKEN:-}" ]] && sleep 2 || sleep 7; fi # search API: 10 requests/minute anonymous
  first=0
  code="$(gh_get "/search/commits?q=hash:${sha,,}&per_page=100" "$tmp")"
  if [[ "$code" != 200 ]] || ! jq -e '.items | type == "array"' "$tmp" >/dev/null 2>&1; then
    echo "${sha:0:12}  search failed (HTTP $code): $(jq -r '.message // "unexpected response"' "$tmp" 2>/dev/null || echo "unexpected response")"
    failed=1
    continue
  fi
  repos="$(jq -r --arg x "$exclude" '[.items[].repository.full_name | select(ascii_downcase != $x)] | unique | .[]' "$tmp")"
  if [[ -z "$repos" ]]; then
    echo "${sha:0:12}  no public copies"
  else
    echo "${sha:0:12}  FOUND in:"
    while read -r r; do echo "              https://github.com/$r"; done <<<"$repos"
    found=1
  fi
done
if ((found)); then exit "$EXIT_FOUND"; fi
if ((failed)); then echo "Some searches failed: the result is incomplete. Set GITHUB_TOKEN and run again." >&2; exit "$EXIT_FAILED"; fi
exit "$EXIT_OK"
