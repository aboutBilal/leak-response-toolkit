# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/aboutBilal/leak-response-toolkit/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/aboutBilal/leak-response-toolkit/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/aboutBilal/leak-response-toolkit/releases/tag/v1.0.0
