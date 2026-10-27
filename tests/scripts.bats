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
  for s in "$ROOT"/scripts/*.sh; do
    run "$s" --help
    [ "$status" -eq 0 ] || { echo "$s exited $status"; false; }
    [[ "$output" == *"Usage:"* ]] || { echo "$s help has no Usage line"; false; }
  done
}

@test "every script exits 2 when required arguments are missing" {
  for s in snapshot-evidence list-forks hunt-copies find-commit-copies scan-secrets; do
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
