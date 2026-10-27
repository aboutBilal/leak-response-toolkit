#!/usr/bin/env bash
# Snapshot a leaked GitHub repository before it is deleted:
# full mirror, repo metadata, forks, commit timeline, traffic (owner token only),
# plus a SHA-256 manifest so the evidence can be shown to be unchanged later.
#
# Usage: leak snapshot <owner>/<repo> [output-dir]   (default output-dir: ./evidence)
# Env:   GITHUB_TOKEN (optional) - higher rate limits; the owner's token also saves
#        traffic data and can mirror a repository that is already private.
# Exit:  0 complete, 2 bad arguments, 4 incomplete (some parts could not be saved)
# Note:  the mirror contains the leaked code and secrets. Keep evidence folders out of
#        every repository and share them only with the people handling the incident.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

repo=""; outroot="evidence"
while (($#)); do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit "$EXIT_USAGE" ;;
    *) if [[ -z "$repo" ]]; then repo="$1"; else outroot="$1"; fi; shift ;;
  esac
done
if [[ ! "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "usage: leak snapshot <owner>/<repo> [output-dir]" >&2
  exit "$EXIT_USAGE"
fi
for cmd in git curl jq; do
  command -v "$cmd" >/dev/null || { echo "missing: $cmd" >&2; exit "$EXIT_USAGE"; }
done
command -v sha256sum >/dev/null || command -v shasum >/dev/null || { echo "missing: sha256sum or shasum" >&2; exit "$EXIT_USAGE"; }

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out="$outroot/${repo/\//_}_${stamp}"
mkdir -p "$out"

incomplete=0

echo "==> Snapshot of $repo into $out"
echo "    taken at $stamp (UTC)" | tee "$out/README.txt"

echo "==> Repository metadata"
code="$(gh_get "/repos/$repo" "$out/metadata.json")"
if [[ "$code" == 200 ]]; then
  jq -r '"    visibility: \(.visibility)\n    created_at: \(.created_at)\n    pushed_at:  \(.pushed_at)\n    forks: \(.forks_count)  stars: \(.stargazers_count)  watchers: \(.subscribers_count)"' \
    "$out/metadata.json" | tee -a "$out/README.txt"
else
  echo "    could not read metadata (HTTP $code: deleted, private, or rate-limited)" | tee -a "$out/README.txt"
  rm -f "$out/metadata.json"; incomplete=1
fi

echo "==> Forks"
page=1
echo "[]" > "$out/forks.json"
forks_ok=1
while :; do
  code="$(gh_get "/repos/$repo/forks?per_page=100&page=$page" "$out/forks.page")"
  if [[ "$code" != 200 ]] || ! jq -e 'type == "array"' "$out/forks.page" >/dev/null 2>&1; then forks_ok=0; break; fi
  [[ "$(jq 'length' "$out/forks.page")" -eq 0 ]] && break
  jq -s '.[0] + .[1]' "$out/forks.json" "$out/forks.page" > "$out/forks.tmp" && mv "$out/forks.tmp" "$out/forks.json"
  page=$((page + 1))
done
rm -f "$out/forks.page"
if ((forks_ok)); then
  echo "    $(jq 'length' "$out/forks.json") fork(s) saved" | tee -a "$out/README.txt"
else
  echo "    fork list incomplete (HTTP $code): $(jq 'length' "$out/forks.json") saved" | tee -a "$out/README.txt"; incomplete=1
fi

echo "==> Traffic (needs the owner's token, last 14 days)"
for kind in clones views; do
  if [[ -n "${GITHUB_TOKEN:-}" ]] && [[ "$(gh_get "/repos/$repo/traffic/$kind" "$out/traffic-$kind.json")" == 200 ]]; then
    jq -r --arg k "$kind" '"    \($k): \(.count) total, \(.uniques) unique"' "$out/traffic-$kind.json" | tee -a "$out/README.txt"
  else
    rm -f "$out/traffic-$kind.json"
    echo "    $kind: not available (no token, or token is not the owner's)" | tee -a "$out/README.txt"
  fi
done

echo "==> Full mirror (every branch, tag and commit)"
git_auth_env
if git clone --quiet --mirror "https://github.com/$repo.git" "$out/repo.git" 2>/dev/null; then
  git --git-dir="$out/repo.git" log --all --format='%H %aI %an <%ae> %s' > "$out/commits.txt"
  first="$(tail -n 1 "$out/commits.txt" | cut -d' ' -f2)"
  echo "    $(wc -l < "$out/commits.txt") commit(s); oldest author date: ${first:-n/a}" | tee -a "$out/README.txt"
  echo "    note: author dates can be set by anyone; pushed_at and the owner's security log are more reliable" >> "$out/README.txt"
else
  echo "    clone failed (repository already gone, or private and no owner token)" | tee -a "$out/README.txt"
  incomplete=1
fi

echo "==> Checksum manifest"
(cd "$out" && sha256_files)
echo "    $(wc -l < "$out/MANIFEST.sha256") file(s) hashed"

echo
echo "Saved: $out"
[[ -d "$out/repo.git" ]] && echo "Next: leak scan $out/repo.git"
if ((incomplete)); then echo "The snapshot is incomplete (see above). Keep what was saved; screenshots can fill the gaps." >&2; exit "$EXIT_FAILED"; fi
