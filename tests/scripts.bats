#!/usr/bin/env bats
# Offline tests for scripts/. No network calls are made.
# Test secrets are generated at runtime in a temporary directory and are never
# written into this repository.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

scanner_available() {
  command -v gitleaks >/dev/null || command -v docker >/dev/null
}

new_repo() {
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.name "test"
  git -C "$1" config user.email "test@example.com"
}

commit_all() {
  git -C "$1" add -A
  git -C "$1" commit -qm "$2"
}

@test "every script prints its help and exits 0" {
  for s in "$ROOT"/scripts/*.sh "$ROOT"/leak; do
    [[ "$s" == */lib.sh ]] && continue   # a sourced library, not a command
    run "$s" --help
    [ "$status" -eq 0 ] || { echo "$s exited $status"; false; }
    [[ "$output" == *"Usage:"* ]] || { echo "$s help has no Usage line"; false; }
  done
}

@test "every script exits 2 when required arguments are missing" {
  for s in snapshot-evidence list-forks hunt-copies find-commit-copies scan-secrets make-report notify rotation-plan rotate; do
    run "$ROOT/scripts/$s.sh"
    [ "$status" -eq 2 ] || { echo "$s exited $status"; false; }
  done
}

@test "repository arguments must look like owner/repo" {
  for s in snapshot-evidence list-forks hunt-copies; do
    run "$ROOT/scripts/$s.sh" "not a repo"
    [ "$status" -eq 2 ] || { echo "$s exited $status"; false; }
  done
}

@test "find-commit-copies skips values that are not commit IDs" {
  run "$ROOT/scripts/find-commit-copies.sh" "not-a-sha"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not a commit ID"* ]]
}

@test "scan-secrets: a clean repository exits 0" {
  scanner_available || skip "needs gitleaks or docker"
  new_repo "$TMP/clean"
  echo "hello" > "$TMP/clean/README.md"
  commit_all "$TMP/clean" "init"

  run "$ROOT/scripts/scan-secrets.sh" "$TMP/clean" "$TMP/clean-report.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No secrets found"* ]]
}

@test "scan-secrets: finds a secret removed from history and never prints its value" {
  scanner_available || skip "needs gitleaks or docker"
  new_repo "$TMP/leaky"
  # Random, format-valid fake access key ID built at runtime. It works nowhere.
  fake="AKIA$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'A-Z2-7' | head -c 16)"
  echo "aws_access_key_id = $fake" > "$TMP/leaky/config"
  commit_all "$TMP/leaky" "add config"
  git -C "$TMP/leaky" rm -q config
  commit_all "$TMP/leaky" "remove config"

  run "$ROOT/scripts/scan-secrets.sh" "$TMP/leaky" "$TMP/leaky-report.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"aws-access-token"* ]]
  [[ "$output" != *"$fake"* ]]
  run grep -c "$fake" "$TMP/leaky-report.json"
  [ "$output" = "0" ]
}

@test "leak: help lists every command and version prints" {
  run "$ROOT/leak" help
  [ "$status" -eq 0 ]
  for c in snapshot scan forks hunt commits plan rotate demo; do [[ "$output" == *"$c"* ]]; done
  run "$ROOT/leak" version
  [ "$status" -eq 0 ]
  [[ "$output" == spillkit* ]]
}

@test "leak: unknown command exits 2; commands reach their script" {
  run "$ROOT/leak" no-such-command
  [ "$status" -eq 2 ]
  run "$ROOT/leak" help scan
  [ "$status" -eq 0 ]
  [[ "$output" == *"FULL git history"* ]]
  run "$ROOT/leak" forks "not a repo"
  [ "$status" -eq 2 ]
}

@test "audit: a repository tracking .env gets grade F and exits 1" {
  new_repo "$TMP/bad"
  echo "DB_PASSWORD=$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | head -c 12)" > "$TMP/bad/.env"
  commit_all "$TMP/bad" "add env"
  NO_COLOR=1 run "$ROOT/scripts/audit.sh" --no-scan "$TMP/bad"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tracked by Git: .env"* ]]
  [[ "$output" == *"Grade F"* ]]
}

@test "audit: a repository using the prevention kit gets grade A" {
  new_repo "$TMP/good"
  cp "$ROOT/prevention/gitignore-secrets" "$TMP/good/.gitignore"
  cp "$ROOT/prevention/pre-commit-config.yaml" "$TMP/good/.pre-commit-config.yaml"
  mkdir -p "$TMP/good/.github/workflows"
  cp "$ROOT/prevention/ci/github-actions.yml" "$TMP/good/.github/workflows/secret-scan.yml"
  cp "$ROOT/prevention/hooks/pre-commit" "$TMP/good/.git/hooks/pre-commit"
  echo "hello" > "$TMP/good/README.md"
  commit_all "$TMP/good" "init"
  NO_COLOR=1 run "$ROOT/scripts/audit.sh" --no-scan "$TMP/good"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Grade A"* ]] || [[ "$output" == *"Grade B"* ]]
}

@test "audit: Spillkit's own pre-commit hooks and GitHub Action count as secret scanning" {
  new_repo "$TMP/own"
  printf 'repos:\n  - repo: https://github.com/aboutBilal/spillkit\n    rev: v3.6.0\n    hooks:\n      - id: forbid-secret-files\n      - id: leak-guard\n' > "$TMP/own/.pre-commit-config.yaml"
  mkdir -p "$TMP/own/.github/workflows"
  printf 'on: [push]\njobs:\n  check:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: aboutBilal/spillkit@v3\n' > "$TMP/own/.github/workflows/checks.yml"
  echo "hello" > "$TMP/own/README.md"
  commit_all "$TMP/own" "init"
  NO_COLOR=1 run "$ROOT/scripts/audit.sh" --no-scan "$TMP/own"
  [[ "$output" == *"✔ pre-commit secret scanner configured"* ]]
  [[ "$output" == *"✔ CI runs a secret scan"* ]]
}

@test "audit: not a git repository exits 2" {
  run "$ROOT/scripts/audit.sh" --no-scan "$TMP"
  [ "$status" -eq 2 ]
}

@test "report: builds HTML from hunt results and escapes content" {
  mkdir -p "$TMP/hunt"
  echo '{"run":"20260101T000000Z","since":"2025-12-01","repos":["someone/example"]}' > "$TMP/hunt/meta.json"
  {
    echo '{"section":"someone/example","check":"Wayback Machine","status":"clean","detail":"0 captures"}'
    echo '{"section":"someone/example","check":"Direct forks","status":"found","detail":"<script>alert(1)</script>"}'
  } > "$TMP/hunt/results.jsonl"
  run "$ROOT/scripts/make-report.sh" "$TMP/hunt" --out "$TMP/r.html"
  [ "$status" -eq 0 ]
  grep -q "1 found" "$TMP/r.html"
  grep -q "someone/example" "$TMP/r.html"
  ! grep -q "<script>alert" "$TMP/r.html"
}

