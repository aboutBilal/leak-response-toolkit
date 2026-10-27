# Post-incident review: `<short name>`

> **Blameless:** this review asks how the system allowed the leak, not who to blame. People act sensibly given what they know and what the system makes easy. Fix the system and the same mistake becomes hard to make.

| Field | Value |
|---|---|
| Date of incident | |
| Date of review | |
| Facilitator | |
| Attendees | |
| Timeline | link to `incident-timeline.md` |

## 1. Summary

Two or three sentences: what was exposed, for how long, the impact, and the current status.

## 2. Impact

| Question | Answer |
|---|---|
| What was exposed (code, secrets, data)? | |
| How long was it public? | |
| Were any credentials used by someone else? (evidence, or "no evidence in the logs we had") | |
| Was personal or customer data involved? | |
| Who had to be notified? | |
| Cost: hours spent, services affected, money | |

## 3. What went well

-
-

## 4. What was hard or slow

-
-

## 5. Contributing factors

Ask **"why was this possible?"** until the answers become things you can change. Typical areas:

| Area | Question | Finding |
|---|---|---|
| Secrets | Why were working secrets in the code at all? | |
| Detection | Why did no scanner stop it before or at push? | |
| Access | Why could the code be copied to a personal or public place? | |
| Awareness | Did the person know this was not allowed, and why? | |
| Response | What slowed rotation, removal or investigation? | |

## 6. Actions

Each action gets an owner and a date. Prefer actions that make the mistake **impossible or caught automatically** over actions that rely on people remembering.

| # | Action | Type (prevent / detect / respond) | Owner | Due | Done |
|---|---|---|---|---|---|
| 1 | | | | | |
| 2 | | | | | |
| 3 | | | | | |

## 7. Follow-up

- Review date to confirm the actions are done:
- Copy hunt repeated after 7 days (result):
