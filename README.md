<p align="center">
  <img src="assets/banner.svg" alt="Leak Response Toolkit: prevent secret leaks, respond in minutes" width="100%">
</p>

<p align="center">
  <a href="https://github.com/aboutBilal/leak-response-toolkit/actions/workflows/secret-scan.yml"><img src="https://github.com/aboutBilal/leak-response-toolkit/actions/workflows/secret-scan.yml/badge.svg" alt="checks"></a>
  <a href="https://scorecard.dev/viewer/?uri=github.com/aboutBilal/leak-response-toolkit"><img src="https://img.shields.io/ossf-scorecard/github.com/aboutBilal/leak-response-toolkit?label=openssf%20scorecard&style=flat" alt="OpenSSF Scorecard"></a>
  <a href="https://github.com/aboutBilal/leak-response-toolkit/releases/latest"><img src="https://img.shields.io/github/v/release/aboutBilal/leak-response-toolkit?label=release&color=ff7a59" alt="latest release"></a>
  <a href="SECURITY.md#verifying-a-release"><img src="https://img.shields.io/badge/releases-sigstore%20signed-6f42c1.svg" alt="Sigstore-signed releases"></a>
  <a href="#-install"><img src="https://img.shields.io/badge/docker-ghcr.io-2496ED.svg?logo=docker&logoColor=white" alt="Docker image"></a>
  <a href="#-use-it-in-your-ci"><img src="https://img.shields.io/badge/GitHub%20Action-ready-2088FF.svg?logo=githubactions&logoColor=white" alt="GitHub Action"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="license MIT"></a>
</p>

<h3 align="center">Stop secrets from leaking. When they do, respond in minutes.</h3>

<p align="center">
  An architecture, a tested prevention kit, incident runbooks and one CLI (<code>leak</code>)<br>
  to <b>audit</b> a repository, <b>scan</b> its history, <b>hunt</b> for surviving copies and <b>report</b> to leadership.
</p>

<p align="center">
  <a href="#-in-an-incident-start-here"><b>🚨 In an incident? Start here</b></a>
  &nbsp;·&nbsp; <a href="#-prevent-it"><b>🛡️ Prevent it</b></a>
  &nbsp;·&nbsp; <a href="#-install"><b>📦 Install</b></a>
  &nbsp;·&nbsp; <a href="CHEATSHEET.md">📄 Cheat sheet</a>
</p>

<p align="center">
  <img src="assets/how-it-works.svg" alt="How it works: prevent with leak audit, detect with leak scan, respond with leak hunt, report and learn with leak report" width="100%">
</p>

## ⚡ Why minutes matter

