#!/usr/bin/env bash
# Find public GitHub repositories that contain specific commits.
# A copy pushed with its history carries the original commit IDs, whatever
# the repository is called, so this finds renamed re-uploads too.
#
# Usage: ./scripts/find-commit-copies.sh [--exclude <owner>/<repo>] <commit-sha> [<commit-sha> ...]
# Tip:   take 2-3 IDs from the original repository: the first commit, and a recent one.
#        git log --reverse --format=%H | head -1 ; git log -1 --format=%H
# Note:  GitHub's commit search indexes default branches of public repositories.
set -euo pipefail

case "${1:-}" in -h|--help) sed -n '2,/^set -/{/^#/s/^# \{0,1\}//p;}' "$0"; exit 0 ;; esac

exclude=""
shas=()
while (($#)); do
  case "$1" in
    --exclude) exclude="${2,,}"; shift 2 ;;
    *) shas+=("$1"); shift ;;
  esac
done
((${#shas[@]})) || { echo "usage: $0 [--exclude <owner>/<repo>] <commit-sha> ..." >&2; exit 2; }
command -v jq >/dev/null || { echo "missing: jq" >&2; exit 2; }

auth=()
[[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
found=0
for sha in "${shas[@]}"; do
  [[ "$sha" =~ ^[0-9a-fA-F]{7,40}$ ]] || { echo "skip, not a commit ID: $sha" >&2; continue; }
  resp="$(curl -s --max-time 60 -H "Accept: application/vnd.github+json" "${auth[@]}" \
    "https://api.github.com/search/commits?q=hash:${sha,,}&per_page=100")"
  if ! jq -e '.items' >/dev/null 2>&1 <<<"$resp"; then
    echo "${sha:0:12}  search failed: $(jq -r '.message // "unknown error"' <<<"$resp")"
    continue
  fi
  repos="$(jq -r --arg x "$exclude" '[.items[].repository.full_name | select(ascii_downcase != $x)] | unique | .[]' <<<"$resp")"
  if [[ -z "$repos" ]]; then
    echo "${sha:0:12}  no public copies"
  else
    echo "${sha:0:12}  FOUND in:"
    while read -r r; do echo "              https://github.com/$r"; done <<<"$repos"
    found=1
  fi
  [[ -n "${GITHUB_TOKEN:-}" ]] && sleep 2 || sleep 7 # search API: 10 requests/minute anonymous
done
exit "$found"
