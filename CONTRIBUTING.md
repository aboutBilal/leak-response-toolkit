# Contributing

Thank you for helping make leak response faster for everyone. Improvements from real experience are the most valuable: a step that was missing, a command that was wrong, a platform that is not covered yet.

## Ground rules

1. **No secrets, ever: not even fake ones.** Commands use placeholders like `<app-id>`. If a test needs a credential-shaped value, generate it at runtime in a temporary directory (see `tests/scripts.bats`). CI scans the full history on every push.
2. **Keep it general.** No real incidents, company names, people or account names. Examples use placeholders or reserved names such as `example.com`.
3. **Scripts stay read-only.** They may query public sources or read a repository they are pointed at; they must never use, test or print a discovered secret.
4. **Plain language.** Short sentences, one idea per step, tables over long lists. Someone may be reading this at 3 a.m. during an incident.
5. **Facts you can check.** If a step depends on a platform behaviour, link the vendor documentation, or say clearly when the behaviour is not documented.

## Making a change

```bash
git clone https://github.com/aboutBilal/spillkit.git
cd spillkit
pre-commit install   # gitleaks before every commit
make check           # shellcheck + bats tests + secret scan (what CI runs)
```

- **Scripts:** `bash`, `set -euo pipefail`, a header comment with `Usage:` (it becomes `--help`), exit `2` on bad arguments, `shellcheck -S warning` clean, and a test in `tests/scripts.bats`. Tests must run offline. A new script also gets a subcommand in `./leak`.
- **Prevention kit:** every file in `prevention/` must be tested before it is added, and the result recorded in `prevention/README.md` ("Tested behaviour").
- **Docs:** check links still work; CI checks every link between files, including heading anchors.
- **README images** come from real output only: capture it with `NO_COLOR=1`, then render with `tools/render-terminal-svg.py`. Colours, type and spacing follow the visual language in [`assets/DESIGN.md`](assets/DESIGN.md).
- **Commits:** a short summary line in the imperative ("Add Bitbucket takedown steps"), then why, if it is not obvious.

## Where to start

- **First contribution:** the issues labelled [good first issue](https://github.com/aboutBilal/spillkit/labels/good%20first%20issue). Each says what to change, which files to touch and how to test it.
- **Bigger pieces:** the issues labelled [help wanted](https://github.com/aboutBilal/spillkit/labels/help%20wanted): GitLab support in `leak respond`, more `leak rotate` recipes, Windows.
- **Your own idea:** rotation and investigation steps for more platforms, more sources for `leak hunt`, translations.

Comment on an issue before you start, so two people do not do the same work, and open an issue first for larger changes, so we can agree on the approach. Questions are welcome in [Discussions](https://github.com/aboutBilal/spillkit/discussions).

## Reporting a security problem

Please do not open a public issue; see [SECURITY.md](SECURITY.md).
