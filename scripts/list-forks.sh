#!/usr/bin/env bash
# List every fork of a GitHub repository, including forks of forks,
# so each one can go into the takedown request.
#
# Usage: leak forks <owner>/<repo>
# Env:   GITHUB_TOKEN (optional) - higher rate limits.
# Exit:  0 listed (possibly none), 2 bad arguments,
#        4 the list is incomplete (repository not found, rate limit or API error)
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

root=""
while (($#)); do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit "$EXIT_USAGE" ;;
    *) root="$1"; shift ;;
  esac
done
[[ "$root" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "usage: leak forks <owner>/<repo>" >&2; exit "$EXIT_USAGE"; }
command -v jq >/dev/null || { echo "missing: jq" >&2; exit "$EXIT_USAGE"; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
code="$(gh_get "/repos/$root" "$tmp/root.json")"
if [[ "$code" != 200 ]]; then
  if [[ "$code" == 404 ]]; then
    echo "Repository not found (deleted or private): $root" >&2
    echo "Forks of a deleted public repository survive; find them with: leak hunt $root" >&2
  else
    echo "GitHub API error (HTTP $code) for $root. Set GITHUB_TOKEN or try again later." >&2
  fi
  exit "$EXIT_FAILED"
fi

rows="$tmp/rows.tsv"; : > "$rows"
queue=("$root"); failed=0
while ((${#queue[@]})); do
  current="${queue[0]}"
  queue=("${queue[@]:1}")
  page=1
  while :; do
    code="$(gh_get "/repos/$current/forks?per_page=100&page=$page" "$tmp/page.json")"
    if [[ "$code" != 200 ]] || ! jq -e 'type == "array"' "$tmp/page.json" >/dev/null 2>&1; then
      echo "could not list forks of $current (HTTP $code)" >&2
      failed=1
      break
    fi
    [[ "$(jq 'length' "$tmp/page.json")" -eq 0 ]] && break
    while IFS=$'\t' read -r name created pushed url forks; do
      printf '%s\t%s\t%s\t%s\n' "$name" "$created" "$pushed" "$url" >> "$rows"
      if ((forks > 0)); then queue+=("$name"); fi
    done < <(jq -r '.[] | [.full_name, .created_at, .pushed_at, .html_url, (.forks_count|tostring)] | @tsv' "$tmp/page.json")
    page=$((page + 1))
  done
done

n="$(wc -l < "$rows" | tr -d ' ')"
if ((n == 0)); then
  echo "No forks of $root."
else
  { printf 'FORK\tCREATED\tLAST_PUSH\tURL\n'; cat "$rows"; } | table
  echo
  echo "$n fork(s). Forks survive deletion of the original: list every URL above in the takedown request."
fi
if ((failed)); then
  echo "The list is incomplete (see the errors above). Set GITHUB_TOKEN and run again." >&2
  exit "$EXIT_FAILED"
fi
