<p align="center">
  <img src="assets/banner.svg" alt="Leak Response Toolkit: rotate, hunt copies, investigate, prevent" width="100%">
</p>

<p align="center">
  <a href="https://github.com/aboutBilal/leak-response-toolkit/actions/workflows/secret-scan.yml"><img src="https://github.com/aboutBilal/leak-response-toolkit/actions/workflows/secret-scan.yml/badge.svg" alt="checks"></a>
  <a href="CHANGELOG.md"><img src="https://img.shields.io/badge/version-1.1.0-informational.svg" alt="version 1.1.0"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="license MIT"></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg" alt="PRs welcome"></a>
</p>

<h3 align="center">Code or secrets went public? Here is what to do in the first hour,<br>how to find where copies survive, and how to stop it happening again.</h3>

<p align="center">
  <a href="#-start-here-what-happened"><b>🚨 In an incident? Start here</b></a> ·
  <a href="CHEATSHEET.md">📄 One-page cheat sheet</a> ·
  <a href="docs/01-runbook.md">📘 Full runbook</a> ·
  <a href="docs/07-practice-drill.md">🎯 Practise first</a>
</p>

---

## ⚡ Why minutes matter

| ⏱️ **5 minutes** | 📈 **28.6 million** | 🧟 **64%** | 🛡️ **5 of 9** |
|:-:|:-:|:-:|:-:|
| Time attackers needed to find and use AWS keys exposed on public GitHub ([Unit 42, 2023](https://unit42.paloaltonetworks.com/malicious-operations-of-exposed-iam-keys-cryptojacking/)) | New hard-coded secrets pushed to public GitHub in 2025, up 34% ([GitGuardian, 2026](https://www.gitguardian.com/state-of-secrets-sprawl-report-2026)) | Secrets leaked in 2022 that were still exploitable four years later ([GitGuardian, 2026](https://www.gitguardian.com/state-of-secrets-sprawl-report-2026)) | Secret types GitHub push protection blocked in our test, while gitleaks caught 9 of 9 ([measured](docs/04-prevention.md#-what-each-layer-catches-a-measured-test)) |

> [!IMPORTANT]
> **Rotate first, delete second.** Deleting a repository does not un-leak anything; a revoked key does. Everything else in this kit limits the spread and tells you what happened.

---

## 🧭 Start here: what happened?

| Situation | Go to |
|---|---|
| 🔑 I committed a secret to a public repo | [Scenario A](docs/06-scenarios.md#a--a-secret-committed-to-your-own-public-repository) |
| 🔓 A private repo was made public by mistake | [Scenario B](docs/06-scenarios.md#b--a-private-repository-was-made-public-by-mistake) |
| 📤 Our code was pushed to someone else's public account | [Full runbook](docs/01-runbook.md) |
| 📧 A provider emailed: "your key was exposed" | [Scenario D](docs/06-scenarios.md#d--a-provider-alert-your-key-was-exposed) |
| 📦 It leaked outside Git: gist, paste, CI logs, image, package, chat | [Scenario E](docs/06-scenarios.md#e--leaks-outside-git) |
| 🙋 Someone reported it to us | [Scenario F](docs/06-scenarios.md#f--someone-reported-it-to-you) |

Whatever the case, the first move is the same: **rotate the exposed secrets** ([how, per secret type](docs/02-rotate-secrets.md)).

---

## ⏱️ The first hour on one page

```mermaid
flowchart LR
    A["📸 1 · Snapshot<br/>evidence"] --> B["🔎 2 · Find every<br/>secret in history"]
    B --> C["🔁 3 · Rotate +<br/>revoke all"]
    C --> D["🗑️ 4 · Take repo<br/>and forks down"]
    D --> E["🕵️ 5 · Check logs<br/>for misuse"]
    E --> F["📣 6 · Notify +<br/>document"]
    style C fill:#b42318,color:#fff
```

| Step | Do | Tool here |
|:-:|---|---|
| 1 | Save a copy of the leaked repo, its metadata and forks **before** anything is deleted | `./leak snapshot` |
| 2 | Scan the **full history**, not only the latest commit | `./leak scan` |
| 3 | Rotate and **revoke** every secret found, most powerful first | [`docs/02-rotate-secrets.md`](docs/02-rotate-secrets.md) |
| 4 | Delete the repo or file a takedown (every fork too), then **hunt for other copies** | `./leak forks`, `./leak hunt`, `./leak commits`, [takedown request](templates/takedown-request.md) |
| 5 | Search logs from the **first push** to the **moment each key was rotated** | [`docs/03-investigate.md`](docs/03-investigate.md) |
| 6 | Tell the right people, keep a timeline, report to leadership | [messages](templates/notification-messages.md), [timeline](templates/incident-timeline.md), [executive report](templates/executive-report.html) |

The full walkthrough is in **[`docs/01-runbook.md`](docs/01-runbook.md)**. To track the response as a team, paste [`templates/incident-issue.md`](templates/incident-issue.md) into a private issue.

---

## 🚀 Quick start

```bash
git clone https://github.com/aboutBilal/leak-response-toolkit.git
cd leak-response-toolkit
./leak help
```

| Command | What it does |
|---|---|
| `./leak snapshot someuser/leaked-repo` | Saves a full mirror, metadata, forks and (with the owner's token) traffic, plus a checksum manifest |
| `./leak scan <path>` | Scans **every commit** for secrets; values are always redacted |
| `./leak forks someuser/leaked-repo` | Lists every fork, including forks of forks, for the takedown |
| `./leak hunt --since 2026-01-31 someuser/leaked-repo` | Checks 15+ public sources for surviving copies and writes a markdown report |
| `./leak commits --exclude someuser/leaked-repo <sha> <sha>` | Finds renamed re-uploads that carry the original commits |

<p align="center"><img src="assets/demo-scan.svg" alt="Real output of ./leak scan: two secrets found in a commit that was later deleted, values redacted" width="88%"></p>

**Needs:** `git`, `curl`, `jq`, and either [`gitleaks`](https://github.com/gitleaks/gitleaks) or Docker (the scan script falls back to the official gitleaks image).
Optional: set `GITHUB_TOKEN` for higher API limits; if the token belongs to the repo owner, the snapshot also saves **clone and visitor traffic** for the last 14 days.

---

## 🗂️ What is in here

```
leak-response-toolkit/
├── docs/
│   ├── 01-runbook.md                the full response, step by step
│   ├── 02-rotate-secrets.md         rotation per secret type (Azure, AWS, Google Cloud, GitHub, DBs, SSH, app secrets)
│   ├── 03-investigate.md            log queries: was the key used?
│   ├── 04-prevention.md             layers that stop leaks, with a measured test of what each catches
│   ├── 05-where-copies-survive.md   archives, forks, re-uploads, evidence that disappears, removal requests
│   ├── 06-scenarios.md              what changes per leak type: own repo, made public, copied, alerts, non-Git leaks
│   └── 07-practice-drill.md         a 45-minute team exercise, no real secrets
├── scripts/                         every script has --help
│   ├── snapshot-evidence.sh         mirror + metadata + forks + traffic, with a checksum manifest
│   ├── scan-secrets.sh              full-history scan, redacted summary
│   ├── list-forks.sh                every fork, for the takedown request
│   ├── hunt-copies.sh               15+ public sources checked, dated markdown report
│   └── find-commit-copies.sh        public repos containing the original commit IDs
├── templates/
│   ├── incident-issue.md            team checklist to paste into a private issue
│   ├── incident-timeline.md         fill-in timeline and decision log
│   ├── notification-messages.md     leadership, affected customers, the person involved, reporters
│   ├── takedown-request.md          the facts a GitHub DMCA notice needs
│   ├── post-incident-review.md      blameless review with actions and owners
│   └── executive-report.html        leadership report, print-ready A4
├── leak                             one command for every script: ./leak help
├── CHEATSHEET.md                    the first 15 minutes on one page
├── tests/scripts.bats               offline tests; test secrets generated at runtime
├── Makefile                         make check = shellcheck + tests + secret scan
└── .github/                         CI (secrets, shellcheck, tests, links), Dependabot, issue and PR templates
```

---

## 🛡️ Prevention in two commands

This repository protects itself the same way it recommends:

```bash
pipx install pre-commit     # or: uv tool install pre-commit
pre-commit install          # gitleaks now runs before every commit
```

And CI runs the same scan on every push ([`secret-scan.yml`](.github/workflows/secret-scan.yml)). The bigger wins, such as removing long-lived keys entirely, are in [`docs/04-prevention.md`](docs/04-prevention.md).

> [!TIP]
> **Measured, not assumed:** in a test with one fake credential of each of 9 types, GitHub push protection blocked 5 and gitleaks caught all 9. Details in [`docs/04-prevention.md`](docs/04-prevention.md#-what-each-layer-catches-a-measured-test).

---

## ⚖️ Scope

- These scripts **only read** public data and the repository you point them at. They never use, test or print a discovered secret.
- Commands in the docs use placeholders like `<app-id>`; nothing here is a real credential.
- This is an engineering checklist, not legal advice. Breach-notification duties (for example GDPR's 72 hours) depend on what data leaked and where you operate.

## 🤝 Contributing

Improvements from real experience are welcome: a missing step, another platform, a better command. Read [CONTRIBUTING.md](CONTRIBUTING.md) first; the two hard rules are **no secrets, not even fake ones**, and **no real incidents or names**. Security problems: [SECURITY.md](SECURITY.md).

```bash
make check   # shellcheck + offline tests + secret scan: the same as CI
```

## 📄 License

[MIT](LICENSE) · [Changelog](CHANGELOG.md) · [Code of conduct](CODE_OF_CONDUCT.md)
