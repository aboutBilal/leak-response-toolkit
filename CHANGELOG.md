# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [3.1.0] - 2026-10-27

### Added

- **Visual language** ([`assets/DESIGN.md`](assets/DESIGN.md)): one accent colour, status colours only for status, an 8-point grid, two corner radii, one type pair. Every README image, the social card, the terminal renderer and the HTML report and dashboard now use the same tokens.

### Changed

- `leak audit` wording is shorter and clearer (for example "no secret files tracked by Git"), and the summary line reads `Score 100/100 · Grade A`. Scripts that parsed `Score:` should match `Score ` instead.
- `leak scan` names the pinned gitleaks version instead of printing the full image reference.

### Fixed

- Tests hung on macOS: BSD `tr` keeps reading `/dev/urandom` when SIGPIPE is ignored. Random test values now come from a bounded read. The macOS CI job passes.

## [3.0.0] - 2026-10-27

### Added

- `leak audit-org`: grades every repository of a GitHub organisation or user, or every repository in a local folder, and writes an HTML dashboard, a markdown summary and JSON.
- `leak scan --sarif`: SARIF 2.1.0 output for GitHub code scanning. Values stay redacted.
- `leak audit --json`: machine-readable grade, score and checks.
- `leak notify`: alerts to Slack, Microsoft Teams (Workflows webhooks) or Discord. The webhook URL is read from `LEAK_WEBHOOK_URL`, never from arguments.
- GitHub Action: `audit-org` mode, `sarif-file`, `webhook-url` and `webhook-format` inputs, and a `report` output.
- `.pre-commit-hooks.yaml`: `forbid-secret-files` and `leak-guard` hooks usable from any repository.
- `leak hunt` checks public GitLab projects with the same name.
- macOS job in CI (Homebrew bash, BSD tools).
- Animated terminal demo (respects reduced-motion settings), and dashboard and report previews in the README.

### Changed

- **Breaking for automation:** `leak hunt` reports use plain words (`clean`, `**found**`, `review`, `not checked`) instead of symbols. Update any script that matched the old markers.
- The `@v3` Action tag replaces `@v2` in examples.
- Documentation edited for precision: plain headings without emoji, measured claims only.

### Fixed

- macOS compatibility: POSIX character classes instead of `\s`, no GNU-only `sed` flags, `shasum` when `sha256sum` is absent, BSD `date` fallback.

## [2.3.0] - 2026-10-27

A new face: the toolkit now presents itself like the product it is.

### Added

- **Brand:** a shield-and-keyhole logo, a product hero banner with a live `leak audit` card, a "How it works" lifecycle graphic, and a matching social preview card.
- **Report preview:** a real `leak report` rendered as a document preview, so readers see what leadership receives.
- **"Built to be trusted"** section: signed releases, SBOM and provenance, OpenSSF Scorecard, pinned dependencies, analysis and tests, each verifiable.

### Changed

- README rebuilt as a product page: hero, live badges (CI, Scorecard, latest release, signed releases), install, demos, incident quick-start, prevention, CI, commands, trust, comparison, FAQ.

## [2.2.0] - 2026-10-27

Supply-chain hardening, guided by the OpenSSF Scorecard results.

### Added

- **Signed releases:** every release gets a source archive, its SHA-256 and a keyless **Sigstore** signature bundle; the container image is signed by digest. Verification commands are in [SECURITY.md](SECURITY.md#verifying-a-release).
- **CodeQL** static analysis of the workflows and Python tooling.
- **Dependabot** now also updates the container base image.
- SECURITY.md: supported versions, what counts as a vulnerability, and a coordinated-disclosure timeline.

### Changed

- Every container image reference (Dockerfile, CI, scripts, prevention kit) is **pinned by digest** as well as by tag.
- The Scorecard badge links directly to the current score.

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

[Unreleased]: https://github.com/aboutBilal/leak-response-toolkit/compare/v3.1.0...HEAD
[3.1.0]: https://github.com/aboutBilal/leak-response-toolkit/compare/v3.0.0...v3.1.0
[3.0.0]: https://github.com/aboutBilal/leak-response-toolkit/compare/v2.3.0...v3.0.0
[2.3.0]: https://github.com/aboutBilal/leak-response-toolkit/compare/v2.2.0...v2.3.0
[2.2.0]: https://github.com/aboutBilal/leak-response-toolkit/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/aboutBilal/leak-response-toolkit/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/aboutBilal/leak-response-toolkit/compare/v1.1.0...v2.0.0
[1.1.0]: https://github.com/aboutBilal/leak-response-toolkit/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/aboutBilal/leak-response-toolkit/releases/tag/v1.0.0
