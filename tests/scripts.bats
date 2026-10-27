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
  for s in snapshot-evidence list-forks hunt-copies find-commit-copies scan-secrets make-report notify; do
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
  for c in snapshot scan forks hunt commits; do [[ "$output" == *"$c"* ]]; done
  run "$ROOT/leak" version
  [ "$status" -eq 0 ]
  [[ "$output" == leak-response-toolkit* ]]
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
  [ "${lines[1]}" = "leak-response-toolkit" ]
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