@test "report: rejects a folder that is not a hunt" {
  run "$ROOT/scripts/make-report.sh" "$TMP"
  [ "$status" -eq 2 ]
}

@test "doctor: runs offline and reports the required tools" {
  NO_COLOR=1 run "$ROOT/scripts/doctor.sh" --offline
  [[ "$output" == *"Required"* ]]
  [[ "$output" == *"jq"* ]]
}

@test "audit: documentation and example files do not cause false warnings" {
  new_repo "$TMP/docs"
  printf 'Load settings with dotenv or os.environ.\n' > "$TMP/docs/GUIDE.md"
  printf 'FROM alpine\nENV API_TOKEN=placeholder\n' > "$TMP/docs/Dockerfile.example"
  cp "$ROOT/prevention/gitignore-secrets" "$TMP/docs/.gitignore"
  commit_all "$TMP/docs" "docs only"
  NO_COLOR=1 run "$ROOT/scripts/audit.sh" --no-scan "$TMP/docs"
  [[ "$output" != *"no .env.example"* ]]
  [[ "$output" == *"no Dockerfiles"* ]]
}

@test "audit: a real Dockerfile baking a secret value is critical, and the value is never printed" {
  new_repo "$TMP/img"
  value="$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | head -c 16)"
  printf 'FROM alpine\nENV API_TOKEN=%s\n' "$value" > "$TMP/img/Dockerfile"
  commit_all "$TMP/img" "image"
  NO_COLOR=1 run "$ROOT/scripts/audit.sh" --no-scan "$TMP/img"
  [ "$status" -eq 1 ]
  [[ "$output" == *"baked into an image"* ]]
  [[ "$output" == *"API_TOKEN=<redacted>"* ]]
  [[ "$output" != *"$value"* ]]
}

@test "leak works through a symlink (make install, container image)" {
  mkdir -p "$TMP/bin"
  ln -s "$ROOT/leak" "$TMP/bin/leak"
  run "$TMP/bin/leak" version
  [ "$status" -eq 0 ]
  run "$TMP/bin/leak" help scan
  [ "$status" -eq 0 ]
  [[ "$output" == *"FULL git history"* ]]
}

@test "scan: --sarif writes valid SARIF 2.1.0 without secret values" {
  scanner_available || skip "needs gitleaks or docker"
  new_repo "$TMP/s"
  fake="AKIA$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'A-Z2-7' | head -c 16)"
  echo "key = $fake" > "$TMP/s/app.ini"
  commit_all "$TMP/s" "add"
  run "$ROOT/scripts/scan-secrets.sh" "$TMP/s" "$TMP/s.json" --sarif "$TMP/s.sarif"
  [ "$status" -eq 1 ]
  run jq -r '.version, .runs[0].tool.driver.name, .runs[0].results[0].ruleId, .runs[0].results[0].locations[0].physicalLocation.artifactLocation.uri' "$TMP/s.sarif"
  [ "${lines[0]}" = "2.1.0" ]
  [ "${lines[1]}" = "spillkit" ]
  [ "${lines[2]}" = "aws-access-token" ]
  [ "${lines[3]}" = "app.ini" ]
  run grep -c "$fake" "$TMP/s.sarif"
  [ "$output" = "0" ]
}

@test "audit: --json prints one object with grade and checks" {
  new_repo "$TMP/j"
  echo "hello" > "$TMP/j/README.md"
  commit_all "$TMP/j" "init"
  run "$ROOT/scripts/audit.sh" --no-scan --json "$TMP/j"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.grade and (.checks | length) > 5 and (.checks[0] | has("fix"))'
}

@test "audit: an unknown option exits 2" {
  run "$ROOT/scripts/audit.sh" --nope
  [ "$status" -eq 2 ]
}

@test "audit-org: grades a folder of repositories and writes the dashboard" {
  mkdir -p "$TMP/org"
  new_repo "$TMP/org/good"
  cp "$ROOT/prevention/gitignore-secrets" "$TMP/org/good/.gitignore"
  echo "ok" > "$TMP/org/good/README.md"
  commit_all "$TMP/org/good" "init"
  new_repo "$TMP/org/bad"
  value="$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | head -c 16)"
  echo "DB_PASSWORD=$value" > "$TMP/org/bad/.env"
  commit_all "$TMP/org/bad" "init"
  run "$ROOT/scripts/audit-org.sh" --no-scan --out "$TMP/out" --dir "$TMP/org"
  [ "$status" -eq 1 ]
  [ -f "$TMP/out/dashboard.html" ] && [ -f "$TMP/out/README.md" ]
  run jq -r '.repositories, .critical, .results[0].repository, .results[0].grade' "$TMP/out/audit-org.json"
  [ "${lines[0]}" = "2" ] && [ "${lines[1]}" = "1" ] && [ "${lines[2]}" = "bad" ] && [ "${lines[3]}" = "F" ]
  run grep -rc "$value" "$TMP/out"
  [[ "$output" != *":1"* ]]
}

@test "audit-org: rejects a missing folder and a bad owner name" {
  run "$ROOT/scripts/audit-org.sh" --dir "$TMP/does-not-exist"
  [ "$status" -eq 2 ]
  run "$ROOT/scripts/audit-org.sh" "not a valid/owner"
  [ "$status" -eq 2 ]
}

@test "notify: needs LEAK_WEBHOOK_URL, refuses plain http and unknown formats" {
  LEAK_WEBHOOK_URL="" run "$ROOT/scripts/notify.sh" "hello"
  [ "$status" -eq 2 ]
  LEAK_WEBHOOK_URL="http://example.com/hook" run "$ROOT/scripts/notify.sh" "hello"
  [ "$status" -eq 2 ]
  LEAK_WEBHOOK_URL="https://example.invalid/hook" run "$ROOT/scripts/notify.sh" --format nope "hello"
  [ "$status" -eq 2 ]
}

@test "leak: help lists audit-org and notify" {
  run "$ROOT/leak" help
  [[ "$output" == *"audit-org"* ]]
  [[ "$output" == *"notify"* ]]
}

