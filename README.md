<p align="center">
  <img src="assets/banner.svg" alt="Spillkit: prevent secret leaks, respond in minutes" width="100%">
</p>

<p align="center">
  <a href="https://github.com/aboutBilal/spillkit/actions/workflows/secret-scan.yml"><img src="https://github.com/aboutBilal/spillkit/actions/workflows/secret-scan.yml/badge.svg" alt="checks"></a>
  <a href="https://scorecard.dev/viewer/?uri=github.com/aboutBilal/spillkit"><img src="https://img.shields.io/ossf-scorecard/github.com/aboutBilal/spillkit?label=openssf%20scorecard&style=flat" alt="OpenSSF Scorecard"></a>
  <a href="https://github.com/aboutBilal/spillkit/releases/latest"><img src="https://img.shields.io/github/v/release/aboutBilal/spillkit?label=release&color=ff7a59" alt="latest release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT license"></a>
</p>

<p align="center"><a href="https://aboutbilal.github.io/spillkit/"><b>Documentation site</b></a> · <a href="docs/01-runbook.md">Incident runbook</a> · <a href="CHEATSHEET.md">Cheat sheet</a></p>

Spillkit helps engineering teams keep secrets out of source control, and respond quickly when one gets out.

It pairs a reference architecture and a set of tested prevention configs with one command-line tool, `leak`, that grades repositories, scans their full Git history, searches public sources for surviving copies of leaked code, and turns the evidence into a report leadership can act on. Detection is done by [gitleaks](https://github.com/gitleaks/gitleaks); this project covers what has to happen around it.

<p align="center">
  <img src="assets/how-it-works.svg" alt="How it works: prevent with leak audit, detect with leak scan, respond with leak hunt, report and learn with leak report" width="100%">
</p>

## Why it matters

- Attackers have found and used AWS keys within [five minutes](https://unit42.paloaltonetworks.com/malicious-operations-of-exposed-iam-keys-cryptojacking/) of their exposure on public GitHub (Unit 42, 2023).
- 28.6 million new hard-coded secrets reached public GitHub in 2025, 34% more than the year before, and 64% of the secrets leaked in 2022 were still exploitable four years later ([GitGuardian, 2026](https://www.gitguardian.com/state-of-secrets-sprawl-report-2026)).
- In our own [measured test](docs/04-prevention.md#what-each-layer-catches-a-measured-test), GitHub push protection blocked 5 of 9 secret types; a pre-commit scan caught all 9. One layer is not enough.

Deleting a repository does not revoke a credential. Rotation does. Everything else limits the spread and establishes what happened.

## Install

**Docker** (no local dependencies; signed image for amd64 and arm64):

```bash
docker run --rm -v "$PWD:/repo" ghcr.io/aboutbilal/spillkit audit /repo
```

**From source** (bash 4.4+, git, curl, jq, and gitleaks or Docker):

```bash
git clone https://github.com/aboutBilal/spillkit.git
cd spillkit && make install      # puts `leak` in ~/.local/bin
leak doctor                                   # confirms the machine is ready
```

**GitHub Actions**: see [CI integration](#ci-integration).

## Quick start

```bash
leak audit .        # grade this repository's secret hygiene, A to F, with a fix for each gap
leak scan .         # find secrets in every commit and branch; values are always redacted
```

<p align="center"><img src="assets/demo-audit.svg" alt="Output of leak audit on a repository with a tracked .env file, no hooks and a secret in a Dockerfile: grade F with a fix for every finding; secret values are redacted" width="92%"></p>

<details>
<summary>Output of <code>leak scan</code></summary>
<br>
<p align="center"><img src="assets/demo-scan.svg" alt="Output of leak scan: two secrets found in a commit that was later deleted; values redacted" width="92%"></p>
</details>

<sub>Images show real output on demo repositories, rendered with <a href="tools/render-terminal-svg.py">tools/render-terminal-svg.py</a>. The test secrets were random and never stored.</sub>

## Responding to a leak

Pick the situation that matches, then follow the steps.

| Situation | Guide |
|---|---|
| A secret was committed to one of our public repositories | [Scenario A](docs/06-scenarios.md#a--a-secret-committed-to-your-own-public-repository) |
| A private repository was made public by mistake | [Scenario B](docs/06-scenarios.md#b--a-private-repository-was-made-public-by-mistake) |
| Our code was pushed to someone else's public account | [Runbook](docs/01-runbook.md) |
| A provider emailed us that a key was exposed | [Scenario D](docs/06-scenarios.md#d--a-provider-alert-your-key-was-exposed) |
| The secret leaked outside Git (gist, paste, CI log, image, package, chat) | [Scenario E](docs/06-scenarios.md#e--leaks-outside-git) |
| Someone outside the company reported it | [Scenario F](docs/06-scenarios.md#f--someone-reported-it-to-you) |

The first hour, in order:

1. **Preserve evidence** before anything is deleted: `leak snapshot owner/repo`.
2. **Find every secret** in the full history: `leak scan <path>`.
3. **Rotate and revoke**, most powerful credential first. The [rotation guide](docs/02-rotate-secrets.md) covers more than 25 secret types.
4. **Remove copies and look for others**: `leak forks`, `leak hunt`, `leak commits`, and the [takedown checklist](templates/takedown-request.md).
5. **Check for misuse** from the first push to the moment each secret was revoked: [investigation guide](docs/03-investigate.md).
6. **Communicate**: [message templates](templates/notification-messages.md), `leak report`, and a [team checklist](templates/incident-issue.md) for your tracker.

The full procedure is in the [runbook](docs/01-runbook.md); the [cheat sheet](CHEATSHEET.md) fits on one page. Teams that rehearse respond faster: the [45-minute drill](docs/07-practice-drill.md) needs no real secrets.

## Preventing leaks

Effective prevention is layered, and every layer assumes the one before it failed: pre-commit hooks on developer machines, push protection on the server, full-history scans in CI, no secrets in container images, keyless (OIDC) deployments, and a secret manager at runtime.

```bash
cp prevention/pre-commit-config.yaml ~/code/my-service/.pre-commit-config.yaml
cd ~/code/my-service && pre-commit install    # .env files, keys and secrets are now blocked at commit
```

Or use the hooks directly from this repository:

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/aboutBilal/spillkit
    rev: v3.3.0
    hooks:
      - id: forbid-secret-files    # no dependencies
      - id: leak-guard             # also scans staged changes with gitleaks
```

- [Secrets by design](docs/08-secrets-by-design.md) is written for architects and platform leads: principles, a reference architecture, an eight-layer control matrix, a maturity model, a 90-day rollout plan and metrics.
- The [prevention kit](prevention/README.md) is for engineers: hooks, CI templates for GitHub Actions, GitLab, Azure Pipelines and Bitbucket, OIDC login to AWS, Azure and Google Cloud, and Docker and `.env` patterns. Every file was tested before it was added.

This repository uses the kit on itself, and `leak audit .` grades it A.

## Organisation dashboard

`leak audit-org` grades every repository in a GitHub organisation (or a local folder of repositories) and writes an HTML dashboard, a markdown summary and JSON. Repositories are listed worst first, each with the fixes it needs.

```bash
leak audit-org my-org                 # GITHUB_TOKEN includes private repositories you can read
leak audit-org --no-scan my-org       # faster: skips full-history scans
```

<p align="center"><img src="assets/dashboard-preview.png" alt="The audit-org dashboard: five repositories with grades from A to F, a grade distribution, and the fixes each repository needs" width="100%"></p>

## Reports for leadership

`leak report` builds a print-ready incident report from the results of `leak hunt` and `leak scan`: an executive summary, the state of every public source that was checked, the secret types to rotate, and the open actions. Secret values are never included. Facts the tools cannot know, such as the exposure window, are left highlighted for you to fill in.

<p align="center"><img src="assets/report-preview.png" alt="A report generated by leak report: executive summary, status cards, key facts and the investigation table" width="100%"></p>

## CI integration

```yaml
# .github/workflows/secrets.yml
on: [push, pull_request]
permissions:
  contents: read
  security-events: write          # only needed to upload SARIF
jobs:
  secrets:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with: { fetch-depth: 0, persist-credentials: false }
      - uses: aboutBilal/spillkit@v3   # pin to a commit SHA in production
        with:
          mode: scan                                # scan, audit, audit-org or hunt
          sarif-file: leak.sarif
          webhook-url: ${{ secrets.SECURITY_WEBHOOK }} # optional: Slack, Teams or Discord
      - uses: github/codeql-action/upload-sarif@9b3254085494b55a0f7c4c2b3d2d52cc712ce370 # v4.39.1
        if: always()
        with: { sarif_file: leak.sarif }
```

Findings appear in the job summary and, with SARIF, in the repository's Security tab. Alerts are sent only when something is found and never contain secret values. A scheduled `mode: hunt` job on your most sensitive repositories works as low-cost public-leak monitoring.

## Command reference

| Command | Purpose |
|---|---|
| `leak audit [--json] [path]` | Grade a repository's secret hygiene from A to F, with a fix for each gap |
| `leak audit-org [--no-scan] <org>` | Grade every repository in an organisation (or `--dir` a folder of repositories); HTML dashboard, markdown and JSON |
| `leak scan <path> [--sarif file]` | Scan every commit for secrets; values are always redacted |
| `leak snapshot owner/repo` | Preserve a leaked repository: mirror, metadata, forks, traffic and a checksum manifest |
| `leak forks owner/repo` | List every fork, including forks of forks, for a takedown request |
| `leak hunt [--since date] owner/repo` | Check GitHub, GitLab, web archives and code search for surviving copies |
| `leak commits <sha>…` | Find public repositories that contain the original commits |
| `leak report <hunt-dir> [--scan file]` | Build the leadership report from the results |
| `leak notify "message"` | Send an alert to Slack, Teams or Discord (URL from `LEAK_WEBHOOK_URL`) |
| `leak doctor` | Check that a machine has everything it needs, before an incident |

Every command has `--help`. Exit codes are the same everywhere: `0` clean, `1` findings, `2` usage error, `4` incomplete (a scanner or remote service failed, so the result must not be read as clean).

## Security of the toolkit

A tool that handles leak investigations has to be trustworthy itself. Each of these can be checked independently:

- Release archives and container images are signed with [Sigstore](https://www.sigstore.dev/) (since v2.2.0). [How to verify](SECURITY.md#verifying-a-release).
- Container images ship with an SBOM and SLSA build provenance.
- [OpenSSF Scorecard](https://scorecard.dev/viewer/?uri=github.com/aboutBilal/spillkit) runs on every push to `main`.
- GitHub Actions are pinned to commit SHAs and container images to digests; Dependabot keeps them current.
- Every push runs shellcheck, actionlint, 34 offline tests on Linux and macOS, and a full-history secret scan; CodeQL analyses every change to `main` and every pull request.
- No command prints or tests a secret value, and tests enforce this. `leak snapshot` keeps a copy of a leaked repository as evidence, so evidence folders are git-ignored and must be handled as sensitive. The repository itself contains no secrets, not even fake ones.
- Tokens and webhook URLs are passed to `curl` on standard input, never as command-line arguments, so they do not appear in process lists.
- A source that fails or is rate-limited is reported as "not checked", never as clean.

Report vulnerabilities privately; see [SECURITY.md](SECURITY.md).

## Comparison

This is not another secret scanner. It uses gitleaks and adds prevention, response and reporting around it, so it works alongside the tools you may already use.

| Capability | gitleaks | TruffleHog | GitGuardian | Spillkit |
|---|---|---|---|---|
| Scan full Git history | Yes | Yes | Yes | Yes (gitleaks) |
| Check whether a found secret is still live | No | Yes | Yes | No, by design |
| Block secrets at commit | Yes | Yes | Yes | Yes, plus blocked file types |
| Grade repositories and organisations | No | No | No | Yes |
| Incident runbooks per leak scenario | No | No | Partial | Yes |
| Search public sources for surviving copies | No | No | Continuous (commercial) | On demand |
| Leadership report from the evidence | No | No | Dashboards | Yes |
| Licence | MIT | AGPL-3.0 | Commercial | MIT |

## FAQ

<details>
<summary>Does it send code or secrets anywhere?</summary>

No. `scan` and `audit` run locally. `hunt`, `forks`, `commits` and `audit-org` send only repository names, account names and commit IDs to public services: GitHub, GitLab, the Internet Archive, Software Heritage, Sourcegraph, Codeberg and the public GitHub event dataset at play.clickhouse.com. Alerts contain counts and secret types, never values.
</details>

<details>
<summary>Why doesn't it check whether a leaked key still works?</summary>

Using a leaked credential is what an attacker does, and it can trigger alarms or breach a provider's terms. The response is the same either way: rotate it.
</details>

<details>
<summary>Does it work outside GitHub?</summary>

`scan`, `audit`, the hooks and the CI templates work with any Git repository on GitHub, GitLab, Azure DevOps or Bitbucket. `hunt` searches public GitHub, public GitLab and web and code archives.
</details>

<details>
<summary>Can my company use and modify it?</summary>

Yes. It is MIT-licensed. Adapt the runbooks to your organisation and ship the prevention kit in your templates.
</details>

<details>
<summary>What is in the repository?</summary>

| Path | Contents |
|---|---|
| `docs/` | Runbook, scenarios, rotation, investigation, where copies survive, prevention, secrets by design, practice drill |
| `prevention/` | Tested hooks, gitleaks configuration, CI templates, OIDC examples, Docker and `.env` patterns |
| `scripts/` | The commands behind `leak` |
| `templates/` | Incident checklist, timeline, messages, takedown request, post-incident review, executive report |
| `action.yml`, `Dockerfile`, `.pre-commit-hooks.yaml` | GitHub Action, container image, pre-commit hooks |
| `tests/` | Offline test suite (bats) |
</details>

## Contributing

Contributions based on real incidents are especially welcome: a missing step, another platform, a better command. Please read [CONTRIBUTING.md](CONTRIBUTING.md) first. Two rules are firm: no secrets in the repository, not even fake ones, and no details of real incidents or people. Planned work is in the [roadmap](ROADMAP.md).

```bash
make check    # shellcheck, tests and a secret scan: the same checks CI runs
```

## License

[MIT](LICENSE). See also the [changelog](CHANGELOG.md), [code of conduct](CODE_OF_CONDUCT.md) and [citation file](CITATION.cff).

<sub>The scripts read only public data and the repositories you point them at. This project is engineering guidance, not legal advice; breach-notification duties depend on what leaked and where you operate.</sub>
