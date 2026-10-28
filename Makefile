SHELL := /bin/bash
SCRIPTS := $(wildcard scripts/*.sh) leak install.sh prevention/hooks/pre-commit tools/build-site.sh
PREFIX ?= $(HOME)/.local

.PHONY: help check lint test scan audit install uninstall image

help: ## List the targets
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-6s %s\n", $$1, $$2}'

check: lint test scan ## Run everything CI runs

lint: ## shellcheck every script (local shellcheck, else Docker)
	@if command -v shellcheck >/dev/null; then shellcheck -S warning -x $(SCRIPTS); \
	else docker run --rm -v "$(CURDIR):/mnt:ro" -w /mnt koalaman/shellcheck:stable -S warning -x $(SCRIPTS); fi
	@echo "lint: ok"

test: ## Offline bats tests (install: apt install bats / brew install bats-core)
	@command -v bats >/dev/null || { echo "bats not found: apt install bats, or brew install bats-core"; exit 2; }
	@BATS_TEST_TIMEOUT=60 bats tests

scan: ## Secret scan of this repository's full history
	@./scripts/scan-secrets.sh . "$${TMPDIR:-/tmp}/spillkit-self-scan.json"

audit: ## Grade this repository's own secret hygiene
	@./leak audit .

install: ## Put `leak` on your PATH (symlink into $(PREFIX)/bin)
	@mkdir -p "$(PREFIX)/bin" && ln -sf "$(CURDIR)/leak" "$(PREFIX)/bin/leak"
	@echo "installed: $(PREFIX)/bin/leak  (run: leak doctor)"

uninstall: ## Remove the `leak` symlink
	@rm -f "$(PREFIX)/bin/leak" && echo "removed: $(PREFIX)/bin/leak"

image: ## Build the container image locally
	@docker build -t spillkit:local .