@test "terminal renderer: animated SVG respects reduced motion" {
  command -v python3 >/dev/null || skip "needs python3"
  printf '  ✔ ok\nScore: 100/100 (100%%) · Grade A\n' > "$TMP/in.txt"
  run python3 -I "$ROOT/tools/render-terminal-svg.py" "$TMP/in.txt" "$TMP/out.svg" --command "leak audit ." --animate
  [ "$status" -eq 0 ]
  grep -q 'prefers-reduced-motion' "$TMP/out.svg"
  grep -q 'class="ln"' "$TMP/out.svg"
}

# ---------- Regression tests for the independent review (v3.2.0) ----------

# fake_curl <http-code> [body]: a curl test double that answers every request the same way.
fake_curl() {
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/curl" <<MOCK
#!/usr/bin/env bash
out=""; reads=0
while ((\$#)); do case "\$1" in -o) out="\$2"; shift 2 ;; -K) [[ "\$2" == - ]] && reads=1; shift 2 ;; *) shift ;; esac; done
((reads)) && cat > "$TMP/curl-config.txt"
[[ -n "\$out" ]] && printf '%s' '${2:-{\}}' > "\$out"
printf '%s' '$1'
MOCK
  chmod +x "$TMP/bin/curl"
  printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/sleep"; chmod +x "$TMP/bin/sleep"
}

@test "scan: a scanner failure exits 4, never 1 (fail closed)" {
  scanner_available || skip "needs gitleaks or docker"
  new_repo "$TMP/broken"
  echo "hello" > "$TMP/broken/README.md"
  echo "not valid toml [[[" > "$TMP/broken/.gitleaks.toml"
  commit_all "$TMP/broken" "init"
  run "$ROOT/scripts/scan-secrets.sh" "$TMP/broken" "$TMP/broken.json"
  [ "$status" -eq 4 ]
  [[ "$output" == *"scan is incomplete"* ]]
}

@test "audit: an odd Dockerfile name cannot leak the value (Dockerfile:v2)" {
  new_repo "$TMP/odd"
  value="$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | head -c 20)"
  printf 'FROM alpine\nENV API_TOKEN=%s\n' "$value" > "$TMP/odd/Dockerfile:v2"
  commit_all "$TMP/odd" "odd name"
  NO_COLOR=1 run "$ROOT/scripts/audit.sh" --no-scan "$TMP/odd"
  [[ "$output" == *"API_TOKEN=<redacted>"* ]]
  [[ "$output" != *"$value"* ]]
  run "$ROOT/scripts/audit.sh" --no-scan --json "$TMP/odd"
  [[ "$output" != *"$value"* ]]
}

@test "hunt: every failing source is 'not checked', never clean, and exits 4" {
  fake_curl 403 '{"message":"API rate limit exceeded"}'
  run env PATH="$TMP/bin:$PATH" "$ROOT/scripts/hunt-copies.sh" --since 2026-01-01 --out "$TMP/h" someone/example
  [ "$status" -eq 4 ]
  report="$(ls "$TMP"/h/hunt_*/REPORT.md)"
  run grep -c '^| .*| clean |' "$report"
  [ "$output" = "0" ]
  run grep -c '^| .*| not checked |' "$report"
  [ "$output" -ge 10 ]
}

@test "notify: the webhook URL never appears in curl's arguments, and all words are sent" {
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/curl" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$TMP/argv.txt"
for a in "\$@"; do [[ "\$a" == "-K" ]] && cat > "$TMP/config.txt"; done
for ((i=1;i<=\$#;i++)); do [[ "\${!i}" == --data-binary ]] && { j=\$((i+1)); cp "\${!j#@}" "$TMP/payload.json"; }; done
exit 0
MOCK
  chmod +x "$TMP/bin/curl"
  run env PATH="$TMP/bin:$PATH" LEAK_WEBHOOK_URL="https://hooks.example.invalid/T000/PLACEHOLDERVALUE" "$ROOT/scripts/notify.sh" Leak found in repo
  [ "$status" -eq 0 ]
  run grep -c PLACEHOLDERVALUE "$TMP/argv.txt"
  [ "$output" = "0" ]
  run jq -r .text "$TMP/payload.json"
  [ "$output" = "Leak found in repo" ]
}

@test "forks and commits: API errors exit 4 instead of an empty result" {
  fake_curl 404 '{"message":"Not Found"}'
  run env PATH="$TMP/bin:$PATH" "$ROOT/scripts/list-forks.sh" someone/example
  [ "$status" -eq 4 ]
  fake_curl 403 '{"message":"rate limited"}'
  run env PATH="$TMP/bin:$PATH" "$ROOT/scripts/find-commit-copies.sh" 0123456789abcdef0123456789abcdef01234567
  [ "$status" -eq 4 ]
}

@test "options without a value exit 2 instead of hanging" {
  # A hang is caught by BATS_TEST_TIMEOUT (set in CI and in `make test`); no GNU timeout needed.
  for args in "audit-org --limit" "audit-org --out" "hunt --since" "report --scan" "commits --exclude" "scan . --sarif"; do
    run "$ROOT/leak" $args
    [ "$status" -eq 2 ] || { echo "leak $args exited $status"; false; }
  done
}

@test "audit-org: includes dot-named repositories such as .github" {
  mkdir -p "$TMP/org"
  for n in .github app; do new_repo "$TMP/org/$n"; echo x > "$TMP/org/$n/README.md"; commit_all "$TMP/org/$n" init; done
  run "$ROOT/scripts/audit-org.sh" --no-scan --out "$TMP/o" --dir "$TMP/org"
  run jq -r '.repositories, ([.results[].repository] | sort | join(","))' "$TMP/o/audit-org.json"
  [ "${lines[0]}" = "2" ]
  [ "${lines[1]}" = ".github,app" ]
}

@test "report: a clean scan is reported as clean" {
  mkdir -p "$TMP/hc"
  echo '{"run":"20260101T000000Z","since":"2025-12-01","repos":["someone/example"]}' > "$TMP/hc/meta.json"
  echo '{"section":"someone/example","check":"Wayback","status":"clean","detail":"0"}' > "$TMP/hc/results.jsonl"
  echo '[]' > "$TMP/empty.json"
  run "$ROOT/scripts/make-report.sh" "$TMP/hc" --scan "$TMP/empty.json" --out "$TMP/r.html"
  [ "$status" -eq 0 ]
  grep -q "found no secrets" "$TMP/r.html"
  ! grep -q "0 type(s) found" "$TMP/r.html"
}

@test "--help works after other arguments" {
  run "$ROOT/leak" audit --no-scan --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: leak audit"* ]]
}

# ---------- Reports: handling labels and the published template ----------

@test "report: shows the TLP label and incident ID, and rejects unknown labels" {
  mkdir -p "$TMP/ht"
  echo '{"run":"20260101T000000Z","since":"2025-12-01","repos":["someone/example"]}' > "$TMP/ht/meta.json"
  echo '{"section":"someone/example","check":"Wayback","status":"clean","detail":"0"}' > "$TMP/ht/results.jsonl"
  run "$ROOT/scripts/make-report.sh" "$TMP/ht" --id INC-2026-001 --tlp red --out "$TMP/r.html"
  [ "$status" -eq 0 ]
  grep -q 'class="tlp tlp-red">TLP:RED<' "$TMP/r.html"
  grep -q "INC-2026-001" "$TMP/r.html"
  run "$ROOT/scripts/make-report.sh" "$TMP/ht" --tlp purple
  [ "$status" -eq 2 ]
}

@test "report: templates/incident-report.html is the current --blank output" {
  run "$ROOT/scripts/make-report.sh" --blank --out "$TMP/blank.html"
  [ "$status" -eq 0 ]
  diff -u "$ROOT/templates/incident-report.html" "$TMP/blank.html" \
    || { echo "regenerate it: ./scripts/make-report.sh --blank --out templates/incident-report.html"; false; }
}

@test "audit-org: the dashboard carries a handling label and the method" {
  mkdir -p "$TMP/o2"
  new_repo "$TMP/o2/one"
  echo "ok" > "$TMP/o2/one/README.md"
  commit_all "$TMP/o2/one" "init"
  run "$ROOT/scripts/audit-org.sh" --no-scan --tlp green --out "$TMP/o2out" --dir "$TMP/o2"
  grep -q 'TLP:GREEN' "$TMP/o2out/dashboard.html"
  grep -q 'Method' "$TMP/o2out/dashboard.html"
  run "$ROOT/scripts/audit-org.sh" --no-scan --tlp purple --dir "$TMP/o2"
  [ "$status" -eq 2 ]
}

# ---------- audit --sarif; audit-org on Bitbucket and Azure DevOps ----------

@test "audit: --sarif writes SARIF 2.1.0 that points at the finding, without its value" {
  new_repo "$TMP/s"
  value="$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | head -c 16)"
  echo "DB_PASSWORD=$value" > "$TMP/s/.env"
  commit_all "$TMP/s" "init"
  run "$ROOT/scripts/audit.sh" --no-scan --sarif "$TMP/a.sarif" "$TMP/s"
  [ "$status" -eq 1 ]
  run jq -r '.version, (.runs[0].tool.driver.rules | length), ([.runs[0].results[] | select(.ruleId == "secret-files")][0].locations[0].physicalLocation.artifactLocation.uri)' "$TMP/a.sarif"
  [ "${lines[0]}" = "2.1.0" ] && [ "${lines[1]}" = "6" ] && [ "${lines[2]}" = ".env" ]
  ! grep -q "$value" "$TMP/a.sarif"
}

# api_curl <body>: a curl double that records its arguments and the config read from stdin.
api_curl() {
  mkdir -p "$TMP/bin"
  printf '%s' "$1" > "$TMP/api-body.json"
  cat > "$TMP/bin/curl" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$@" >> "$TMP/argv.txt"
out=""; while ((\$#)); do case "\$1" in -o) out="\$2"; shift 2 ;; -K) [[ "\$2" == - ]] && cat >> "$TMP/config.txt"; shift 2 ;; *) shift ;; esac; done
cp "$TMP/api-body.json" "\$out"; printf 200
MOCK
  chmod +x "$TMP/bin/curl"
}

@test "audit-org: lists a Bitbucket workspace, skips forks, keeps the token out of arguments" {
  api_curl '{"values":[{"slug":"api","links":{"clone":[{"name":"https","href":"https://user@127.0.0.1:9/ws/api.git"}]}},{"slug":"fork","parent":{"full_name":"x/y"},"links":{"clone":[{"name":"https","href":"https://127.0.0.1:9/ws/fork.git"}]}}]}'
  run env PATH="$TMP/bin:$PATH" BITBUCKET_TOKEN=bb-test-token-123 "$ROOT/scripts/audit-org.sh" --no-scan --bitbucket ws --out "$TMP/bb"
  run jq -r '.repositories, .not_audited, .results[0].repository' "$TMP/bb/audit-org.json"
  [ "${lines[0]}" = "1" ] && [ "${lines[1]}" = "1" ] && [ "${lines[2]}" = "api" ]
  ! grep -q "bb-test-token-123" "$TMP/argv.txt"
  grep -q "Authorization: Bearer bb-test-token-123" "$TMP/config.txt"
}

@test "audit-org: lists an Azure DevOps project, skips disabled repositories, keeps the PAT out of arguments" {
  api_curl '{"count":2,"value":[{"name":"api","project":{"name":"Payments"},"remoteUrl":"https://org@127.0.0.1:9/org/Payments/_git/api","isDisabled":false},{"name":"old","project":{"name":"Payments"},"remoteUrl":"https://127.0.0.1:9/org/Payments/_git/old","isDisabled":true}]}'
  run env PATH="$TMP/bin:$PATH" AZURE_DEVOPS_PAT=ado-test-pat-456 "$ROOT/scripts/audit-org.sh" --no-scan --azure-devops "org/Payments" --out "$TMP/ado"
  run jq -r '.repositories, .results[0].repository' "$TMP/ado/audit-org.json"
  [ "${lines[0]}" = "1" ] && [ "${lines[1]}" = "Payments/api" ]
  [ -f "$TMP/ado/results/Payments__api.json" ]
  ! grep -q "ado-test-pat-456" "$TMP/argv.txt"
  grep -q "dev.azure.com/org/Payments/_apis/git/repositories" "$TMP/argv.txt"
}

@test "audit-org: an API error while listing exits 4, never an empty clean result" {
  fake_curl 401 '{"error":{"message":"Unauthorized"}}'
  run env PATH="$TMP/bin:$PATH" "$ROOT/scripts/audit-org.sh" --no-scan --bitbucket ws --out "$TMP/e1"
  [ "$status" -eq 4 ]
  run env PATH="$TMP/bin:$PATH" "$ROOT/scripts/audit-org.sh" --no-scan --azure-devops org --out "$TMP/e2"
  [ "$status" -eq 4 ]
  run "$ROOT/scripts/audit-org.sh" --no-scan --bitbucket ws --azure-devops org
  [ "$status" -eq 2 ]
}

# ---------- 3.5: plan, rotate, demo, GitLab groups, install script ----------

# scan_report <file>: a redacted gitleaks report with one AWS key pair, a webhook and an SSH key.
scan_report() {
  cat > "$1" <<'JSON'
[{"RuleID":"slack-webhook-url","File":"notify<x>.sh","StartLine":3,"Commit":"1111111111aaaa","Date":"2026-01-02T00:00:00Z","Secret":"REDACTED"},
 {"RuleID":"generic-api-key","File":".env","StartLine":2,"Commit":"2222222222bbbb","Date":"2026-01-05T00:00:00Z","Secret":"REDACTED"},
 {"RuleID":"aws-access-token","File":".env","StartLine":1,"Commit":"2222222222bbbb","Date":"2026-01-05T00:00:00Z","Secret":"REDACTED"},
 {"RuleID":"aws-access-token","File":".env","StartLine":1,"Commit":"3333333333cccc","Date":"2026-01-06T00:00:00Z","Secret":"REDACTED"},
 {"RuleID":"private-key","File":"deploy/id_ed25519","StartLine":1,"Commit":"2222222222bbbb","Date":"2026-01-05T00:00:00Z","Secret":"REDACTED"},
 {"RuleID":"private-key","File":"keys/ci.json","StartLine":5,"Commit":"2222222222bbbb","Date":"2026-01-05T00:00:00Z","Secret":"REDACTED"}]
JSON
}

@test "plan: orders secrets by danger, pairs an unidentified secret with its neighbour, exits 1" {
  scan_report "$TMP/r.json"
  run "$ROOT/scripts/rotation-plan.sh" "$TMP/r.json" --id INC-7 --tlp red
  [ "$status" -eq 1 ]
  run grep -E '^- \[ \] \*\*[0-9]' "$TMP/rotation-plan.md"
  [[ "${lines[0]}" == *"1. AWS access key"*'`.env`'*"in 2 commits"* ]]
  [[ "${lines[1]}" == *"2. Secret next to the AWS access key"* ]]
  [[ "${lines[2]}" == *"3. Google Cloud service account key"*"keys/ci.json"* ]]
  [[ "${lines[3]}" == *"4. SSH or TLS private key"* ]]
  [[ "${lines[4]}" == *"5. Chat webhook or bot credential"* ]]
  grep -q 'leak rotate aws-key' "$TMP/rotation-plan.md"
  grep -q 'TLP:RED' "$TMP/rotation-plan.html"
  grep -q 'Rotation plan · INC-7' "$TMP/rotation-plan.html"
  grep -q 'notify&lt;x&gt;.sh' "$TMP/rotation-plan.html"
  ! grep -q 'notify<x>' "$TMP/rotation-plan.html"
  jq -e '.count == 5 and .incident == "INC-7" and .items[0].recipe == "aws-key" and (.items[0].guide_url | endswith("#aws"))
         and .items[1].note != null and .items[4].recipe == null' "$TMP/rotation-plan.json"
}

@test "plan: a clean scan exits 0, and anything but a scan report exits 2" {
  echo '[]' > "$TMP/clean.json"
  run "$ROOT/scripts/rotation-plan.sh" "$TMP/clean.json" --out "$TMP/p"
  [ "$status" -eq 0 ]
  grep -q 'Nothing to rotate' "$TMP/p/rotation-plan.md"
  echo '{"not":"a report"}' > "$TMP/bad.json"
  run "$ROOT/scripts/rotation-plan.sh" "$TMP/bad.json"
  [ "$status" -eq 2 ]
  run "$ROOT/scripts/rotation-plan.sh" "$TMP/missing.json"
  [ "$status" -eq 2 ]
  run "$ROOT/scripts/rotation-plan.sh" "$TMP/clean.json" --tlp purple
  [ "$status" -eq 2 ]
}

@test "secret types: every catalog line is complete and links to a real guide section" {
  slugs="$(sed -n 's/^##* //p' "$ROOT/docs/02-rotate-secrets.md" | tr 'A-Z' 'a-z' | sed -E 's/[^a-z0-9 -]//g; s/ /-/g')"
  grep -vE '^[[:space:]]*(#|$)' "$ROOT/scripts/secret-types.txt" | while IFS= read -r line; do
    n="$(awk -F' [|] ' '{print NF}' <<<"$line")"
    [ "$n" -eq 7 ] || { echo "not 7 columns: $line"; false; }
    tier="$(awk -F' [|] ' '{print $3}' <<<"$line")"
    [[ "$tier" =~ ^[1-4]$ ]] || { echo "bad tier: $line"; false; }
    anchor="$(awk -F' [|] ' '{print $5}' <<<"$line")"
    grep -qx "$anchor" <<<"$slugs" || { echo "no section #$anchor in docs/02-rotate-secrets.md"; false; }
  done
  tail -n 1 "$ROOT/scripts/secret-types.txt" | grep -q '^\* | - | 4 '
}

# key_id: a random, format-valid AWS access key ID that works nowhere.
key_id() { printf 'AKIA%s' "$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'A-Z2-7' | head -c 16)"; }

# fake_cloud: aws, az and gcloud doubles. They record their arguments, keep what is piped to a
# secret store, and answer "create" calls with a fresh fake secret held in $TMP/secret. Sets $old
# (the leaked key ID) and $new (the ID the double hands out), both generated now.
fake_cloud() {
  mkdir -p "$TMP/bin"
  head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 40 > "$TMP/secret"
  old="$(key_id)"; new="$(key_id)"; printf '%s' "$new" > "$TMP/new-key-id"
  for c in aws az gcloud; do
    cat > "$TMP/bin/$c" <<MOCK
#!/usr/bin/env bash
printf '$c %s\n' "\$*" >> "$TMP/argv.txt"
secret="\$(cat "$TMP/secret")"; new="\$(cat "$TMP/new-key-id")"
case "\$*" in
  *create-access-key*) printf '{"AccessKey":{"AccessKeyId":"%s","SecretAccessKey":"%s"}}' "\$new" "\$secret" ;;
  *"credential reset"*) printf '%s\n' "\$secret" ;;
  *"credential list"*rotated-*) echo "11111111-2222-3333-4444-555555555555" ;;
  *"keys create /dev/stdout"*) printf '{"private_key_id":"feedface","private_key":"%s"}' "\$secret" ;;
  *put-secret-value*|*"keyvault secret set"*|*"versions add"*) { cat; echo; } >> "$TMP/store.txt"; if [[ -n "\${STORE_FAILS:-}" ]]; then exit 1; fi ;;
  *) echo "ok" ;;
esac
MOCK
    chmod +x "$TMP/bin/$c"
  done
}

