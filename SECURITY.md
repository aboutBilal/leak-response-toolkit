# Security policy

## This repository holds no secrets

Every command uses placeholders such as `<app-id>`, and every push is scanned by gitleaks in CI. If you find something that looks like a real credential, please report it as below so it can be checked and removed.

## Reporting a problem

Please **do not open a public issue** for a security problem, such as a script that could leak data or a step in the runbook that would make an incident worse.

Use GitHub's private reporting instead: **Security → Report a vulnerability** on this repository.

Include what you found, where (file and line), and how to reproduce it. You will get a reply as soon as possible.

## Using the scripts safely

- The scripts only send read-only queries to public sources, or read a repository you point them at.
- Scan output is **redacted**: secret values are never printed or written to reports.
- Evidence folders (`evidence/`, `hunts/`) can contain leaked code. They are git-ignored here; keep them out of any repository and share them only with the people handling the incident.
