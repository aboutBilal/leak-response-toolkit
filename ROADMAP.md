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

## Done in 3.5
- `leak plan`: a rotation checklist from a scan, most dangerous first.
- `leak rotate`: AWS, Azure and Google Cloud keys rotated step by step, with a dry run by default and new secrets piped straight into a secret store.
- `leak demo`, a one-line signed install, and GitLab groups as an `audit-org` source.

## Done in 3.6
- `leak rotate gitlab-token`: personal, project and group access tokens, checked, rotated into a secret store, or revoked.
- `leak plan` in the GitHub Action: a scan with findings ends with what to rotate first, and the full plan as an output.
- `leak plan` also writes JSON, for automation.
- A Homebrew tap: `brew install aboutbilal/tap/spillkit` on macOS and Linux.

## Done in 3.7
- `leak respond`: the first hour of an incident in one command, with a UTC timeline, resumable.
- Fast pull request scans: `leak scan --commits` and `scope: changes` in the GitHub Action.

## Done in 3.8
- `leak rotate azure-devops-pat`: Azure DevOps personal access tokens, replaced with the same scope, then revoked.
- Accessibility: every page of the site and every generated report checked with axe-core against WCAG 2.1 AA.

## Next
- More `leak rotate` recipes: database passwords, and GitHub App private keys once GitHub offers an API for them.

## Later
- Translations of the runbook and cheat sheet.

## Principles that will not change

- **No secret is ever printed, stored or tested** by the toolkit.
- **No real incidents, names or secrets** in the repository, not even fake ones.
- **Everything in the prevention kit is tested** before it is published.
- **Read-only by default:** tools inspect and report; people decide and act.
