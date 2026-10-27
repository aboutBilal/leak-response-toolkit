#!/usr/bin/env bash
# Score a local repository's secret hygiene, with a grade from A to F.
# Checks ignore rules, secret files tracked by Git, .env.example, commit hooks,
# CI secret scanning, Docker hygiene and (unless --no-scan) the full history.
# Read-only: changes nothing. See docs/08-secrets-by-design.md for the why.
#
# Usage: ./scripts/audit.sh [--no-scan] [--json] [path]   (default path: current directory)
#   --no-scan   skip the full-history secret scan (fast; history is reported as not checked)
#   --json      print one JSON object (grade, score, every check) instead of text
# Exit:  0 no critical findings, 1 critical findings, 2 bad arguments
set -uo pipefail

case "${1:-}" in -h|--help) sed -n '2,/^set -/{/^#/s/^# \{0,1\}//p;}' "$0"; exit 0 ;; esac
scan=1; json=0; repo=""
while (($#)); do
  case "$1" in
    --no-scan) scan=0 ;;
    --json) json=1 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) repo="$1" ;;
  esac
  shift
done
repo="${repo:-.}"
git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repository: $repo" >&2; exit 2; }
repo="$(git -C "$repo" rev-parse --show-toplevel)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -t 1 && -z "${NO_COLOR:-}" && "$json" == 0 ]]; then G=$'\033[32m' Y=$'\033[33m' R=$'\033[31m' B=$'\033[1m' N=$'\033[0m'; else G="" Y="" R="" B="" N=""; fi
points=0; max=0; critical=0; section=""; rows=()
say() { ((json)) || printf "$@"; }
record() { rows+=("$section"$'\t'"$1"$'\t'"$2"$'\t'"$3"$'\t'); }
heading() { section="$1"; say '%s%s%s\n' "$B" "$1" "$N"; }
pass() { say '  %s✔%s %s\n' "$G" "$N" "$1"; points=$((points + $2)); max=$((max + $2)); record pass "$2" "$1"; }
warn() { say '  %s!%s %s\n' "$Y" "$N" "$1"; max=$((max + $2)); record warn "$2" "$1"; }
fail() { say '  %s✘%s %s\n' "$R" "$N" "$1"; max=$((max + $2)); critical=1; record fail "$2" "$1"; }
tip()  { say '      → %s\n' "$1"; local last=$(( ${#rows[@]} - 1 )); rows[last]="${rows[last]}$1"; }

secret_files='(^|/)(\.env(\.[^/]*)?|[^/]*\.(pem|key|p12|pfx|jks|keystore)|id_(rsa|dsa|ecdsa|ed25519)|[^/]*\.tfstate(\.[^/]*)?|kubeconfig|[^/]*\.kubeconfig)$'
examples='(^|/)\.env\.(example|sample|template)$'

say '%sSecret hygiene audit:%s %s\n' "$B" "$N" "$repo"

heading "1. Files that usually hold secrets"
tracked="$(git -C "$repo" ls-files | grep -E "$secret_files" | grep -vE "$examples" || true)"
if [[ -z "$tracked" ]]; then pass "no secret files tracked by Git" 20
else
  fail "tracked by Git: $(echo "$tracked" | head -5 | paste -sd' ' -)$( (( $(echo "$tracked" | wc -l) > 5 )) && echo ' …')" 20
  tip "rotate anything inside them, then: git rm --cached <file> and add to .gitignore"
fi

heading "2. Ignore rules"
missing=()
for f in .env .env.local server.pem id_rsa terraform.tfstate; do
  git -C "$repo" check-ignore -q --no-index "$f" || missing+=("$f")
done
if ((${#missing[@]} == 0)); then pass ".env, keys and state files are ignored" 15
else warn "not ignored: ${missing[*]}" 15; tip "append prevention/gitignore-secrets to .gitignore"; fi

# Source code only: documentation that merely mentions these names does not count.
code_globs=('*.js' '*.mjs' '*.cjs' '*.ts' '*.jsx' '*.tsx' '*.py' '*.go' '*.rb' '*.java' '*.kt' '*.cs' '*.php' '*.rs' '*.ex' '*.exs')
uses_env="$(git -C "$repo" grep -lE 'process\.env|os\.environ|getenv\(|dotenv|ENV\[' -- "${code_globs[@]}" 2>/dev/null | head -1 || true)"
if [[ -n "$(git -C "$repo" ls-files | grep -E "$examples" || true)" ]]; then pass ".env.example documents the settings" 5
elif [[ -n "$uses_env" ]]; then warn "code reads environment variables but there is no .env.example" 5; tip "commit prevention/env/env.example, adapted"
else pass "no environment-based settings detected" 5; fi

heading "3. Commit-time blocking"
hooksdir="$(git -C "$repo" rev-parse --git-path hooks)"; [[ "$hooksdir" = /* ]] || hooksdir="$repo/$hooksdir"
cfg="$repo/.pre-commit-config.yaml"
if [[ -f "$cfg" ]] && grep -qiE 'gitleaks|trufflehog|detect-secrets' "$cfg"; then pass "pre-commit secret scanner configured" 10
else warn "no pre-commit secret scanner configured" 10; tip "copy prevention/pre-commit-config.yaml to .pre-commit-config.yaml"; fi
if [[ -x "$hooksdir/pre-commit" ]] || [[ -n "$(git -C "$repo" config core.hooksPath)" ]]; then pass "pre-commit hook installed in this clone" 5
else warn "no pre-commit hook installed in this clone" 5; tip "pre-commit install   (or copy prevention/hooks/pre-commit)"; fi

heading "4. CI secret scanning"
ci_files="$(cd "$repo" && ls .github/workflows/*.y*ml .gitlab-ci.yml azure-pipelines.yml bitbucket-pipelines.yml 2>/dev/null || true)"
if [[ -n "$ci_files" ]] && (cd "$repo" && grep -qliE 'gitleaks|trufflehog|secret[-_ ]?(scan|detection)|detect-secrets' $ci_files 2>/dev/null); then
  pass "CI runs a secret scan" 15
elif [[ -n "$ci_files" ]]; then warn "CI exists but runs no secret scan" 15; tip "add a job from prevention/ci/"
else warn "no CI configuration found" 15; tip "add a job from prevention/ci/"; fi

heading "5. Container hygiene"
# Files ending in .example or kept under examples/ are documentation, not builds.
dockerfiles="$(git -C "$repo" ls-files | grep -E '(^|/)(Dockerfile[^/]*|[^/]*\.Dockerfile)$' | grep -vE '(\.example$|(^|/)examples?/)' || true)"
if [[ -z "$dockerfiles" ]]; then pass "no Dockerfiles" 10
else
  bad_lines="$(cd "$repo" && grep -nHiE '^[[:space:]]*(ARG|ENV)[[:space:]]+[A-Z0-9_]*(SECRET|PASSWORD|PASSWD|TOKEN|API_KEY|PRIVATE_KEY)[A-Z0-9_]*[[:space:]]*=[[:space:]]*[^$[:space:]]' $dockerfiles 2>/dev/null | head -3 || true)"
  if [[ -f "$repo/.dockerignore" ]] && grep -qE '^\.env' "$repo/.dockerignore" && [[ -z "$bad_lines" ]]; then pass ".env excluded from builds; no secrets in ARG/ENV" 10
  else
    # Show where, never the value: file:line and the variable name only.
    where="$(echo "$bad_lines" | head -1 | sed -E 's/^([^:]+:[0-9]+):[[:space:]]*([Aa][Rr][Gg]|[Ee][Nn][Vv])[[:space:]]+([A-Za-z0-9_]+).*/\1 (\2 \3=<redacted>)/')"
    [[ -n "$bad_lines" ]] && { fail "secret-looking value baked into an image: $where" 10; tip "use BuildKit secret mounts: prevention/docker/Dockerfile.build-secrets.example"; }
    [[ -z "$bad_lines" ]] && { warn ".dockerignore missing or does not exclude .env" 10; tip "copy prevention/docker/dockerignore to .dockerignore"; }
  fi
fi

heading "6. Full history"
if ((scan)); then
  report="$(mktemp -t audit-scan-XXXXXX.json)"
  out="$("$here/scan-secrets.sh" "$repo" "$report" 2>&1)"; rc=$?
  case "$rc" in
    0) pass "no secrets found in any commit" 20 ;;
    1) fail "$(jq 'length' "$report") secret finding(s) in history (types: $(jq -r '[.[].RuleID]|unique|join(", ")' "$report"))" 20
       tip "rotate them first, then see docs/06-scenarios.md (scenario A) to clean history" ;;
    *) warn "scan could not run: $(echo "$out" | tail -1)" 20; tip "./leak doctor" ;;
  esac
  rm -f "$report"
else
  warn "history not scanned (--no-scan)" 20
fi

pct=$(( max > 0 ? points * 100 / max : 0 ))
if ((critical)); then grade=F
elif ((pct >= 90)); then grade=A
elif ((pct >= 75)); then grade=B
elif ((pct >= 60)); then grade=C
elif ((pct >= 40)); then grade=D
else grade=F; fi
if ((json)); then
  printf '%s\n' "${rows[@]}" | jq -R -s --arg repo "$repo" --argjson points "$points" --argjson max "$max" \
    --argjson pct "$pct" --arg grade "$grade" --argjson critical "$critical" '{
      repository: $repo, grade: $grade, score: $points, max: $max, percent: $pct, critical: ($critical == 1),
      checks: (split("\n") | map(select(length > 0) | split("\t")
        | {section: .[0], status: .[1], weight: (.[2] | tonumber), message: .[3], fix: (.[4] // "")}))
    }'
else
  echo
  echo "${B}Score $points/$max · Grade $grade${N}$( ((critical)) && echo "  (critical findings cap the grade at F)")"
fi
exit "$critical"
