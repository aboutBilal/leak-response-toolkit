#!/usr/bin/env bash
# Shared helpers for the toolkit scripts. Sourced, never run directly.
# Rules this file enforces for every script:
#   - credentials (GITHUB_TOKEN, webhook URLs) never appear in command-line
#     arguments, so they cannot be read from process lists or shell history;
#   - an API error is reported as an error, never as an empty (clean) result;
#   - a missing option value is a usage error (exit 2), not a hang.

# Exit codes shared by all commands.
EXIT_OK=0          # nothing found / success
EXIT_FOUND=1       # findings (secrets, copies, critical audit results)
EXIT_USAGE=2       # bad arguments or missing prerequisites
EXIT_FAILED=4      # a scanner or remote service failed; results are incomplete
export EXIT_OK EXIT_FOUND EXIT_USAGE EXIT_FAILED

# need_value <option> <value>: exit 2 unless the option was given a value.
need_value() {
  if [[ -z "${2:-}" || "$2" == -* ]]; then
    echo "$1 needs a value" >&2
    exit "$EXIT_USAGE"
  fi
}

# print_help <script>: print the script's header comment (up to "set -").
print_help() { sed -n '2,/^set -/{/^#/s/^# \{0,1\}//p;}' "$1"; }

# _curl_auth: curl config on stdin carrying the GitHub token, if any.
# Using `curl -K -` keeps the token out of argv.
_curl_auth() {
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    printf 'header = "Authorization: Bearer %s"\n' "${GITHUB_TOKEN//\"/}"
  fi
}

# gh_get <path> <outfile>: GET https://api.github.com<path> into <outfile>.
# Prints the HTTP status code ("000" when the request itself failed).
gh_get() {
  _curl_auth | curl -s --max-time 60 -K - -o "$2" -w '%{http_code}' \
    -H "Accept: application/vnd.github+json" "https://api.github.com$1" || echo "000"
}

# bb_get <url> <outfile>: GET a Bitbucket Cloud API URL. BITBUCKET_TOKEN (a workspace, project
# or repository access token) is sent as a Bearer header on stdin. Prints the HTTP status code.
bb_get() {
  { if [[ -n "${BITBUCKET_TOKEN:-}" ]]; then printf 'header = "Authorization: Bearer %s"\n' "${BITBUCKET_TOKEN//\"/}"; fi; } \
    | curl -s --max-time 60 -K - -o "$2" -w '%{http_code}' "$1" || echo "000"
}

# ado_get <url> <outfile>: GET an Azure DevOps API URL. AZURE_DEVOPS_PAT (a personal access
# token with Code: Read) is sent as Basic auth on stdin. Prints the HTTP status code.
ado_get() {
  { if [[ -n "${AZURE_DEVOPS_PAT:-}" ]]; then printf 'header = "Authorization: Basic %s"\n' "$(printf ':%s' "$AZURE_DEVOPS_PAT" | base64 | tr -d '\n')"; fi; } \
    | curl -s --max-time 60 -K - -o "$2" -w '%{http_code}' "$1" || echo "000"
}

# gitlab_url: the GitLab instance, from GITLAB_URL (default https://gitlab.com), without a trailing slash.
gitlab_url() { local u="${GITLAB_URL:-https://gitlab.com}"; printf '%s' "${u%/}"; }

# gl_get <url> <outfile>: GET a GitLab API URL. GITLAB_TOKEN (a personal, group or project access
# token with read_api) is sent as a PRIVATE-TOKEN header on stdin. Prints the HTTP status code.
gl_get() {
  { if [[ -n "${GITLAB_TOKEN:-}" ]]; then printf 'header = "PRIVATE-TOKEN: %s"\n' "${GITLAB_TOKEN//\"/}"; fi; } \
    | curl -s --max-time 60 -K - -o "$2" -w '%{http_code}' "$1" || echo "000"
}

# http_get <url> <outfile>: anonymous GET; prints the HTTP status code.
http_get() {
  curl -s --max-time 90 -A "spillkit" -o "$2" -w '%{http_code}' "$1" || echo "000"
}

# table: align tab-separated input when `column` exists, otherwise pass it through.
table() {
  if command -v column >/dev/null 2>&1; then column -t -s $'\t'; else cat; fi
}

# sha256_files: hash every file under the current folder into MANIFEST.sha256.
sha256_files() {
  local cmd=(sha256sum)
  command -v sha256sum >/dev/null 2>&1 || cmd=(shasum -a 256)
  find . -type f ! -name MANIFEST.sha256 -print0 | sort -z | xargs -0 "${cmd[@]}" > MANIFEST.sha256
}

# tlp_info <name>: handling label for reports, per FIRST TLP 2.0. Prints
# "LABEL|RULE|CSS-CLASS"; returns 1 for an unknown name.
tlp_info() {
  case "${1,,}" in
    clear) echo "TLP:CLEAR|Disclosure is not limited.|tlp-clear" ;;
    green) echo "TLP:GREEN|Recipients may share within their community, not publicly.|tlp-green" ;;
    amber) echo "TLP:AMBER|Recipients may share on a need-to-know basis within their organisation and its clients.|tlp-amber" ;;
    amber+strict) echo "TLP:AMBER+STRICT|Recipients may share on a need-to-know basis within their organisation only.|tlp-amber-strict" ;;
    red) echo "TLP:RED|For the named recipients only. No further disclosure.|tlp-red" ;;
    *) return 1 ;;
  esac
}

# git_auth_env: let `git clone` use GITHUB_TOKEN, BITBUCKET_TOKEN, AZURE_DEVOPS_PAT and GITLAB_TOKEN
# without putting them in argv (each only for its own host), and never prompt for credentials.
git_auth_env() {
  export GIT_TERMINAL_PROMPT=0
  local n=0
  _git_header() {   # <host> <user:secret>
    export "GIT_CONFIG_KEY_$n=http.https://$1/.extraheader"
    export "GIT_CONFIG_VALUE_$n=Authorization: Basic $(printf '%s' "$2" | base64 | tr -d '\n')"
    n=$((n + 1))
  }
  [[ -n "${GITHUB_TOKEN:-}" ]] && _git_header github.com "x-access-token:$GITHUB_TOKEN"
  [[ -n "${BITBUCKET_TOKEN:-}" ]] && _git_header bitbucket.org "x-token-auth:$BITBUCKET_TOKEN"
  [[ -n "${AZURE_DEVOPS_PAT:-}" ]] && _git_header dev.azure.com ":$AZURE_DEVOPS_PAT"
  if [[ -n "${GITLAB_TOKEN:-}" ]]; then local h; h="$(gitlab_url)"; h="${h#https://}"; _git_header "${h%%/*}" "oauth2:$GITLAB_TOKEN"; fi
  if ((n)); then export GIT_CONFIG_COUNT=$n; fi
}