@test "rotate: a dry run prints every step and calls no cloud CLI" {
  fake_cloud
  run env PATH="$TMP/bin:$PATH" "$ROOT/scripts/rotate.sh" aws-key --user deploy-bot --key-id "$old"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dry run: nothing was changed"* ]]
  [[ "$output" == *"--status Inactive"* && "$output" == *"delete-access-key"* ]]
  [ ! -e "$TMP/argv.txt" ]
  run "$ROOT/scripts/rotate.sh" no-such-recipe
  [ "$status" -eq 2 ]
  run "$ROOT/scripts/rotate.sh" aws-key --key-id not-a-key
  [ "$status" -eq 2 ]
  run env PATH="$TMP/bin:$PATH" "$ROOT/scripts/rotate.sh" aws-key --user u --key-id "$old" --apply deploy
  [ "$status" -eq 2 ]
  run env PATH="$TMP/bin:$PATH" "$ROOT/scripts/rotate.sh" aws-key --user u --key-id "$old" --apply replace
  [ "$status" -eq 2 ]
  for bad in aws-sm aws-sm: gcp-sm:-x azure-kv:-kv/name; do
    run env PATH="$TMP/bin:$PATH" "$ROOT/scripts/rotate.sh" aws-key --user u --key-id "$old" --apply replace --store "$bad"
    [ "$status" -eq 2 ]
  done
  [ ! -e "$TMP/argv.txt" ]
  run "$ROOT/scripts/rotate.sh" gcp-sa-key --account my-proj@appspot.gserviceaccount.com
  [[ "$output" == *"--project my-proj"* ]]
  run "$ROOT/scripts/rotate.sh" gcp-sa-key --account 123456789012-compute@developer.gserviceaccount.com
  [[ "$output" == *"--project 123456789012"* ]]
  run "$ROOT/scripts/rotate.sh" gcp-sa-key --account ci@proj-1.iam.gserviceaccount.com
  [[ "$output" == *"--project proj-1"* ]]
}

