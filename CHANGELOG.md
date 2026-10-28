# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [3.5.1] - 2026-10-28

### Added

- **SLSA build provenance on every release** for the source archive and the install script, attached as `spillkit-vX.Y.Z.intoto.jsonl` and verifiable with `gh attestation verify spillkit-vX.Y.Z.tar.gz --repo aboutBilal/spillkit`.

### Fixed

- `install.sh` refused to install when cosign 2 was installed, because releases use the newer Sigstore bundle format. It now passes `--new-bundle-format` to cosign 2.4 and later, and says when cosign is too old.
- `leak audit` in CI (and the GitHub Action in `audit` mode) no longer reports "no pre-commit hook installed in this clone": a CI checkout never has one, so the finding was noise in code scanning. Developer clones are still checked.

## [3.5.0] - 2026-10-28

From finding secrets to getting them rotated, and from hearing about Spillkit to seeing it work.

### Added

- **`leak plan`** turns a scan report into a rotation checklist, most dangerous first: anything that can create resources or read data, then anything with billing attached, then anything that grants further access, then the rest, oldest first within each. Every item says where the secret is revoked, links to its section of the rotation guide and names the `leak rotate` recipe where one exists. An unidentified secret right next to a known one (an AWS secret key under its key ID) is kept as its own item but rotated with its pair. Output: `rotation-plan.md` with checkboxes for the incident issue and a print-ready `rotation-plan.html` with a TLP label. The order comes from `scripts/secret-types.txt`, a catalog of gitleaks rules that a test keeps in step with the guide.
- **`leak rotate`** rotates an AWS access key, an Entra ID app registration secret, a Google Cloud service account key or an Azure storage account key, one step at a time: check, replace, disable, delete (renew for storage keys). Without `--apply` it is a dry run that prints every step with its exact command. The new secret goes from the provider's CLI straight into AWS Secrets Manager, Azure Key Vault or Google Secret Manager (`--store`) through a pipe: never shown, never written to disk, never in a command line; if the store refuses it, the new credential is deleted again. Disabling and deleting ask for the key ID first. Every applied step is logged with its UTC time in `rotation-log.tsv`.
- **`leak demo`** builds a repository with a leak made for the purpose (random keys that work nowhere) and runs audit, scan, plan and a rotation dry run on it, in about a minute.
- **One-line install:** `curl -fsSL https://github.com/aboutBilal/spillkit/releases/latest/download/install.sh | bash`. It checks the release's SHA-256 and, when cosign is installed, its Sigstore signature (`--require-signature` makes that mandatory), installs under `~/.local` without root, and runs on the bash 3.2 that macOS ships. Releases now carry `install.sh` and its signature.
- **GitLab groups in `leak audit-org`:** `--gitlab <group>`, including subgroups, with `GITLAB_TOKEN` (read_api) for private projects and `GITLAB_URL` for self-managed GitLab. Forks and archived projects are skipped.

### Changed

- `leak scan` and `leak audit` now point to `leak plan` as the next step; `leak doctor` also reports the cloud CLIs `leak rotate` uses and cosign.
- The runbook, cheat sheet, rotation guide, README and home page show the new commands. 51 tests, up from 41.

## [3.4.0] - 2026-10-27

### Added

- **`leak audit --sarif FILE`** writes the audit findings as SARIF 2.1.0 for GitHub code scanning. Each finding points at the file it concerns (the tracked secret file, the code that reads environment variables, the exact Dockerfile line, the first commit with a secret) and carries a severity, so critical findings rank as High. The GitHub Action passes `sarif-file` through in `audit` mode too.
- **Bitbucket Cloud and Azure DevOps in `leak audit-org`:** `--bitbucket <workspace>` (with `BITBUCKET_TOKEN`, an access token) and `--azure-devops <org>[/<project>]` (with `AZURE_DEVOPS_PAT`). Forks and disabled repositories are skipped, and a listing error exits `4` instead of reporting an empty organisation as clean. As everywhere else, tokens reach `curl` and `git` on standard input or through the environment, never as command-line arguments.

## [3.3.0] - 2026-10-27

### Changed

- **Reports rebuilt as standard incident documents.** `leak report` now follows the structure of NIST SP 800-61r3: document control (incident ID, severity, version, author, approver, distribution), a bottom-line summary with the decisions needed, incident details, a UTC timeline filled in from the tool runs, the investigation, secrets to rotate, impact, a notification assessment (for example GDPR Articles 33 and 34), actions with owners and due dates, root cause, and appendices for evidence checksums, method and limitations, a severity scale and document history. Every page carries a FIRST TLP 2.0 handling label, the incident ID and "Page X of Y" when printed. New options: `--id`, `--tlp` and `--blank`. The default file name is now `incident-report.html`, and the hand-fill template is `templates/incident-report.html`.
- **The organisation dashboard** (`leak audit-org`) uses the same document style: colours follow the data, every finding is labelled Critical or Fix with its remedy, and a method section states the weights and grade thresholds. New option: `--tlp`.

