# Roadmap

What is planned next. Ideas and help are welcome: open an [improvement issue](https://github.com/aboutBilal/spillkit/issues/new/choose) or see [CONTRIBUTING.md](CONTRIBUTING.md).

## Done in 3.0

- `leak audit-org`: grade every repository in an organisation, with an HTML dashboard.
- SARIF output for `leak scan`; JSON output for `leak audit`.
- `leak hunt` searches public GitLab as well as GitHub.
- Alerts to Slack, Microsoft Teams and Discord from the GitHub Action.
- Pre-commit hooks published from this repository; macOS support tested in CI.

## Done in 3.3 and 3.4
- A documentation site with full-text search, built from `docs/` and checked on every pull request.
- Standard incident reports (NIST SP 800-61r3 structure, FIRST TLP 2.0 labels) and a print-ready organisation report.
- SARIF output for `leak audit`, with a precise location for each finding.
- Bitbucket Cloud and Azure DevOps as `audit-org` sources.

## Next
- A Homebrew formula for macOS and Linux.
- Rotation recipes as scripts for the most common cloud credentials (with a dry-run mode).
- GitLab groups as an `audit-org` source.

## Later
- Translations of the runbook and cheat sheet.

## Principles that will not change

- **No secret is ever printed, stored or tested** by the toolkit.
- **No real incidents, names or secrets** in the repository, not even fake ones.
- **Everything in the prevention kit is tested** before it is published.
- **Read-only by default:** tools inspect and report; people decide and act.