@test "rotate: a new secret reaches only the store, never arguments, output or the log" {
  fake_cloud
  cd "$TMP"
  run env PATH="$TMP/bin:$PATH" "$ROOT/scripts/rotate.sh" aws-key --user deploy-bot --key-id "$old" --apply replace --store aws-sm:prod/deploy-bot
  [ "$status" -eq 0 ]
  [[ "$output" == *"$new is in AWS Secrets Manager secret prod/deploy-bot"* ]]
  run env PATH="$TMP/bin:$PATH" "$ROOT/scripts/rotate.sh" azure-app-secret --app 00000000-1111-2222-3333-444444444444 --key-id 99999999-1111-2222-3333-444444444444 --apply replace --store azure-kv:kv-prod/app-secret
  [ "$status" -eq 0 ]
  run env PATH="$TMP/bin:$PATH" "$ROOT/scripts/rotate.sh" gcp-sa-key --account ci@proj-1.iam.gserviceaccount.com --key-id 0123456789abcdef0123456789abcdef01234567 --apply replace --store gcp-sm:ci-key
  [ "$status" -eq 0 ]
  secret="$(cat "$TMP/secret")"
  [ "$(grep -c "$secret" "$TMP/store.txt")" -eq 3 ]
  ! grep -q "$secret" "$TMP/argv.txt"
  ! grep -q "$secret" "$TMP/rotation-log.tsv"
  [[ "$output" != *"$secret"* ]]
  grep -q 'secret-string file:///dev/stdin' "$TMP/argv.txt"
  grep -q 'keyvault secret set --vault-name kv-prod --name app-secret --file /dev/stdin' "$TMP/argv.txt"
  grep -q 'secrets versions add ci-key --data-file=-' "$TMP/argv.txt"
  [ "$(cut -f4,5 "$TMP/rotation-log.tsv" | grep -c 'replace.ok')" -eq 3 ]
  # Tracing would print it: rotate switches it off.
  run env PATH="$TMP/bin:$PATH" bash -x "$ROOT/scripts/rotate.sh" aws-key --user deploy-bot --key-id "$old" --apply replace --store aws-sm:prod/deploy-bot
  [ "$status" -eq 0 ]
  [[ "$output" != *"$secret"* ]]
}