- **Renamed to Spillkit.** The project is now Spillkit: the emergency kit you keep ready for leaked secrets. The command is still `leak`. The repository moves to `aboutBilal/spillkit` (GitHub redirects the old address), the container image to `ghcr.io/aboutbilal/spillkit` (images for 3.2.0 and earlier stay at `ghcr.io/aboutbilal/leak-response-toolkit`), and the documentation to `aboutbilal.github.io/spillkit`. Update `uses:` lines and pre-commit `repo:` entries to the new name.
- New logo: an emergency case with a key, in place of the shield.

### Added

- **Redesigned documentation site and home page.** The home page is built around one idea: a leaked key can be in use within five minutes. A clock starts when the page opens and a stopwatch fills toward five minutes in real time, next to the product's own output, four verified numbers, illustrated stages, a map of where copies survive, product screenshots, the first-15-minutes plan, release verification and installation. The documentation has light and dark themes with a switch, IBM Plex Sans, dark code blocks with copy buttons, callouts with icons, heading links, an "On this page" rail, a mobile drawer, print styles for runbooks, and a 404 page.
- **Documentation search.** Press `Ctrl K`, `⌘K` or `/` on any page to search every runbook, guide and template by section.
- **Site checks in CI.** `tools/check-site.py` checks every internal link and anchor, page titles, descriptions, headings, image alt text and the search index on every pull request, before anything is deployed.

### Fixed

- Documentation site: links in the README's HTML header pointed at `.md` files and returned 404 on the site; the Overview and Incident checklist pages had no main heading.

- Documentation site: the home page no longer overflows on phones (grid columns shrink; long command lines scroll inside their box).
- The test suite no longer needs GNU `timeout`, which macOS does not have; hangs are caught by bats' own per-test limit (`BATS_TEST_TIMEOUT`) on every platform.

## [3.2.0] - 2026-10-27

An independent review found 18 issues before launch. All are fixed, each with a regression test.

### Security

- `leak audit` could print a secret value for a Dockerfile with an unusual name (for example `Dockerfile:v2`). The finding is now assembled from the file, line and variable name only, so the value cannot appear.
- `GITHUB_TOKEN` and webhook URLs are passed to `curl` and `git` on standard input or through the environment, never as command-line arguments, so they no longer appear in process lists.

### Fixed

- **Fail closed.** A scanner error (for example an invalid `.gitleaks.toml`) exited with the same code as "secrets found", and the GitHub Action then passed. Scanner failures now exit `4`, and the Action fails.
- **No false "clean".** `leak hunt` reported rate-limited or failed sources (Sourcegraph, GitHub activity, the event archive) as clean. Every source now reports "not checked" on failure, and `hunt` exits `4` when the result is incomplete.
- `leak forks` and `leak commits` exit `4` on API errors instead of printing an empty result.
- `leak audit-org` includes repositories whose names start with a dot (such as `.github`), clones private repositories with the token, marks repositories it could not clone as "not audited" (excluded from the average), and stops listing once `--limit` is reached.
- A missing option value (for example `--limit` with nothing after it) exits `2` instead of hanging.
- `leak notify` sends every word of the message, not only the last.
- `leak report` reports a clean scan as clean.
- `leak scan` writes its default report to `./secrets-report.json` instead of the parent folder.
- `--help` works after other arguments; usage lines name the `leak` command.
- Tables print without `column` installed; the minimum bash version is stated correctly (4.4); `leak` no longer needs `readlink -f`.
- README and SECURITY claims corrected: CodeQL runs on `main` and pull requests, every contacted service is listed, and `snapshot` is described as keeping a copy of the leaked repository.

### Added

- `scripts/lib.sh`: shared helpers enforcing the rules above (credentials out of argv, errors never reported as clean, one set of exit codes).
- Exit codes are documented everywhere: `0` clean, `1` findings, `2` usage error, `4` incomplete.
- GitHub Action: `github-token` input (defaults to the workflow token); hunts warn when sources could not be checked.
- Releases move the major tag (`v3`) automatically, so `@v3` always means the latest 3.x release.
- CI runs actionlint.
- Documentation site (GitHub Pages): a product home page and the docs, with sidebar filtering, an "On this page" contents rail, copy buttons, previous and next links, dark mode and self-hosted fonts. Lighthouse: accessibility 100 on every page.
- 9 regression tests (34 in total).

## [3.1.0] - 2026-10-27

### Added

