# Roadmap

What is planned next. Ideas and help are welcome: open an [improvement issue](https://github.com/aboutBilal/leak-response-toolkit/issues/new/choose) or see [CONTRIBUTING.md](CONTRIBUTING.md).

## Next

- **`leak hunt` beyond GitHub:** public GitLab and Bitbucket projects as copy sources.
- **SARIF output** for `scan` and `audit`, so findings appear in code-scanning dashboards.
- **`leak audit --org`:** grade every repository in an organisation and produce one table.
- **Homebrew formula** for macOS and Linux.

## Later

- A documentation site with search.
- Rotation recipes as scripts for the most common cloud credentials (with a dry-run mode).
- Translations of the runbook and cheat sheet.

## Principles that will not change

- **No secret is ever printed, stored or tested** by the toolkit.
- **No real incidents, names or secrets** in the repository, not even fake ones.
- **Everything in the prevention kit is tested** before it is published.
- **Read-only by default:** tools inspect and report; people decide and act.
