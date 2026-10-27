#!/usr/bin/env bash
# Scan the FULL git history of a repository for secrets, with values redacted.
# Uses a local gitleaks if installed, otherwise the official gitleaks Docker image.
#
# Usage: leak scan <path-to-repo-or-mirror> [report.json] [--sarif findings.sarif]
#   report.json    where to write the redacted JSON report (default: ./secrets-report.json)
#   --sarif FILE   also write SARIF 2.1.0 for GitHub code scanning; values stay redacted
# Exit:  0 clean, 1 secrets found, 2 bad arguments, 4 the scanner failed (results incomplete)
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

GITLEAKS_IMAGE="ghcr.io/gitleaks/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f"

src=""; report=""; sarif=""
while (($#)); do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --sarif) need_value "$1" "${2:-}"; sarif="$2"; shift 2 ;;
    -*) echo "unknown option: $1" >&2; exit "$EXIT_USAGE" ;;
    *) if [[ -z "$src" ]]; then src="$1"; elif [[ -z "$report" ]]; then report="$1"; else echo "unexpected argument: $1" >&2; exit "$EXIT_USAGE"; fi; shift ;;
  esac
done
[[ -n "$src" && -d "$src" ]] || { echo "usage: leak scan <path-to-repo-or-mirror> [report.json] [--sarif findings.sarif]" >&2; exit "$EXIT_USAGE"; }
command -v jq >/dev/null || { echo "missing: jq" >&2; exit "$EXIT_USAGE"; }

src="$(cd "$src" && pwd)"
report="${report:-$PWD/secrets-report.json}"
[[ -d "$(dirname "$report")" ]] || { echo "report folder does not exist: $(dirname "$report")" >&2; exit "$EXIT_USAGE"; }
report_dir="$(cd "$(dirname "$report")" && pwd)"
report_name="$(basename "$report")"
json="$report_dir/$report_name"
rm -f "$json"

# A bare mirror (repo.git) is scanned as-is; gitleaks walks every commit on every ref.
# gitleaks exits 3 for findings (set below), 0 when clean and anything else on errors.
set +e
if command -v gitleaks >/dev/null; then
  echo "==> gitleaks $(gitleaks version) on $src"
  gitleaks git "$src" --redact --no-banner --exit-code 3 \
    --report-format json --report-path "$json"
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
  echo "need gitleaks or docker: run 'leak doctor'" >&2
  exit "$EXIT_USAGE"
fi
set -e

if [[ "$rc" != 0 && "$rc" != 3 ]] || ! jq -e 'type == "array"' "$json" >/dev/null 2>&1; then
  echo "gitleaks failed (exit $rc): the scan is incomplete. Check the gitleaks configuration and run 'leak doctor'." >&2
  exit "$EXIT_FAILED"
fi

write_sarif() {
  # SARIF 2.1.0 built from the redacted JSON report: rule IDs, files, lines, commits. Never values.
  jq '{
    "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
    version: "2.1.0",
    runs: [{
      tool: { driver: {
        name: "spillkit",
        informationUri: "https://github.com/aboutBilal/spillkit",
        rules: ([.[].RuleID] | unique | map({
          id: ., name: .,
          shortDescription: { text: ("Secret detected: " + .) },
          helpUri: "https://github.com/aboutBilal/spillkit/blob/main/docs/02-rotate-secrets.md",
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
[[ -n "$sarif" ]] && write_sarif

if [[ "$rc" == 0 ]]; then
  echo
  echo "No secrets found in any commit. Report: $json"
  echo "Still check by hand: .env, *.pem, *.pfx, *.tfvars, appsettings*.json, kubeconfigs."
  exit "$EXIT_OK"
fi

echo
total="$(jq 'length' "$json")"
echo "==> $total finding(s), secret values redacted. Full report: $json"
echo "    Oldest first (when each secret entered the history); first 50 shown:"
jq -r '
  (["RULE","FILE","LINE","COMMIT","DATE"] | @tsv),
  (sort_by(.Date)[:50][] | [.RuleID, .File, (.StartLine|tostring), .Commit[0:10], .Date] | @tsv)
' "$json" | table

echo
echo "==> Distinct secret types to rotate"
jq -r 'group_by(.RuleID)[] | "  \(.[0].RuleID): \(length) finding(s) in \([.[].File] | unique | length) file(s)"' "$json"
echo
echo "Next: rotate every one of these - docs/02-rotate-secrets.md"
exit "$EXIT_FOUND"