| ⏱️ **5 minutes** | 📈 **28.6 million** | 🧟 **64%** | 🛡️ **5 of 9** |
|:-:|:-:|:-:|:-:|
| Time attackers needed to find and use AWS keys exposed on public GitHub ([Unit 42, 2023](https://unit42.paloaltonetworks.com/malicious-operations-of-exposed-iam-keys-cryptojacking/)) | New hard-coded secrets pushed to public GitHub in 2025, up 34% ([GitGuardian, 2026](https://www.gitguardian.com/state-of-secrets-sprawl-report-2026)) | Secrets leaked in 2022 that were still exploitable four years later ([GitGuardian, 2026](https://www.gitguardian.com/state-of-secrets-sprawl-report-2026)) | Secret types GitHub push protection blocked in our test, while gitleaks caught 9 of 9 ([measured](docs/04-prevention.md#-what-each-layer-catches-a-measured-test)) |

> [!IMPORTANT]
> **Rotate first, delete second.** Deleting a repository does not un-leak anything; a revoked key does. Everything else limits the spread and tells you what happened.

## 📦 Install

| | Command | Best for |
|---|---|---|
| 🐳 **Docker** | `docker run --rm -v "$PWD:/repo" ghcr.io/aboutbilal/leak-response-toolkit audit /repo` | Zero installs. Everything, gitleaks included, in one signed image (amd64 + arm64) |
| 💻 **Clone** | `git clone https://github.com/aboutBilal/leak-response-toolkit.git && cd leak-response-toolkit && make install` | Your laptop: puts `leak` on your PATH |
| 🤖 **GitHub Action** | `uses: aboutBilal/leak-response-toolkit@v2` ([example](#-use-it-in-your-ci)) | Every pull request, in every repository |

Then run **`leak doctor`** once, *before* you need it.

## 🎬 See it in action

**`leak audit`**: grade any repository, with a fix for every gap. Secret values are never printed.

<p align="center"><img src="assets/demo-audit.svg" alt="Real output of leak audit on a repository with a tracked .env, no hooks and a secret in a Dockerfile: grade F with a fix for every finding, secret values redacted" width="92%"></p>

<details>
<summary><b><code>leak scan</code></b>: every commit, every branch, values always redacted (click to see the output)</summary>
<br>
<p align="center"><img src="assets/demo-scan.svg" alt="Real output of leak scan: two secrets found in a commit that was later deleted, values redacted" width="92%"></p>
</details>

**`leak report`**: from raw evidence to a leadership-ready report.

<p align="center">
  <img src="assets/report-preview.png" alt="leak report turns the evidence into a print-ready leadership report: executive summary, risk cards, key facts, every check and every secret type, never secret values" width="100%">
</p>

<sub>All images are real output of the tool on demo repositories, rendered with <a href="tools/render-terminal-svg.py"><code>tools/render-terminal-svg.py</code></a>. Test secrets were random and never stored.</sub>

## 🚨 In an incident? Start here

| What happened | Go to |
|---|---|
| 🔑 I committed a secret to a public repo | [Scenario A](docs/06-scenarios.md#a--a-secret-committed-to-your-own-public-repository) |
| 🔓 A private repo was made public by mistake | [Scenario B](docs/06-scenarios.md#b--a-private-repository-was-made-public-by-mistake) |
| 📤 Our code was pushed to someone else's public account | [Full runbook](docs/01-runbook.md) |
| 📧 A provider emailed: "your key was exposed" | [Scenario D](docs/06-scenarios.md#d--a-provider-alert-your-key-was-exposed) |
| 📦 It leaked outside Git: gist, paste, CI logs, image, package, chat | [Scenario E](docs/06-scenarios.md#e--leaks-outside-git) |
| 🙋 Someone reported it to us | [Scenario F](docs/06-scenarios.md#f--someone-reported-it-to-you) |

**The first hour:**

| | Do | With |
|:-:|---|---|
| 1 | Save evidence **before** anything is deleted | `leak snapshot owner/repo` |
| 2 | Find every secret in the **full history** | `leak scan <path>` |
| 3 | **Rotate and revoke**, most powerful first | [Rotation guide](docs/02-rotate-secrets.md) (25+ secret types) |
| 4 | Remove copies, then hunt for the rest | `leak forks` · `leak hunt` · `leak commits` · [takedown](templates/takedown-request.md) |
| 5 | Check logs from first push to rotation | [Investigation guide](docs/03-investigate.md) |
| 6 | Tell the right people; report to leadership | [Messages](templates/notification-messages.md) · `leak report` · [team checklist](templates/incident-issue.md) |

Full walkthrough: **[the runbook](docs/01-runbook.md)** · Practise first: **[45-minute drill](docs/07-practice-drill.md)**

## 🔐 Prevent it

Most leaks are preventable with layers that each assume the previous one failed: **commit** (hooks) → **push** (push protection) → **CI** (full-history scan) → **build** (no secrets in images) → **deploy** (OIDC, no stored keys) → **run** (vault, identity, alerts).

```bash
leak audit ~/code/my-service                                   # grade A–F, with a fix for every gap
cp prevention/pre-commit-config.yaml ~/code/my-service/.pre-commit-config.yaml
cd ~/code/my-service && pre-commit install                     # .env, keys and secrets now blocked at commit
```

| For | Read |
|---|---|
| 🏛️ **Architects and platform leads** | [**Secrets by design**](docs/08-secrets-by-design.md): principles, reference architecture, 8-layer control matrix, maturity levels 0–4, 90-day rollout, metrics, design-review checklist |
| 🔧 **Engineers** | [**Prevention kit**](prevention/README.md): tested hooks, CI templates for GitHub, GitLab, Azure Pipelines and Bitbucket, keyless OIDC to AWS, Azure and Google Cloud, Docker and `.env` patterns |

> [!TIP]
> **This repository follows its own advice.** It uses the kit's hooks and ignore rules, scans its full history on every push, and `leak audit .` gives it **Grade A**.

## 🤖 Use it in your CI

```yaml
# .github/workflows/secrets.yml
on: [push, pull_request]
permissions:
  contents: read
jobs:
  secrets:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with: { fetch-depth: 0, persist-credentials: false }
      - uses: aboutBilal/leak-response-toolkit@v2   # pin to a commit SHA in production
        with:
          mode: scan        # or: audit (grade A–F), hunt (public copies of `repos`)
```

Results land in the job summary, values always redacted. A weekly `mode: hunt` job on your critical repositories doubles as free public-leak monitoring.

## 🧰 Commands

| Command | What it does |
|---|---|
| `leak audit [path]` | Grades a repository's secret hygiene **A–F**, with a fix for every gap |
| `leak scan <path>` | Scans **every commit** for secrets; values are always redacted |
| `leak snapshot owner/repo` | Saves a mirror, metadata, forks and (with the owner's token) traffic, plus a checksum manifest |
| `leak forks owner/repo` | Lists every fork, including forks of forks, for the takedown |
| `leak hunt [--since DATE] owner/repo` | Checks **15+ public sources** for surviving copies; writes a dated report |
| `leak commits [--exclude owner/repo] <sha>…` | Finds renamed re-uploads carrying the original commits |
| `leak report <hunt-dir> [--scan r.json]` | Builds the **print-ready leadership report** (types only, never values) |
| `leak doctor` | Checks a machine is ready: tools, scanner, token, API budget |

## 🔏 Built to be trusted

A security tool has to earn trust. Every claim below is verifiable:

| | |
|---|---|
| ✍️ **Signed releases** | Since v2.2.0, every release archive and container image is signed with [Sigstore](https://www.sigstore.dev/) (keyless). [Verify it yourself](SECURITY.md#verifying-a-release) |
| 📦 **SBOM and provenance** | Container images ship with a software bill of materials and SLSA build provenance |
| 📊 **OpenSSF Scorecard** | Independent security assessment on every push: [see the report](https://scorecard.dev/viewer/?uri=github.com/aboutBilal/leak-response-toolkit) |
| 📌 **Everything pinned** | GitHub Actions by commit SHA, container images by digest, updated by Dependabot |
| 🔍 **Analysed and tested** | CodeQL, shellcheck, actionlint, 17 offline tests and a full-history secret scan on every push |
| 🙈 **Never touches a secret** | No command prints, stores or tests a secret value; tests enforce it |
| 🧾 **No secrets, ever** | Not even fake ones: test values are generated at run time and thrown away |

## 🆚 How it fits with other tools

This kit is **not another secret scanner**. It uses [gitleaks](https://github.com/gitleaks/gitleaks) for detection and adds everything **around** detection.

| | gitleaks | TruffleHog | GitGuardian | **This toolkit** |
|---|:-:|:-:|:-:|:-:|
| Find secrets in the full git history | ✅ | ✅ | ✅ | ✅ via gitleaks |
| Check whether a found secret is still live | — | ✅ | ✅ | ❌ **by design**: never touches a leaked key |
| Block secrets and secret files at commit | ✅ | ✅ | ✅ | ✅ tested configs, plus blocked file types |
| Grade a repository's hygiene A–F | — | — | — | ✅ `leak audit` |
| Incident runbook for every leak scenario | — | — | partial | ✅ |
| Hunt for surviving public copies | — | — | continuous (commercial) | ✅ point-in-time, free |
| Leadership report from the evidence | — | — | dashboards | ✅ `leak report` |
| Architecture, maturity model, rollout plan | — | — | — | ✅ |
| Licence | MIT | AGPL-3.0 | Commercial | **MIT** |

## ❓ FAQ

<details>
<summary><b>Does it send my code or secrets anywhere?</b></summary>

No. `scan` and `audit` run locally. `hunt`, `forks` and `commits` send only repository names and commit IDs to public APIs (GitHub, the Internet Archive, Software Heritage, Sourcegraph, GitLab, Codeberg).
</details>

<details>
<summary><b>Will it tell me if a leaked key still works?</b></summary>

No, on purpose. Testing a leaked credential is what attackers do, and it can trigger alarms or break terms of service. The answer is always the same anyway: rotate it.
</details>

<details>
<summary><b>Does it only work with GitHub?</b></summary>

`scan`, `audit`, the hooks and the CI templates work with any Git repository on GitHub, GitLab, Azure DevOps or Bitbucket. `hunt`, `forks` and `commits` look for copies on public GitHub and in public archives.
</details>

<details>
<summary><b>Can my company use it, change it, or build on it?</b></summary>

Yes. It is MIT-licensed: use it commercially, adapt the runbooks to your organisation, and ship the prevention kit in your templates.
</details>

<details>
<summary><b>How do I know the prevention configs actually work?</b></summary>

Each one was tested before it was added; the results are in [`prevention/README.md`](prevention/README.md#-tested-behaviour). The scripts have 17 offline tests that run on every push.
</details>

<details>
<summary><b>What is in the repository?</b></summary>

```
docs/          runbook · rotation (25+ types) · investigation · prevention · where copies survive
               scenarios · practice drill · secrets by design (architecture)
prevention/    tested, copy-ready: hooks, gitleaks config, CI for 4 platforms, OIDC, Docker, .env
scripts/       snapshot · scan · forks · hunt · commits · report · audit · doctor (all with --help)
templates/     incident checklist · timeline · messages · takedown · post-incident review · executive report
leak           one command for every script        action.yml   the GitHub Action
Dockerfile     the toolkit as one signed image     tests/       17 offline tests
```
</details>

## 🤝 Contributing

Improvements from real experience are welcome: a missing step, another platform, a better command. Read [CONTRIBUTING.md](CONTRIBUTING.md); the two hard rules are **no secrets, not even fake ones**, and **no real incidents or names**. See the [roadmap](ROADMAP.md) for what is planned, and [SECURITY.md](SECURITY.md) to report a problem privately.

```bash
make check   # shellcheck + offline tests + secret scan: the same as CI
```

<sub>⚖️ The scripts only read public data and the repository you point them at. This is an engineering guide, not legal advice: breach-notification duties depend on what leaked and where you operate.</sub>

<p align="center">
  <img src="assets/logo.svg" alt="" width="40"><br>
  <sub><a href="LICENSE">MIT</a> · <a href="CHANGELOG.md">Changelog</a> · <a href="CODE_OF_CONDUCT.md">Code of conduct</a> · <a href="CITATION.cff">Cite</a></sub>
</p>
