# Prevention kit

Ready-to-copy files that stop secrets from being committed, pushed, built into images or stored in pipelines. **Every file here was tested** (see [Tested behaviour](#tested-behaviour)). The reasoning behind each one is in [`docs/08-secrets-by-design.md`](../docs/08-secrets-by-design.md).

## Roll it out in this order

| Step | File | Copy to | Effort | Stops |
|:-:|---|---|:-:|---|
| 1 | [`gitignore-secrets`](gitignore-secrets) | append to `.gitignore`, or `git config --global core.excludesFile` | 1 min | `.env`, keys, state files ever being staged by accident |
| 2 | [`env/env.example`](env/env.example) | `.env.example` (adapted) | 5 min | Teams sharing real `.env` files to "show the format" |
| 3 | [`pre-commit-config.yaml`](pre-commit-config.yaml) | `.pre-commit-config.yaml`, then `pre-commit install` | 5 min | Secret files and secret values at commit time |
| 3b | [`hooks/pre-commit`](hooks/pre-commit) | `.git/hooks/pre-commit` (no framework needed) | 1 min | Same, for teams without the pre-commit framework |
| 4 | [`ci/`](ci) (GitHub, GitLab, Azure Pipelines, Bitbucket) | your CI configuration | 10 min | Anything that skipped the hook (`--no-verify`, web edits, new machines) |
| 5 | [`gitleaks.toml`](gitleaks.toml) | `.gitleaks.toml` | 15 min | Your **own** token formats, which no public scanner knows |
| 6 | [`docker/dockerignore`](docker/dockerignore), [`docker/Dockerfile.build-secrets.example`](docker/Dockerfile.build-secrets.example) | `.dockerignore`, your Dockerfiles | 15 min | Secrets baked into image layers |
| 7 | [`oidc/github-to-clouds.yml`](oidc/github-to-clouds.yml) | your deploy workflow | 1 hour | Stored cloud keys in CI: removes the secret entirely |

Then check the result: `./leak audit <repo>` gives a grade from A to F, with a fix for each gap.

Steps 3 and 3b are also available as hooks published from this repository, with nothing to copy:

```yaml
repos:
  - repo: https://github.com/aboutBilal/spillkit
    rev: v3.6.1
    hooks:
      - id: forbid-secret-files
      - id: leak-guard
```

## Server-side settings (no file to copy)

Hooks can be skipped; these cannot:

- **Push protection** on for every repository (organisation-wide where possible).
- **Forking private repositories to personal accounts: off.**
- **Repository visibility changes: admins only.**
- **Audit log** streamed to your SIEM, with alerts on visibility changes.

## Tested behaviour

| Test | Result |
|---|---|
| `pre-commit-config.yaml` in a fresh repository | `.env` blocked · private key blocked by **two** hooks · AWS key blocked · `.env.example` and a normal README allowed |
| `hooks/pre-commit` (plain hook) | Same results, using local gitleaks or the Docker image |
| `gitleaks.toml` | Custom token rule fires; allow-listed fixture folder is skipped |
| `Dockerfile.build-secrets.example` pattern | Secret readable during the build step; **not present** in image history or layers |
| Hooks published in `.pre-commit-hooks.yaml`, used from another repository | `.env` blocked by both hooks; `.env.example` and normal changes allowed |
| This repository | Uses this kit on itself: `./leak audit .` gives grade A |

All test secrets were generated at run time and never written into this repository.
