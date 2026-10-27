#!/usr/bin/env bash
# Snapshot a leaked GitHub repository before it is deleted:
# full mirror, repo metadata, forks, commit timeline, traffic (owner token only),
# plus a SHA-256 manifest so the evidence can be shown to be unchanged later.
#
# Usage: ./scripts/snapshot-evidence.sh <owner>/<repo> [output-dir]
# Env:   GITHUB_TOKEN (optional) - higher rate limits; owner's token also saves traffic data.
set -euo pipefail

case "${1:-}" in -h|--help) sed -n '2,/^set -/{/^#/s/^# \{0,1\}//p;}' "$0"; exit 0 ;; esac

repo="${1:-}"
if [[ ! "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "usage: $0 <owner>/<repo> [output-dir]" >&2
  exit 2
fi
for cmd in git curl jq; do
  command -v "$cmd" >/dev/null || { echo "missing: $cmd" >&2; exit 2; }
done
# GNU coreutils on Linux, shasum on macOS.
if command -v sha256sum >/dev/null; then SHA256=(sha256sum)
elif command -v shasum >/dev/null; then SHA256=(shasum -a 256)
else echo "missing: sha256sum or shasum" >&2; exit 2; fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out="${2:-evidence}/${repo/\//_}_${stamp}"
mkdir -p "$out"

api() {
  local auth=()
  [[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  curl -fsS -H "Accept: application/vnd.github+json" "${auth[@]}" "https://api.github.com$1"
}

echo "==> Snapshot of $repo into $out"
echo "    taken at $stamp (UTC)" | tee "$out/README.txt"

echo "==> Repository metadata"
if api "/repos/$repo" > "$out/metadata.json"; then
  jq -r '"    visibility: \(.visibility)\n    created_at: \(.created_at)\n    pushed_at:  \(.pushed_at)\n    forks: \(.forks_count)  stars: \(.stargazers_count)  watchers: \(.subscribers_count)"' \
    "$out/metadata.json" | tee -a "$out/README.txt"
else
  echo "    could not read metadata (repo deleted, private, or rate-limited)" | tee -a "$out/README.txt"
fi

echo "==> Forks"
page=1
echo "[]" > "$out/forks.json"
while :; do
  batch="$(api "/repos/$repo/forks?per_page=100&page=$page" 2>/dev/null || echo "[]")"
  [[ "$(jq 'length' <<<"$batch")" -eq 0 ]] && break
  jq -s '.[0] + .[1]' "$out/forks.json" <(echo "$batch") > "$out/forks.tmp" && mv "$out/forks.tmp" "$out/forks.json"
  page=$((page + 1))
done
echo "    $(jq 'length' "$out/forks.json") fork(s) saved" | tee -a "$out/README.txt"

echo "==> Traffic (needs the owner's token, last 14 days)"
for kind in clones views; do
  if [[ -n "${GITHUB_TOKEN:-}" ]] && api "/repos/$repo/traffic/$kind" > "$out/traffic-$kind.json" 2>/dev/null; then
    jq -r --arg k "$kind" '"    \($k): \(.count) total, \(.uniques) unique"' "$out/traffic-$kind.json" | tee -a "$out/README.txt"
  else
    rm -f "$out/traffic-$kind.json"
    echo "    $kind: not available (no token, or token is not the owner's)" | tee -a "$out/README.txt"
  fi
done

echo "==> Full mirror (every branch, tag and commit)"
if git clone --quiet --mirror "https://github.com/$repo.git" "$out/repo.git"; then
  git --git-dir="$out/repo.git" log --all --format='%H %aI %an <%ae> %s' > "$out/commits.txt"
  first="$(tail -n 1 "$out/commits.txt" | cut -d' ' -f2)"
  echo "    $(wc -l < "$out/commits.txt") commit(s); oldest author date: ${first:-n/a}" | tee -a "$out/README.txt"
  echo "    note: author dates can be set by anyone; pushed_at and the owner's security log are more reliable" >> "$out/README.txt"
else
  echo "    clone failed (repo already gone or private)" | tee -a "$out/README.txt"
fi

echo "==> Checksum manifest"
(cd "$out" && find . -type f ! -name MANIFEST.sha256 -print0 | sort -z | xargs -0 "${SHA256[@]}" > MANIFEST.sha256)
echo "    $(wc -l < "$out/MANIFEST.sha256") file(s) hashed"

echo
echo "Done: $out"
echo "Next: ./scripts/scan-secrets.sh $out/repo.git"