@test "rotate: if the store refuses the new secret, the new credential is deleted again (exit 4)" {
  fake_cloud
  cd "$TMP"
  run env PATH="$TMP/bin:$PATH" STORE_FAILS=1 "$ROOT/scripts/rotate.sh" aws-key --user deploy-bot --key-id "$old" --apply replace --store aws-sm:prod/deploy-bot
  [ "$status" -eq 4 ]
  grep -q "aws iam delete-access-key --user-name deploy-bot --access-key-id $new" "$TMP/argv.txt"
  ! grep -q "$old --status" "$TMP/argv.txt"
  [[ "$output" != *"$(cat "$TMP/secret")"* ]]
}

@test "rotate: disable and delete ask first; without a terminal they need --yes" {
  fake_cloud
  cd "$TMP"
  run env PATH="$TMP/bin:$PATH" "$ROOT/scripts/rotate.sh" aws-key --user deploy-bot --key-id "$old" --apply disable < /dev/null
  [ "$status" -eq 2 ]
  [ ! -e "$TMP/argv.txt" ]
  run env PATH="$TMP/bin:$PATH" "$ROOT/scripts/rotate.sh" aws-key --user deploy-bot --key-id "$old" --apply disable --yes
  [ "$status" -eq 0 ]
  grep -q "update-access-key --user-name deploy-bot --access-key-id $old --status Inactive" "$TMP/argv.txt"
  run env PATH="$TMP/bin:$PATH" "$ROOT/scripts/rotate.sh" azure-storage-key --group rg --account stprod01 --key key2 --apply renew --yes --log "$TMP/r.tsv"
  [ "$status" -eq 0 ]
  grep -q 'storage account keys renew -g rg -n stprod01 --key key2 -o none' "$TMP/argv.txt"
  grep -q $'azure-storage-key\tkey2@stprod01\trenew\tok' "$TMP/r.tsv"
}

# fake_gitlab: a GitLab API double for leak rotate gitlab-token. It records curl's arguments and
# the header config read on stdin, and answers a rotation with the fake secret from fake_cloud.
fake_gitlab() {
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/curl" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMP/argv.txt"
method=GET; url=""
while ((\$#)); do case "\$1" in -X) method="\$2"; shift 2 ;; -K) [[ "\$2" == - ]] && cat >> "$TMP/config.txt"; shift 2 ;; http*) url="\$1"; shift ;; *) shift ;; esac; done
case "\$method \$url" in
  "GET "*per_page=100) code=200; body='[{"id":42,"name":"ci-deploy","scopes":["api"],"active":true,"last_used_at":"2026-10-27T10:00:00Z","expires_at":"2026-12-01"},{"id":7,"name":"retired","scopes":["read_api"],"active":false}]' ;;
  "GET "*/42) code=200; body='{"id":42,"name":"ci-deploy","scopes":["api"],"active":true,"revoked":false,"created_at":"2026-01-01T00:00:00Z","last_used_at":"2026-10-27T10:00:00Z","last_used_ips":["203.0.113.9"],"expires_at":"2026-12-01"}' ;;
  "POST "*/42/rotate*) code=200; body="{\"id\":43,\"name\":\"ci-deploy\",\"token\":\"\$(cat "$TMP/secret")\",\"expires_at\":\"2027-01-31\"}" ;;
  "DELETE "*) code=204; body="" ;;
  *) code=404; body='{"message":"404 Not Found"}' ;;
