#!/usr/bin/env bash
# Check that this machine is ready to run the toolkit, before an incident.
# Reports required tools, a secret scanner (gitleaks or Docker), optional tools,
# the GitHub token and the remaining API budget. Changes nothing.
#
# Usage: ./scripts/doctor.sh [--offline]
#   --offline   skip the GitHub API budget check
# Exit:  0 ready, 1 something required is missing
set -uo pipefail

case "${1:-}" in -h|--help) sed -n '2,/^set -/{/^#/s/^# \{0,1\}//p;}' "$0"; exit 0 ;; esac
offline=0
[[ "${1:-}" == "--offline" ]] && offline=1

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
if ((BASH_VERSINFO[0] < 4)); then bad "bash 4+" "found ${BASH_VERSION}; macOS: brew install bash"; fi

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
for cmd in sha256sum column; do
  if command -v "$cmd" >/dev/null; then ok "$cmd" "found"; else warn "$cmd" "missing: some output is less tidy"; fi
done
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  ok "GITHUB_TOKEN" "set (5,000 API requests/hour)"
else
  warn "GITHUB_TOKEN" "not set: 60 API requests/hour; hunts over many forks pause for the limit"
fi

if ((offline == 0)); then
  echo "GitHub API"
  auth=()
  [[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  if rl="$(curl -fsS --max-time 15 "${auth[@]}" https://api.github.com/rate_limit 2>/dev/null)"; then
    core="$(jq -r '.resources.core | "\(.remaining)/\(.limit)"' <<<"$rl")"
    search="$(jq -r '.resources.search | "\(.remaining)/\(.limit)"' <<<"$rl")"
    ok "reachable" "core $core · search $search remaining"
  else
    warn "reachable" "api.github.com not reachable from here"
  fi
fi

echo
if ((missing)); then echo "Not ready: fix the ✘ items above."; exit 1; fi
echo "Ready."