- **Visual language** ([`assets/DESIGN.md`](assets/DESIGN.md)): one accent colour, status colours only for status, an 8-point grid, two corner radii, one type pair. Every README image, the social card, the terminal renderer and the HTML report and dashboard now use the same tokens.

### Changed

- `leak audit` wording is shorter and clearer (for example "no secret files tracked by Git"), and the summary line reads `Score 100/100 · Grade A`. Scripts that parsed `Score:` should match `Score ` instead.
- `leak scan` names the pinned gitleaks version instead of printing the full image reference.

### Fixed

- Tests hung on macOS: BSD `tr` keeps reading `/dev/urandom` when SIGPIPE is ignored. Random test values now come from a bounded read. The macOS CI job passes.

## [3.0.0] - 2026-10-27

### Added

- `leak audit-org`: grades every repository of a GitHub organisation or user, or every repository in a local folder, and writes an HTML dashboard, a markdown summary and JSON.
- `leak scan --sarif`: SARIF 2.1.0 output for GitHub code scanning. Values stay redacted.
- `leak audit --json`: machine-readable grade, score and checks.
- `leak notify`: alerts to Slack, Microsoft Teams (Workflows webhooks) or Discord. The webhook URL is read from `LEAK_WEBHOOK_URL`, never from arguments.
- GitHub Action: `audit-org` mode, `sarif-file`, `webhook-url` and `webhook-format` inputs, and a `report` output.
- `.pre-commit-hooks.yaml`: `forbid-secret-files` and `leak-guard` hooks usable from any repository.
- `leak hunt` checks public GitLab projects with the same name.
- macOS job in CI (Homebrew bash, BSD tools).
- Animated terminal demo (respects reduced-motion settings), and dashboard and report previews in the README.

### Changed

- **Breaking for automation:** `leak hunt` reports use plain words (`clean`, `**found**`, `review`, `not checked`) instead of symbols. Update any script that matched the old markers.
- The `@v3` Action tag replaces `@v2` in examples.
- Documentation edited for precision: plain headings without emoji, measured claims only.

### Fixed

- macOS compatibility: POSIX character classes instead of `\s`, no GNU-only `sed` flags, `shasum` when `sha256sum` is absent, BSD `date` fallback.

## [2.3.0] - 2026-10-27

A new face: the toolkit now presents itself like the product it is.

### Added

- **Brand:** a shield-and-keyhole logo, a product hero banner with a live `leak audit` card, a "How it works" lifecycle graphic, and a matching social preview card.
- **Report preview:** a real `leak report` rendered as a document preview, so readers see what leadership receives.
- **"Built to be trusted"** section: signed releases, SBOM and provenance, OpenSSF Scorecard, pinned dependencies, analysis and tests, each verifiable.

### Changed

- README rebuilt as a product page: hero, live badges (CI, Scorecard, latest release, signed releases), install, demos, incident quick-start, prevention, CI, commands, trust, comparison, FAQ.

## [2.2.0] - 2026-10-27

Supply-chain hardening, guided by the OpenSSF Scorecard results.

### Added

