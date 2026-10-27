#!/usr/bin/env bash
# List every fork of a GitHub repository, including forks of forks,
# so each one can go into the takedown request.
#
# Usage: ./scripts/list-forks.sh <owner>/<repo>
# Env:   GITHUB_TOKEN (optional) - higher rate limits.
set -euo pipefail

case "${1:-}" in -h|--help) sed -n '2,/^set -/{/^#/s/^# \{0,1\}//p;}' "$0"; exit 0 ;; esac

root="${1:-}"
[[ "$root" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "usage: $0 <owner>/<repo>" >&2; exit 2; }
command -v jq >/dev/null || { echo "missing: jq" >&2; exit 2; }

api() {
  local auth=()
  [[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  curl -fsS -H "Accept: application/vnd.github+json" "${auth[@]}" "https://api.github.com$1"
}

queue=("$root")
printf '%s\t%s\t%s\t%s\n' "FORK" "CREATED" "LAST_PUSH" "URL"
while ((${#queue[@]})); do
  current="${queue[0]}"
  queue=("${queue[@]:1}")
  page=1
  while :; do
    batch="$(api "/repos/$current/forks?per_page=100&page=$page" 2>/dev/null || echo "[]")"
    [[ "$(jq 'length' <<<"$batch")" -eq 0 ]] && break
    while IFS=$'\t' read -r name created pushed url forks; do
      printf '%s\t%s\t%s\t%s\n' "$name" "$created" "$pushed" "$url"
      if ((forks > 0)); then queue+=("$name"); fi
    done < <(jq -r '.[] | [.full_name, .created_at, .pushed_at, .html_url, (.forks_count|tostring)] | @tsv' <<<"$batch")
    page=$((page + 1))
  done
done | column -t -s $'\t'

echo
echo "Forks survive deletion of the original. List every URL above in the takedown request."
