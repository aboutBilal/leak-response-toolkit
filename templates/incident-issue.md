<!--
Incident tracking checklist. Copy everything below this comment into a new issue
(GitHub, GitLab, Jira, Azure Boards) in a PRIVATE project, so the team can tick
items off together. Never paste secret values into it.
-->
## Leak incident: `<short name>`

**Lead:** @`<name>` · **Rotator:** @`<name>` · **Investigator:** @`<name>` · **Comms:** @`<name>`
**Detected:** `<time UTC>` · **Exposure window:** `<start>` → `<end>` (source: `<security log / alert email>`)

### 1. Contain (first hour)
- [ ] Evidence saved: `./leak snapshot <owner>/<repo>`, traffic screenshots, security log
- [ ] Full-history scan: `./leak scan <path>`; secret types listed below
- [ ] Every secret rotated **and the old value revoked** (table below)
- [ ] Public copy removed (made private / deleted / DMCA filed)
- [ ] Forks listed and included in the takedown: `./leak forks <owner>/<repo>`

| Secret type | Where it is used | Rotated (UTC) | Old revoked (UTC) | By |
|---|---|---|---|---|
| | | | | |

### 2. Investigate (same day)
- [ ] Logs reviewed from first push to each rotation (cloud, database, billing)
- [ ] Copy hunt: `./leak hunt --since <date> <owner>/<repo>`; report attached
- [ ] Re-uploads by commit ID: `./leak commits --exclude <owner>/<repo> <sha> <sha>`
- [ ] Personal or customer data in scope? **yes / no**

### 3. Communicate
- [ ] Leadership first alert sent
- [ ] Affected parties notified (if required; legal consulted)
- [ ] Status updates on schedule until closed

### 4. Close
- [ ] Copy hunt repeated after 7 days
- [ ] Post-incident review held; actions have owners and dates
- [ ] Prevention measures tracked as separate issues
