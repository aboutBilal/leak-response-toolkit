# Roadmap

What is planned next. Ideas and help are welcome: open an [improvement issue](https://github.com/aboutBilal/leak-response-toolkit/issues/new/choose) or see [CONTRIBUTING.md](CONTRIBUTING.md).

## Done in 3.0

- `leak audit-org`: grade every repository in an organisation, with an HTML dashboard.
- SARIF output for `leak scan`; JSON output for `leak audit`.
- `leak hunt` searches public GitLab as well as GitHub.
- Alerts to Slack, Microsoft Teams and Discord from the GitHub Action.
- Pre-commit hooks published from this repository; macOS support tested in CI.

## Next

- Bitbucket Cloud and Azure DevOps as `audit-org` sources.
- SARIF output for `leak audit`.
- A Homebrew formula for macOS and Linux.

## Later

- A documentation site with search (built from `docs/`, with hash-pinned dependencies).
- Rotation recipes as scripts for the most common cloud credentials (with a dry-run mode).
- Translations of the runbook and cheat sheet.

## Principles that will not change

- **No secret is ever printed, stored or tested** by the toolkit.
- **No real incidents, names or secrets** in the repository, not even fake ones.
- **Everything in the prevention kit is tested** before it is published.
- **Read-only by default:** tools inspect and report; people decide and act.
