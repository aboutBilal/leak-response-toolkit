# Security policy

## Supported versions

| Version | Supported |
|---|:-:|
| Latest 3.x release | Security fixes |
| Older releases | No, please upgrade |

## Reporting a vulnerability

**Please do not open a public issue.** Report privately through GitHub's private vulnerability reporting:

**[Report a vulnerability](https://github.com/aboutBilal/spillkit/security/advisories/new)** (Security tab → *Report a vulnerability*)

Include what you found, where (file and line, or command), how to reproduce it, and the impact you expect. If the report involves a real secret, **describe it; do not send the value**.

Examples of what counts as a vulnerability here:

- a script that prints, writes or sends a secret value anywhere (the toolkit must only ever show types and locations);
- a way to make a script run code or commands it should not (for example through crafted repository names, file names or API responses);
- a step in the runbook that would make an incident worse if followed;
- a weakness in the CI, release or container image supply chain.

## Coordinated disclosure

| Step | Target |
|---|---|
| Acknowledge your report | within **3 working days** |
| Initial assessment and severity | within **7 days** |
| Fix released for confirmed issues | within **30 days** (sooner for high severity) |
| Public advisory and credit (if you want it) | when the fix is released |

Please give us a reasonable time to release a fix before any public disclosure. We will keep you informed throughout and credit you in the advisory unless you prefer otherwise.

## This repository holds no secrets

Every command uses placeholders such as `<app-id>`, test secrets are generated at run time, and every push is scanned by gitleaks over the full history in CI. If you find something that looks like a real credential, report it as above so it can be checked and removed.

## Verifying a release

Release archives are signed with [Sigstore](https://www.sigstore.dev/) by this repository's release workflow, with no long-lived key. To verify one:

```bash
cosign verify-blob spillkit-vX.Y.Z.tar.gz \
  --bundle spillkit-vX.Y.Z.tar.gz.sigstore.json \
  --certificate-identity-regexp '^https://github.com/aboutBilal/spillkit/\.github/workflows/release\.yml@refs/tags/v' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

The install script is signed the same way: verify `install.sh` with `install.sh.sigstore.json` from the same release before running it, or run `bash install.sh --require-signature`, which refuses any archive whose signature does not verify.

Container images are signed the same way:

```bash
cosign verify ghcr.io/aboutbilal/spillkit:X.Y.Z \
  --certificate-identity-regexp '^https://github.com/aboutBilal/spillkit/\.github/workflows/release\.yml@refs/tags/v' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Using the toolkit safely

- `scan`, `audit` and `plan` run locally. `hunt`, `forks`, `commits` and `audit-org` send only repository names, account names and commit IDs to public services: GitHub, GitLab, the Internet Archive, Software Heritage, Sourcegraph, Codeberg and play.clickhouse.com.
- Tokens (`GITHUB_TOKEN`) and webhook URLs (`LEAK_WEBHOOK_URL`) are handed to `curl` and `git` through standard input or the environment, never as command-line arguments, so they do not appear in process lists. Alerts contain counts and types, never values.
- Output and reports are **redacted**: secret values are never printed or written to reports. `leak snapshot` does keep a full copy of the leaked repository, which is the evidence itself.
- `leak rotate` is the only command that changes anything, and only with `--apply STEP`. It uses the `aws`, `az` or `gcloud` CLI you are signed in to. A new secret travels from that CLI to your secret store through a pipe: it is held in memory for that step only, never printed, written to disk, logged or passed as an argument. `rotation-log.tsv` records times, steps and credential IDs, never values.
- Evidence folders (`evidence/`, `hunts/`) can contain leaked code. They are git-ignored here; keep them out of any repository and share them only with the people handling the incident.
- Releases include a source archive signed with Sigstore; container images ship with an SBOM and build provenance.
