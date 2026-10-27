## What and why

<!-- One or two sentences. Link the issue if there is one. -->

## Checklist

- [ ] No secrets, real or fake, in any file or commit (test values are generated at runtime)
- [ ] No real incidents, company names, people or account names
- [ ] `make check` passes (shellcheck, tests, secret scan)
- [ ] Scripts: `Usage:` header, exit 2 on bad arguments, a test in `tests/scripts.bats`
- [ ] Docs: plain language; platform behaviour linked to vendor docs or marked as undocumented
- [ ] `CHANGELOG.md` updated under *Unreleased*
