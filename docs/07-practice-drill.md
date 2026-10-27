# 07 · Practice drill (45 minutes)

Teams that have practised respond in minutes; teams that have not lose the first hour finding out who owns what. Run this drill once a quarter, or whenever the team changes.

> [!IMPORTANT]
> The drill uses **no real secrets and no public repository**. Everything happens in a throwaway **private** repository, and the fake credential is generated on the spot.

---

## Goals

- Everyone knows where this toolkit is and which page to open first.
- The roles (lead, rotator, investigator, communicator) are filled within 5 minutes.
- Each person has run the scripts once, so tooling problems surface now, not during an incident.
- The team knows who can rotate each kind of secret, and where that is still unclear.

## Setup (facilitator, 10 minutes before)

```bash
# A private throwaway repository with a fake secret deep in its history
mkdir drill && cd drill && git init -q
echo "# Drill service" > README.md && git add -A && git commit -qm "init"
echo "aws_access_key_id = AKIA$(LC_ALL=C tr -dc 'A-Z2-7' </dev/urandom | head -c 16)" > settings.ini
git add -A && git commit -qm "add settings"
git rm -q settings.ini && git commit -qm "remove settings"
```

Keep it local, or push it to a **private** repository only. The key is random and works nowhere.

## The drill

| Minute | Prompt from the facilitator | Expected response |
|---|---|---|
| 0 | "A colleague found our service's code in a public repository on a personal account. Go." | Someone takes the lead, opens the README's start-here table, assigns roles |
| 5 | "What do you do before asking for it to be deleted?" | Evidence snapshot; ask the owner for traffic screenshots and the security log |
| 10 | "Which secrets were in it?" | `./scripts/scan-secrets.sh <drill-repo>` finds the key deleted from history; nobody prints its value |
| 15 | "Who can rotate this key, right now?" | A named person and the exact steps from `02-rotate-secrets.md`. If nobody knows: **that is a finding** |
| 25 | "How do we know if it was used?" | The right log queries from `03-investigate.md`, and the time window (first push → rotation) |
| 30 | "The repository is gone. Is the code still out there?" | `hunt-copies.sh` and `find-commit-copies.sh`; the "what no one can check" limits |
| 35 | "Leadership wants an update in 10 minutes." | First message from `templates/notification-messages.md` |
| 40 | Debrief | What was slow, unclear or missing? |

## Debrief questions

1. Which step took longest, and why?
2. Was there any secret type nobody knew how to rotate?
3. Did every script run on everyone's machine?
4. What would we change in our own setup, not just in this drill?

Record the answers in `templates/post-incident-review.md` (yes, for a drill too) and turn them into actions with owners.

## Clean up

Delete the drill repository locally and, if you pushed it, on the server.
