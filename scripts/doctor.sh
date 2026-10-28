#!/usr/bin/env bash
# Check that this machine is ready to run the toolkit, before an incident.
# Reports required tools, a secret scanner (gitleaks or Docker), optional tools (the
# cloud CLIs leak rotate uses, cosign to verify releases), the GitHub token and the
# remaining API budget. Changes nothing.
#
# Usage: leak doctor [--offline]
#   --offline   skip the GitHub API budget check
# Exit:  0 ready, 1 something required is missing
set -uo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

offline=0
while (($#)); do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --offline) offline=1 ;;
    *) echo "unknown option: $1" >&2; exit "$EXIT_USAGE" ;;
  esac
  shift
done

missing=0
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then G=$'\033[32m' Y=$'\033[33m' R=$'\033[31m' N=$'\033[0m'; else G="" Y="" R="" N=""; fi
ok()   { printf '  %s✔%s %-28s %s\n' "$G" "$N" "$1" "$2"; }
warn() { printf '  %s!%s %-28s %s\n' "$Y" "$N" "$1" "$2"; }
bad()  { printf '  %s✘%s %-28s %s\n' "$R" "$N" "$1" "$2"; missing=1; }

echo "Required"
for cmd in bash git curl jq; do
  if command -v "$cmd" >/dev/null; then
    case "$cmd" in
      bash) v="${BASH_VERSION}" ;;
      git) v="$(git --version | awk '{print $3}')" ;;
      curl) v="$(curl --version | awk 'NR==1{print $2}')" ;;
      jq) v="$(jq --version)" ;;
    esac
    ok "$cmd" "$v"
  else
    bad "$cmd" "not found: install it with your package manager"
  fi
done
if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4))); then bad "bash 4.4+" "found ${BASH_VERSION}; macOS: brew install bash, or install Spillkit with brew install aboutbilal/tap/spillkit"; fi

echo "Secret scanner (one of)"
if command -v gitleaks >/dev/null; then
  ok "gitleaks" "$(gitleaks version 2>/dev/null)"
elif command -v docker >/dev/null && docker info >/dev/null 2>&1; then
  ok "docker" "will run the official gitleaks image"
elif command -v docker >/dev/null; then
  bad "docker" "installed but not usable by this user (daemon down or no permission)"
else
  bad "gitleaks or docker" "install gitleaks: https://github.com/gitleaks/gitleaks#installing"
fi

echo "Optional"
if command -v sha256sum >/dev/null || command -v shasum >/dev/null; then ok "sha256" "found (evidence checksums)"
else warn "sha256" "missing sha256sum/shasum: evidence manifests cannot be written"; fi
if command -v column >/dev/null; then ok "column" "found"; else warn "column" "missing: tables are printed unaligned"; fi
for cli in aws az gcloud; do
  if command -v "$cli" >/dev/null; then ok "$cli" "found (leak rotate)"
  else warn "$cli" "not found: needed only to rotate its keys with leak rotate"; fi
done
if command -v cosign >/dev/null; then ok "cosign" "found (verifies release signatures)"
else warn "cosign" "not found: needed only to verify release signatures"; fi
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  ok "GITHUB_TOKEN" "set (5,000 API requests/hour)"
else
  warn "GITHUB_TOKEN" "not set: 60 API requests/hour; hunts over many forks pause for the limit"
fi

if ((offline == 0)); then
  echo "GitHub API"
  rl_file="$(mktemp)"
  if [[ "$(gh_get /rate_limit "$rl_file")" == 200 ]]; then
    core="$(jq -r '.resources.core | "\(.remaining)/\(.limit)"' "$rl_file")"
    search="$(jq -r '.resources.search | "\(.remaining)/\(.limit)"' "$rl_file")"
    ok "reachable" "core $core · search $search remaining"
  else
    warn "reachable" "api.github.com not reachable from here"
  fi
  rm -f "$rl_file"
fi

echo
if ((missing)); then echo "Not ready: fix the ✘ items above."; exit 1; fi
echo "Ready."
