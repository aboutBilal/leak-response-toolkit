# Takedown request: the facts to gather

GitHub removes infringing repositories (and their forks) on a valid DMCA notice. Submit it at **<https://github.com/contact/dmca>**; GitHub's form and its [guide to submitting a notice](https://docs.github.com/en/site-policy/content-removal-policies/guide-to-submitting-a-dmca-takedown-notice) are the authority. This page only collects what you will be asked for, so you are not hunting for it under pressure.

> [!NOTE]
> The notice must come from the **copyright owner** (normally the company) or someone authorised to act for it. Check with legal before sending.

---

## What you will need

| Item | Your answer |
|---|---|
| Copyright owner (company legal name) | |
| Your name, role, and authority to act | |
| Contact email and address | |
| **The original work**: what it is, where the authoritative copy lives (a private URL is fine; describe it if it cannot be shared) | |
| **The infringing repository URL** | |
| **Every fork URL** (`./scripts/list-forks.sh <owner>/<repo>`) | |
| Is the whole repository infringing, or only some files? | Whole repository / specific paths: |
| Have you contacted the repository owner? When, and what was the reply? | |
| What do you want GitHub to do? | Disable the repository and all listed forks |

## Statements GitHub's notice requires

The form asks you to confirm, in substance:

- you have a good-faith belief that the use is not authorised by the copyright owner, its agent or the law;
- the information in the notice is accurate, and under penalty of perjury you are authorised to act for the owner;
- your full legal name as an electronic signature.

## Before you send

- [ ] Evidence snapshot taken (`./scripts/snapshot-evidence.sh`)
- [ ] Owner asked to delete it themselves first (fastest), unless that is unsafe
- [ ] Legal has approved sending
- [ ] **Secrets already rotated** - a takedown removes the copy, not what was taken from it

## After

- GitHub usually acts within days and notifies the repo owner. Track the request ID in the incident timeline.
- Re-run `list-forks.sh` after removal to catch forks created in the meantime.
