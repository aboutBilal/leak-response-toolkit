#!/usr/bin/env bash
# Scan the FULL git history of a repository for secrets, with values redacted.
# Uses a local gitleaks if installed, otherwise the official gitleaks Docker image.
#
# Usage: ./scripts/scan-secrets.sh <path-to-repo-or-mirror> [report.json] [--sarif findings.sarif]
#   --sarif FILE   also write SARIF 2.1.0 (for GitHub code scanning); values stay redacted
# Exit:  0 clean, 1 secrets found, 2 bad arguments, other = scanner failure
set -euo pipefail

case "${1:-}" in -h|--help) sed -n '2,/^set -/{/^#/s/^# \{0,1\}//p;}' "$0"; exit 0 ;; esac

GITLEAKS_IMAGE="ghcr.io/gitleaks/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f"

src=""; report=""; sarif=""
while (($#)); do
  case "$1" in
    --sarif) sarif="${2:-}"; [[ -n "$sarif" ]] || { echo "--sarif needs a file name" >&2; exit 2; }; shift 2 ;;
    *) if [[ -z "$src" ]]; then src="$1"; elif [[ -z "$report" ]]; then report="$1"; else echo "unexpected argument: $1" >&2; exit 2; fi; shift ;;
  esac
done
[[ -n "$src" && -d "$src" ]] || { echo "usage: $0 <path-to-repo-or-mirror> [report.json] [--sarif findings.sarif]" >&2; exit 2; }
command -v jq >/dev/null || { echo "missing: jq" >&2; exit 2; }

src="$(cd "$src" && pwd)"
report="${report:-$(dirname "$src")/secrets-report.json}"
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
  version="${GITLEAKS_IMAGE#*:}"; version="${version%%@*}"
  echo "==> gitleaks $version (Docker image, pinned by digest) on $src"
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

write_sarif() {
  # SARIF 2.1.0 built from the redacted JSON report: rule IDs, files, lines, commits. Never values.
  local json="$report_dir/$report_name"
  [[ -s "$json" ]] || echo "[]" > "$json"
  jq '{
    "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
    version: "2.1.0",
    runs: [{
      tool: { driver: {
        name: "leak-response-toolkit",
        informationUri: "https://github.com/aboutBilal/leak-response-toolkit",
        rules: ([.[].RuleID] | unique | map({
          id: ., name: .,
          shortDescription: { text: ("Secret detected: " + .) },
          helpUri: "https://github.com/aboutBilal/leak-response-toolkit/blob/main/docs/02-rotate-secrets.md",
          defaultConfiguration: { level: "error" }
        }))
      }},
      results: map({
        ruleId: .RuleID,
        level: "error",
        message: { text: ("\(.RuleID) committed in \(.Commit[0:10]) on \(.Date[0:10]). Rotate it first; removing it from Git does not un-leak it. (Value redacted.)") },
        locations: [{ physicalLocation: { artifactLocation: { uri: .File }, region: { startLine: (.StartLine // 1) } } }],
        partialFingerprints: { "leakToolkit/v1": .Fingerprint }
      })
    }]
  }' "$json" > "$sarif"
  echo "SARIF: $sarif"
}

case "$rc" in
  0) [[ -n "$sarif" ]] && write_sarif; echo; echo "No secrets found by gitleaks. Still check by hand: .env, *.pem, *.pfx, *.tfvars, appsettings*.json, kubeconfigs."; exit 0 ;;
  3) [[ -n "$sarif" ]] && write_sarif ;;
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
