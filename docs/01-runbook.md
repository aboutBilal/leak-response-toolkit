# 01 · Runbook: code or secrets exposed in a public repository

**Situation:** a repository that should be private, or secrets inside one, became publicly readable: pushed to a public repo, made public by mistake, or copied to someone else's account. It may contain secrets (keys, passwords, connection strings) and proprietary code.

This is the full response. For what changes in your specific case (your own repo, a provider alert, leaks outside Git), see [`06-scenarios.md`](06-scenarios.md).

**Goal, in order:** stop the damage → remove the copy → find out what happened → stop it happening again.

> [!WARNING]
> **Assume every secret in the repo is already stolen**, no matter how short the exposure. Automated scanners pick up keys from public pushes within minutes. An exposure of minutes or hours is not "probably fine".

---

## Roles (even a team of two)

| Role | Owns |
|---|---|
| **Incident lead** | Decisions, the timeline, who does what |
| **Rotator** | Revoking and replacing secrets |
| **Investigator** | Logs, forks, scope of what leaked |
| **Communicator** | Manager, security, legal, affected customers or data owners |

One person can hold several roles. Write down who holds which.

---

## First hour

### 1. Snapshot evidence (5 minutes)

Do this **before** the repo is deleted: once it is gone, you lose the exact contents, the commit times and GitHub's traffic numbers.

```bash
./scripts/snapshot-evidence.sh <owner>/<repo>
```

It saves a full mirror, repo metadata (`created_at`, `pushed_at`, fork count), the fork list and, when your token belongs to the owner, **clones and unique visitors for the last 14 days**. Take screenshots too.

Ask the owner for screenshots of **Insights → Traffic** and their **account security log** now: traffic is gone once the repository is deleted, and the security log gives the exact exposure window ([what disappears](05-where-copies-survive.md#evidence-that-disappears)).

### 2. Find every secret, in the full history

```bash
./scripts/scan-secrets.sh evidence/<snapshot>/repo.git
```

- A secret "removed in a later commit" is **still leaked**: every old commit was public.
- Scanners miss things. Also search by hand for `.env`, `*.pem`, `*.pfx`, `*.tfvars`, `appsettings*.json`, `docker-compose*.yml`, kubeconfigs and connection strings.

### 3. Rotate and revoke, most powerful first

| Priority | Secret type | Why first |
|:-:|---|---|
| 1 | Cloud credentials: service principal secrets, access keys, storage keys | Can create resources, read data, run up costs |
| 2 | Database passwords and connection strings | Direct data access |
| 3 | SSH keys, deploy keys, certificates (`.pem`, `.pfx`) | Server and pipeline access |
| 4 | Third-party API keys (email, payments, AI, maps) | Abuse and billing |
| 5 | App signing secrets (JWT, cookie, webhook) | Forged sessions and requests |

**Revoke the old secret**; creating a new one is not enough. Commands per type: [`02-rotate-secrets.md`](02-rotate-secrets.md).

With a scan report, let Spillkit put them in order and walk through the cloud keys:

```bash
./leak plan secrets-report.json         # checklist, most dangerous first: rotation-plan.md for the issue, .html to print
./leak rotate aws-key --user <user> --key-id <AKIA...>     # a dry run: every step with its exact command
./leak rotate aws-key --user <user> --key-id <AKIA...> --apply replace --store aws-sm:<secret-id>
```

`leak rotate` also handles Azure app registration secrets, Google Cloud service account keys, Azure storage keys and GitLab access tokens. Each applied step is logged with its UTC time in `rotation-log.tsv`, ready for the timeline.

Record the **exact time** each secret was revoked. The investigation window ends there.

### 4. Take it down

1. **Ask the owner to delete it.** This is the fastest route: *Settings → Danger zone → Delete this repository*.
2. **If they cannot or will not:** the company owns the copyright, so file a **GitHub DMCA takedown** at <https://github.com/contact/dmca>. List the repo **and every fork** ([`list-forks.sh`](../scripts/list-forks.sh)). The facts you need are in [`takedown-request.md`](../templates/takedown-request.md).
3. **Forks survive** when a public repo is deleted; each needs its own takedown.
4. Making the repo private is a stop-gap, not a fix: forks and clones already exist.
5. **Hunt for other copies** (archives, re-uploads, mirrors) and record the result:
   ```bash
   ./scripts/hunt-copies.sh --since <first-push-date> <owner>/<repo>
   ./scripts/find-commit-copies.sh --exclude <owner>/<repo> <commit-sha> <commit-sha>
   ```
   Every place a copy can survive is in [`05-where-copies-survive.md`](05-where-copies-survive.md).

---

## Same day

### 5. Was anything used?

Search from **the first public push** until **the moment each secret was revoked**, not until the repo was deleted. Queries for Azure, AWS and databases: [`03-investigate.md`](03-investigate.md).

Signs of abuse: logins from unfamiliar IPs or countries, new compute (crypto-mining), new users or role assignments, large data reads, cost spikes.

**If you find misuse, this is now a breach, not a leak:** widen the scope and bring in security and legal.

### 6. What else was exposed?

| Exposed | Risk |
|---|---|
| Hostnames, IPs, architecture, internal URLs | Easier targeted attacks |
| Business logic, pricing, algorithms | Competitive and contractual |
| **Personal or customer data** (seed files, dumps, test fixtures) | Possible legal notification duty (GDPR: 72 hours) |
| Third-party or client code | Contractual notification to that party |

### 7. Tell the right people

- Manager, security and legal.
- **The owner of the code or data**, if it is not yours (a customer, partner or employer). Contracts usually require prompt notice.
- Keep a written timeline from the start: [`incident-timeline.md`](../templates/incident-timeline.md).
- Ready-to-adapt messages for each audience: [`notification-messages.md`](../templates/notification-messages.md).
- For leadership, use [`incident-report.html`](../templates/incident-report.html): one page of summary, then the evidence.

### 8. The person involved

- Review or suspend their access to repositories, cloud and CI while the facts are gathered.
- Separate *what happened* (often a well-meaning backup or portfolio upload) from *what to do about it*; HR and legal own the second part.
- Fix the process too: if one person could do this, someone else can.

---

## Afterwards

- **Do not rely on rewriting history** (`git filter-repo`, BFG) to "un-leak" anything. It is useful for cleaning your *own* repo later; it does nothing about copies already taken.
- Run a short blameless review with [`post-incident-review.md`](../templates/post-incident-review.md): how did the code leave, why was a secret in the repo, what would have caught it sooner?
- Practise before the next one: [`07-practice-drill.md`](07-practice-drill.md).
- Pick at least two changes from [`08-secrets-by-design.md`](08-secrets-by-design.md) (the [prevention kit](../prevention/README.md) has tested files) and give each an owner and a date.

## Done when

- [ ] Every secret found is revoked, with the time recorded
- [ ] Repo and all forks are gone (or a takedown is filed and tracked)
- [ ] Copy hunt run and repeated after 7 days, reports kept
- [ ] Logs checked for the full window, findings written down
- [ ] Data exposure assessed and legal or affected parties notified where required
- [ ] Timeline complete and prevention actions assigned
