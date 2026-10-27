# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [2.1.0] - 2026-10-27

### Added

- **Container image** `ghcr.io/aboutbilal/leak-response-toolkit` (amd64 and arm64) with every dependency, gitleaks included; runs as a non-root user.
- **Release automation:** every version tag publishes GitHub release notes from this changelog (backfilling earlier tags) and the image, with an **SBOM and build provenance**.
- **OpenSSF Scorecard** analysis on every push to `main` and weekly, with a README badge.
- `make install` / `make uninstall` (puts `leak` on your PATH) and `make image`.
- README: install options, a real `leak audit` demo, an honest comparison with gitleaks, TruffleHog and GitGuardian, and an FAQ.
- `tools/render-terminal-svg.py`: README images are generated from real command output.
- `CITATION.cff`, `ROADMAP.md`, a social preview image.

### Fixed

- `leak audit` printed the value of a secret found in a Dockerfile `ARG`/`ENV` line. It now shows only the file, line and variable name (`API_TOKEN=<redacted>`), and a test enforces it.
- `leak` now resolves symlinks, so it works when installed on the PATH or inside the image.
- `leak audit` no longer warns about documentation that mentions environment variables, or about example Dockerfiles.

## [2.0.0] - 2026-10-27

Prevention becomes the second half of the kit: not only responding to leaks, but designing them out.

### Added

- **[Secrets by design](docs/08-secrets-by-design.md)**: an architecture guide with five principles, a reference architecture, an 8-layer control matrix, maturity levels 0–4, a 90-day rollout, metrics and a design-review checklist.
- **[Prevention kit](prevention/README.md)**, every file tested: secret-aware `.gitignore`, pre-commit config (gitleaks, private-key detection, blocked secret file types), a plain git hook, a gitleaks config with custom rules, CI templates for GitHub Actions, GitLab, Azure Pipelines and Bitbucket, keyless OIDC login to AWS, Azure and Google Cloud, `.dockerignore`, a BuildKit build-secret example, `.env.example`.
- `./leak audit`: grades a repository's secret hygiene A–F with a fix for every gap.
- `./leak report`: builds the leadership report from hunt and scan results (secret types only; content HTML-escaped).
- `./leak doctor`: checks a machine is ready before an incident.
- **GitHub Action** (`action.yml`): `scan`, `audit` or `hunt` in any repository's CI, with job summaries; self-tested in this repository's CI.
- `hunt` also writes machine-readable `results.jsonl` and `meta.json`.
- Rotation guide: AI provider keys, container and package registries, Kubernetes, Terraform Cloud, source platform tokens, messaging, payments, webhooks.
- Tests: 16 offline tests (audit grades, report escaping, doctor).

### Changed

- This repository now uses the prevention kit on itself (`./leak audit .` → Grade A).
- README reorganised around **prevent** and **respond**.

## [1.1.0] - 2026-10-27

### Added

- `./leak`: one command for every script (`snapshot`, `scan`, `forks`, `hunt`, `commits`), with tests.
- `CHEATSHEET.md`: the first 15 minutes on one page, with a "who to call" table to fill in ahead of time.
- `templates/incident-issue.md`: a team checklist to paste into a private issue tracker.
- README front page: banner, sourced "why minutes matter" figures, command table and a terminal image of real, redacted output.

## [1.0.0] - 2026-10-27

### Added

- **Runbook** for code or secrets exposed in a public repository, and a **scenario guide**: own repository, made public by mistake, copied to another account, provider alerts, leaks outside Git (gists, pastes, CI logs, images, packages, chat), external reports, non-GitHub platforms.
- **Rotation guide** per secret type (Azure, AWS, Google Cloud, GitHub, databases, SSH and certificates, application secrets) and guidance for keys meant to be public.
- **Investigation guide** with log queries for Azure, AWS, Google Cloud and databases.
- **Where copies survive**: archives, forks, re-uploads, evidence that disappears, removal requests.
- **Prevention guide**, including a measured test of what push protection and gitleaks each catch.
- **Practice drill** for teams.
- Scripts: `snapshot-evidence.sh`, `scan-secrets.sh` (redacted, full history), `list-forks.sh`, `hunt-copies.sh` (15+ public sources, markdown report), `find-commit-copies.sh`, all with `--help`.
- Templates: incident timeline, takedown request, notification messages, post-incident review, executive report (print-ready HTML).
- Quality: offline bats tests, shellcheck, gitleaks on full history, link and anchor checks in CI, Dependabot for pinned actions, pre-commit hook, contribution guide, issue and pull request templates, security policy.

[Unreleased]: https://github.com/aboutBilal/leak-response-toolkit/compare/v2.1.0...HEAD
[2.1.0]: https://github.com/aboutBilal/leak-response-toolkit/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/aboutBilal/leak-response-toolkit/compare/v1.1.0...v2.0.0
[1.1.0]: https://github.com/aboutBilal/leak-response-toolkit/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/aboutBilal/leak-response-toolkit/releases/tag/v1.0.0
