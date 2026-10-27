SHELL := /bin/bash
SCRIPTS := $(wildcard scripts/*.sh) leak

.PHONY: help check lint test scan

help: ## List the targets
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-6s %s\n", $$1, $$2}'

check: lint test scan ## Run everything CI runs

lint: ## shellcheck every script (local shellcheck, else Docker)
	@if command -v shellcheck >/dev/null; then shellcheck -S warning $(SCRIPTS); \
	else docker run --rm -v "$(CURDIR):/mnt:ro" -w /mnt koalaman/shellcheck:stable -S warning $(SCRIPTS); fi
	@echo "lint: ok"

test: ## Offline bats tests (install: apt install bats / brew install bats-core)
	@command -v bats >/dev/null || { echo "bats not found: apt install bats, or brew install bats-core"; exit 2; }
	@bats tests

scan: ## Secret scan of this repository's full history
	@./scripts/scan-secrets.sh . "$${TMPDIR:-/tmp}/leak-response-toolkit-self-scan.json"
