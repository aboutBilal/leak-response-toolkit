#!/usr/bin/env bash
# Score a local repository's secret hygiene, with a grade from A to F.
# Checks ignore rules, secret files tracked by Git, .env.example, commit hooks,
# CI secret scanning, Docker hygiene and (unless --no-scan) the full history.
# Read-only: changes nothing. See docs/08-secrets-by-design.md for the why.
#
# Usage: leak audit [--no-scan] [--json] [--sarif FILE] [path]   (default path: current directory)
#   --no-scan     skip the full-history secret scan (fast; history is reported as not checked)
#   --json        print one JSON object (grade, score, every check) instead of text
#   --sarif FILE  also write the findings as SARIF 2.1.0 for GitHub code scanning
# Exit:  0 no critical findings, 1 critical findings, 2 bad arguments
set -uo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

scan=1; json=0; repo=""; sarif=""
while (($#)); do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --no-scan) scan=0 ;;
    --json) json=1 ;;
    --sarif) need_value "$1" "${2:-}"; sarif="$2"; shift ;;
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
points=0; max=0; critical=0; section=""; rows=(); loc=
say() { ((json)) || printf "$@"; }
# loc: where a finding applies (path or path:line), set just before warn/fail; used for SARIF.
record() { rows+=("$section"$'\t'"$1"$'\t'"$2"$'\t'"$3"$'\t'"$loc"$'\t'); loc=""; }
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
  loc="$(echo "$tracked" | head -1)"
  fail "tracked by Git: $(echo "$tracked" | head -5 | paste -sd' ' -)$( (( $(echo "$tracked" | wc -l) > 5 )) && echo ' …')" 20
  tip "rotate anything inside them, then: git rm --cached <file> and add to .gitignore"
fi

heading "2. Ignore rules"
missing=()
for f in .env .env.local server.pem id_rsa terraform.tfstate; do
  git -C "$repo" check-ignore -q --no-index "$f" || missing+=("$f")
