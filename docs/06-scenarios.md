# 06 · Scenarios: what changes for each kind of leak

The core response is always the same: **rotate secrets first, then remove copies, then investigate and prevent.** What differs is how much you control, where copies can be, and how you clean up. Find your situation below, then follow the linked steps.

| | Scenario | You control the copy? | Jump to |
|:-:|---|:-:|---|
| A | You (or your team) committed a secret to a public repository | Yes | [A](#a--a-secret-committed-to-your-own-public-repository) |
| B | A private repository was made public by mistake | Yes | [B](#b--a-private-repository-was-made-public-by-mistake) |
| C | Code was copied to **someone else's** public account | No | [C](#c--code-copied-to-someone-elses-public-account) |
| D | A provider emailed you: "your key was exposed" | Partly | [D](#d--a-provider-alert-your-key-was-exposed) |
| E | The secret leaked **outside Git**: gist, paste site, CI logs, container image, package, chat | Varies | [E](#e--leaks-outside-git) |
| F | A stranger or researcher reported it to you | Varies | [F](#f--someone-reported-it-to-you) |

---

## A · A secret committed to your own public repository

The most common leak. You own the repository, so you can collect evidence and clean up yourself.

1. **Rotate the secret now** ([02](02-rotate-secrets.md)). Removing the commit does not help: it was public the moment it was pushed.
2. Scan the whole history for anything else: `./scripts/scan-secrets.sh .`
3. Check for misuse from the commit time to the rotation time ([03](03-investigate.md)).
4. **Then** clean the history, so the dead secret stops triggering alerts and copying:
   ```bash
   # Remove a whole file from every commit
   git filter-repo --invert-paths --path <path/to/file>
   # Or replace the value wherever it appears (one value per line in the file)
   git filter-repo --replace-text <file-listing-values-to-remove>
   git push --force --all && git push --force --tags
   ```
   Everyone with a clone must re-clone. Forks keep the old history; on GitHub, contact Support to remove cached views and references from pull requests.
5. Add the prevention layers so it does not happen again ([04](04-prevention.md)).

## B · A private repository was made public by mistake

1. **Make it private again immediately.** Unlike deletion, this keeps your evidence.
2. As the owner you can see **Insights → Traffic**: screenshot clones, visitors and referrers now (14 days only).
3. The **security log** shows exactly when visibility changed (`repo.access`): that is your exposure window.
4. Treat every secret in the full history as leaked: scan and rotate ([02](02-rotate-secrets.md)).
5. Check forks created while it was public: forks of a public repository can stay public ([05](05-where-copies-survive.md)).
6. Run `hunt-copies.sh` for archives and re-uploads.

## C · Code copied to someone else's public account

For example an employee's backup or portfolio, a contractor, or a former team member. You do not control the copy, so speed and evidence matter.

Follow the full [runbook](01-runbook.md): snapshot evidence, scan, rotate, ask the account owner to delete (fastest), otherwise a DMCA notice for the repository **and every fork**, then hunt for copies and check logs. Keep the conversation with the person factual and separate from the technical response.

## D · A provider alert: "your key was exposed"

Providers (cloud, payments, chat, source hosting) receive keys found in public code and email the account owner, sometimes after disabling the key.

1. Treat the email as **proof** the key was public. Save it: its timestamp anchors the timeline.
2. Find **where** it leaked: the email usually names the repository or URL. If not, search your organisation's public repositories and scan them.
3. Rotate that key **and** everything stored next to it: a leaked `.env` rarely holds just one secret.
4. If the key was disabled automatically, check what broke and replace it properly (ideally with a short-lived credential).
5. Continue with the scenario that matches where it leaked (A, B, C or E).

## E · Leaks outside Git

| Where it leaked | Remove it | Extra notes |
|---|---|---|
| **Public or "secret" gist** | Delete the gist | A secret gist is unlisted, not private: anyone with the URL can read it |
| **Paste sites** | Delete or report the paste | Scraped heavily and quickly; assume it was copied |
| **CI logs** (public projects) | Delete the run's logs | Registered secrets are masked, but values derived from them (encoded, split, printed by tools) are not |
| **Container image** on a public registry | Delete the tag and rebuild without the secret | Anyone who pulled has every layer; a secret removed in a later layer is still in the earlier one |
| **Published package** (npm, PyPI, NuGet, …) | Unpublish or yank where the registry allows it, then publish a fixed version | Registries limit removal (time windows, dependants), and mirrors keep copies: rotation is what matters |
| **Chat, tickets, wikis, screenshots** | Delete the message or attachment | Exposure depends on who can read the space; rotate if it was wide or external |
| **Front-end bundle or mobile app** | Ship a version without it | Anything shipped to clients is public by design: only keys meant to be public belong there ([02](02-rotate-secrets.md#-keys-that-are-meant-to-be-public)) |

Then: rotate ([02](02-rotate-secrets.md)), investigate ([03](03-investigate.md)), prevent ([04](04-prevention.md)).

## F · Someone reported it to you

1. Thank them and ask for the exact URL, what they saw and when, and whether they kept a copy (ask them to delete it).
2. Do not test the secret yourself to "confirm" it: rotate it.
3. Continue with the matching scenario above.
4. Tell them when it is fixed. A good experience makes people report the next one too; consider a `SECURITY.md` and a reporting address.

---

## Not on GitHub?

The steps are the same on GitLab, Bitbucket, Azure DevOps and others; the buttons differ.

| Need | Where to look |
|---|---|
| Secret detection before or after push | Each platform's secret detection / push protection feature (availability depends on plan) |
| Who changed visibility, when | The platform's audit log or project activity |
| Takedown of copies on that platform | Its abuse or copyright (DMCA) process |
| Forks and mirrors | The project's forks list, plus `hunt-copies.sh` for GitHub-side copies and archives |
