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
  fake="AKIA$(LC_ALL=C tr -dc 'A-Z2-7' </dev/urandom | head -c 16)"
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
  echo "DB_PASSWORD=$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 12)" > "$TMP/bad/.env"
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
  value="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 16)"
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
  fake="AKIA$(LC_ALL=C tr -dc 'A-Z2-7' </dev/urandom | head -c 16)"
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
  value="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 16)"
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
