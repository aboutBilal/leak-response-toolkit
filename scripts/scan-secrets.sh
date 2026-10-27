#!/usr/bin/env bash
# Scan the FULL git history of a repository for secrets, with values redacted.
# Uses a local gitleaks if installed, otherwise the official gitleaks Docker image.
#
# Usage: ./scripts/scan-secrets.sh <path-to-repo-or-mirror> [report.json]
set -euo pipefail

case "${1:-}" in -h|--help) sed -n '2,/^set -/{/^#/s/^# \{0,1\}//p;}' "$0"; exit 0 ;; esac

GITLEAKS_IMAGE="ghcr.io/gitleaks/gitleaks:v8.30.1"

src="${1:-}"
[[ -n "$src" && -d "$src" ]] || { echo "usage: $0 <path-to-repo-or-mirror> [report.json]" >&2; exit 2; }
command -v jq >/dev/null || { echo "missing: jq" >&2; exit 2; }

src="$(cd "$src" && pwd)"
report="${2:-$(dirname "$src")/secrets-report.json}"
report_dir="$(cd "$(dirname "$report")" && pwd)"
report_name="$(basename "$report")"

# A bare mirror (repo.git) is scanned as-is; gitleaks walks every commit on every ref.
set +e
if command -v gitleaks >/dev/null; then
  echo "==> gitleaks $(gitleaks version) on $src"
  gitleaks git "$src" --redact --no-banner --exit-code 3 \
    --report-format json --report-path "$report_dir/$report_name"
  rc=$?
elif command -v docker >/dev/null; then
  echo "==> gitleaks (Docker: $GITLEAKS_IMAGE) on $src"
  docker run --rm --network none --user "$(id -u):$(id -g)" \
    -v "$src:/repo:ro" -v "$report_dir:/out" \
    "$GITLEAKS_IMAGE" git /repo --redact --no-banner --exit-code 3 \
    --report-format json --report-path "/out/$report_name"
  rc=$?
else
  echo "need gitleaks or docker" >&2
  exit 2
fi
set -e

case "$rc" in
  0) echo; echo "No secrets found by gitleaks. Still check by hand: .env, *.pem, *.pfx, *.tfvars, appsettings*.json, kubeconfigs."; exit 0 ;;
  3) ;;
  *) echo "gitleaks failed (exit $rc)" >&2; exit "$rc" ;;
esac

echo
total="$(jq 'length' "$report_dir/$report_name")"
echo "==> $total finding(s), secret values redacted. Full report: $report_dir/$report_name"
echo "    Oldest first (when each secret entered the history); first 50 shown:"
jq -r '
  (["RULE","FILE","LINE","COMMIT","DATE"] | @tsv),
  (sort_by(.Date)[:50][] | [.RuleID, .File, (.StartLine|tostring), .Commit[0:10], .Date] | @tsv)
' "$report_dir/$report_name" | column -t -s $'\t'

echo
echo "==> Distinct secret types to rotate"
jq -r 'group_by(.RuleID)[] | "  \(.[0].RuleID): \(length) finding(s) in \([.[].File] | unique | length) file(s)"' "$report_dir/$report_name"
echo
echo "Next: rotate every one of these - docs/02-rotate-secrets.md"
exit 1
