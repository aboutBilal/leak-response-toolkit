#!/usr/bin/env bash
# See Spillkit work in about a minute, on a leak made for the purpose. It builds a small
# repository where a developer commits a cloud key, a chat webhook and a deploy key, then
# deletes them in the next commit; then it runs the real commands on it: audit, scan,
# plan, and a dry run of the first rotation. The keys are random, generated now, and work
# nowhere. Nothing leaves this machine and nothing is changed outside the demo folder.
#
# Usage: leak demo [--out DIR]
#   --out DIR   where to build it (default: ./spillkit-demo); must not exist yet
# Needs: git, jq, and gitleaks or Docker (the same as leak scan)
# Exit:  0 the demo ran, 2 missing tools or the folder exists, 4 a command failed
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

out="spillkit-demo"
while (($#)); do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --out) need_value "$1" "${2:-}"; out="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit "$EXIT_USAGE" ;;
  esac
done
for c in git jq; do command -v "$c" >/dev/null || { echo "missing: $c (run leak doctor)" >&2; exit "$EXIT_USAGE"; }; done
command -v gitleaks >/dev/null || command -v docker >/dev/null \
  || { echo "the demo scans history, which needs gitleaks or Docker: run leak doctor" >&2; exit "$EXIT_USAGE"; }
[[ ! -e "$out" ]] || { echo "already exists: $out (remove it, or pick another with --out)" >&2; exit "$EXIT_USAGE"; }
leak="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leak"

bold=""; dim=""; off=""
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then bold=$'\e[1m'; dim=$'\e[2m'; off=$'\e[0m'; fi
stage() { printf '\n%s[%s/5] %s%s\n%s%s%s\n\n' "$bold" "$1" "$2" "$off" "$dim" "$3" "$off"; }
random() { head -c 4096 /dev/urandom | LC_ALL=C tr -dc "$1" | head -c "$2"; }

mkdir -p "$out"
out="$(cd "$out" && pwd)"
repo="$out/payments-api"
mkdir -p "$repo/src" "$repo/deploy"
start=$SECONDS

printf '%sSpillkit demo%s: from a leaked commit to a rotation plan.\n' "$bold" "$off"
echo "Working in $out. The keys are random, made just now, and work nowhere."

# ---------- 1. The leak ----------
stage 1 "A developer commits secrets, notices, and deletes them in the next commit" \
  "Deleting a file does not delete it from the history: anyone who cloned the repository still has it."
git -C "$repo" init -q -b main
git -C "$repo" config user.name "Demo Developer"
git -C "$repo" config user.email "developer@example.com"
git -C "$repo" config commit.gpgsign false
printf '# payments-api\n\nA demo service for Spillkit.\n' > "$repo/README.md"
printf 'export function charge(amount) {\n  return { ok: true, amount };\n}\n' > "$repo/src/charge.js"
git -C "$repo" add -A && git -C "$repo" commit -qm "Initial commit"

key_id="AKIA$(random 'A-Z2-7' 16)"
{
  echo "AWS_ACCESS_KEY_ID=$key_id"
  echo "AWS_SECRET_ACCESS_KEY=$(random 'A-Za-z0-9' 40)"
  echo "SLACK_WEBHOOK=https://hooks.slack.com/services/T$(random 'A-Z0-9' 8)/B$(random 'A-Z0-9' 10)/$(random 'A-Za-z0-9' 24)"
} > "$repo/.env"
kind="OPENSSH PRIVATE KEY"   # assembled at run time, so this script itself holds no key-shaped text
{
  echo "-----BEGIN $kind-----"
  for _ in 1 2 3 4 5; do random 'A-Za-z0-9+/' 70; echo; done
  echo "-----END $kind-----"
} > "$repo/deploy/id_ed25519"
git -C "$repo" add -A && git -C "$repo" commit -qm "Add deployment settings"
git -C "$repo" rm -q .env deploy/id_ed25519 && git -C "$repo" commit -qm "Remove secrets"
git -C "$repo" log --oneline --stat --format='  %h %s' | sed '/^$/d'

# ---------- 2. Audit ----------
stage 2 "leak audit: how exposed is this repository?" \
  "A grade from A to F, with the fix for each finding. Run it on your own repositories before an incident."
set +e
NO_COLOR=1 "$leak" audit "$repo"; rc=$?
set -e
((rc <= 1)) || { echo "audit failed (exit $rc)" >&2; exit "$EXIT_FAILED"; }

# ---------- 3. Scan ----------
stage 3 "leak scan: which secrets are in the history?" \
  "Every commit on every branch. Values are redacted: Spillkit never prints, stores or tests a secret."
set +e
"$leak" scan "$repo" "$out/secrets-report.json"; rc=$?
set -e
((rc == 1)) || { echo "the scan should have found the demo secrets (exit $rc)" >&2; exit "$EXIT_FAILED"; }

# ---------- 4. Plan ----------
stage 4 "leak plan: what to rotate first?" \
  "Most dangerous first, each with where to revoke it. Paste the Markdown into the incident issue; print the HTML."
set +e
"$leak" plan "$out/secrets-report.json" --id DEMO-1; rc=$?
set -e
((rc == 1)) || { echo "plan failed (exit $rc)" >&2; exit "$EXIT_FAILED"; }

# ---------- 5. Rotate ----------
stage 5 "leak rotate: the first rotation, as a dry run" \
  "Each step runs only with --apply. New secrets go straight into your secret store, never to the screen."
"$leak" rotate aws-key --user demo-deploy-bot --key-id "$key_id" --log "$out/rotation-log.tsv"

printf '\n%sDone in %ss.%s Open the plan: %s/rotation-plan.html\n' "$bold" "$((SECONDS - start))" "$off" "$out"
echo "In a real incident, start with the runbook: https://aboutbilal.github.io/spillkit/docs/01-runbook.html"
echo "Clean up when you are done: rm -rf $out"
