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

# http_get <url> <outfile>: anonymous GET; prints the HTTP status code.
http_get() {
  curl -s --max-time 90 -A "leak-response-toolkit" -o "$2" -w '%{http_code}' "$1" || echo "000"
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

# git_auth_env: let `git clone` use GITHUB_TOKEN without putting it in argv,
# and never prompt for credentials.
git_auth_env() {
  export GIT_TERMINAL_PROMPT=0
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    local basic
    basic="$(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 | tr -d '\n')"
    export GIT_CONFIG_COUNT=1
    export GIT_CONFIG_KEY_0="http.https://github.com/.extraheader"
    export GIT_CONFIG_VALUE_0="Authorization: Basic $basic"
  fi
}
