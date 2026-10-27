# Security policy

## Supported versions

| Version | Supported |
|---|:-:|
| 3.x (latest release) | Security fixes |
| 2.x | Critical fixes until 2027-01-31 |
| 1.x | No, please upgrade |

## Reporting a vulnerability

**Please do not open a public issue.** Report privately through GitHub's private vulnerability reporting:

**[Report a vulnerability](https://github.com/aboutBilal/leak-response-toolkit/security/advisories/new)** (Security tab → *Report a vulnerability*)

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
cosign verify-blob leak-response-toolkit-vX.Y.Z.tar.gz \
  --bundle leak-response-toolkit-vX.Y.Z.tar.gz.sigstore.json \
  --certificate-identity-regexp '^https://github.com/aboutBilal/leak-response-toolkit/\.github/workflows/release\.yml@refs/tags/v' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

Container images are signed the same way:

```bash
cosign verify ghcr.io/aboutbilal/leak-response-toolkit:X.Y.Z \
  --certificate-identity-regexp '^https://github.com/aboutBilal/leak-response-toolkit/\.github/workflows/release\.yml@refs/tags/v' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Using the toolkit safely

- `scan` and `audit` run locally; `hunt`, `forks`, `commits` and `audit-org` send only repository names and commit IDs to public APIs.
- `notify` reads the webhook URL from `LEAK_WEBHOOK_URL`, so it never appears in arguments, process lists or logs; messages contain counts and types, never values.
- Output and reports are **redacted**: secret values are never printed or written.
- Evidence folders (`evidence/`, `hunts/`) can contain leaked code. They are git-ignored here; keep them out of any repository and share them only with the people handling the incident.
- Releases include a source archive signed with Sigstore; container images ship with an SBOM and build provenance.