done
if ((${#missing[@]} == 0)); then pass ".env, keys and state files are ignored" 15
else loc=".gitignore"; warn "not ignored: ${missing[*]}" 15; tip "append prevention/gitignore-secrets to .gitignore"; fi

# Source code only: documentation that merely mentions these names does not count.
code_globs=('*.js' '*.mjs' '*.cjs' '*.ts' '*.jsx' '*.tsx' '*.py' '*.go' '*.rb' '*.java' '*.kt' '*.cs' '*.php' '*.rs' '*.ex' '*.exs')
uses_env="$(git -C "$repo" grep -lE 'process\.env|os\.environ|getenv\(|dotenv|ENV\[' -- "${code_globs[@]}" 2>/dev/null | head -1 || true)"
if [[ -n "$(git -C "$repo" ls-files | grep -E "$examples" || true)" ]]; then pass ".env.example documents the settings" 5
elif [[ -n "$uses_env" ]]; then loc="$uses_env"; warn "code reads environment variables but there is no .env.example" 5; tip "commit prevention/env/env.example, adapted"
else pass "no environment-based settings detected" 5; fi

heading "3. Commit-time blocking"
hooksdir="$(git -C "$repo" rev-parse --git-path hooks)"; [[ "$hooksdir" = /* ]] || hooksdir="$repo/$hooksdir"
cfg="$repo/.pre-commit-config.yaml"
if [[ -f "$cfg" ]] && grep -qiE 'gitleaks|trufflehog|detect-secrets' "$cfg"; then pass "pre-commit secret scanner configured" 10
else loc=".pre-commit-config.yaml"; warn "no pre-commit secret scanner configured" 10; tip "copy prevention/pre-commit-config.yaml to .pre-commit-config.yaml"; fi
if [[ -x "$hooksdir/pre-commit" ]] || [[ -n "$(git -C "$repo" config core.hooksPath)" ]]; then pass "pre-commit hook installed in this clone" 5
else loc=".pre-commit-config.yaml"; warn "no pre-commit hook installed in this clone" 5; tip "pre-commit install   (or copy prevention/hooks/pre-commit)"; fi

heading "4. CI secret scanning"
ci_files="$(cd "$repo" && ls .github/workflows/*.y*ml .gitlab-ci.yml azure-pipelines.yml bitbucket-pipelines.yml 2>/dev/null || true)"
if [[ -n "$ci_files" ]] && (cd "$repo" && grep -qliE 'gitleaks|trufflehog|secret[-_ ]?(scan|detection)|detect-secrets' $ci_files 2>/dev/null); then
  pass "CI runs a secret scan" 15
elif [[ -n "$ci_files" ]]; then loc="$(echo "$ci_files" | head -1)"; warn "CI exists but runs no secret scan" 15; tip "add a job from prevention/ci/"
else loc=".github/workflows"; warn "no CI configuration found" 15; tip "add a job from prevention/ci/"; fi

heading "5. Container hygiene"
# Files ending in .example or kept under examples/ are documentation, not builds.
dockerfiles=()
while IFS= read -r f; do dockerfiles+=("$f"); done < <(git -C "$repo" ls-files | grep -E '(^|/)(Dockerfile[^/]*|[^/]*\.Dockerfile)$' | grep -vE '(\.example$|(^|/)examples?/)' || true)
if ((${#dockerfiles[@]} == 0)); then pass "no Dockerfiles" 10
else
  # Report where a secret-looking value is baked in: file, line and variable name only.
  # The message is assembled from those three parts, so the value can never be printed.
  where=""
  secret_kv='^[[:space:]]*([Aa][Rr][Gg]|[Ee][Nn][Vv])[[:space:]]+([A-Za-z0-9_]*([Ss][Ee][Cc][Rr][Ee][Tt]|[Pp][Aa][Ss][Ss][Ww][Oo]?[Rr][Dd]|[Tt][Oo][Kk][Ee][Nn]|[Aa][Pp][Ii]_[Kk][Ee][Yy]|[Pp][Rr][Ii][Vv][Aa][Tt][Ee]_[Kk][Ee][Yy])[A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*[^$[:space:]]'
  for f in "${dockerfiles[@]}"; do
    n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      n=$((n + 1))
      if [[ "$line" =~ $secret_kv ]]; then
        where="$f:$n (${BASH_REMATCH[1]^^} ${BASH_REMATCH[2]}=<redacted>)"
        dloc="$f:$n"
        break 2
      fi
    done < "$repo/$f"
  done
  if [[ -n "$where" ]]; then
    loc="$dloc"
    fail "secret-looking value baked into an image: $where" 10
    tip "use BuildKit secret mounts: prevention/docker/Dockerfile.build-secrets.example"
  elif [[ -f "$repo/.dockerignore" ]] && grep -qE '^\.env' "$repo/.dockerignore"; then
    pass ".env excluded from builds; no secrets in ARG/ENV" 10
  else
    loc=".dockerignore"
    warn ".dockerignore missing or does not exclude .env" 10
    tip "copy prevention/docker/dockerignore to .dockerignore"
  fi
fi

heading "6. Full history"
if ((scan)); then
  report="$(mktemp -t audit-scan-XXXXXX.json)"
  out="$("$here/scan-secrets.sh" "$repo" "$report" 2>&1)"; rc=$?
  case "$rc" in
    0) pass "no secrets found in any commit" 20 ;;
    1) loc="$(jq -r '.[0] | "\(.File):\(.StartLine // 1)"' "$report")"
       fail "$(jq 'length' "$report") secret finding(s) in history (types: $(jq -r '[.[].RuleID]|unique|join(", ")' "$report"))" 20
       tip "rotate them first: leak scan, then leak plan; then docs/06-scenarios.md (scenario A) cleans history" ;;
    *) warn "history scan failed, so history is not checked: $(echo "$out" | tail -1)" 20; tip "leak doctor" ;;
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
result="$(printf '%s\n' "${rows[@]}" | jq -R -s --arg repo "$repo" --argjson points "$points" --argjson max "$max" \
  --argjson pct "$pct" --arg grade "$grade" --argjson critical "$critical" '{
    repository: $repo, grade: $grade, score: $points, max: $max, percent: $pct, critical: ($critical == 1),
    checks: (split("\n") | map(select(length > 0) | split("\t")
      | {section: .[0], status: .[1], weight: (.[2] | tonumber), message: .[3], fix: (.[5] // "")}
        + (if (.[4] // "") != "" then {location: .[4]} else {} end)))
  }')"

if [[ -n "$sarif" ]]; then
  # SARIF 2.1.0 for GitHub code scanning: one rule per audit section; findings only.
  # Messages are the audit's own, which never contain secret values.
  version="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$here/../leak")"
  jq --arg version "$version" '
    def id: {"1":"secret-files","2":"ignore-rules","3":"commit-blocking","4":"ci-scanning","5":"container-hygiene","6":"history-secrets"}[.section[0:1]] // "hygiene";
    def fallback: {"1":".gitignore","2":".gitignore","3":".pre-commit-config.yaml","4":".github/workflows","5":"Dockerfile","6":".gitignore"}[.section[0:1]] // ".gitignore";
    def doc: "https://github.com/aboutBilal/spillkit/blob/main/" + .;
    def rule($id; $name; $text; $sev; $help): {id: $id, name: $name, shortDescription: {text: $text}, helpUri: ($help | doc),
      defaultConfiguration: {level: (if $sev >= 7 then "error" else "warning" end)},
      properties: {tags: ["security", "secrets"], "security-severity": ($sev | tostring)}};
    {
      "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
      version: "2.1.0",
      runs: [{
        tool: { driver: { name: "spillkit audit", version: $version, informationUri: "https://github.com/aboutBilal/spillkit",
          rules: [
            rule("secret-files"; "SecretFilesTracked"; "A file that usually holds secrets is tracked by Git"; 8.5; "docs/02-rotate-secrets.md"),
            rule("ignore-rules"; "SecretFilesNotIgnored"; "Secret files are not ignored, or settings are undocumented"; 5.0; "prevention/README.md"),
            rule("commit-blocking"; "NoCommitTimeScan"; "Secrets are not blocked at commit time"; 5.0; "docs/04-prevention.md"),
            rule("ci-scanning"; "NoCISecretScan"; "CI does not scan for secrets"; 5.0; "prevention/README.md"),
            rule("container-hygiene"; "SecretInContainerBuild"; "A secret can reach a container image"; 8.0; "prevention/README.md"),
            rule("history-secrets"; "SecretInGitHistory"; "A secret is present in the Git history"; 9.0; "docs/01-runbook.md")
          ] } },
        results: [ .checks[] | select(.status != "pass") | (.location // fallback) as $loc | {
          ruleId: id,
          level: (if .status == "fail" then "error" else "warning" end),
          message: { text: (.message + (if .fix != "" then ". Fix: " + .fix else "" end)) },
          locations: [{ physicalLocation: {
            artifactLocation: { uri: ($loc | split(":")[0]) },
            region: { startLine: (($loc | split(":")[1] // "1") | tonumber? // 1) } } }],
          partialFingerprints: { "spillkit/audit/v1": (id + ":" + .message) }
        } ]
      }]
    }' <<<"$result" > "$sarif"
  ((json)) || echo "SARIF: $sarif"
fi

if ((json)); then
  printf '%s\n' "$result"
else
  echo
  echo "${B}Score $points/$max · Grade $grade${N}$( ((critical)) && echo "  (critical findings cap the grade at F)")"
fi
exit "$critical"