esac
printf '%s\n%s' "\$body" "\$code"
MOCK
  chmod +x "$TMP/bin/curl"
}

@test "rotate gitlab-token: finds the token, rotates it into the store only, revokes the new one if the store fails" {
  fake_cloud; fake_gitlab
  cd "$TMP"
  gl=(env PATH="$TMP/bin:$PATH" GITLAB_TOKEN=gl-api-token-for-tests GITLAB_URL=https://gitlab.example.com "$ROOT/scripts/rotate.sh" gitlab-token)
  run "${gl[@]}" --apply check
  [ "$status" -eq 0 ]
  [[ "$output" == *"ci-deploy"* && "$output" != *"retired"* ]]
  run "${gl[@]}" --token-id 42 --project acme/api --apply check
  [ "$status" -eq 0 ]
  [[ "$output" == *"last used:  2026-10-27T10:00:00Z from 203.0.113.9"* ]]
  grep -q 'https://gitlab.example.com/api/v4/projects/acme%2Fapi/access_tokens/42$' "$TMP/argv.txt"
  run "${gl[@]}" --token-id 42 --apply rotate --store gcp-sm:gl-token < /dev/null
  [ "$status" -eq 2 ]
  ! grep -q 'POST' "$TMP/argv.txt"
  run "${gl[@]}" --token-id 42 --apply rotate --store gcp-sm:gl-token --expires 2027-01-31 --yes
  [ "$status" -eq 0 ]
  grep -q -- '-X POST .*/personal_access_tokens/42/rotate?expires_at=2027-01-31' "$TMP/argv.txt"
  grep -q 'gcloud secrets describe gl-token' "$TMP/argv.txt"
  secret="$(cat "$TMP/secret")"
  grep -qx "$secret" "$TMP/store.txt"
  ! grep -q "$secret" "$TMP/argv.txt"
  ! grep -q 'gl-api-token-for-tests' "$TMP/argv.txt"
  grep -q 'PRIVATE-TOKEN: gl-api-token-for-tests' "$TMP/config.txt"
  [[ "$output" != *"$secret"* ]]
  grep -q $'gitlab-token\t42@personal\trotate\tok\t43' "$TMP/rotation-log.tsv"
  run env STORE_FAILS=1 "${gl[@]}" --token-id 42 --apply rotate --store gcp-sm:gl-token --yes
  [ "$status" -eq 4 ]
  grep -q -- '-X DELETE .*/personal_access_tokens/43$' "$TMP/argv.txt"
  [[ "$output" != *"$secret"* ]]
  run env PATH="$TMP/bin:$PATH" "$ROOT/scripts/rotate.sh" gitlab-token --token-id 42 --apply check
  [ "$status" -eq 2 ]
  run "${gl[@]}" --token-id 42 --project acme/api --group acme
  [ "$status" -eq 2 ]
  run "${gl[@]}" --token-id 42 --project 'acme/api?x=1'
  [ "$status" -eq 2 ]
  printf '%s' '[{"RuleID":"gitlab-pat","File":"ci.env","StartLine":1,"Commit":"4444444444dddd","Date":"2026-02-01T00:00:00Z","Secret":"REDACTED"},
    {"RuleID":"aws-amazon-bedrock-api-key-long-lived","File":"ai.env","StartLine":1,"Commit":"5555555555eeee","Date":"2026-02-02T00:00:00Z","Secret":"REDACTED"}]' > "$TMP/gl.json"
  run "$ROOT/scripts/rotation-plan.sh" "$TMP/gl.json"
  [ "$status" -eq 1 ]
  grep -q 'leak rotate gitlab-token' "$TMP/rotation-plan.md"
  grep -q 'Amazon Bedrock API key' "$TMP/rotation-plan.md"
  ! grep -q 'leak rotate aws-key' "$TMP/rotation-plan.md"
}

@test "demo: builds a leak and runs audit, scan, plan and a rotation dry run" {
  scanner_available || skip "needs gitleaks or docker"
  cd "$TMP"
  run "$ROOT/scripts/demo.sh" --out "$TMP/demo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Grade F"* && "$output" == *"Rotation plan:"* && "$output" == *"Dry run: nothing was changed"* ]]
  grep -q '1. AWS access key' "$TMP/demo/rotation-plan.md"
  run "$ROOT/scripts/demo.sh" --out "$TMP/demo"
  [ "$status" -eq 2 ]
  # Someone who uses Spillkit's ignore file and hook globally can still run the demo.
  printf '[core]\n\texcludesFile = %s\n\thooksPath = %s\n' "$ROOT/prevention/gitignore-secrets" "$ROOT/prevention/hooks" > "$TMP/gitconfig"
  run env GIT_CONFIG_GLOBAL="$TMP/gitconfig" "$ROOT/scripts/demo.sh" --out "$TMP/demo2"
  [ "$status" -eq 0 ]
  grep -q '1. AWS access key' "$TMP/demo2/rotation-plan.md"
}