- **Signed releases:** every release gets a source archive, its SHA-256 and a keyless **Sigstore** signature bundle; the container image is signed by digest. Verification commands are in [SECURITY.md](SECURITY.md#verifying-a-release).
- **CodeQL** static analysis of the workflows and Python tooling.
- **Dependabot** now also updates the container base image.
- SECURITY.md: supported versions, what counts as a vulnerability, and a coordinated-disclosure timeline.

### Changed

- Every container image reference (Dockerfile, CI, scripts, prevention kit) is **pinned by digest** as well as by tag.
- The Scorecard badge links directly to the current score.

## [2.1.0] - 2026-10-27

### Added

- **Container image** `ghcr.io/aboutbilal/leak-response-toolkit` (amd64 and arm64) with every dependency, gitleaks included; runs as a non-root user.
- **Release automation:** every version tag publishes GitHub release notes from this changelog (backfilling earlier tags) and the image, with an **SBOM and build provenance**.
- **OpenSSF Scorecard** analysis on every push to `main` and weekly, with a README badge.
- `make install` / `make uninstall` (puts `leak` on your PATH) and `make image`.
- README: install options, a real `leak audit` demo, an honest comparison with gitleaks, TruffleHog and GitGuardian, and an FAQ.
- `tools/render-terminal-svg.py`: README images are generated from real command output.
- `CITATION.cff`, `ROADMAP.md`, a social preview image.

### Fixed

- `leak audit` printed the value of a secret found in a Dockerfile `ARG`/`ENV` line. It now shows only the file, line and variable name (`API_TOKEN=<redacted>`), and a test enforces it.
- `leak` now resolves symlinks, so it works when installed on the PATH or inside the image.
- `leak audit` no longer warns about documentation that mentions environment variables, or about example Dockerfiles.

## [2.0.0] - 2026-10-27

Prevention becomes the second half of the kit: not only responding to leaks, but designing them out.

### Added

- **[Secrets by design](docs/08-secrets-by-design.md)**: an architecture guide with five principles, a reference architecture, an 8-layer control matrix, maturity levels 0–4, a 90-day rollout, metrics and a design-review checklist.
- **[Prevention kit](prevention/README.md)**, every file tested: secret-aware `.gitignore`, pre-commit config (gitleaks, private-key detection, blocked secret file types), a plain git hook, a gitleaks config with custom rules, CI templates for GitHub Actions, GitLab, Azure Pipelines and Bitbucket, keyless OIDC login to AWS, Azure and Google Cloud, `.dockerignore`, a BuildKit build-secret example, `.env.example`.
- `./leak audit`: grades a repository's secret hygiene A–F with a fix for every gap.
- `./leak report`: builds the leadership report from hunt and scan results (secret types only; content HTML-escaped).
- `./leak doctor`: checks a machine is ready before an incident.
- **GitHub Action** (`action.yml`): `scan`, `audit` or `hunt` in any repository's CI, with job summaries; self-tested in this repository's CI.
- `hunt` also writes machine-readable `results.jsonl` and `meta.json`.
- Rotation guide: AI provider keys, container and package registries, Kubernetes, Terraform Cloud, source platform tokens, messaging, payments, webhooks.
- Tests: 16 offline tests (audit grades, report escaping, doctor).

### Changed

- This repository now uses the prevention kit on itself (`./leak audit .` → Grade A).
- README reorganised around **prevent** and **respond**.

## [1.1.0] - 2026-10-27

### Added

- `./leak`: one command for every script (`snapshot`, `scan`, `forks`, `hunt`, `commits`), with tests.
- `CHEATSHEET.md`: the first 15 minutes on one page, with a "who to call" table to fill in ahead of time.
- `templates/incident-issue.md`: a team checklist to paste into a private issue tracker.
- README front page: banner, sourced "why minutes matter" figures, command table and a terminal image of real, redacted output.

## [1.0.0] - 2026-10-27

### Added

- **Runbook** for code or secrets exposed in a public repository, and a **scenario guide**: own repository, made public by mistake, copied to another account, provider alerts, leaks outside Git (gists, pastes, CI logs, images, packages, chat), external reports, non-GitHub platforms.
- **Rotation guide** per secret type (Azure, AWS, Google Cloud, GitHub, databases, SSH and certificates, application secrets) and guidance for keys meant to be public.
- **Investigation guide** with log queries for Azure, AWS, Google Cloud and databases.
- **Where copies survive**: archives, forks, re-uploads, evidence that disappears, removal requests.
- **Prevention guide**, including a measured test of what push protection and gitleaks each catch.
- **Practice drill** for teams.
- Scripts: `snapshot-evidence.sh`, `scan-secrets.sh` (redacted, full history), `list-forks.sh`, `hunt-copies.sh` (15+ public sources, markdown report), `find-commit-copies.sh`, all with `--help`.
- Templates: incident timeline, takedown request, notification messages, post-incident review, executive report (print-ready HTML).
- Quality: offline bats tests, shellcheck, gitleaks on full history, link and anchor checks in CI, Dependabot for pinned actions, pre-commit hook, contribution guide, issue and pull request templates, security policy.

[Unreleased]: https://github.com/aboutBilal/spillkit/compare/v3.5.1...HEAD
[3.5.1]: https://github.com/aboutBilal/spillkit/compare/v3.5.0...v3.5.1
[3.5.0]: https://github.com/aboutBilal/spillkit/compare/v3.4.0...v3.5.0
[3.4.0]: https://github.com/aboutBilal/spillkit/compare/v3.3.0...v3.4.0
[3.3.0]: https://github.com/aboutBilal/spillkit/compare/v3.2.0...v3.3.0
[3.2.0]: https://github.com/aboutBilal/spillkit/compare/v3.1.0...v3.2.0
[3.1.0]: https://github.com/aboutBilal/spillkit/compare/v3.0.0...v3.1.0
[3.0.0]: https://github.com/aboutBilal/spillkit/compare/v2.3.0...v3.0.0
[2.3.0]: https://github.com/aboutBilal/spillkit/compare/v2.2.0...v2.3.0
[2.2.0]: https://github.com/aboutBilal/spillkit/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/aboutBilal/spillkit/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/aboutBilal/spillkit/compare/v1.1.0...v2.0.0
[1.1.0]: https://github.com/aboutBilal/spillkit/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/aboutBilal/spillkit/releases/tag/v1.0.0