@test "audit-org: lists a GitLab group with subgroups, skips forks, keeps the token out of arguments" {
  mkdir -p "$TMP/bin"
  printf '%s' '[{"path_with_namespace":"acme/platform/api","http_url_to_repo":"https://oauth2@127.0.0.1:9/acme/platform/api.git"},{"path_with_namespace":"acme/web","http_url_to_repo":"https://127.0.0.1:9/acme/web.git","forked_from_project":{"id":1}}]' > "$TMP/page1.json"
  cat > "$TMP/bin/curl" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$@" >> "$TMP/argv.txt"
out=""; url=""; while ((\$#)); do case "\$1" in -o) out="\$2"; shift 2 ;; -K) [[ "\$2" == - ]] && cat >> "$TMP/config.txt"; shift 2 ;; http*) url="\$1"; shift ;; *) shift ;; esac; done
if [[ "\$url" == *page=1 ]]; then cp "$TMP/page1.json" "\$out"; else echo '[]' > "\$out"; fi; printf 200
MOCK
  chmod +x "$TMP/bin/curl"
  run env PATH="$TMP/bin:$PATH" GITLAB_TOKEN=gl-test-token-789 GITLAB_URL=https://gitlab.example.com/ "$ROOT/scripts/audit-org.sh" --no-scan --gitlab acme --out "$TMP/gl"
  run jq -r '.repositories, .results[0].repository' "$TMP/gl/audit-org.json"
  [ "${lines[0]}" = "1" ] && [ "${lines[1]}" = "platform/api" ]
  [ -f "$TMP/gl/results/platform__api.json" ]
  ! grep -q "gl-test-token-789" "$TMP/argv.txt"
  grep -q "PRIVATE-TOKEN: gl-test-token-789" "$TMP/config.txt"
  grep -q "gitlab.example.com/api/v4/groups/acme/projects?include_subgroups=true&with_shared=false" "$TMP/argv.txt"
  fake_curl 401 '{"message":"401 Unauthorized"}'
  run env PATH="$TMP/bin:$PATH" "$ROOT/scripts/audit-org.sh" --no-scan --gitlab acme --out "$TMP/gl2"
  [ "$status" -eq 4 ]
  run "$ROOT/scripts/audit-org.sh" --gitlab "not a group"
  [ "$status" -eq 2 ]
}

@test "install.sh: installs a release whose checksum matches, and refuses a tampered one" {
  rel="$TMP/rel/download/v9.9.9"; mkdir -p "$rel"
  mkdir -p "$TMP/stage/spillkit-v9.9.9" && cp -R "$ROOT/leak" "$ROOT/scripts" "$TMP/stage/spillkit-v9.9.9/"
  tar -czf "$rel/spillkit-v9.9.9.tar.gz" -C "$TMP/stage" spillkit-v9.9.9
  (cd "$rel" && { sha256sum spillkit-v9.9.9.tar.gz 2>/dev/null || shasum -a 256 spillkit-v9.9.9.tar.gz; } > spillkit-v9.9.9.tar.gz.sha256 && echo '{}' > spillkit-v9.9.9.tar.gz.sigstore.json)
  run env SPILLKIT_RELEASES="file://$TMP/rel" "$ROOT/install.sh" --version 9.9.9 --prefix "$TMP/p"
  [ "$status" -eq 0 ]
  run "$TMP/p/bin/leak" version
  [[ "$output" == spillkit* ]]
  cd "$TMP"
  run env SPILLKIT_RELEASES="file://$TMP/rel" "$ROOT/install.sh" --version 9.9.9 --prefix relative-prefix
  [ "$status" -eq 0 ]
  run "$TMP/relative-prefix/bin/leak" version
  [[ "$output" == spillkit* ]]
  # An archive that matches its checksum but cannot be unpacked: the installed version survives.
  printf 'not an archive' > "$rel/spillkit-v9.9.9.tar.gz"
  (cd "$rel" && { sha256sum spillkit-v9.9.9.tar.gz 2>/dev/null || shasum -a 256 spillkit-v9.9.9.tar.gz; } > spillkit-v9.9.9.tar.gz.sha256)
  run env SPILLKIT_RELEASES="file://$TMP/rel" "$ROOT/install.sh" --version 9.9.9 --prefix "$TMP/p"
  [ "$status" -ne 0 ]
  run "$TMP/p/bin/leak" version
  [[ "$output" == spillkit* ]]
  [ -z "$(find "$TMP/p/share/spillkit" -maxdepth 1 -name '.install.*')" ]
  echo tampered >> "$rel/spillkit-v9.9.9.tar.gz"
  run env SPILLKIT_RELEASES="file://$TMP/rel" "$ROOT/install.sh" --version v9.9.9 --prefix "$TMP/p2"
  [ "$status" -ne 0 ]
  [ ! -e "$TMP/p2/bin/leak" ]
  run "$ROOT/install.sh" --version not-a-version
  [ "$status" -ne 0 ]
}

@test "audit: in CI, a missing local hook is not a finding (hooks live in developer clones)" {
  new_repo "$TMP/ci"
  cp "$ROOT/prevention/pre-commit-config.yaml" "$TMP/ci/.pre-commit-config.yaml"
  commit_all "$TMP/ci" "init"
  run env -u TF_BUILD CI=true "$ROOT/scripts/audit.sh" --no-scan "$TMP/ci"
  [[ "$output" == *"local hook not checked in CI"* && "$output" != *"no pre-commit hook installed"* ]]
  run env -u CI -u TF_BUILD "$ROOT/scripts/audit.sh" --no-scan "$TMP/ci"
  [[ "$output" == *"no pre-commit hook installed in this clone"* ]]
}

@test "install.sh: verifies the signature for this exact release, with cosign 2 or 3" {
  rel="$TMP/rel/download/v9.9.9"; mkdir -p "$rel" "$TMP/stage/spillkit-v9.9.9" "$TMP/bin"
  cp -R "$ROOT/leak" "$ROOT/scripts" "$TMP/stage/spillkit-v9.9.9/"
  tar -czf "$rel/spillkit-v9.9.9.tar.gz" -C "$TMP/stage" spillkit-v9.9.9
  (cd "$rel" && { sha256sum spillkit-v9.9.9.tar.gz 2>/dev/null || shasum -a 256 spillkit-v9.9.9.tar.gz; } > spillkit-v9.9.9.tar.gz.sha256 && echo '{}' > spillkit-v9.9.9.tar.gz.sigstore.json)
  for v in v2.4.1 v3.0.2; do
    cat > "$TMP/bin/cosign" <<MOCK
#!/usr/bin/env bash
if [[ "\$1" == version ]]; then echo "GitVersion:    $v"; exit 0; fi
printf '%s\n' "\$*" > "$TMP/cosign-args.txt"
MOCK
    chmod +x "$TMP/bin/cosign"
    run env PATH="$TMP/bin:$PATH" SPILLKIT_RELEASES="file://$TMP/rel" "$ROOT/install.sh" --version v9.9.9 --prefix "$TMP/p-$v" --require-signature
    [ "$status" -eq 0 ]
    [[ "$output" == *"Signature verified"* ]]
    grep -q -- "--certificate-identity https://github.com/aboutBilal/spillkit/.github/workflows/release.yml@refs/tags/v9.9.9" "$TMP/cosign-args.txt"
    if [[ "$v" == v2* ]]; then grep -q -- "--new-bundle-format" "$TMP/cosign-args.txt"; else ! grep -q -- "--new-bundle-format" "$TMP/cosign-args.txt"; fi
  done
}
